import random
import time
from pathlib import Path

from llm import GeminiProvider


PROMPT_FILE = Path(__file__).parent.parent / "prompts" / "system_prompt.txt"


def main() -> None:
    system_prompt = PROMPT_FILE.read_text(encoding="utf-8")

    llm = GeminiProvider()
    llm.setup(system_prompt)

    print("=== BOS-Funk Trainer ===")
    print("Szenario: B3 Scheunenbrand, Birkach Hauptstraße 12")
    print("Du bist: Florian Birkach 47/1")
    print("Gegenstelle: Leitstelle (Florian Roth)")
    print("Eingabe mit Enter senden. 'quit' zum Beenden.\n")

    while True:
        user_input = input("🎙  Du (Florian Birkach 47/1): ").strip()
        if not user_input or user_input.lower() == "quit":
            print("Training beendet.")
            break

        delay = random.uniform(1.0, 4.0)
        print(f"   ⏳ Funkverkehr... ({delay:.1f}s)")
        time.sleep(delay)

        response = llm.send(user_input)
        print(f"📻  Leitstelle (Florian Roth): {response}\n")


if __name__ == "__main__":
    main()
