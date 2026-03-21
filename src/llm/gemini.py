import os

from google import genai
from google.genai import types

from .base import LLMProvider, LLMResponse, Message, Role

AUDIO_INSTRUCTION = (
    "Der Nutzer sendet dir eine Audio-Aufnahme eines BOS-Funkspruchs. "
    "Antworte im folgenden Format:\n"
    "TRANSKRIPT: <wortgetreue Transkription der Audio-Aufnahme>\n"
    "ANTWORT: <deine Funk-Antwort>"
)


class GeminiProvider(LLMProvider):
    """Google Gemini LLM provider."""

    def __init__(self, model: str = "gemini-2.5-flash") -> None:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            raise RuntimeError("GEMINI_API_KEY environment variable is not set")
        self._client = genai.Client(api_key=api_key)
        self._model = model
        self._system_prompt: str = ""
        self._history: list[Message] = []

    def setup(self, system_prompt: str) -> None:
        self._system_prompt = system_prompt
        self._history = []

    def send(self, message: str, max_tokens: int = 512) -> str:
        self._history.append(Message(role=Role.USER, content=message))

        contents = self._build_contents()
        response = self._generate(contents, max_tokens=max_tokens)

        reply = response.text.strip()
        self._history.append(Message(role=Role.ASSISTANT, content=reply))
        return reply

    def send_audio(self, wav_bytes: bytes) -> LLMResponse:
        contents = self._build_contents()
        contents.append(
            types.Content(
                role="user",
                parts=[
                    types.Part(inline_data=types.Blob(mime_type="audio/wav", data=wav_bytes)),
                    types.Part(text=AUDIO_INSTRUCTION),
                ],
            )
        )

        response = self._generate(contents)
        raw = response.text.strip()

        transcript, reply = self._parse_audio_response(raw)

        self._history.append(Message(role=Role.USER, content=transcript))
        self._history.append(Message(role=Role.ASSISTANT, content=reply))
        return LLMResponse(transcript=transcript, reply=reply)

    def reset(self) -> None:
        self._history = []

    def _build_contents(self) -> list[types.Content]:
        contents = []
        for msg in self._history:
            role = "user" if msg.role == Role.USER else "model"
            contents.append(types.Content(role=role, parts=[types.Part(text=msg.content)]))
        return contents

    def _generate(self, contents: list[types.Content], max_tokens: int = 512) -> types.GenerateContentResponse:
        return self._client.models.generate_content(
            model=self._model,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=self._system_prompt,
                temperature=0.7,
                max_output_tokens=max_tokens,
                thinking_config=types.ThinkingConfig(thinking_budget=0),
            ),
        )

    @staticmethod
    def _parse_audio_response(raw: str) -> tuple[str, str]:
        transcript = ""
        reply = raw

        for line in raw.splitlines():
            upper = line.strip().upper()
            if upper.startswith("TRANSKRIPT:"):
                transcript = line.split(":", 1)[1].strip()
            elif upper.startswith("ANTWORT:"):
                reply = line.split(":", 1)[1].strip()

        if not transcript:
            transcript = "(nicht erkannt)"

        return transcript, reply
