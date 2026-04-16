import 'package:flutter/foundation.dart';

import 'model_manager.dart';
import 'settings_service.dart';
import 'stt_platform.dart';
import 'stt_provider.dart';
import 'stt_sherpa.dart';
import 'stt_vosk.dart';

/// Facade that delegates to the active [SttProvider] based on settings.
///
/// Created once at app startup. Reads the selected STT engine from
/// [SettingsService] and creates the appropriate provider. The provider
/// is initialized lazily (models must be downloaded first via settings).
class SttService extends ChangeNotifier {
  final ModelManager _modelManager;
  final SettingsService _settings;
  SttProvider? _provider;
  bool _disposed = false;
  bool _modelMissing = false;

  SttService({
    required ModelManager modelManager,
    required SettingsService settings,
  })  : _modelManager = modelManager,
        _settings = settings;

  SttProvider? get provider => _provider;
  bool get isInitialized => _provider?.isInitialized ?? false;
  bool get isListening => _provider?.isListening ?? false;
  bool get isTranscribing => _provider?.isTranscribing ?? false;
  bool get supportsStreaming => _provider?.supportsStreaming ?? false;
  String get currentText => _provider?.currentText ?? '';
  String? get error => _provider?.error;
  bool get modelMissing => _modelMissing;

  SttEngine get activeEngine => _settings.sttEngine;

  /// Initialize the provider for the configured engine.
  /// Only loads already-downloaded models — does NOT trigger downloads.
  /// If initialization fails, falls back to Platform STT.
  Future<bool> initialize() async {
    final engine = _settings.sttEngine;
    debugPrint('[SttService] Initializing engine: ${engine.name}');

    // Step 1: Check if model is available (no download)
    final pathsOk = await _modelManager.prepareModelPaths(
      engine,
      sherpaSize: _settings.sherpaModelSize,
      voskSize: _settings.voskModelSize,
    );
    if (!pathsOk) {
      _modelMissing = true;
      _safeNotify();
      return false;
    }
    _modelMissing = false;

    // Step 2: Create and initialize the provider
    final ok = await _initProvider(engine);
    if (ok) return true;

    // Step 3: Fallback to Platform STT if native engine fails
    if (engine != SttEngine.platform) {
      debugPrint('[SttService] ${engine.name} failed, falling back to Platform STT');
      final fallbackOk = await _initProvider(SttEngine.platform);
      if (fallbackOk) {
        _safeNotify();
        return true;
      }
    }

    _safeNotify();
    return false;
  }

  Future<bool> _initProvider(SttEngine engine) async {
    _provider?.removeListener(_onProviderChanged);
    _provider?.dispose();
    _provider = null;

    try {
      switch (engine) {
        case SttEngine.vosk:
          _provider = VoskSttProvider(
            modelPath: _modelManager.voskModelPath,
            grammar: (_settings.voskGrammarEnabled && _settings.voskModelSize == VoskModelSize.small)
                ? _settings.voskGrammarWords
                : null,
          );
          break;
        case SttEngine.sherpaOnnx:
          _provider = SherpaSttProvider(
            encoderPath: _modelManager.encoderPath,
            decoderPath: _modelManager.decoderPath,
            tokensPath: _modelManager.tokensPath,
          );
          break;
        case SttEngine.platform:
          _provider = PlatformSttProvider();
          break;
      }

      _provider!.addListener(_onProviderChanged);
      return await _provider!.initialize();
    } catch (e) {
      debugPrint('[SttService] Provider init crashed: $e');
      _provider?.dispose();
      _provider = null;
      return false;
    }
  }

  Future<void> startListening() async {
    await _provider?.startListening();
  }

  Future<String> stopListening() async {
    return await _provider?.stopListening() ?? '';
  }

  Future<void> cancelListening() async {
    await _provider?.cancelListening();
  }

  void _onProviderChanged() {
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _provider?.removeListener(_onProviderChanged);
    _provider?.dispose();
    super.dispose();
  }
}
