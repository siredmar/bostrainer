import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Platform STT service using Google Speech (Android) / Apple Speech (iOS).
///
/// Recording and transcription are decoupled from the PTT button:
/// - PTT hold: audio streams to recognizer, partial results shown as preview
/// - PTT release: `stopListening()` tells the engine to finalize, then waits
///   for the final transcript before returning. The caller only sends to the
///   AI once the full text is available.
class SttService extends ChangeNotifier {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _isListening = false;
  bool _isTranscribing = false;
  String _currentText = '';
  String? _error;
  Completer<String>? _finalResultCompleter;

  bool get isInitialized => _initialized;
  bool get isListening => _isListening;
  bool get isTranscribing => _isTranscribing;
  String get currentText => _currentText;
  String? get error => _error;

  Future<bool> initialize() async {
    try {
      _initialized = await _speech.initialize(
        onError: (error) {
          debugPrint('STT error: ${error.errorMsg} (permanent: ${error.permanent})');
          if (error.permanent) {
            _error = error.errorMsg;
            _isListening = false;
            _isTranscribing = false;
            _finalResultCompleter?.complete(_currentText);
            _finalResultCompleter = null;
            notifyListeners();
          }
        },
        onStatus: (status) {
          debugPrint('STT status: $status');
          // When engine signals done, resolve the completer if pending
          if (status == 'done' || status == 'notListening') {
            if (_finalResultCompleter != null && !_finalResultCompleter!.isCompleted) {
              _finalResultCompleter!.complete(_currentText);
            }
            _isTranscribing = false;
            notifyListeners();
          }
        },
      );
      if (!_initialized) {
        _error = 'Spracherkennung nicht verfügbar';
      }
      notifyListeners();
      return _initialized;
    } catch (e) {
      _error = e.toString();
      _initialized = false;
      notifyListeners();
      return false;
    }
  }

  /// Start listening. Calls [onResult] with live partial transcription.
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!_initialized) {
      _error = 'STT nicht initialisiert';
      notifyListeners();
      return;
    }

    _error = null;
    _currentText = '';
    _isListening = true;
    _isTranscribing = false;
    _finalResultCompleter = null;
    notifyListeners();

    await _speech.listen(
      onResult: (result) {
        _currentText = result.recognizedWords;
        onResult(result.recognizedWords, result.finalResult);
        // If we're waiting for final and got it, resolve
        if (result.finalResult &&
            _finalResultCompleter != null &&
            !_finalResultCompleter!.isCompleted) {
          _finalResultCompleter!.complete(_currentText);
        }
      },
      localeId: 'de_DE',
      pauseFor: const Duration(seconds: 60),
      listenFor: const Duration(seconds: 120),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  /// Stop recording and wait for the engine to deliver the final transcript.
  /// Returns the complete recognized text.
  Future<String> stopListening() async {
    _isListening = false;
    _isTranscribing = true;
    notifyListeners();

    // Set up completer to wait for the final result
    _finalResultCompleter = Completer<String>();

    // Tell the engine to stop and finalize
    await _speech.stop();

    // Wait for final result (with timeout to avoid hanging forever)
    final text = await _finalResultCompleter!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => _currentText,
    );

    _isTranscribing = false;
    _finalResultCompleter = null;
    notifyListeners();
    return text;
  }

  Future<void> cancelListening() async {
    await _speech.cancel();
    _isListening = false;
    _isTranscribing = false;
    _currentText = '';
    _finalResultCompleter?.complete('');
    _finalResultCompleter = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.cancel();
    _finalResultCompleter?.complete('');
    _isListening = false;
    _isTranscribing = false;
    _initialized = false;
    super.dispose();
  }
}
