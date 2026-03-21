from pathlib import Path

from llm.base import LLMProvider

PROMPTS_DIR = Path(__file__).parent.parent / "prompts"

EVAL_PROMPT = """Du bist ein erfahrener BOS-Funk-Ausbilder für die Freiwillige Feuerwehr Bayern.
Analysiere die folgenden Funksprüche des Schülers anhand der FwDV 810 Funkregeln.

BEWERTUNGSKRITERIEN:
1. ANRUF-STRUKTUR: Korrekte Reihenfolge "Empfänger von Sender"?
2. KOMMEN/ENDE: "kommen" wenn Antwort erwartet, "Ende" zum Beenden?
3. KLARHEIT: Kurz, klar, eindeutig? Keine Umgangssprache?
4. RUFNAMEN: Korrekte Verwendung der Funkrufnamen?
5. MELDUNGSINHALT: Vollständig? Alle relevanten Infos enthalten?
6. ZAHLEN: Einzeln gesprochen? "Zwo" statt "Zwei"?
7. HÖFLICHKEITSFORMEN: Vermieden? Kein "Danke", "Bitte"?
8. DISKRETION: Keine Personennamen genannt?

ANTWORTFORMAT (halte dich exakt daran):

Gib für JEDEN Funkspruch des Schülers folgende Bewertung:

---
FUNKSPRUCH [Nr]: "[Text des Funkspruchs]"
BEWERTUNG: [Gut/Ausreichend/Mangelhaft]
DETAILS:
✅ [Was war korrekt]
⚠️ [Was kann verbessert werden]
❌ [Was war falsch]
VERBESSERUNG: "[Verbesserter Funkspruch so wie er korrekt wäre]"
---

Am Ende:

===
GESAMTBEWERTUNG: [X]%
ZUSAMMENFASSUNG: [2-3 Sätze Gesamteindruck]
TOP 3 VERBESSERUNGSTIPPS:
1. [Wichtigster Tipp]
2. [Zweiter Tipp]
3. [Dritter Tipp]
===
"""


def evaluate_transcript(
    llm: LLMProvider,
    transcript_log: list[dict[str, str]],
    scenario_name: str,
) -> str:
    """Evaluate user radio messages and return detailed analysis."""
    user_messages = [e for e in transcript_log if e["role"] == "user"]
    if not user_messages:
        return "Keine Funksprüche zum Auswerten."

    conversation = []
    for entry in transcript_log:
        role = "SCHÜLER" if entry["role"] == "user" else "GEGENSTELLE"
        conversation.append(f"{role}: {entry['text']}")

    prompt = (
        f"{EVAL_PROMPT}\n\n"
        f"SZENARIO: {scenario_name}\n\n"
        f"GESPRÄCHSVERLAUF:\n" + "\n".join(conversation)
    )

    # Use a fresh LLM call (not the conversation history) for evaluation
    llm.reset()
    return llm.send(prompt, max_tokens=4096)
