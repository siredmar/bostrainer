import io
import wave
from pathlib import Path

from piper import PiperVoice

DEFAULT_MODEL = Path(__file__).parent.parent / "models" / "piper" / "de_DE-thorsten_emotional-medium.onnx"


class TextToSpeech:
    """Text-to-speech using Piper."""

    def __init__(self, model_path: str | Path = DEFAULT_MODEL) -> None:
        print(f"   Lade Piper-Modell...")
        self._voice = PiperVoice.load(str(model_path))
        self._sample_rate = self._voice.config.sample_rate
        print(f"   Piper-Modell geladen (sample_rate={self._sample_rate}).")

    def synthesize(self, text: str) -> bytes:
        """Synthesize text to WAV bytes."""
        audio_chunks: list[bytes] = []
        sample_width = 2
        channels = 1

        for chunk in self._voice.synthesize(text):
            audio_chunks.append(chunk.audio_int16_bytes)
            sample_width = chunk.sample_width
            channels = chunk.sample_channels

        buf = io.BytesIO()
        wf = wave.open(buf, "wb")
        wf.setnchannels(channels)
        wf.setsampwidth(sample_width)
        wf.setframerate(self._sample_rate)
        wf.writeframes(b"".join(audio_chunks))
        wf.close()
        return buf.getvalue()
