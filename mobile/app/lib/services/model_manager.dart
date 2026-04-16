import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import 'settings_service.dart';

/// Manages downloading and caching of STT model files.
///
/// Supports both Vosk (single zip) and sherpa-onnx Whisper (individual files).
/// On Android: `/storage/emulated/0/BOSTrainer/models/` (survives reinstall).
/// On Linux: `~/.local/share/BOSTrainer/models/`.
class ModelManager extends ChangeNotifier {
  static String get _storageRoot {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/BOSTrainer';
    }
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, '.local', 'share', 'BOSTrainer');
  }

  // Vosk German models
  static const _voskModels = {
    VoskModelSize.small: _VoskModelInfo(
      name: 'vosk-model-small-de-0.15',
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip',
    ),
    VoskModelSize.large: _VoskModelInfo(
      name: 'vosk-model-de-0.21',
      url: 'https://alphacephei.com/vosk/models/vosk-model-de-0.21.zip',
    ),
  };

  // Sherpa-onnx Whisper models by size
  static const _sherpaModels = {
    SherpaModelSize.tiny: _SherpaModelInfo(
      dir: 'whisper-tiny',
      prefix: 'tiny',
      repo: 'csukuangfj/sherpa-onnx-whisper-tiny',
    ),
    SherpaModelSize.small: _SherpaModelInfo(
      dir: 'whisper-small',
      prefix: 'small',
      repo: 'csukuangfj/sherpa-onnx-whisper-small',
    ),
    SherpaModelSize.medium: _SherpaModelInfo(
      dir: 'whisper-medium',
      prefix: 'medium',
      repo: 'csukuangfj/sherpa-onnx-whisper-medium',
    ),
  };

  ModelState _state = ModelState.checking;
  double _progress = 0.0;
  String? _error;
  String? _modelPath;

  ModelState get state => _state;
  double get progress => _progress;
  String? get error => _error;
  String? get modelPath => _modelPath;

  // Sherpa-specific paths
  String get encoderPath {
    final info = _activeSherpaInfo;
    return p.join(_modelPath!, '${info.prefix}-encoder.int8.onnx');
  }

  String get decoderPath {
    final info = _activeSherpaInfo;
    return p.join(_modelPath!, '${info.prefix}-decoder.int8.onnx');
  }

  String get tokensPath {
    final info = _activeSherpaInfo;
    return p.join(_modelPath!, '${info.prefix}-tokens.txt');
  }

  // Vosk model path (the extracted model directory)
  String get voskModelPath => p.join(_modelPath!, _activeVoskInfo.name);

  _SherpaModelInfo _activeSherpaInfo = _sherpaModels[SherpaModelSize.small]!;
  _VoskModelInfo _activeVoskInfo = _voskModels[VoskModelSize.small]!;

  /// Check if the model for the given engine/size is already downloaded.
  /// Does NOT download anything.
  Future<bool> isModelAvailable(SttEngine engine, {SherpaModelSize? sherpaSize, VoskModelSize? voskSize}) async {
    if (engine == SttEngine.platform) return true;

    if (engine == SttEngine.vosk) {
      final info = _voskModels[voskSize ?? VoskModelSize.small]!;
      final dir = Directory(p.join(_storageRoot, 'models', 'vosk', info.name));
      return dir.existsSync();
    } else {
      final info = _sherpaModels[sherpaSize ?? SherpaModelSize.small]!;
      final modelDir = Directory(p.join(_storageRoot, 'models', info.dir));
      final files = _sherpaFiles(info);
      return _allFilesExist(modelDir, files.keys);
    }
  }

  /// Prepare paths for an already-downloaded model (no download).
  /// Returns true if model exists and paths are set.
  Future<bool> prepareModelPaths(SttEngine engine, {SherpaModelSize? sherpaSize, VoskModelSize? voskSize}) async {
    _state = ModelState.checking;
    _error = null;
    notifyListeners();

    if (engine == SttEngine.platform) {
      _state = ModelState.ready;
      _modelPath = '';
      notifyListeners();
      return true;
    }

    if (engine == SttEngine.vosk) {
      final size = voskSize ?? VoskModelSize.small;
      _activeVoskInfo = _voskModels[size]!;
      final modelDir = Directory(p.join(_storageRoot, 'models', 'vosk'));
      _modelPath = modelDir.path;
      final extractedDir = Directory(p.join(modelDir.path, _activeVoskInfo.name));
      if (await extractedDir.exists()) {
        _state = ModelState.ready;
        notifyListeners();
        return true;
      }
    } else {
      final size = sherpaSize ?? SherpaModelSize.small;
      _activeSherpaInfo = _sherpaModels[size]!;
      final modelDir = Directory(p.join(_storageRoot, 'models', _activeSherpaInfo.dir));
      _modelPath = modelDir.path;
      final files = _sherpaFiles(_activeSherpaInfo);
      if (await _allFilesExist(modelDir, files.keys)) {
        _state = ModelState.ready;
        notifyListeners();
        return true;
      }
    }

    _state = ModelState.error;
    _error = 'Modell nicht heruntergeladen';
    notifyListeners();
    return false;
  }

  /// Download the model for the given engine/size.
  /// Call this only after user confirmation.
  Future<bool> downloadModel(SttEngine engine, {SherpaModelSize? sherpaSize, VoskModelSize? voskSize}) async {
    _state = ModelState.checking;
    _error = null;
    notifyListeners();

    try {
      if (engine == SttEngine.platform) {
        _state = ModelState.ready;
        _modelPath = '';
        notifyListeners();
        return true;
      }

      if (!await _ensureStoragePermission()) {
        _state = ModelState.error;
        _error = 'Speicherzugriff verweigert. '
            'Bitte erlaube den Zugriff in den App-Einstellungen.';
        notifyListeners();
        return false;
      }

      if (engine == SttEngine.vosk) {
        final size = voskSize ?? VoskModelSize.small;
        _activeVoskInfo = _voskModels[size]!;
        return await _ensureVoskModel(_activeVoskInfo);
      } else {
        final size = sherpaSize ?? SherpaModelSize.small;
        _activeSherpaInfo = _sherpaModels[size]!;
        return await _ensureSherpaModel(_activeSherpaInfo);
      }
    } catch (e) {
      debugPrint('[ModelManager] Error: $e');
      _state = ModelState.error;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Get the download size label for an engine/model combination.
  static String downloadSizeLabel(SttEngine engine, {VoskModelSize? voskSize, SherpaModelSize? sherpaSize}) {
    if (engine == SttEngine.vosk) {
      return voskModelSizeLabel(voskSize ?? VoskModelSize.small);
    } else if (engine == SttEngine.sherpaOnnx) {
      return sherpaModelSizeLabel(sherpaSize ?? SherpaModelSize.small);
    }
    return '';
  }

  Future<bool> _ensureVoskModel(_VoskModelInfo info) async {
    final modelDir = Directory(p.join(_storageRoot, 'models', 'vosk'));
    _modelPath = modelDir.path;
    final extractedDir = Directory(p.join(modelDir.path, info.name));

    if (await extractedDir.exists()) {
      debugPrint('[ModelManager] Vosk model found at ${extractedDir.path}');
      _state = ModelState.ready;
      notifyListeners();
      return true;
    }

    _state = ModelState.downloading;
    _progress = 0.0;
    notifyListeners();

    await modelDir.create(recursive: true);

    final zipPath = p.join(modelDir.path, '${info.name}.zip');
    debugPrint('[ModelManager] Downloading Vosk model ${info.name}...');
    await _downloadFileWithProgress(info.url, zipPath);

    // Extract zip
    debugPrint('[ModelManager] Extracting Vosk model...');
    _progress = 0.9;
    notifyListeners();

    final result = await Process.run('unzip', ['-o', zipPath, '-d', modelDir.path]);
    if (result.exitCode != 0) {
      throw Exception('Entpacken fehlgeschlagen: ${result.stderr}');
    }

    // Clean up zip
    await File(zipPath).delete();

    if (await extractedDir.exists()) {
      _state = ModelState.ready;
      _progress = 1.0;
      notifyListeners();
      return true;
    } else {
      _state = ModelState.error;
      _error = 'Vosk-Modell nicht gefunden nach Entpacken';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _ensureSherpaModel(_SherpaModelInfo info) async {
    final modelDir = Directory(p.join(_storageRoot, 'models', info.dir));
    _modelPath = modelDir.path;

    final files = _sherpaFiles(info);
    if (await _allFilesExist(modelDir, files.keys)) {
      debugPrint('[ModelManager] Sherpa model found at ${modelDir.path}');
      _state = ModelState.ready;
      notifyListeners();
      return true;
    }

    _state = ModelState.downloading;
    _progress = 0.0;
    notifyListeners();

    await modelDir.create(recursive: true);

    int filesDownloaded = 0;
    for (final entry in files.entries) {
      final filePath = p.join(modelDir.path, entry.key);
      debugPrint('[ModelManager] Downloading ${entry.key}...');
      await _downloadFile(entry.value, filePath);
      filesDownloaded++;
      _progress = filesDownloaded / files.length;
      notifyListeners();
    }

    if (await _allFilesExist(modelDir, files.keys)) {
      _state = ModelState.ready;
      notifyListeners();
      return true;
    } else {
      _state = ModelState.error;
      _error = 'Modelldateien unvollständig nach Download';
      notifyListeners();
      return false;
    }
  }

  Map<String, String> _sherpaFiles(_SherpaModelInfo info) {
    final base = 'https://huggingface.co/${info.repo}/resolve/main';
    return {
      '${info.prefix}-encoder.int8.onnx': '$base/${info.prefix}-encoder.int8.onnx',
      '${info.prefix}-decoder.int8.onnx': '$base/${info.prefix}-decoder.int8.onnx',
      '${info.prefix}-tokens.txt': '$base/${info.prefix}-tokens.txt',
    };
  }

  Future<bool> _ensureStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;
      final result = await Permission.manageExternalStorage.request();
      return result.isGranted;
    }
    return true;
  }

  Future<bool> _allFilesExist(Directory dir, Iterable<String> fileNames) async {
    if (!await dir.exists()) return false;
    for (final name in fileNames) {
      final f = File(p.join(dir.path, name));
      if (!await f.exists() || await f.length() == 0) return false;
    }
    return true;
  }

  Future<void> _downloadFile(String url, String destPath) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception(
          'Download fehlgeschlagen: HTTP ${response.statusCode} für $url');
    }

    final file = File(destPath);
    final sink = file.openWrite();
    await response.stream.pipe(sink);
    await sink.close();

    debugPrint(
        '[ModelManager] Downloaded ${p.basename(destPath)} (${await file.length()} bytes)');
  }

  Future<void> _downloadFileWithProgress(String url, String destPath) async {
    final request = http.Request('GET', Uri.parse(url));
    final client = http.Client();
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception(
          'Download fehlgeschlagen: HTTP ${response.statusCode} für $url');
    }

    final contentLength = response.contentLength ?? 0;
    final file = File(destPath);
    final sink = file.openWrite();
    int received = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        _progress = (received / contentLength) * 0.85; // 85% for download
        notifyListeners();
      }
    }

    await sink.close();
    client.close();

    debugPrint(
        '[ModelManager] Downloaded ${p.basename(destPath)} (${await file.length()} bytes)');
  }

  /// Delete all cached models.
  Future<void> deleteModels() async {
    final modelsDir = Directory(p.join(_storageRoot, 'models'));
    if (await modelsDir.exists()) {
      await modelsDir.delete(recursive: true);
    }
    _state = ModelState.checking;
    _modelPath = null;
    notifyListeners();
  }

  /// Get human-readable size estimate for a Sherpa model.
  static String sherpaModelSizeLabel(SherpaModelSize size) {
    switch (size) {
      case SherpaModelSize.tiny:
        return '~75 MB';
      case SherpaModelSize.small:
        return '~460 MB';
      case SherpaModelSize.medium:
        return '~1.5 GB';
    }
  }

  /// Get human-readable size estimate for a Vosk model.
  static String voskModelSizeLabel(VoskModelSize size) {
    switch (size) {
      case VoskModelSize.small:
        return '~45 MB';
      case VoskModelSize.large:
        return '~420 MB';
    }
  }
}

class _VoskModelInfo {
  final String name;
  final String url;

  const _VoskModelInfo({
    required this.name,
    required this.url,
  });
}

class _SherpaModelInfo {
  final String dir;
  final String prefix;
  final String repo;

  const _SherpaModelInfo({
    required this.dir,
    required this.prefix,
    required this.repo,
  });
}

enum ModelState { checking, downloading, ready, error }
