import random
import time
from pathlib import Path

from audio import play_wav, record_until_release
from llm import GeminiProvider
from stt import SpeechToText
from tts import TextToSpeech

PROMPT_FILE = Path(__file__).parent.parent / "prompts" / "system_prompt.txt"


def main() -> None:
    system_prompt = PROMPT_FILE.read_text(encoding="utf-8")

    print("=== BOS-Funk Trainer ===")
    print("Komponenten werden geladen...\n")

    llm = GeminiProvider()
    llm.setup(system_prompt)

    stt = SpeechToText()
    tts = TextToSpeech()

    print()
    print("Szenario: B3 Scheunenbrand, Birkach Hauptstraße 12")
    print("Du bist: Florian Birkach 47/1 (MLF)")
    print("Gegenstelle: Leitstelle (Florian Roth)")
    print()
    print("Enter drücken → Aufnahme startet")
    print("Enter drücken → Aufnahme stoppt, Funkspruch wird verarbeitet")
    print("'quit' eintippen + Enter → Beenden")
    print("=" * 40)
    print()

    transcript_log: list[dict[str, str]] = []

    while True:
        cmd = input("🎙  Enter drücken zum Sprechen (oder 'quit'): ").strip()
        if cmd.lower() == "quit":
            break

        wav_bytes = record_until_release()
        if not wav_bytes:
            print("   Keine Aufnahme erkannt.\n")
            continue

        print("   🔄 Transkribiere...")
        user_text = stt.transcribe(wav_bytes)
        if not user_text:
            print("   Kein Text erkannt.\n")
            continue

        print(f"   📝 Du: {user_text}")
        transcript_log.append({"role": "user", "text": user_text})

        delay = random.uniform(1.0, 4.0)
        print(f"   ⏳ Funkverkehr... ({delay:.1f}s)")
        time.sleep(delay)

        response = llm.send(user_text)
        print(f"   📻 Leitstelle: {response}")
        transcript_log.append({"role": "leitstelle", "text": response})

        response_wav = tts.synthesize(response)
        play_wav(response_wav)
        print()

    print("\n=== Training beendet ===")
    if transcript_log:
        print("\nProtokoll:")
        for i, entry in enumerate(transcript_log, 1):
            role = "DU" if entry["role"] == "user" else "LEITSTELLE"
            print(f"  {i:2d}. [{role}] {entry['text']}")


if __name__ == "__main__":
    main()
