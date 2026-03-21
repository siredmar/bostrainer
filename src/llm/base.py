from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum


class Role(Enum):
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"


@dataclass
class Message:
    role: Role
    content: str


@dataclass
class LLMResponse:
    transcript: str
    reply: str


class LLMProvider(ABC):
    """Abstract base class for LLM providers."""

    @abstractmethod
    def setup(self, system_prompt: str) -> None:
        """Initialize the provider with a system prompt."""
        ...

    @abstractmethod
    def send(self, message: str, max_tokens: int = 512) -> str:
        """Send a user message and return the assistant's response.

        The provider is responsible for maintaining conversation history.
        """
        ...

    @abstractmethod
    def send_audio(self, wav_bytes: bytes) -> LLMResponse:
        """Send audio and return transcript + response in one call.

        The provider is responsible for maintaining conversation history.
        """
        ...

    @abstractmethod
    def reset(self) -> None:
        """Reset conversation history, keeping the system prompt."""
        ...
