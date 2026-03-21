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
    ),
    Scenario(
        key="2",
        name="Gruppenführer ↔ Einsatzleiter",
        description="Du bist Gruppenführer und erhältst Aufträge vom Einsatzleiter vor Ort",
        user_role="Florian Birkach 47/1 (Gruppenführer MLF)",
        ai_role="Florian Birkach 10/1 (Einsatzleiter)",
        prompt_file="einsatzleiter.txt",
    ),
    Scenario(
        key="3",
        name="Gruppenführer ↔ Trupps (Einsatzstellenfunk)",
        description="Du bist Gruppenführer und koordinierst deine Trupps über DMO",
        user_role="Florian Birkach 47/1-1 (Gruppenführer)",
        ai_role="Angriffstrupp / Wassertrupp",
        prompt_file="trupp.txt",
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

    while True:
        choice = input("Szenario wählen (1/2/3): ").strip()
        for s in SCENARIOS:
            if s.key == choice:
                return s
        print("Ungültige Auswahl, bitte 1, 2 oder 3 eingeben.")
