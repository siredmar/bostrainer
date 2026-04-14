import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_processor.dart';

/// Platform TTS service with optional radio effect (bandpass + noise).
class TtsService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  bool _speaking = false;
  String? _tempDir;

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

      final dir = await getTemporaryDirectory();
      _tempDir = dir.path;

      _initialized = true;
      return true;
    } catch (e) {
      _initialized = false;
      return false;
    }
  }

  /// Speak text directly (no radio effects).
  Future<void> speakDirect(String text) async {
    if (!_initialized || text.trim().isEmpty) return;
    final prepared = prepareTtsText(text);
    _speaking = true;
    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      _speaking = false;
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((msg) {
      _speaking = false;
      if (!completer.isCompleted) completer.completeError(Exception('TTS: $msg'));
    });
    _tts.setCancelHandler(() {
      _speaking = false;
      if (!completer.isCompleted) completer.complete();
    });

    await _tts.speak(prepared);
    return completer.future;
  }

  /// Speak text with radio effects (bandpass filter + white noise).
  Future<void> speakWithRadioEffect(
    String text, {
    bool bandpassEnabled = true,
    bool noiseEnabled = true,
    double noiseDb = -35.0,
  }) async {
    if (!_initialized || text.trim().isEmpty || _tempDir == null) return;
    final prepared = prepareTtsText(text);
    _speaking = true;

    try {
      // Synthesize to WAV file
      final wavPath = '$_tempDir/tts_raw.wav';
      final completer = Completer<void>();

      _tts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      _tts.setErrorHandler((msg) {
        if (!completer.isCompleted) completer.completeError(Exception('TTS: $msg'));
      });

      await _tts.synthesizeToFile(prepared, wavPath);
      await completer.future;

      // Read WAV, extract PCM data
      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        _speaking = false;
        return;
      }
      final wavBytes = await wavFile.readAsBytes();
      final parsed = _parseWav(wavBytes);
      if (parsed == null) {
        _speaking = false;
        return;
      }

      // Process audio
      final processed = AudioProcessor.process(
        samples: parsed.pcmData,
        sampleRate: parsed.sampleRate,
        bandpassEnabled: bandpassEnabled,
        noiseEnabled: noiseEnabled,
        noiseDb: noiseDb,
      );

      // Write processed WAV
      final outPath = '$_tempDir/tts_radio.wav';
      final outWav = _buildWav(
        processed,
        sampleRate: parsed.sampleRate,
        channels: parsed.channels,
        bitsPerSample: 16,
      );
      await File(outPath).writeAsBytes(outWav);

      // Play with just_audio
      await _player.setFilePath(outPath);
      final playCompleter = Completer<void>();
      late StreamSubscription sub;
      sub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (!playCompleter.isCompleted) playCompleter.complete();
          sub.cancel();
        }
      });
      await _player.play();
      await playCompleter.future;
    } catch (_) {
      // Non-fatal
    } finally {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    await _player.stop();
    _speaking = false;
  }

  void dispose() {
    _tts.stop();
    _player.dispose();
    _initialized = false;
  }

  /// Parse a WAV file and extract PCM data + metadata.
  _WavData? _parseWav(Uint8List wav) {
    if (wav.length < 44) return null;
    final bd = ByteData.sublistView(wav);

    // "RIFF" header
    if (wav[0] != 0x52 || wav[1] != 0x49 || wav[2] != 0x46 || wav[3] != 0x46) {
      return null;
    }

    // Find "fmt " chunk
    int offset = 12;
    int sampleRate = 22050;
    int channels = 1;
    int bitsPerSample = 16;

    while (offset + 8 < wav.length) {
      final chunkId = String.fromCharCodes(wav.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        channels = bd.getUint16(offset + 10, Endian.little);
        sampleRate = bd.getUint32(offset + 12, Endian.little);
        bitsPerSample = bd.getUint16(offset + 22, Endian.little);
      } else if (chunkId == 'data') {
        final dataStart = offset + 8;
        final dataEnd = dataStart + chunkSize;
        if (dataEnd > wav.length) return null;

        // Convert to 16-bit if needed
        Uint8List pcm;
        if (bitsPerSample == 16) {
          pcm = Uint8List.sublistView(wav, dataStart, dataEnd);
        } else if (bitsPerSample == 8) {
          // 8-bit unsigned → 16-bit signed
          pcm = Uint8List(chunkSize * 2);
          final out = ByteData.sublistView(pcm);
          for (var i = 0; i < chunkSize; i++) {
            final s16 = (wav[dataStart + i] - 128) * 256;
            out.setInt16(i * 2, s16, Endian.little);
          }
        } else {
          return null;
        }

        return _WavData(
          pcmData: pcm,
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: 16,
        );
      }

      offset += 8 + chunkSize;
      if (chunkSize.isOdd) offset++; // padding byte
    }

    return null;
  }

  /// Build a WAV file from 16-bit PCM data.
  Uint8List _buildWav(
    Uint8List pcmData, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final wav = BytesBuilder();

    // RIFF header
    wav.add([0x52, 0x49, 0x46, 0x46]); // "RIFF"
    wav.add(_uint32le(fileSize));
    wav.add([0x57, 0x41, 0x56, 0x45]); // "WAVE"

    // fmt chunk
    wav.add([0x66, 0x6D, 0x74, 0x20]); // "fmt "
    wav.add(_uint32le(16)); // chunk size
    wav.add(_uint16le(1)); // PCM format
    wav.add(_uint16le(channels));
    wav.add(_uint32le(sampleRate));
    wav.add(_uint32le(byteRate));
    wav.add(_uint16le(blockAlign));
    wav.add(_uint16le(bitsPerSample));

    // data chunk
    wav.add([0x64, 0x61, 0x74, 0x61]); // "data"
    wav.add(_uint32le(dataSize));
    wav.add(pcmData);

    return wav.toBytes();
  }

  Uint8List _uint32le(int value) {
    final bd = ByteData(4)..setUint32(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }

  Uint8List _uint16le(int value) {
    final bd = ByteData(2)..setUint16(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }
}

class _WavData {
  final Uint8List pcmData;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  _WavData({
    required this.pcmData,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });
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
