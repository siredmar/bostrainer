import 'package:flutter/foundation.dart';

/// Abstract interface for all STT engine implementations.
///
/// Three behaviors:
/// - **Streaming** (Vosk): partial results arrive during recording
/// - **Record-then-transcribe** (Sherpa): audio buffered in RAM, decoded on stop
/// - **Platform** (speech_to_text): system STT with pauseFor timeout
abstract class SttProvider extends ChangeNotifier {
  /// Whether the provider is ready to accept audio.
  bool get isInitialized;

  /// Whether audio is currently being captured.
  bool get isListening;

  /// Whether transcription is in progress (only relevant for non-streaming).
  bool get isTranscribing;

  /// Whether this provider delivers partial results during recording.
  bool get supportsStreaming;

  /// Current partial or final recognized text.
  String get currentText;

  /// Error message, if any.
  String? get error;

  /// One-time initialization (load model, request permissions, etc.).
  Future<bool> initialize();

  /// Start capturing and recognizing audio.
  Future<void> startListening();

  /// Stop capturing. For streaming providers, returns the final text
  /// immediately. For record-then-transcribe, triggers decoding and returns
  /// the result when complete.
  Future<String> stopListening();

  /// Cancel without producing a result.
  Future<void> cancelListening();
}
