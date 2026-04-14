/// STT service stub for sherpa-onnx whisper integration.
///
/// This is a placeholder that will be implemented with sherpa_onnx package
/// for on-device speech-to-text using whisper models.
class SttService {
  bool _initialized = false;
  bool _modelDownloaded = false;

  bool get isInitialized => _initialized;
  bool get isModelDownloaded => _modelDownloaded;

  /// Initialize the STT engine with whisper model.
  /// Downloads the model on first launch if not present.
  Future<void> initialize({
    void Function(double progress)? onDownloadProgress,
  }) async {
    // TODO: Implement sherpa-onnx whisper initialization
    // 1. Check if model exists in local storage
    // 2. If not, download from HuggingFace (whisper-base ~140MB)
    // 3. Initialize sherpa-onnx offline recognizer
    _modelDownloaded = true;
    _initialized = true;
  }

  /// Transcribe audio data (16kHz PCM) to text.
  Future<String> transcribe(List<double> audioSamples) async {
    if (!_initialized) {
      throw StateError('STT service not initialized');
    }
    // TODO: Implement sherpa-onnx transcription
    // 1. Create OfflineStream
    // 2. Feed audio samples
    // 3. Decode and return text
    return '';
  }

  void dispose() {
    // TODO: Clean up sherpa-onnx resources
    _initialized = false;
  }
}
