import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Platform TTS service using Android/iOS native text-to-speech.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  Completer<void>? _speakCompleter;

  bool get isInitialized => _initialized;
  bool get isSpeaking => _speaking;

  Future<bool> initialize() async {
    try {
      await _tts.setLanguage('de-DE');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      // Pick a German voice if available
      final voices = await _tts.getVoices;
      if (voices is List) {
        final deVoice = voices.cast<Map>().where(
          (v) => (v['locale'] ?? '').toString().startsWith('de'),
        );
        if (deVoice.isNotEmpty) {
          await _tts.setVoice({
            'name': deVoice.first['name'].toString(),
            'locale': deVoice.first['locale'].toString(),
          });
        }
      }

      _tts.setCompletionHandler(() {
        _speaking = false;
        _speakCompleter?.complete();
        _speakCompleter = null;
      });

      _tts.setErrorHandler((msg) {
        _speaking = false;
        _speakCompleter?.completeError(Exception('TTS error: $msg'));
        _speakCompleter = null;
      });

      _tts.setCancelHandler(() {
        _speaking = false;
        _speakCompleter?.complete();
        _speakCompleter = null;
      });

      _initialized = true;
      return true;
    } catch (e) {
      _initialized = false;
      return false;
    }
  }

  /// Speak text and return a Future that completes when speech is done.
  Future<void> speak(String text) async {
    if (!_initialized || text.trim().isEmpty) return;
    final prepared = prepareTtsText(text);
    _speaking = true;
    _speakCompleter = Completer<void>();
    await _tts.speak(prepared);
    return _speakCompleter!.future;
  }

  Future<void> stop() async {
    if (_speaking) {
      await _tts.stop();
      _speaking = false;
      _speakCompleter?.complete();
      _speakCompleter = null;
    }
  }

  void dispose() {
    _tts.stop();
    _initialized = false;
  }
}

/// Prepare text for TTS by converting radio call signs and fixing pronunciation.
/// Ported from Go: server/internal/tts/service.go PrepareTTSText()
String prepareTtsText(String text) {
  // Sanitize markdown and control characters
  text = text.replaceAll(RegExp(r'[*_#~`]+'), '');
  text = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
  text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  // Convert call signs: 47/1 → 47 1, 47/1-1 → 47 1 1
  text = text.replaceAllMapped(
    RegExp(r'(\d+)/(\d+)(?:-(\d+))?'),
    (m) {
      var result = '${m[1]} ${m[2]}';
      if (m[3] != null) result += ' ${m[3]}';
      return result;
    },
  );

  // Fix compound word pronunciation (TTS says "schtrupp" instead of "trupp")
  const fixes = {
    'Angriffstrupp': 'Angriffs-Trupp',
    'Wassertrupp': 'Wasser-Trupp',
    'Schlauchtrupp': 'Schlauch-Trupp',
    'Sicherheitstrupp': 'Sicherheits-Trupp',
    'Rettungstrupp': 'Rettungs-Trupp',
    'Angriffstruppführer': 'Angriffs-Truppführer',
    'Wassertruppführer': 'Wasser-Truppführer',
    'Schlauchtruppführer': 'Schlauch-Truppführer',
    'Sicherheitstruppführer': 'Sicherheits-Truppführer',
    'Rettungstruppführer': 'Rettungs-Truppführer',
    'Angriffstruppmann': 'Angriffs-Truppmann',
    'Wassertruppmann': 'Wasser-Truppmann',
    'Schlauchtruppmann': 'Schlauch-Truppmann',
    'Sicherheitstruppmann': 'Sicherheits-Truppmann',
  };

  for (final entry in fixes.entries) {
    text = text.replaceAll(entry.key, entry.value);
    // Title case variant
    final titleKey = entry.key[0].toUpperCase() + entry.key.substring(1);
    final titleVal = entry.value[0].toUpperCase() + entry.value.substring(1);
    text = text.replaceAll(titleKey, titleVal);
  }

  return text;
}
