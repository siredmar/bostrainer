from dataclasses import dataclass
from pathlib import Path

PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


@dataclass
class Scenario:
    key: str
    name: str
    description: str
    user_role: str
    ai_role: str
    prompt_file: str
    briefing: str
    first_message_hint: str

    def load_prompt(self) -> str:
        base_rules = (PROMPTS_DIR / "base_rules.txt").read_text(encoding="utf-8")
        scenario_prompt = (PROMPTS_DIR / "scenarios" / self.prompt_file).read_text(encoding="utf-8")
        return scenario_prompt + "\n\n" + base_rules


SCENARIOS = [
    Scenario(
        key="1",
        name="Fahrzeug ↔ Leitstelle",
        description="Du fährst als Gruppenführer (MLF) einen Einsatz und kommunizierst mit der Leitstelle",
        user_role="Florian Birkach 47/1 (Gruppenführer MLF)",
        ai_role="Leitstelle Roth",
        prompt_file="leitstelle.txt",
        briefing=(
            "B3 – Scheunenbrand in Birkach, Hauptstraße 12.\n"
            "Du wurdest alarmiert und sitzt im MLF.\n"
            "Deine Aufgabe: Melde dich bei der Leitstelle, fahre zur Einsatzstelle,\n"
            "gib eine Lagemeldung ab und führe den Einsatz durch."
        ),
        first_message_hint=(
            '💡 Erster Funkspruch z.B.:\n'
            '   "Leitstelle Roth von Florian Birkach 47/1, sind ausgerückt mit Staffelbesatzung, kommen"'
        ),
    ),
    Scenario(
        key="2",
        name="Gruppenführer ↔ Einsatzleiter",
        description="Du bist Gruppenführer und erhältst Aufträge vom Einsatzleiter vor Ort",
        user_role="Florian Birkach 47/1 (Gruppenführer MLF)",
        ai_role="Florian Birkach 10/1 (Einsatzleiter)",
        prompt_file="einsatzleiter.txt",
        briefing=(
            "B3 – Scheunenbrand in Birkach, Hauptstraße 12.\n"
            "Du bist mit deinem MLF an der Einsatzstelle eingetroffen.\n"
            "Der Einsatzleiter (KdoW) ist bereits vor Ort und gibt dir Aufträge.\n"
            "Deine Aufgabe: Melde dich beim Einsatzleiter und führe seine Befehle aus."
        ),
        first_message_hint=(
            '💡 Erster Funkspruch z.B.:\n'
            '   "Florian Birkach 10/1 von Florian Birkach 47/1, sind an der Einsatzstelle, melde mich einsatzbereit, kommen"'
        ),
    ),
    Scenario(
        key="3",
        name="Gruppenführer ↔ Trupps (Einsatzstellenfunk)",
        description="Du bist Gruppenführer und koordinierst deine Trupps über DMO",
        user_role="Florian Birkach 47/1-1 (Gruppenführer)",
        ai_role="Angriffstrupp / Wassertrupp",
        prompt_file="trupp.txt",
        briefing=(
            "B3 – Scheunenbrand in Birkach, Hauptstraße 12.\n"
            "Du bist Gruppenführer und deine Trupps sind bereit.\n"
            "Deine Aufgabe: Gib dem Angriffstrupp einen Einsatzbefehl\n"
            "(z.B. Innenangriff, Menschenrettung) und koordiniere den Einsatz."
        ),
        first_message_hint=(
            '💡 Erster Funkspruch z.B.:\n'
            '   "Angriffstrupp von Florian Birkach 47/1-1, Auftrag: Innenangriff über den Haupteingang, ein C-Rohr, kommen"'
        ),
    ),
    Scenario(
        key="4",
        name="Truppführer ↔ Gruppenführer (Atemschutzeinsatz)",
        description="Du bist Angriffstruppführer unter Atemschutz und meldest dem Gruppenführer",
        user_role="Angriffstrupp (Florian Birkach 47/1-2)",
        ai_role="Florian Birkach 47/1-1 (Gruppenführer)",
        prompt_file="truppfuehrer.txt",
        briefing=(
            "B3 – Scheunenbrand in Birkach, Hauptstraße 12.\n"
            "Du bist Angriffstruppführer und wurdest gerade unter Atemschutz\n"
            "an der Atemschutzüberwachung angemeldet. Dein Trupp ist einsatzbereit.\n"
            "Deine Aufgabe: Melde dich beim Gruppenführer, nimm den Einsatzauftrag\n"
            "entgegen und melde regelmäßig deine Lage (Sicht, Temperatur, Brandherd, Flaschendruck)."
        ),
        first_message_hint=(
            '💡 Erster Funkspruch z.B.:\n'
            '   "Florian Birkach 47/1-1 von Angriffstrupp, unter Atemschutz angemeldet, einsatzbereit, kommen"'
        ),
    ),
]


def select_scenario() -> Scenario:
    print("=== Szenario auswählen ===\n")
    for s in SCENARIOS:
        print(f"  [{s.key}] {s.name}")
        print(f"      {s.description}")
        print(f"      Du: {s.user_role}")
        print(f"      Gegenstelle: {s.ai_role}")
        print()

    keys = "/".join(s.key for s in SCENARIOS)
    while True:
        choice = input(f"Szenario wählen ({keys}): ").strip()
        for s in SCENARIOS:
            if s.key == choice:
                return s
        print(f"Ungültige Auswahl, bitte {keys} eingeben.")
