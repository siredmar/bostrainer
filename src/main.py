import random
import time

from audio import play_wav, record_until_release
from llm import GeminiProvider
from scenario import select_scenario
from tts import TextToSpeech


def main() -> None:
    print("=== BOS-Funk Trainer ===\n")

    scenario = select_scenario()
    system_prompt = scenario.load_prompt()

    print("Komponenten werden geladen...\n")

    llm = GeminiProvider()
    llm.setup(system_prompt)

    tts = TextToSpeech()

    print()
    print(f"Szenario: {scenario.name}")
    print(f"Du bist: {scenario.user_role}")
    print(f"Gegenstelle: {scenario.ai_role}")
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

        print("   🔄 Verarbeite Funkspruch...")
        result = llm.send_audio(wav_bytes)

        print(f"   📝 Du: {result.transcript}")
        transcript_log.append({"role": "user", "text": result.transcript})

        if "ende" in result.transcript.lower().split():
            print("   📻 Funkverkehr beendet (Ende)")
            break

        delay = random.uniform(1.0, 4.0)
        print(f"   ⏳ Funkverkehr... ({delay:.1f}s)")
        time.sleep(delay)

        print(f"   📻 {scenario.ai_role}: {result.reply}")
        transcript_log.append({"role": "gegenstelle", "text": result.reply})

        response_wav = tts.synthesize(result.reply)
        play_wav(response_wav)
        print()

    print("\n=== Training beendet ===")
    if transcript_log:
        print("\nProtokoll:")
        for i, entry in enumerate(transcript_log, 1):
            role = "DU" if entry["role"] == "user" else scenario.ai_role.upper()
            print(f"  {i:2d}. [{role}] {entry['text']}")


if __name__ == "__main__":
    main()
