import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'stt_provider.dart';

/// STT provider using sherpa-onnx Whisper (offline, record-then-transcribe).
///
/// Audio is streamed into memory during recording. On stop, the accumulated
/// PCM is fed to Whisper for batch decoding.
class SherpaSttProvider extends SttProvider {
  final String encoderPath;
  final String decoderPath;
  final String tokensPath;

  final AudioRecorder _recorder = AudioRecorder();
  sherpa.OfflineRecognizer? _recognizer;

  bool _initialized = false;
  bool _isListening = false;
  bool _isTranscribing = false;
  bool _disposed = false;
  String _currentText = '';
  String? _error;

  final List<int> _pcmBuffer = [];
  StreamSubscription<Uint8List>? _streamSub;

  static const int _sampleRate = 16000;

  SherpaSttProvider({
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
  });

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isListening => _isListening;
  @override
  bool get isTranscribing => _isTranscribing;
  @override
  bool get supportsStreaming => false;
  @override
  String get currentText => _currentText;
  @override
  String? get error => _error;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      sherpa.initBindings();

      final whisperConfig = sherpa.OfflineWhisperModelConfig(
        encoder: encoderPath,
        decoder: decoderPath,
        language: 'de',
        task: 'transcribe',
      );

      final modelConfig = sherpa.OfflineModelConfig(
        whisper: whisperConfig,
        tokens: tokensPath,
        modelType: 'whisper',
        numThreads: 4,
        debug: false,
      );

      final config = sherpa.OfflineRecognizerConfig(model: modelConfig);
      _recognizer = sherpa.OfflineRecognizer(config);

      _initialized = true;
      _error = null;
      debugPrint('[Sherpa] Whisper initialized');
      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('[Sherpa] Init error: $e');
      _error = 'Sherpa-Initialisierung fehlgeschlagen: $e';
      _initialized = false;
      _safeNotify();
      return false;
    }
  }

  @override
  Future<void> startListening() async {
    if (!_initialized || _isListening || _isTranscribing) return;

    _error = null;
    _currentText = '';
    _pcmBuffer.clear();

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    );

    final audioStream = await _recorder.startStream(config);
    _streamSub = audioStream.listen((chunk) {
      _pcmBuffer.addAll(chunk);
    });

    _isListening = true;
    debugPrint('[Sherpa] Recording started (streaming to RAM)');
    _safeNotify();
  }

  @override
  Future<String> stopListening() async {
    if (!_isListening) return '';

    _isListening = false;
    _isTranscribing = true;
    _safeNotify();

    try {
      await _streamSub?.cancel();
      _streamSub = null;
      await _recorder.stop();

      final byteCount = _pcmBuffer.length;
      debugPrint('[Sherpa] Recording stopped, $byteCount bytes in buffer');

      if (byteCount < 3200) {
        debugPrint('[Sherpa] Recording too short');
        _pcmBuffer.clear();
        _isTranscribing = false;
        _safeNotify();
        return '';
      }

      final samples = _pcm16ToFloat32(Uint8List.fromList(_pcmBuffer));
      _pcmBuffer.clear();

      debugPrint('[Sherpa] Transcribing ${samples.length} samples '
          '(${(samples.length / _sampleRate).toStringAsFixed(1)}s)...');

      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      stream.free();

      _currentText = result.text.trim();
      debugPrint('[Sherpa] Transcribed: "$_currentText"');

      _isTranscribing = false;
      _safeNotify();
      return _currentText;
    } catch (e) {
      debugPrint('[Sherpa] Transcription error: $e');
      _error = 'Transkription fehlgeschlagen: $e';
      _pcmBuffer.clear();
      _isTranscribing = false;
      _safeNotify();
      return '';
    }
  }

  @override
  Future<void> cancelListening() async {
    if (_isListening) {
      await _streamSub?.cancel();
      _streamSub = null;
      await _recorder.stop();
    }
    _pcmBuffer.clear();
    _isListening = false;
    _isTranscribing = false;
    _currentText = '';
    _safeNotify();
  }

  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final numSamples = bytes.length ~/ 2;
    final samples = Float32List(numSamples);
    final byteData = ByteData.sublistView(bytes);
    for (int i = 0; i < numSamples; i++) {
      final int16 = byteData.getInt16(i * 2, Endian.little);
      samples[i] = int16 / 32768.0;
    }
    return samples;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _streamSub?.cancel();
    _recorder.dispose();
    _initialized = false;
    super.dispose();
  }
}
