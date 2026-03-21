import asyncio
import io
import subprocess
import wave
from pathlib import Path

import edge_tts


class TextToSpeech:
    """Text-to-speech using Microsoft Edge TTS (high quality, free)."""

    def __init__(self, voice: str = "de-DE-ConradNeural") -> None:
        self._voice = voice
        print(f"   TTS bereit (Edge TTS, Stimme: {voice})")

    def synthesize(self, text: str) -> bytes:
        """Synthesize text to WAV bytes."""
        return asyncio.run(self._synthesize_async(text))

    async def _synthesize_async(self, text: str) -> bytes:
        comm = edge_tts.Communicate(text, voice=self._voice)

        mp3_data = b""
        async for chunk in comm.stream():
            if chunk["type"] == "audio":
                mp3_data += chunk["data"]

        proc = subprocess.run(
            ["ffmpeg", "-i", "pipe:0", "-f", "wav", "-ar", "16000", "-ac", "1", "-loglevel", "quiet", "pipe:1"],
            input=mp3_data,
            capture_output=True,
        )
        return proc.stdout
