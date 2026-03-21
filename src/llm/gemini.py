import os

from google import genai
from google.genai import types

from .base import LLMProvider, Message, Role


class GeminiProvider(LLMProvider):
    """Google Gemini LLM provider."""

    def __init__(self, model: str = "gemini-2.0-flash") -> None:
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

    def send(self, message: str) -> str:
        self._history.append(Message(role=Role.USER, content=message))

        contents = []
        for msg in self._history:
            role = "user" if msg.role == Role.USER else "model"
            contents.append(types.Content(role=role, parts=[types.Part(text=msg.content)]))

        response = self._client.models.generate_content(
            model=self._model,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=self._system_prompt,
                temperature=0.7,
                max_output_tokens=256,
            ),
        )

        reply = response.text.strip()
        self._history.append(Message(role=Role.ASSISTANT, content=reply))
        return reply

    def reset(self) -> None:
        self._history = []
