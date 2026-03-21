import io
import wave

import numpy as np
import sounddevice as sd

SAMPLE_RATE = 16000
CHANNELS = 1
DTYPE = "int16"


def record_until_release() -> bytes:
    """Record audio while Enter is held (press Enter to start, Enter to stop).

    Returns WAV-encoded bytes.
    """
    print("   ⏺  Aufnahme läuft... (Enter drücken zum Stoppen)")
    frames: list[np.ndarray] = []

    def callback(indata: np.ndarray, frame_count: int, time_info: object, status: object) -> None:
        frames.append(indata.copy())

    with sd.InputStream(samplerate=SAMPLE_RATE, channels=CHANNELS, dtype=DTYPE, callback=callback):
        input()

    if not frames:
        return b""

    audio_data = np.concatenate(frames)
    return _to_wav(audio_data)


def play_wav(wav_bytes: bytes) -> None:
    """Play WAV audio bytes through the default output device."""
    buf = io.BytesIO(wav_bytes)
    with wave.open(buf, "rb") as wf:
        rate = wf.getframerate()
        channels = wf.getnchannels()
        data = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16)
        if channels > 1:
            data = data.reshape(-1, channels)
    sd.play(data, samplerate=rate)
    sd.wait()


def _to_wav(audio: np.ndarray) -> bytes:
    """Convert numpy audio array to WAV bytes."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(2)  # 16-bit = 2 bytes
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(audio.tobytes())
    return buf.getvalue()
