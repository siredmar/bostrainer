import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart';

import 'stt_provider.dart';

/// STT provider using Vosk for real-time streaming recognition.
///
/// Uses Vosk's built-in SpeechService which handles microphone input
/// directly. Delivers partial results while the user is speaking.
class VoskSttProvider extends SttProvider {
  final String modelPath;
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  SpeechService? _speechService;
  Recognizer? _recognizer;

  bool _initialized = false;
  bool _isListening = false;
  bool _disposed = false;
  String _currentText = '';
  String _partialText = '';
  String? _error;

  VoskSttProvider({required this.modelPath});

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isListening => _isListening;
  @override
  bool get isTranscribing => false; // Vosk is always streaming
  @override
  bool get supportsStreaming => true;
  @override
  String get currentText => _partialText.isNotEmpty ? _partialText : _currentText;
  @override
  String? get error => _error;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      debugPrint('[Vosk] Loading model from $modelPath');
      final model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: model,
        sampleRate: 16000,
      );
      _speechService = await _vosk.initSpeechService(_recognizer!);

      _speechService!.onPartial().listen((partial) {
        final decoded = jsonDecode(partial);
        _partialText = (decoded['partial'] ?? '').toString().trim();
        debugPrint('[Vosk] Partial event: "$_partialText"');
        _safeNotify();
      });

      _speechService!.onResult().listen((result) {
        final decoded = jsonDecode(result);
        final text = (decoded['text'] ?? '').toString().trim();
        debugPrint('[Vosk] Result event: "$text"');
        if (text.isNotEmpty) {
          _currentText = text;
          _partialText = '';
          _safeNotify();
        }
      });

      _initialized = true;
      _error = null;
      debugPrint('[Vosk] Initialized');
      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('[Vosk] Init error: $e');
      _error = 'Vosk-Initialisierung fehlgeschlagen: $e';
      _initialized = false;
      _safeNotify();
      return false;
    }
  }

  @override
  Future<void> startListening() async {
    if (!_initialized || _isListening) return;

    _currentText = '';
    _partialText = '';
    _error = null;

    try {
      await _speechService!.start();
      _isListening = true;
      debugPrint('[Vosk] Listening started');
      _safeNotify();
    } catch (e) {
      debugPrint('[Vosk] Start error: $e');
      _error = 'Vosk-Aufnahme fehlgeschlagen: $e';
      _safeNotify();
    }
  }

  @override
  Future<String> stopListening() async {
    if (!_isListening) return _currentText;

    try {
      await _speechService!.stop();
    } catch (e) {
      debugPrint('[Vosk] Stop error: $e');
    }

    // Give Vosk time to deliver the final result event via the stream
    await Future.delayed(const Duration(milliseconds: 200));

    _isListening = false;

    // Use partial if no final result was received
    final result = _currentText.isNotEmpty ? _currentText : _partialText;
    _partialText = '';
    debugPrint('[Vosk] Final text: "$result"');
    _safeNotify();
    return result;
  }

  @override
  Future<void> cancelListening() async {
    if (_isListening) {
      try {
        await _speechService!.stop();
      } catch (_) {}
    }
    _isListening = false;
    _currentText = '';
    _partialText = '';
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _speechService?.stop();
    _recognizer?.dispose();
    super.dispose();
  }
}
