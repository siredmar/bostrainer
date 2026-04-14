package scenario

import (
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
)

// Scenario defines a training scenario.
type Scenario struct {
	Key              string `json:"key"`
	Name             string `json:"name"`
	Description      string `json:"description"`
	UserRole         string `json:"user_role"`
	AIRole           string `json:"ai_role"`
	PromptFile       string `json:"-"`
	Briefing         string `json:"briefing"`
	FirstMessageHint string `json:"first_hint"`
	VariantFiles     []string `json:"-"`
	IsDemo           bool   `json:"is_demo"`
	Category         string `json:"category"`
}

const (
	CategoryEinsatz = "Einsatz-Szenarien"
	CategoryDMO     = "Sprechfunkübungen im DMO-Betrieb"
	CategoryDemo    = "Demos"
)

// Loader loads scenarios from the prompts directory.
type Loader struct {
	promptsDir string
}

// NewLoader creates a scenario loader.
func NewLoader(promptsDir string) *Loader {
	return &Loader{promptsDir: promptsDir}
}

// GetScenarios returns all available scenarios.
func (l *Loader) GetScenarios() []*Scenario {
	scenarios := []*Scenario{}
	standardSzenarios := []*Scenario{
		{
			Key:         "1",
			Name:        "Fahrzeug ↔ Leitstelle",
			Description: "Du fährst als Gruppenführer (MLF) einen Einsatz und kommunizierst mit der Leitstelle",
			UserRole:    "Florian Birkach 47/1 (Gruppenführer MLF)",
			AIRole:      "Leitstelle Roth",
			PromptFile:  "leitstelle.txt",
			Category:    CategoryEinsatz,
			Briefing: `B3 – Scheunenbrand in Birkach, Hauptstraße 12.
Du wurdest alarmiert und sitzt im MLF.
Deine Aufgabe: Melde dich bei der Leitstelle, fahre zur Einsatzstelle,
gib eine Lagemeldung ab und führe den Einsatz durch.`,
			FirstMessageHint: `💡 Erster Funkspruch z.B.:
   "Leitstelle Roth von Florian Birkach 47/1, sind ausgerückt mit Staffelbesatzung, kommen"`,
		},
		{
			Key:         "2",
			Name:        "Gruppenführer ↔ Einsatzleiter",
			Description: "Du bist Gruppenführer und erhältst Aufträge vom Einsatzleiter vor Ort",
			UserRole:    "Florian Birkach 47/1 (Gruppenführer MLF)",
			AIRole:      "Florian Birkach 10/1 (Einsatzleiter)",
			PromptFile:  "einsatzleiter.txt",
			Category:    CategoryEinsatz,
			Briefing: `B3 – Scheunenbrand in Birkach, Hauptstraße 12.
Du bist mit deinem MLF an der Einsatzstelle eingetroffen.
Der Einsatzleiter (KdoW) ist bereits vor Ort und gibt dir Aufträge.
Deine Aufgabe: Melde dich beim Einsatzleiter und führe seine Befehle aus.`,
			FirstMessageHint: `💡 Erster Funkspruch z.B.:
   "Florian Birkach 10/1 von Florian Birkach 47/1, sind an der Einsatzstelle, melde mich einsatzbereit, kommen"`,
		},
		{
			Key:         "3",
			Name:        "Gruppenführer ↔ Trupps (Einsatzstellenfunk)",
			Description: "Du bist Gruppenführer und koordinierst deine Trupps über DMO",
			UserRole:    "Florian Birkach 47/1 (Gruppenführer)",
			AIRole:      "Angriffstrupp / Wassertrupp",
			PromptFile:  "trupp.txt",
			Category:    CategoryEinsatz,
			Briefing: `B3 – Scheunenbrand in Birkach, Hauptstraße 12.
Du bist Gruppenführer und deine Trupps sind bereit.
Deine Aufgabe: Gib dem Angriffstrupp einen Einsatzbefehl
(z.B. Innenangriff, Menschenrettung) und koordiniere den Einsatz.`,
			FirstMessageHint: `💡 Erster Funkspruch z.B.:
   "Angriffstrupp von Florian Birkach 47/1, Auftrag: Innenangriff über den Haupteingang, ein C-Rohr, kommen"`,
		},
		{
			Key:         "4",
			Name:        "Truppführer ↔ Gruppenführer (Atemschutzeinsatz)",
			Description: "Du bist Angriffstruppführer unter Atemschutz – zufälliges Einsatzszenario",
			UserRole:    "Angriffstrupp",
			AIRole:      "Florian Birkach 47/1 (Gruppenführer)",
			PromptFile:  "truppfuehrer_base.txt",
			Category:    CategoryEinsatz,
			Briefing:    "",
			FirstMessageHint: `💡 Erster Funkspruch z.B.:
   "Florian Birkach 47/1 von Angriffstrupp, unter Atemschutz angemeldet, einsatzbereit, kommen"`,
			VariantFiles: []string{
				"truppfuehrer_scheunenbrand.txt",
				"truppfuehrer_kellerbrand.txt",
				"truppfuehrer_zimmerbrand.txt",
				"truppfuehrer_dachstuhl.txt",
				"truppfuehrer_tiefgarage.txt",
			},
		},
	}

	demoSzenarios := []*Scenario{
		{
			Key:         "demo1",
			Name:        "🎧 Demo: Wasserförderung Schlauchplatzer",
			Description: "Zuhören: Zwei Maschinisten bei einer Wasserförderung - Schlauchplatzer muss behoben werden",
			UserRole:    "(Zuhörer - keine Interaktion)",
			AIRole:      "Florian Waldberg 44/1 & Florian Waldberg 47/1",
			PromptFile:  "demo_wasserfoerderung.txt",
			Category:    CategoryDemo,
			Briefing: `🎧 DEMO-MODUS - Nur Zuhören

Waldbrand mit Wasserförderung über lange Wegstrecke (800m, 3 Pumpen).
Plötzlich fällt bei Pumpe 2 der Eingangsdruck ab - ein Schlauch ist geplatzt.

Du hörst den Funkverkehr zwischen:
• Florian Waldberg 44/1 (Pumpe 1, Wasserentnahme)
• Florian Waldberg 47/1 (Pumpe 2, Verstärker)

Beobachte, wie die Maschinisten das Problem kommunizieren und lösen.`,
			FirstMessageHint: `🎧 Klicke "Demo starten" um den Funkverkehr zu hören`,
			IsDemo:           true,
		},
	}

	dmoExercises := l.getDMOExercises()
	scenarios = append(scenarios, dmoExercises...)
	scenarios = append(scenarios, standardSzenarios...)
	scenarios = append(scenarios, demoSzenarios...)

	return scenarios
}

// getDMOExercises returns all 40 DMO exercise scenarios.
func (l *Loader) getDMOExercises() []*Scenario {
	return []*Scenario{
		{Key: "dmo-01", Name: "1. Standort erfragen", Description: "Fragen Sie die Gegenstelle nach dem Standort",
			UserRole: "Schlauchtrupp", AIRole: "Angriffstrupp", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_01.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie die Gegenstelle nach ihrem Standort.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Standort, kommen"`},
		{Key: "dmo-02", Name: "2. Eigenen Standort mitteilen", Description: "Teilen Sie der Gegenstelle Ihren Standort mit",
			UserRole: "Angriffstrupp", AIRole: "Gruppenführer", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_02.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Teilen Sie der Gegenstelle Ihren eigenen Standort mit.", FirstMessageHint: `"[Gegenstelle] von [Rufname], mein Standort: [Ort], kommen"`},
		{Key: "dmo-03", Name: "3. Lautstärke-Durchsage", Description: "Durchsage an alle: Lautstärke prüfen",
			UserRole: "Gruppenführer", AIRole: "Übungsteilnehmer", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_03.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Geben Sie an die Gruppe die Durchsage, dass alle die Lautstärke prüfen sollen.", FirstMessageHint: `"An alle von [Rufname], überprüft die Lautstärke..."`},
		{Key: "dmo-04", Name: "4. Verletzte Person gefunden", Description: "Melden Sie dem Staffelführer eine verletzte Person",
			UserRole: "Angriffstruppführer", AIRole: "Florian Birkach 44/1", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_04.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Melden Sie als Angriffstruppführer, dass Sie eine verletzte Person gefunden haben.", FirstMessageHint: `"Florian Birkach 44/1 von Angriffstrupp, verletzte Person gefunden..."`},
		{Key: "dmo-05", Name: "5. Gruppenwechsel anordnen", Description: "Ordnen Sie einen Gruppenwechsel mit Rückmeldung an",
			UserRole: "Gruppenführer", AIRole: "Übungsteilnehmer", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_05.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Ordnen Sie einen Gruppenwechsel in 1 Minute an und fordern Sie Rückmeldung.", FirstMessageHint: `"An alle von [Rufname], Gruppenwechsel auf [Gruppe] in einer Minute..."`},
		{Key: "dmo-06", Name: "6. Kennwort Rotes Kreuz", Description: "Fragen Sie nach dem Kennwort für das Rote Kreuz",
			UserRole: "Angriffstrupp", AIRole: "Leitstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_06.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Kennwort für das Rote Kreuz.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Kennwort für das Rote Kreuz, kommen"`},
		{Key: "dmo-07", Name: "7. Rauchentwicklung - Rückfrage", Description: "Starke Rauchentwicklung ohne PA - soll ich weiter vorgehen?",
			UserRole: "Angriffstrupp", AIRole: "Florian Birkach 44/1", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_07.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Sie sind ohne PA im Gebäude und stellen starke Rauchentwicklung fest. Fragen Sie, ob Sie weiter vorgehen sollen.", FirstMessageHint: `"Florian Birkach 44/1 von [Trupp], starke Rauchentwicklung, sollen wir weiter vorgehen..."`},
		{Key: "dmo-08", Name: "8. Ordnungskennzahl TSF (buchstabieren)", Description: "Fragen Sie nach der Ordnungskennzahl für TSF und buchstabieren Sie",
			UserRole: "Schlauchtrupp", AIRole: "Leitstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_08.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der Ordnungskennzahl für ein TSF und buchstabieren Sie die Abkürzung.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Ordnungskennzahl für Theodor Samuel Friedrich, kommen"`},
		{Key: "dmo-09", Name: "9. Einsatzauftrag erfragen", Description: "Erkundigen Sie sich beim Einsatzleiter nach Ihrem Auftrag",
			UserRole: "Staffelführer TSF", AIRole: "Florian Birkach 10/1 (Einsatzleiter)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_09.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Erkundigen Sie sich als Staffelführer des TSF beim Einsatzleiter nach Ihrem Einsatzauftrag.", FirstMessageHint: `"Florian Birkach 10/1 von Florian Birkach 44/1, erkundige mich nach Einsatzauftrag..."`},
		{Key: "dmo-10", Name: "10. Brand unter Kontrolle", Description: "Melden Sie dem Staffelführer, dass der Brand unter Kontrolle ist",
			UserRole: "Angriffstrupp", AIRole: "Florian Birkach 44/1 (Staffelführer)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_10.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Geben Sie als Angriffstrupp Rückmeldung, dass der Brand unter Kontrolle ist.", FirstMessageHint: `"Florian Birkach 44/1 von Angriffstrupp, Brand unter Kontrolle, kommen"`},
		{Key: "dmo-11", Name: "11. Repeater schalten (Sicherheitstrupp)", Description: "Auftrag: Auf Repeater schalten und Rückmeldung anfordern",
			UserRole: "Sicherheitstrupp (unter PA)", AIRole: "Angriffstrupp", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_11.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Sie erhalten den Auftrag auf Repeater zu schalten. Bestätigen Sie und fordern Sie Rückmeldung vom Angriffstrupp.", FirstMessageHint: `"Angriffstrupp von Sicherheitstrupp, Repeater geschaltet, bestätigt Empfang, kommen"`},
		{Key: "dmo-12", Name: "12. Repeaterempfang bestätigen", Description: "Überprüfen und melden Sie den Repeaterempfang",
			UserRole: "Angriffstrupp", AIRole: "Sicherheitstrupp", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_12.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Überprüfen Sie den Repeaterempfang auf Ihrem Display und geben Sie Rückmeldung.", FirstMessageHint: `"Sicherheitstrupp von Angriffstrupp, Repeaterempfang vorhanden, kommen"`},
		{Key: "dmo-13", Name: "13. TMO-Verbindung erfragen", Description: "Fragen Sie den Maschinisten nach TMO-Verbindung zur Leitstelle",
			UserRole: "Trupp", AIRole: "Maschinist", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_13.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie beim Maschinisten nach, ob er im TMO Verbindung zur Leitstelle hat.", FirstMessageHint: `"Florian Birkach 44/1 Maschinist von [Trupp], Frage: Haben Sie TMO-Verbindung, kommen"`},
		{Key: "dmo-14", Name: "14. TMO-Verbindung bestätigen", Description: "Geben Sie als Maschinist Rückmeldung zur TMO-Verbindung",
			UserRole: "Maschinist", AIRole: "Trupp", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_14.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Geben Sie als Maschinist die Rückmeldung, dass TMO-Verbindung zur Leitstelle besteht.", FirstMessageHint: `"[Trupp] von Florian Birkach 44/1 Maschinist, TMO-Verbindung zur Leitstelle vorhanden, kommen"`},
		{Key: "dmo-15", Name: "15. Förderstrom erfragen", Description: "Fragen Sie bei der Einsatzleitung nach dem benötigten Förderstrom",
			UserRole: "Trupp", AIRole: "Florian Birkach 10/1 (Einsatzleiter)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_15.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Sie haben den Auftrag die Wasserentnahmestelle herzurichten. Fragen Sie nach dem benötigten Förderstrom.", FirstMessageHint: `"Florian Birkach 10/1 von [Trupp], Frage: Welcher Förderstrom wird benötigt, kommen"`},
		{Key: "dmo-16", Name: "16. Kennwort Malteser", Description: "Fragen Sie nach dem Kennwort für den Malteser-Hilfsdienst",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_16.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Kennwort für den Malteser-Hilfsdienst.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Kennwort für den Malteser-Hilfsdienst, kommen"`},
		{Key: "dmo-17", Name: "17. Lagemeldung anfordern", Description: "Rufen Sie den Wassertrupp und fordern Sie eine Lagemeldung an",
			UserRole: "Gruppenführer", AIRole: "Wassertrupp", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_17.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Rufen Sie als Gruppenführer den Wassertrupp und fordern Sie eine Lagemeldung an.", FirstMessageHint: `"Wassertrupp von Florian Birkach 47/1, Lagemeldung, kommen"`},
		{Key: "dmo-18", Name: "18. Kennwort DLRG", Description: "Fragen Sie nach dem Kennwort für die DLRG",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_18.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Kennwort für die DLRG.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Kennwort für die DLRG, kommen"`},
		{Key: "dmo-19", Name: "19. Wasserversorgungsauftrag weitergeben", Description: "Geben Sie den Auftrag zur Wasserversorgung an den Zugführer",
			UserRole: "Melder/Sprechfunker Einsatzleiter", AIRole: "Florian Birkach 11/1 (Zugführer)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_19.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Teilen Sie dem Zugführer mit: Wasserversorgung für 2 B- und 3 C-Rohre, Wasserentnahme vom Teich an der Hauptstraße.", FirstMessageHint: `"Florian Birkach 11/1 von Florian Birkach 10/1 Melder, Auftrag vom Einsatzleiter..."`},
		{Key: "dmo-20", Name: "20. Ordnungskennzahl GW-G (buchstabieren)", Description: "Fragen Sie nach der Ordnungskennzahl für GW-G und buchstabieren Sie",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_20.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der Ordnungskennzahl für einen Gerätewagen Gefahrgut und buchstabieren Sie GW-G.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Ordnungskennzahl für Gustav Wilhelm Strich Gustav, kommen"`},
		{Key: "dmo-21", Name: "21. Feuerwehrleinen auf LF", Description: "Fragen Sie nach der Anzahl der Feuerwehrleinen auf einem LF",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_21.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der Anzahl der Feuerwehrleinen auf einem Löschgruppenfahrzeug.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Wie viele Feuerwehrleinen auf einem LF, kommen"`},
		{Key: "dmo-22", Name: "22. Widerstandslinie melden", Description: "Melden Sie dem Einsatzleiter den Aufbau einer Widerstandslinie",
			UserRole: "Gruppenführer", AIRole: "Florian Birkach 10/1 (Einsatzleiter)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_22.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Melden Sie dem Einsatzleiter, dass Ihre Gruppe die Widerstandslinie zwischen Scheune und Wohnhaus aufbaut.", FirstMessageHint: `"Florian Birkach 10/1 von Florian Birkach 47/1, Gruppe führt Auftrag aus..."`},
		{Key: "dmo-23", Name: "23. Ordnungskennzahl TLF 2000", Description: "Fragen Sie nach der Ordnungskennzahl für ein TLF 2000",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_23.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der Ordnungskennzahl für ein Tanklöschfahrzeug TLF 2000.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Ordnungskennzahl für TLF 2000, kommen"`},
		{Key: "dmo-24", Name: "24. MAYDAY - Notruf", Description: "Setzen Sie einen Notruf (Mayday) ab - Truppmann gestürzt",
			UserRole: "Angriffstruppführer (unter PA)", AIRole: "Florian Birkach 47/1 (Gruppenführer)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_24.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Ihr Truppmann ist gestürzt und kann sich nicht bewegen. Setzen Sie den Notruf ab. Nach ca. 1 Minute: Mayday beenden.", FirstMessageHint: `"Mayday, Mayday, Mayday, hier Angriffstrupp..."`},
		{Key: "dmo-25", Name: "25. Wasserversorgung aufgebaut", Description: "Melden Sie dem Gruppenführer, dass die Wasserversorgung steht",
			UserRole: "Wassertrupp", AIRole: "Florian Birkach 47/1 (Gruppenführer)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_25.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Melden Sie als Wassertrupp, dass die Wasserversorgung aufgebaut ist und Sie bereit sind.", FirstMessageHint: `"Florian Birkach 47/1 von Wassertrupp, Wasserversorgung aufgebaut, stehen bereit, kommen"`},
		{Key: "dmo-26", Name: "26. Brandherd nicht erreicht", Description: "Melden Sie dem Gruppenführer, dass der Brandherd noch nicht erreicht ist",
			UserRole: "Angriffstruppführer", AIRole: "Florian Birkach 47/1 (Gruppenführer)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_26.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Sie sind bei einem Kellerbrand. Geben Sie dem Gruppenführer die Lagemeldung, dass der Brandherd noch nicht erreicht ist.", FirstMessageHint: `"Florian Birkach 47/1 von Angriffstrupp, Brandherd noch nicht erreicht..."`},
		{Key: "dmo-27", Name: "27. Ordnungskennzahl DLK 23", Description: "Fragen Sie nach der Ordnungskennzahl für eine DLK 23",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_27.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der Ordnungskennzahl für eine Drehleiter DLK 23.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Ordnungskennzahl für DLK 23, kommen"`},
		{Key: "dmo-28", Name: "28. Wasserversorgung mit Buchstabieren", Description: "Geben Sie einen Wasserversorgungsauftrag mit buchstabiertem Namen",
			UserRole: "Sprechfunker Einsatzleiter", AIRole: "Florian Birkach 47/1 (Gruppenführer)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_28.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Geben Sie den Auftrag: Wasserversorgung für 1 B- und 2 C-Rohre, Wasserentnahme vom unterirdischen Behälter bei Fa. Mayer (buchstabieren!).", FirstMessageHint: `"Florian Birkach 47/1 von Florian Birkach 10/1 Melder, Auftrag: Wasserversorgung... Firma Martha Anton Ypsilon Emil Richard..."`},
		{Key: "dmo-29", Name: "29. Polizei-Funkrufname erfragen", Description: "Fragen Sie nach dem Funkrufnamen der zuständigen Polizeidienststelle",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_29.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Funkrufnamen der für den Standort zuständigen Polizeidienststelle.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Funkrufname der zuständigen Polizeidienststelle, kommen"`},
		{Key: "dmo-30", Name: "30. Fahrzeug zu UTM-Koordinate", Description: "Schicken Sie ein Fahrzeug zu einer UTM-Koordinate",
			UserRole: "Übungsleiter", AIRole: "Florian Birkach 22/1 (Staffelführer TLF 2000)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_30.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Geben Sie dem TLF 2000 den Auftrag, zur UTM-Koordinate PV 124 076 zu fahren und sich bei der Einsatzleitung zu melden.", FirstMessageHint: `"Florian Birkach 22/1 von [Rufname], Auftrag: Fahrt zu Paula Viktor 124 076..."`},
		{Key: "dmo-31", Name: "31. Einheitsstärke mitteilen", Description: "Teilen Sie dem Ausbilder die Stärke Ihrer Einheit mit",
			UserRole: "Einheitsführer", AIRole: "Ausbilder", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_31.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Teilen Sie dem Ausbilder die Stärke Ihrer Einheit mit (Format: 1/5/6).", FirstMessageHint: `"Ausbilder von [Rufname], melde Einheitsstärke: 1 Schrägstrich 5 Schrägstrich 6, kommen"`},
		{Key: "dmo-32", Name: "32. Gruppenwechsel an alle (Gruppenruf)", Description: "Teilen Sie allen Teilnehmern einen Gruppenwechsel auf 307_F mit",
			UserRole: "Übungsleiter", AIRole: "Übungsteilnehmer", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_32.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Teilen Sie in einem Gruppenruf mit, dass ein Gruppenwechsel auf 307_F stattfindet (nicht wirklich ausführen).", FirstMessageHint: `"An alle von [Rufname], Gruppenwechsel auf 307_F, kommen"`},
		{Key: "dmo-33", Name: "33. Löschzug eingetroffen", Description: "Melden Sie dem Einsatzleiter das Eintreffen eines Löschzugs",
			UserRole: "Sprechfunker Zugführer", AIRole: "Florian Birkach 10/1 (Einsatzleiter)", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_33.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Melden Sie: Löschzug mit KdoW, zwei HLF 20 und einer DLK 23 eingetroffen, Zugführer meldet sich in Kürze.", FirstMessageHint: `"Florian Birkach 10/1 von [Rufname], Löschzug mit KdoW, zwo HLF 20 und DLK 23 eingetroffen..."`},
		{Key: "dmo-34", Name: "34. Kennwort THW", Description: "Fragen Sie nach dem Kennwort für das THW",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_34.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Kennwort für das Technische Hilfswerk.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Kennwort für das THW, kommen"`},
		{Key: "dmo-35", Name: "35. Kennwort Staatsministerium", Description: "Fragen Sie nach dem Kennwort für das Bayerische Staatsministerium des Innern",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_35.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Kennwort für das Bayerische Staatsministerium des Innern.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Kennwort für das Bayerische Staatsministerium des Innern, kommen"`},
		{Key: "dmo-36", Name: "36. Rettungshubschrauber Rufname", Description: "Fragen Sie nach dem Rufnamen des zuständigen Rettungshubschraubers",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_36.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Rufnamen des für den Standort zuständigen Rettungshubschraubers.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Rufname des zuständigen Rettungshubschraubers, kommen"`},
		{Key: "dmo-37", Name: "37. Kennwort DLRG (Wiederholung)", Description: "Fragen Sie nach dem Kennwort für die DLRG",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_37.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach dem Kennwort für die DLRG.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Kennwort für die DLRG, kommen"`},
		{Key: "dmo-38", Name: "38. Ordnungskennzahl LF 20", Description: "Fragen Sie nach der Ordnungskennzahl für ein LF 20",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_38.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der Ordnungskennzahl für ein Löschgruppenfahrzeug LF 20.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Ordnungskennzahl für LF 20, kommen"`},
		{Key: "dmo-39", Name: "39. Ordnungskennzahl LF 10", Description: "Fragen Sie nach der zweiten Teilkennzahl für ein LF 10",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_39.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der zweiten Teilkennzahl (Ordnungskennzahl) für ein Löschgruppenfahrzeug LF 10.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Ordnungskennzahl für LF 10, kommen"`},
		{Key: "dmo-40", Name: "40. Ordnungskennzahl MZF (buchstabieren)", Description: "Fragen Sie nach der Ordnungskennzahl für MZF und buchstabieren Sie",
			UserRole: "Übungsteilnehmer", AIRole: "Gegenstelle", PromptFile: "dmo_base.txt", VariantFiles: []string{"dmo_aufgabe_40.txt"}, Category: CategoryDMO,
			Briefing: "Aufgabe: Fragen Sie nach der Ordnungskennzahl für ein Mehrzweckfahrzeug und buchstabieren Sie MZF.", FirstMessageHint: `"[Gegenstelle] von [Rufname], Frage: Ordnungskennzahl für Martha Zacharias Friedrich, kommen"`},
	}
}

// GetByKey returns a scenario by its key.
func (l *Loader) GetByKey(key string) *Scenario {
	for _, s := range l.GetScenarios() {
		if s.Key == key {
			return s
		}
	}
	return nil
}

// LoadPrompt loads and assembles the full system prompt for a scenario.
func (l *Loader) LoadPrompt(s *Scenario) (string, error) {
	baseRules, err := os.ReadFile(filepath.Join(l.promptsDir, "base_rules.txt"))
	if err != nil {
		return "", fmt.Errorf("read base_rules.txt: %w", err)
	}

	scenarioPrompt, err := os.ReadFile(filepath.Join(l.promptsDir, "scenarios", s.PromptFile))
	if err != nil {
		return "", fmt.Errorf("read %s: %w", s.PromptFile, err)
	}

	var parts []string
	parts = append(parts, string(baseRules))
	parts = append(parts, string(scenarioPrompt))

	if len(s.VariantFiles) > 0 {
		variantFile := s.VariantFiles[rand.Intn(len(s.VariantFiles))]
		variantPrompt, err := os.ReadFile(filepath.Join(l.promptsDir, "scenarios", variantFile))
		if err != nil {
			return "", fmt.Errorf("read %s: %w", variantFile, err)
		}
		parts = append(parts, string(variantPrompt))
	}

	return strings.Join(parts, "\n\n"), nil
}

// LoadDemoPrompt loads the prompt for a demo scenario.
func (l *Loader) LoadDemoPrompt(s *Scenario) (string, error) {
	prompt, err := os.ReadFile(filepath.Join(l.promptsDir, "scenarios", s.PromptFile))
	if err != nil {
		return "", fmt.Errorf("read %s: %w", s.PromptFile, err)
	}
	return string(prompt), nil
}

// GetVariantName extracts the scenario name from a loaded prompt.
func GetVariantName(prompt string) string {
	for _, line := range strings.Split(prompt, "\n") {
		if strings.HasPrefix(line, "EINSATZ:") {
			return strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		}
	}
	return ""
}
