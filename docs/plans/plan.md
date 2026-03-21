Projektidee (LLM-optimiert)

Ein interaktiver Trainingssimulator für BOS-Sprechfunk (Freiwillige Feuerwehr Bayern).

Der Nutzer befindet sich in einem realitätsnahen Einsatzszenario und kommuniziert per Sprache über simulierten Funk.
Die Gegenstellen (z. B. Leitstelle, andere Fahrzeuge, Trupps) werden durch eine KI gesteuert.

Die Kommunikation folgt strikt den Regeln des BOS-Funks:

    strukturierte Funksprüche

    definierte Funkrufnamen

    klare, kurze Meldungen

    Verwendung von „kommen“ und korrekter Funkdisziplin

Die KI reagiert kontextabhängig auf den Nutzer und entwickelt das Szenario dynamisch weiter.

Nach Abschluss eines Szenarios:

    werden alle Funksprüche analysiert

    strukturell bewertet (Regelkonformität, Klarheit, Vollständigkeit)

    mit Verbesserungsvorschlägen versehen

Ziel ist das realitätsnahe Üben von Sprechfunk unter verschiedenen Einsatzbedingungen.
⚙️ POC Plan (kompakt)
Rahmen

    Plattform: Linux (CLI oder einfache Desktop-App)

    festes Szenario

    feste Funkrufnamen

    Fokus: Audio ↔ KI Loop

Komponenten

STT

    Whisper (lokal)

LLM

    Llama (lokal via Ollama)

    Systemprompt erzwingt BOS-Funkstil

TTS

    Piper (lokal)

Ablauf

    Start:

        KI sendet initiale Alarmierung (TTS)

    Loop:

        Nutzer spricht (Push-to-Talk)

        Audio → Text (STT)

        Text → KI (LLM)

        KI antwortet im Funkstil

        Antwort → Audio (TTS)

    Parallel:

        Speicherung aller Funksprüche (Audio + Text)

Szenario (fest)

    B3 Scheunenbrand

    Rollen:

        Nutzer: Florian Birkach 47/1

        KI: Leitstelle (Florian Roth)

Bewertung (einfach)

    Regelbasierte Checks:

        „kommen“ vorhanden

        korrekte Rufnamen

        Satzlänge

    Score pro Funkspruch

Ergebnisanzeige

    Liste aller Funksprüche

    pro Eintrag:

        Audio Replay

        Transkript

        Score

        Verbesserungsvorschlag

Ziel des POC

    funktionierender End-to-End Voice Loop

    KI spricht im Funkstil

    einfache Auswertung vorhanden

Wenn du willst, kann ich daraus direkt:

    einen exakten Systemprompt (sehr wichtig für Funkstil)

    oder ein startbares Grundprojekt in Go

ableiten.
