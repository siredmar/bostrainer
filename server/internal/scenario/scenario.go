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
	Key              string
	Name             string
	Description      string
	UserRole         string
	AIRole           string
	PromptFile       string
	Briefing         string
	FirstMessageHint string
	VariantFiles     []string
	IsDemo           bool // Demo mode: AI plays all roles, user just listens
}

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
	return []*Scenario{
		{
			Key:         "1",
			Name:        "Fahrzeug ↔ Leitstelle",
			Description: "Du fährst als Gruppenführer (MLF) einen Einsatz und kommunizierst mit der Leitstelle",
			UserRole:    "Florian Birkach 47/1 (Gruppenführer MLF)",
			AIRole:      "Leitstelle Roth",
			PromptFile:  "leitstelle.txt",
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
			Briefing:    "", // Set dynamically based on variant
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
		// Demo scenarios - AI plays all roles
		{
			Key:         "demo1",
			Name:        "🎧 Demo: Wasserförderung Schlauchplatzer",
			Description: "Zuhören: Zwei Maschinisten bei einer Wasserförderung - Schlauchplatzer muss behoben werden",
			UserRole:    "(Zuhörer - keine Interaktion)",
			AIRole:      "Florian Waldberg 44/1 & Florian Waldberg 47/1",
			PromptFile:  "demo_wasserfoerderung.txt",
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
	parts = append(parts, string(scenarioPrompt))

	// Add random variant if available
	if len(s.VariantFiles) > 0 {
		variantFile := s.VariantFiles[rand.Intn(len(s.VariantFiles))]
		variantPrompt, err := os.ReadFile(filepath.Join(l.promptsDir, "scenarios", variantFile))
		if err != nil {
			return "", fmt.Errorf("read %s: %w", variantFile, err)
		}
		parts = append(parts, string(variantPrompt))
	}

	parts = append(parts, string(baseRules))

	return strings.Join(parts, "\n\n"), nil
}

// LoadDemoPrompt loads the prompt for a demo scenario (no base rules needed).
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
