import io
import wave

import numpy as np
from faster_whisper import WhisperModel


class SpeechToText:
    """Speech-to-text using faster-whisper."""

    def __init__(self, model_size: str = "base") -> None:
        print(f"   Lade Whisper-Modell '{model_size}'...")
        self._model = WhisperModel(model_size, device="cpu", compute_type="int8")
        print("   Whisper-Modell geladen.")

    def transcribe(self, wav_bytes: bytes) -> str:
        """Transcribe WAV audio bytes to text."""
        audio = self._wav_to_float(wav_bytes)
        segments, _ = self._model.transcribe(audio, language="de", beam_size=5)
        return " ".join(seg.text.strip() for seg in segments).strip()

    @staticmethod
    def _wav_to_float(wav_bytes: bytes) -> np.ndarray:
        """Convert WAV bytes to float32 numpy array (mono, 16kHz)."""
        buf = io.BytesIO(wav_bytes)
        with wave.open(buf, "rb") as wf:
            data = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16)
        return data.astype(np.float32) / 32768.0
