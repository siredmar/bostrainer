import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'stt_provider.dart';

/// STT provider using the platform's built-in speech recognition.
///
/// Uses Android/iOS native STT with a 60-second pause timeout.
/// Delivers partial results while the user is speaking.
class PlatformSttProvider extends SttProvider {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _isListening = false;
  bool _disposed = false;
  String _currentText = '';
  String? _error;

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isListening => _isListening;
  @override
  bool get isTranscribing => false;
  @override
  bool get supportsStreaming => true;
  @override
  String get currentText => _currentText;
  @override
  String? get error => _error;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('[PlatformSTT] Status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            _safeNotify();
          }
        },
        onError: (error) {
          debugPrint('[PlatformSTT] Error: ${error.errorMsg}');
          _error = error.errorMsg;
          _isListening = false;
          _safeNotify();
        },
      );

      if (!available) {
        _error = 'Spracherkennung nicht verfügbar auf diesem Gerät';
        _safeNotify();
        return false;
      }

      _initialized = true;
      _error = null;
      debugPrint('[PlatformSTT] Initialized');
      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('[PlatformSTT] Init error: $e');
      _error = 'Platform-STT-Initialisierung fehlgeschlagen: $e';
      _safeNotify();
      return false;
    }
  }

  @override
  Future<void> startListening() async {
    if (!_initialized || _isListening) return;

    _currentText = '';
    _error = null;

    try {
      await _speech.listen(
        onResult: (result) {
          _currentText = result.recognizedWords;
          debugPrint('[PlatformSTT] ${result.finalResult ? "Final" : "Partial"}: "$_currentText"');
          _safeNotify();
        },
        localeId: 'de_DE',
        pauseFor: const Duration(seconds: 60),
        listenFor: const Duration(seconds: 120),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
      _isListening = true;
      debugPrint('[PlatformSTT] Listening started');
      _safeNotify();
    } catch (e) {
      debugPrint('[PlatformSTT] Start error: $e');
      _error = 'Aufnahme fehlgeschlagen: $e';
      _safeNotify();
    }
  }

  @override
  Future<String> stopListening() async {
    if (!_isListening) return _currentText;

    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('[PlatformSTT] Stop error: $e');
    }

    _isListening = false;
    final result = _currentText;
    debugPrint('[PlatformSTT] Final text: "$result"');
    _safeNotify();
    return result;
  }

  @override
  Future<void> cancelListening() async {
    if (_isListening) {
      try {
        await _speech.cancel();
      } catch (_) {}
    }
    _isListening = false;
    _currentText = '';
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _speech.stop();
    super.dispose();
  }
}
