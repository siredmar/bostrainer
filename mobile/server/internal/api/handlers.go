package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/siredmar/bostrainer/mobile/server/internal/llm"
	"github.com/siredmar/bostrainer/mobile/server/internal/scenario"
	"github.com/siredmar/bostrainer/mobile/server/internal/session"
)

// Handler holds dependencies for REST API handlers.
type Handler struct {
	geminiClient   *llm.Client
	scenarioLoader *scenario.Loader
	sessionManager *session.Manager
}

// NewHandler creates a new API handler.
func NewHandler(gemini *llm.Client, loader *scenario.Loader, sessions *session.Manager) *Handler {
	return &Handler{
		geminiClient:   gemini,
		scenarioLoader: loader,
		sessionManager: sessions,
	}
}

// RegisterRoutes registers all API routes on the given mux.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/scenarios", h.listScenarios)
	mux.HandleFunc("POST /api/sessions", h.createSession)
	mux.HandleFunc("POST /api/sessions/{id}/message", h.sendMessage)
	mux.HandleFunc("POST /api/sessions/{id}/end", h.endSession)
	mux.HandleFunc("DELETE /api/sessions/{id}", h.deleteSession)
}

// ScenarioResponse is the JSON representation of a scenario.
type ScenarioResponse struct {
	Key         string `json:"key"`
	Name        string `json:"name"`
	Description string `json:"description"`
	UserRole    string `json:"user_role"`
	AIRole      string `json:"ai_role"`
	Category    string `json:"category"`
	IsDemo      bool   `json:"is_demo"`
}

func (h *Handler) listScenarios(w http.ResponseWriter, r *http.Request) {
	scenarios := h.scenarioLoader.GetScenarios()
	resp := make([]ScenarioResponse, len(scenarios))
	for i, s := range scenarios {
		resp[i] = ScenarioResponse{
			Key:         s.Key,
			Name:        s.Name,
			Description: s.Description,
			UserRole:    s.UserRole,
			AIRole:      s.AIRole,
			Category:    s.Category,
			IsDemo:      s.IsDemo,
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

// CreateSessionRequest is the request body for creating a session.
type CreateSessionRequest struct {
	ScenarioKey string `json:"scenario_key"`
}

// CreateSessionResponse is the response for session creation.
type CreateSessionResponse struct {
	SessionID string `json:"session_id"`
	Briefing  string `json:"briefing"`
	UserRole  string `json:"user_role"`
	AIRole    string `json:"ai_role"`
	FirstHint string `json:"first_hint"`
}

func (h *Handler) createSession(w http.ResponseWriter, r *http.Request) {
	var req CreateSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	sc := h.scenarioLoader.GetByKey(req.ScenarioKey)
	if sc == nil {
		writeError(w, http.StatusNotFound, "scenario not found")
		return
	}

	var systemPrompt string
	var err error
	if sc.IsDemo {
		systemPrompt, err = h.scenarioLoader.LoadDemoPrompt(sc)
	} else {
		systemPrompt, err = h.scenarioLoader.LoadPrompt(sc)
	}
	if err != nil {
		log.Printf("Error loading prompt for scenario %s: %v", sc.Key, err)
		writeError(w, http.StatusInternalServerError, "failed to load scenario prompt")
		return
	}

	// Update briefing from variant if applicable
	briefing := sc.Briefing
	if variantName := scenario.GetVariantName(systemPrompt); variantName != "" && briefing == "" {
		briefing = variantName
	}

	sessionID := uuid.New().String()
	h.sessionManager.Create(sessionID, sc, systemPrompt)

	log.Printf("Session created: %s (scenario: %s)", sessionID, sc.Name)

	writeJSON(w, http.StatusCreated, CreateSessionResponse{
		SessionID: sessionID,
		Briefing:  briefing,
		UserRole:  sc.UserRole,
		AIRole:    sc.AIRole,
		FirstHint: sc.FirstMessageHint,
	})
}

// SendMessageRequest is the request body for sending a message.
type SendMessageRequest struct {
	Text string `json:"text"`
}

// SendMessageResponse is the response for a message.
type SendMessageResponse struct {
	Reply      string            `json:"reply"`
	Evaluation *EvaluationResult `json:"evaluation,omitempty"`
}

func (h *Handler) sendMessage(w http.ResponseWriter, r *http.Request) {
	sessionID := r.PathValue("id")
	sess := h.sessionManager.Get(sessionID)
	if sess == nil {
		writeError(w, http.StatusNotFound, "session not found")
		return
	}

	var req SendMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if strings.TrimSpace(req.Text) == "" {
		writeError(w, http.StatusBadRequest, "text is required")
		return
	}

	log.Printf("[%s] Received message (raw): %q", sessionID, req.Text)

	// "Ende" means conversation is over — no AI response needed per BOS protocol
	trimmed := strings.TrimSpace(req.Text)
	// STT engines often append punctuation — strip trailing dots, commas, etc.
	trimmed = strings.TrimRight(trimmed, ".,;:!? ")
	if strings.HasSuffix(strings.ToLower(trimmed), "ende") {
		sess.AddMessage("user", req.Text)
		evalResult := h.generateEvaluation(sessionID, sess)
		h.sessionManager.Delete(sessionID)
		log.Printf("[%s] Session ended via 'Ende' — evaluation generated", sessionID)
		writeJSON(w, http.StatusOK, SendMessageResponse{Reply: "", Evaluation: evalResult})
		return
	}

	// Add user message to history
	sess.AddMessage("user", req.Text)

	// Send to Gemini
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()

	history := sess.GetHistory()
	reply, err := h.geminiClient.SendText(ctx, sess.SystemPrompt, history[:len(history)-1], req.Text)
	if err != nil {
		log.Printf("[%s] Gemini error: %v", sessionID, err)
		writeError(w, http.StatusInternalServerError, "failed to get AI response")
		return
	}

	// Add AI reply to history
	sess.AddMessage("assistant", reply)

	writeJSON(w, http.StatusOK, SendMessageResponse{Reply: reply})
}

// EvaluationResult holds the structured evaluation response.
type EvaluationResult struct {
	Messages     []MessageScore `json:"messages"`
	OverallScore int            `json:"overall_score"`
	Summary      string         `json:"summary"`
	Tips         []string       `json:"tips"`
}

// MessageScore holds the evaluation of a single user message.
type MessageScore struct {
	Number       int      `json:"number"`
	Text         string   `json:"text"`
	Score        int      `json:"score"`
	Correct      []string `json:"correct"`
	Improvements []string `json:"improvements"`
	Errors       []string `json:"errors"`
	Improved     string   `json:"improved"`
}

// EndSessionResponse wraps the evaluation result.
type EndSessionResponse struct {
	Evaluation *EvaluationResult `json:"evaluation"`
}

func (h *Handler) endSession(w http.ResponseWriter, r *http.Request) {
	sessionID := r.PathValue("id")
	sess := h.sessionManager.Get(sessionID)
	if sess == nil {
		writeError(w, http.StatusNotFound, "session not found")
		return
	}

	history := sess.GetHistory()
	if len(history) == 0 {
		writeJSON(w, http.StatusOK, EndSessionResponse{
			Evaluation: &EvaluationResult{
				Messages:     []MessageScore{},
				OverallScore: 0,
				Summary:      "Keine Funksprüche zum Auswerten.",
				Tips:         []string{},
			},
		})
		h.sessionManager.Delete(sessionID)
		return
	}

	evalResult := h.generateEvaluation(sessionID, sess)

	// Clean up session
	h.sessionManager.Delete(sessionID)

	writeJSON(w, http.StatusOK, EndSessionResponse{Evaluation: evalResult})
}

func (h *Handler) deleteSession(w http.ResponseWriter, r *http.Request) {
	sessionID := r.PathValue("id")
	sess := h.sessionManager.Get(sessionID)
	if sess == nil {
		writeError(w, http.StatusNotFound, "session not found")
		return
	}

	h.sessionManager.Delete(sessionID)
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) generateEvaluation(sessionID string, sess *session.Session) *EvaluationResult {
	history := sess.GetHistory()

	userRole := sess.Scenario.UserRole
	aiRole := sess.Scenario.AIRole

	var userMessages []string
	var transcript string
	for _, msg := range history {
		if msg.Role == "user" {
			transcript += fmt.Sprintf("%s (SCHÜLER): %s\n", userRole, msg.Content)
			userMessages = append(userMessages, msg.Content)
		} else {
			transcript += fmt.Sprintf("%s (GEGENSTELLE): %s\n", aiRole, msg.Content)
		}
	}

	// Log chat history for debugging
	log.Printf("[%s] === EVALUATION START ===", sessionID)
	log.Printf("[%s] Scenario: %s", sessionID, sess.Scenario.Name)
	log.Printf("[%s] User role: %s | AI role: %s", sessionID, userRole, aiRole)
	for i, msg := range history {
		log.Printf("[%s] Message %d [%s]: %s", sessionID, i+1, msg.Role, msg.Content)
	}

	evalPrompt := fmt.Sprintf(`Du bist ein erfahrener BOS-Funk-Ausbilder für die Freiwillige Feuerwehr Bayern.

ROLLENVERTEILUNG IN DIESEM SZENARIO:
Szenario: %s
- Der SCHÜLER (Benutzer) funkt als: %s
- Die GEGENSTELLE (KI) funkt als: %s

KONKRETES BEISPIEL FÜR KORREKTEN ANRUF IN DIESEM SZENARIO:
Wenn der Schüler (%s) die Gegenstelle (%s) anruft, lautet der korrekte Funkspruch:
  "%s von %s" (= Gerufener von Rufendem)
Das bedeutet: "%s" steht VOR "von" (= wird gerufen), "%s" steht NACH "von" (= ruft an).
DIESES FORMAT IST KORREKT. Wenn der Schüler genau so funkt, ist die Anruf-Struktur PERFEKT.

Wenn der Schüler auf einen Anruf antwortet: "hier %s"

Bewerte NUR die Nachrichten des SCHÜLERS (%s). Ignoriere alle Nachrichten der GEGENSTELLE (%s).`,
		sess.Scenario.Name,
		userRole, aiRole,
		userRole, aiRole,
		aiRole, userRole,
		aiRole, userRole,
		userRole,
		userRole, aiRole)

	evalPrompt += fmt.Sprintf(`

ABSOLUTE REGEL – SCHREIBWEISE (HÖCHSTE PRIORITÄT):
Texteingabe simuliert gesprochene Sprache (STT-Platzhalter).
Gesprochene Sprache HAT KEINE Groß-/Kleinschreibung.
- "angriffstrupp" = "Angriffstrupp" = IDENTISCH, 0 Punkte Abzug
- "verstanden ende" = "Verstanden Ende" = IDENTISCH, 0 Punkte Abzug
- "%s von %s" = "%s von %s" = IDENTISCH, 0 Punkte Abzug
Vergleiche CASE-INSENSITIVE. Nur INHALT und STRUKTUR zählen.
Im "improved"-Feld: EXAKTE Schreibweise des Schülers beibehalten.
In "improvements"/"errors": NIEMALS Schreibweise erwähnen.
Inhalt+Struktur korrekt = 100%%%%, egal wie geschrieben.`,
		strings.ToLower(aiRole), strings.ToLower(userRole),
		aiRole, userRole)

	evalPrompt += `

FUNKREGELN (FwDV 810):
1. ANRUF-STRUKTUR: "[Gerufener] von [Rufender]"
2. ANTWORT: "Hier [eigener Rufname]"
3. FRAGEN: MUSS mit "Frage" eingeleitet werden (PFLICHT!)
4. "KOMMEN": Bedeutet "Antwort wird erwartet". Wenn der Schüler eine Frage stellt oder eine Antwort braucht, ist "kommen" am Ende KORREKT und NOTWENDIG.
5. "ENDE": Gespräch sofort beendet. Wird verwendet wenn KEINE Antwort mehr erwartet wird.
6. BESTÄTIGUNG: "Verstanden" oder Wiederholung
7. ZAHLEN: Einzeln, "Zwo" statt "Zwei"
8. HÖFLICHKEITSFORMEN: Vermeiden
9. DISKRETION: Keine Personennamen

BEWERTUNGSKRITERIEN (NUR SCHÜLER-Nachrichten):
1. ANRUF-STRUKTUR: Gerufener VOR "von", Rufender NACH "von"?
2. ANTWORT: "Hier [Rufname]"?
3. FRAGEN: Mit "Frage" eingeleitet?
4. KOMMEN/ENDE: Korrekt? ("kommen" bei Fragen = IMMER korrekt!)
5. KLARHEIT: Kurz, klar?
6. RUFNAMEN: Korrekt?
7. MELDUNGSINHALT: Vollständig?
8. ZAHLEN: Einzeln? "Zwo"?
9. HÖFLICHKEITSFORMEN: Vermieden?

NICHT BEWERTEN: Groß-/Kleinschreibung, Interpunktion, Tippfehler.
NUR INHALT UND STRUKTUR. Korrekt = 100%%.

WICHTIGE SCORING-REGEL:
Wenn ein Funkspruch inhaltlich und strukturell KORREKT ist, MUSS der Score 100 sein.
"improvements" und "errors" MÜSSEN dann LEERE Arrays [] sein.
Erfinde KEINE Verbesserungsvorschläge für korrekte Funksprüche!
Nur ECHTE Fehler gegen die obigen Funkregeln dürfen zu Punktabzug führen.

Antworte NUR mit validem JSON:
{
  "messages": [
    {
      "number": 1,
      "text": "Originaler Funkspruch",
      "score": 85,
      "correct": ["Korrekt 1"],
      "improvements": ["Verbesserung 1"],
      "errors": ["Fehler 1"],
      "improved": "Verbesserter Funkspruch (nur Inhalt/Struktur, Schreibweise beibehalten!)"
    }
  ],
  "overall_score": 82,
  "summary": "Zusammenfassung",
  "tips": ["Tipp 1"]
}

SCORE: 90-100%%=Perfekt, 70-89%%=Gut, 50-69%%=Ausreichend, 0-49%%=Mangelhaft`

	evalPrompt += fmt.Sprintf(`

GESPRÄCHSVERLAUF:
%s

Antworte NUR mit dem JSON.`, transcript)

	// Log the full evaluation prompt
	log.Printf("[%s] Evaluation prompt:\n%s", sessionID, evalPrompt)

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	response, err := h.geminiClient.SendTextLong(ctx, "", nil, evalPrompt)
	if err != nil {
		log.Printf("[%s] Evaluation error: %v", sessionID, err)
		return &EvaluationResult{
			Messages:     []MessageScore{},
			OverallScore: 0,
			Summary:      "Auswertung konnte nicht erstellt werden: " + err.Error(),
			Tips:         []string{},
		}
	}

	// Log the raw evaluation response
	log.Printf("[%s] Evaluation raw response:\n%s", sessionID, response)

	cleanedResponse := llm.ExtractJSON(response)

	var evalResult EvaluationResult
	if err := json.Unmarshal([]byte(cleanedResponse), &evalResult); err != nil {
		log.Printf("[%s] Failed to parse evaluation JSON: %v", sessionID, err)
		messages := make([]MessageScore, len(userMessages))
		for i, msg := range userMessages {
			messages[i] = MessageScore{
				Number:       i + 1,
				Text:         msg,
				Score:        0,
				Correct:      []string{},
				Improvements: []string{},
				Errors:       []string{"Auswertung konnte nicht analysiert werden"},
				Improved:     "",
			}
		}
		return &EvaluationResult{
			Messages:     messages,
			OverallScore: 0,
			Summary:      "Fehler bei der Auswertung. Rohantwort: " + response,
			Tips:         []string{},
		}
	}

	// Log parsed evaluation result
	log.Printf("[%s] Evaluation: %d messages, overall score: %d%%",
		sessionID, len(evalResult.Messages), evalResult.OverallScore)
	for _, msg := range evalResult.Messages {
		log.Printf("[%s]   Message %d (score: %d): %s", sessionID, msg.Number, msg.Score, msg.Text)
		if len(msg.Errors) > 0 {
			log.Printf("[%s]     Errors: %v", sessionID, msg.Errors)
		}
		if len(msg.Improvements) > 0 {
			log.Printf("[%s]     Improvements: %v", sessionID, msg.Improvements)
		}
	}
	log.Printf("[%s] === EVALUATION END ===", sessionID)

	return &evalResult
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
