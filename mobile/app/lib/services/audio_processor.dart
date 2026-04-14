import 'dart:math';
import 'dart:typed_data';

/// DSP audio processor for radio effect simulation.
/// Applies bandpass filter (300–3000 Hz) and white noise overlay.
class AudioProcessor {
  /// Apply radio effects to 16-bit PCM samples.
  ///
  /// [samples] — raw 16-bit PCM data (little-endian).
  /// [sampleRate] — sample rate in Hz (e.g. 22050).
  /// [bandpassEnabled] — apply 300–3000 Hz bandpass filter.
  /// [noiseEnabled] — mix in white noise.
  /// [noiseDb] — noise level in dB relative to full scale (e.g. -35).
  static Uint8List process({
    required Uint8List samples,
    required int sampleRate,
    bool bandpassEnabled = true,
    bool noiseEnabled = true,
    double noiseDb = -35.0,
  }) {
    // Convert bytes to float samples [-1.0, 1.0]
    final numSamples = samples.length ~/ 2;
    final floats = Float64List(numSamples);
    final byteData = ByteData.sublistView(samples);

    for (var i = 0; i < numSamples; i++) {
      final int16 = byteData.getInt16(i * 2, Endian.little);
      floats[i] = int16 / 32768.0;
    }

    // Apply bandpass filter
    if (bandpassEnabled) {
      _applyBiquad(floats, sampleRate, 300.0, FilterType.highPass);
      _applyBiquad(floats, sampleRate, 3000.0, FilterType.lowPass);
    }

    // Add white noise
    if (noiseEnabled) {
      final noiseAmp = pow(10.0, noiseDb / 20.0).toDouble();
      final rng = Random();
      for (var i = 0; i < numSamples; i++) {
        final noise = (rng.nextDouble() * 2.0 - 1.0) * noiseAmp;
        floats[i] = (floats[i] + noise).clamp(-1.0, 1.0);
      }
    }

    // Convert back to 16-bit PCM
    final output = Uint8List(numSamples * 2);
    final outData = ByteData.sublistView(output);
    for (var i = 0; i < numSamples; i++) {
      final clamped = floats[i].clamp(-1.0, 1.0);
      outData.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
    }

    return output;
  }

  /// Second-order biquad filter (Butterworth-style).
  static void _applyBiquad(
    Float64List samples,
    int sampleRate,
    double cutoffHz,
    FilterType type,
  ) {
    final omega = 2.0 * pi * cutoffHz / sampleRate;
    final sinOmega = sin(omega);
    final cosOmega = cos(omega);
    // Q = 0.707 (Butterworth)
    final alpha = sinOmega / (2.0 * 0.707);

    double b0, b1, b2, a0, a1, a2;

    switch (type) {
      case FilterType.lowPass:
        b0 = (1.0 - cosOmega) / 2.0;
        b1 = 1.0 - cosOmega;
        b2 = (1.0 - cosOmega) / 2.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosOmega;
        a2 = 1.0 - alpha;
      case FilterType.highPass:
        b0 = (1.0 + cosOmega) / 2.0;
        b1 = -(1.0 + cosOmega);
        b2 = (1.0 + cosOmega) / 2.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosOmega;
        a2 = 1.0 - alpha;
    }

    // Normalize
    b0 /= a0;
    b1 /= a0;
    b2 /= a0;
    a1 /= a0;
    a2 /= a0;

    // Direct Form I
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (var i = 0; i < samples.length; i++) {
      final x = samples[i];
      final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = x;
      y2 = y1;
      y1 = y;
      samples[i] = y;
    }
  }
}

enum FilterType { lowPass, highPass }
