import 'dart:typed_data';

/// TTS service stub for sherpa-onnx Piper integration.
///
/// This is a placeholder that will be implemented with sherpa_onnx package
/// for on-device text-to-speech using Piper German voice models.
class TtsService {
  bool _initialized = false;
  bool _modelDownloaded = false;

  bool get isInitialized => _initialized;
  bool get isModelDownloaded => _modelDownloaded;

  /// Initialize the TTS engine with Piper model.
  Future<void> initialize({
    void Function(double progress)? onDownloadProgress,
  }) async {
    // TODO: Implement sherpa-onnx Piper initialization
    // 1. Check if model exists in local storage
    // 2. If not, download de_DE-thorsten-medium (~30MB)
    // 3. Initialize sherpa-onnx TTS engine
    _modelDownloaded = true;
    _initialized = true;
  }

  /// Synthesize text to audio (PCM samples).
  Future<Float32List> synthesize(String text) async {
    if (!_initialized) {
      throw StateError('TTS service not initialized');
    }
    final prepared = prepareTtsText(text);
    // TODO: Implement sherpa-onnx TTS synthesis
    // 1. Call tts.generate(prepared)
    // 2. Return audio samples
    return Float32List(0);
  }

  void dispose() {
    // TODO: Clean up sherpa-onnx resources
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
