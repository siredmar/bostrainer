package websocket

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/siredmar/bostrainer/server/internal/gemini"
	"github.com/siredmar/bostrainer/server/internal/scenario"
	"github.com/siredmar/bostrainer/server/internal/tts"
)

const (
	writeWait      = 30 * time.Second
	pongWait       = 120 * time.Second // 2 minutes - enough for long evaluations
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 10 * 1024 * 1024 // 10MB for audio
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for development
	},
}

// Client represents a WebSocket client connection.
type Client struct {
	hub            *Hub
	conn           *websocket.Conn
	send           chan []byte
	id             string
	session        *Session
	geminiClient   *gemini.Client
	ttsProvider    tts.Provider
	scenarioLoader *scenario.Loader
}

// Session holds per-client training state.
type Session struct {
	ScenarioKey  string
	Scenario     *scenario.Scenario
	History      []gemini.Message
	SystemPrompt string
	UserRole     string
	AIRole       string
}

// Message represents a conversation message (for transcript log).
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
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

// IncomingMessage represents a message from the client.
type IncomingMessage struct {
	Type        string `json:"type"`
	ScenarioKey string `json:"scenario_key,omitempty"`
	Data        string `json:"data,omitempty"` // base64 audio
}

// OutgoingMessage represents a message to the client.
type OutgoingMessage struct {
	Type       string `json:"type"`
	Briefing   string `json:"briefing,omitempty"`
	UserRole   string `json:"user_role,omitempty"`
	AIRole     string `json:"ai_role,omitempty"`
	FirstHint  string `json:"first_hint,omitempty"`
	Transcript string `json:"transcript,omitempty"`
	Reply      string `json:"reply,omitempty"`
	Audio      string `json:"audio,omitempty"` // base64 audio
	Analysis   string `json:"analysis,omitempty"`
	Evaluation *EvaluationResult `json:"evaluation,omitempty"` // Structured evaluation
	Message    string `json:"message,omitempty"`
	Status     string `json:"status,omitempty"`     // Current server status
	Progress   string `json:"progress,omitempty"`   // Progress info (e.g., "3/12")
	Scenarios  []ScenarioInfo `json:"scenarios,omitempty"`
	DemoLines  []DemoLine `json:"demo_lines,omitempty"`
}

// sendStatus sends a status update to the client.
func (c *Client) sendStatus(status string, progress string) {
	c.sendJSON(OutgoingMessage{
		Type:     "status",
		Status:   status,
		Progress: progress,
	})
}

// ScenarioInfo provides scenario metadata for client.
type ScenarioInfo struct {
	Key         string `json:"key"`
	Name        string `json:"name"`
	Description string `json:"description"`
	UserRole    string `json:"user_role"`
	AIRole      string `json:"ai_role"`
	IsDemo      bool   `json:"is_demo"`
	Category    string `json:"category"`
}

// DemoLine represents a single line in a demo dialogue.
type DemoLine struct {
	Speaker string `json:"speaker"`
	Text    string `json:"text"`
	Audio   string `json:"audio,omitempty"`
}

// ServeWs handles WebSocket requests from clients.
func ServeWs(hub *Hub, geminiClient *gemini.Client, ttsProvider tts.Provider, scenarioLoader *scenario.Loader, w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	client := &Client{
		hub:            hub,
		conn:           conn,
		send:           make(chan []byte, 256),
		id:             uuid.New().String(),
		geminiClient:   geminiClient,
		ttsProvider:    ttsProvider,
		scenarioLoader: scenarioLoader,
	}

	hub.register <- client

	// Send scenarios immediately on connect
	go func() {
		time.Sleep(100 * time.Millisecond) // Small delay to ensure connection is ready
		client.handleListScenarios()
	}()

	go client.writePump()
	go client.readPump()
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[%s] WebSocket read error: %v", c.id, err)
			} else {
				log.Printf("[%s] WebSocket closed: %v", c.id, err)
			}
			break
		}

		c.handleMessage(message)
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) handleMessage(data []byte) {
	var msg IncomingMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		c.sendError("Invalid message format")
		return
	}

	log.Printf("[%s] Received message type: %s", c.id, msg.Type)

	switch msg.Type {
	case "list_scenarios":
		c.handleListScenarios()
	case "start_session":
		c.handleStartSession(msg.ScenarioKey)
	case "start_demo":
		c.handleStartDemo(msg.ScenarioKey)
	case "audio":
		c.handleAudio(msg.Data)
	case "text":
		// Text simulation for testing (no audio required)
		c.handleTextSimulation(msg.Data)
	case "end_session":
		c.handleEndSession()
	default:
		c.sendError("Unknown message type: " + msg.Type)
	}
}

func (c *Client) handleListScenarios() {
	allScenarios := c.scenarioLoader.GetScenarios()
	scenarios := make([]ScenarioInfo, len(allScenarios))
	for i, s := range allScenarios {
		scenarios[i] = ScenarioInfo{
			Key:         s.Key,
			Name:        s.Name,
			Description: s.Description,
			UserRole:    s.UserRole,
			AIRole:      s.AIRole,
			IsDemo:      s.IsDemo,
			Category:    s.Category,
		}
	}

	c.sendJSON(OutgoingMessage{
		Type:      "scenarios",
		Scenarios: scenarios,
	})
}

func (c *Client) handleStartSession(scenarioKey string) {
	sc := c.scenarioLoader.GetByKey(scenarioKey)
	if sc == nil {
		c.sendError("Unknown scenario: " + scenarioKey)
		return
	}

	systemPrompt, err := c.scenarioLoader.LoadPrompt(sc)
	if err != nil {
		log.Printf("Failed to load prompt: %v", err)
		c.sendError("Failed to load scenario prompt")
		return
	}

	// Get dynamic briefing for variant scenarios
	briefing := sc.Briefing
	if briefing == "" {
		variantName := scenario.GetVariantName(systemPrompt)
		if variantName != "" {
			briefing = "Einsatz: " + variantName + "\nDein Trupp ist unter Atemschutz angemeldet und einsatzbereit."
		}
	}

	c.session = &Session{
		ScenarioKey:  scenarioKey,
		Scenario:     sc,
		History:      []gemini.Message{},
		SystemPrompt: systemPrompt,
		UserRole:     sc.UserRole,
		AIRole:       sc.AIRole,
	}

	c.sendJSON(OutgoingMessage{
		Type:      "session_started",
		Briefing:  briefing,
		UserRole:  sc.UserRole,
		AIRole:    sc.AIRole,
		FirstHint: sc.FirstMessageHint,
	})
}

func (c *Client) handleStartDemo(scenarioKey string) {
	sc := c.scenarioLoader.GetByKey(scenarioKey)
	if sc == nil {
		c.sendError("Unknown scenario: " + scenarioKey)
		return
	}

	if !sc.IsDemo {
		c.sendError("Not a demo scenario")
		return
	}

	c.sendStatus("Demo-Prompt wird geladen...", "")

	// Load demo prompt
	prompt, err := c.scenarioLoader.LoadDemoPrompt(sc)
	if err != nil {
		log.Printf("Failed to load demo prompt: %v", err)
		c.sendError("Failed to load demo")
		return
	}

	// Send briefing first
	c.sendJSON(OutgoingMessage{
		Type:     "demo_started",
		Briefing: sc.Briefing,
		UserRole: sc.UserRole,
		AIRole:   sc.AIRole,
	})

	// System prompt for German radio communication
	systemPrompt := `Du bist ein Experte für BOS-Funk (Behörden und Organisationen mit Sicherheitsaufgaben) in Deutschland.
Du sprichst und schreibst ausschließlich auf Deutsch.
Du kennst die Funkrichtlinien der FwDV 810 und bayerische Rufnamenregelungen.

WICHTIG - Aussprache von Fahrzeugkennungen:
- Schreibe Nummern ausgeschrieben für korrekte TTS-Aussprache
- "44/1" wird NICHT "vierundvierzig Eintel" sondern "vierundvierzig eins"
- "47/1" = "siebenundvierzig eins"  
- "21/1" = "einundzwanzig eins"
- Schreibe also: "Florian Waldberg siebenundvierzig eins" statt "Florian Waldberg 47/1"

WICHTIG - Funkprotokoll (STRIKT EINHALTEN):
- JEDE Antwort auf einen Anruf beginnt mit "Hier": "Hier Florian Waldberg vierundvierzig eins, kommen"
- Anruf-Format: "[Gerufener] von [Rufender], kommen"
- Antwort-Format: "Hier [Eigener Rufname], [Nachricht], kommen"
- Niemals eine Antwort ohne "Hier" am Anfang!
- Bestätigung: "Verstanden"
- Gesprächsende: "Ende"`

	c.sendStatus("Dialog wird generiert (KI)...", "")

	// Generate the demo dialogue
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	dialogueText, err := c.geminiClient.SendText(ctx, systemPrompt, nil, prompt)
	if err != nil {
		log.Printf("Demo generation error: %v", err)
		c.sendError("Failed to generate demo: " + err.Error())
		return
	}

	log.Printf("Generated demo dialogue:\n%s", dialogueText)

	// Parse dialogue lines and generate TTS for each
	lines := c.parseDemoDialogue(dialogueText)
	log.Printf("Parsed %d demo lines", len(lines))
	
	totalLines := len(lines)
	c.sendStatus(fmt.Sprintf("Dialog generiert: %d Funksprüche", totalLines), "")

	// Send each line with TTS audio
	for i, line := range lines {
		log.Printf("Demo line %d: [%s] %s", i, line.Speaker, line.Text)
		
		c.sendStatus(fmt.Sprintf("TTS: %s", line.Speaker), fmt.Sprintf("%d/%d", i+1, totalLines))
		
		audio, err := c.ttsProvider.Synthesize(line.Text)
		if err != nil {
			log.Printf("TTS error for line %d: %v", i, err)
			line.Audio = ""
		} else {
			line.Audio = base64.StdEncoding.EncodeToString(audio)
		}

		c.sendJSON(OutgoingMessage{
			Type:      "demo_line",
			DemoLines: []DemoLine{line},
		})
	}

	// Send demo complete
	c.sendJSON(OutgoingMessage{
		Type:    "demo_complete",
		Message: "Demo beendet",
	})
}

func (c *Client) parseDemoDialogue(text string) []DemoLine {
	var lines []DemoLine
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Parse format: [SPEAKER]: Text or SPEAKER: Text
		if idx := strings.Index(line, "]:"); idx > 0 && strings.HasPrefix(line, "[") {
			speaker := strings.TrimPrefix(line[:idx], "[")
			text := strings.TrimSpace(line[idx+2:])
			if text != "" {
				lines = append(lines, DemoLine{Speaker: speaker, Text: text})
			}
		} else if idx := strings.Index(line, ":"); idx > 0 && idx < 50 {
			speaker := strings.TrimSpace(line[:idx])
			text := strings.TrimSpace(line[idx+1:])
			speakerUpper := strings.ToUpper(speaker)
			// Accept lines with radio callsigns (Florian, Rotkreuz, etc.)
			if text != "" && (strings.HasPrefix(speakerUpper, "FLORIAN") || 
				strings.HasPrefix(speakerUpper, "ROTKREUZ") ||
				strings.HasPrefix(speakerUpper, "PELIKAN") ||
				strings.HasPrefix(speakerUpper, "KATER") ||
				!strings.Contains(speaker, " ")) {
				lines = append(lines, DemoLine{Speaker: speaker, Text: text})
			}
		}
	}
	return lines
}

func (c *Client) handleAudio(base64Audio string) {
	if c.session == nil {
		log.Printf("[%s] handleAudio: No active session", c.id)
		c.sendError("No active session")
		return
	}

	log.Printf("[%s] handleAudio: Decoding audio (%d bytes base64)", c.id, len(base64Audio))

	// Decode base64 audio
	audioData, err := base64.StdEncoding.DecodeString(base64Audio)
	if err != nil {
		log.Printf("[%s] Failed to decode audio: %v", c.id, err)
		c.sendError("Failed to decode audio")
		return
	}

	log.Printf("[%s] Audio decoded: %d bytes", c.id, len(audioData))
	c.sendStatus("Transkription läuft...", "")

	// Send to Gemini for transcription and response (auto-detects MIME type)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	log.Printf("[%s] Sending to Gemini...", c.id)
	resp, err := c.geminiClient.SendAudio(ctx, c.session.SystemPrompt, c.session.History, audioData, "")
	if err != nil {
		log.Printf("[%s] Gemini error: %v", c.id, err)
		c.sendError("Failed to process audio: " + err.Error())
		return
	}

	log.Printf("[%s] Transkript: %s", c.id, resp.Transcript)
	log.Printf("[%s] KI-Antwort: %s", c.id, resp.Reply)
	c.sendStatus("Antwort wird generiert...", "")

	// Check if USER said "Ende" - end session immediately without AI response
	if c.containsEnde(resp.Transcript) {
		log.Printf("[%s] User said 'Ende' - ending session (no response per BOS protocol)", c.id)
		// Add user message to history before ending (for evaluation)
		c.session.History = append(c.session.History,
			gemini.Message{Role: "user", Content: resp.Transcript},
		)
		// Send transcript to client so it's visible in UI (no audio response)
		c.sendJSON(OutgoingMessage{
			Type:       "response",
			Transcript: resp.Transcript,
		})
		// No AI response - "Ende" ends the conversation immediately without confirmation
		c.handleEndSession()
		return
	}

	// Update conversation history
	c.session.History = append(c.session.History,
		gemini.Message{Role: "user", Content: resp.Transcript},
		gemini.Message{Role: "assistant", Content: resp.Reply},
	)

	c.sendStatus("Sprache wird synthetisiert...", "")
	log.Printf("[%s] Starting TTS...", c.id)

	// Synthesize TTS response
	ttsAudio, err := c.ttsProvider.Synthesize(resp.Reply)
	if err != nil {
		log.Printf("[%s] TTS error: %v", c.id, err)
		// Send response without audio
		c.sendJSON(OutgoingMessage{
			Type:       "response",
			Transcript: resp.Transcript,
			Reply:      resp.Reply,
		})
		// Check if conversation ended with "Ende"
		c.checkForEnde(resp.Reply)
		return
	}

	log.Printf("[%s] TTS complete: %d bytes", c.id, len(ttsAudio))

	// Send response with audio
	c.sendJSON(OutgoingMessage{
		Type:       "response",
		Transcript: resp.Transcript,
		Reply:      resp.Reply,
		Audio:      base64.StdEncoding.EncodeToString(ttsAudio),
	})
	
	log.Printf("[%s] Response sent to client", c.id)
	
	// Check if conversation ended with "Ende"
	c.checkForEnde(resp.Reply)
}

// handleTextSimulation handles text input for testing (bypasses audio).
func (c *Client) handleTextSimulation(text string) {
	if c.session == nil {
		log.Printf("[%s] handleTextSimulation: No active session", c.id)
		c.sendError("No active session")
		return
	}

	log.Printf("[%s] Text simulation: %s", c.id, text)
	c.sendStatus("Text wird verarbeitet...", "")

	// Check if USER said "Ende"
	if c.containsEnde(text) {
		log.Printf("[%s] User said 'Ende' - ending session (no response per BOS protocol)", c.id)
		// Add user message to history before ending (for evaluation)
		c.session.History = append(c.session.History,
			gemini.Message{Role: "user", Content: text},
		)
		// Send transcript to client so it's visible in UI (no AI response)
		c.sendJSON(OutgoingMessage{
			Type:       "response",
			Transcript: text,
		})
		// No AI response - "Ende" ends the conversation immediately without confirmation
		c.handleEndSession()
		return
	}

	// Send to Gemini for response (text only, no audio)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	log.Printf("[%s] Sending text to Gemini...", c.id)
	reply, err := c.geminiClient.SendText(ctx, c.session.SystemPrompt, c.session.History, text)
	if err != nil {
		log.Printf("[%s] Gemini error: %v", c.id, err)
		c.sendError("Failed to process text: " + err.Error())
		return
	}

	log.Printf("[%s] KI-Antwort: %s", c.id, reply)

	// Update conversation history
	c.session.History = append(c.session.History,
		gemini.Message{Role: "user", Content: text},
		gemini.Message{Role: "assistant", Content: reply},
	)

	c.sendStatus("Sprache wird synthetisiert...", "")
	log.Printf("[%s] Starting TTS...", c.id)

	// Synthesize TTS response
	ttsAudio, err := c.ttsProvider.Synthesize(reply)
	if err != nil {
		log.Printf("[%s] TTS error: %v", c.id, err)
		// Send response without audio
		c.sendJSON(OutgoingMessage{
			Type:       "response",
			Transcript: text,
			Reply:      reply,
		})
		c.checkForEnde(reply)
		return
	}

	log.Printf("[%s] TTS complete: %d bytes", c.id, len(ttsAudio))

	// Send response with audio
	c.sendJSON(OutgoingMessage{
		Type:       "response",
		Transcript: text,
		Reply:      reply,
		Audio:      base64.StdEncoding.EncodeToString(ttsAudio),
	})

	log.Printf("[%s] Response sent to client", c.id)
	c.checkForEnde(reply)
}

// containsEnde checks if text contains "Ende" as end of conversation.
// Handles common STT variations of "Ende".
func (c *Client) containsEnde(text string) bool {
	text = strings.TrimSpace(text)
	text = strings.ToLower(text)
	
	// Remove trailing punctuation for cleaner matching
	text = strings.TrimRight(text, ".!?,;:")
	
	// Common STT transcriptions of "Ende"
	endeVariants := []string{
		"ende",
		"ente",      // Common mishearing
		"ände",      // Accent variation
		"and",       // English mishearing
		"end",       // English
		"ender",     // Sometimes adds syllable
		"enden",     // Verb form
	}
	
	for _, variant := range endeVariants {
		// Check if text ends with the variant
		if strings.HasSuffix(text, variant) {
			return true
		}
		// Check for ", ende" pattern (with comma before)
		if strings.Contains(text, ", "+variant) || strings.Contains(text, " "+variant+".") {
			return true
		}
	}
	
	return false
}

// checkForEnde checks if the reply ends with "Ende" and auto-terminates the session.
func (c *Client) checkForEnde(reply string) {
	if c.containsEnde(reply) {
		log.Printf("[%s] AI said 'Ende' - auto-terminating session in 3s", c.id)
		// Small delay to let audio play
		go func() {
			time.Sleep(3 * time.Second)
			c.handleEndSession()
		}()
	}
}

func (c *Client) handleEndSession() {
	if c.session == nil {
		log.Printf("[%s] handleEndSession: No active session", c.id)
		c.sendError("No active session")
		return
	}

	log.Printf("[%s] Generating evaluation (history: %d messages)...", c.id, len(c.session.History))
	c.sendStatus("Auswertung wird erstellt...", "")

	// Start a goroutine to send periodic status updates during evaluation
	// This keeps the WebSocket connection alive
	done := make(chan bool)
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		dots := 1
		for {
			select {
			case <-done:
				log.Printf("[%s] Heartbeat goroutine stopped", c.id)
				return
			case <-ticker.C:
				status := "Auswertung wird erstellt" + strings.Repeat(".", dots)
				log.Printf("[%s] Sending heartbeat: %s", c.id, status)
				c.sendStatus(status, "")
				dots = (dots % 3) + 1
			}
		}
	}()

	// Generate structured evaluation
	startTime := time.Now()
	evalResult := c.generateStructuredEvaluation()
	log.Printf("[%s] Evaluation generated in %v", c.id, time.Since(startTime))
	
	// Stop the heartbeat
	close(done)
	
	log.Printf("[%s] Sending evaluation to client (messages: %d, score: %d%%)", 
		c.id, len(evalResult.Messages), evalResult.OverallScore)
	c.sendJSON(OutgoingMessage{
		Type:       "evaluation",
		Evaluation: evalResult,
	})
	log.Printf("[%s] Evaluation sent successfully", c.id)

	c.session = nil
}

func (c *Client) generateStructuredEvaluation() *EvaluationResult {
	if len(c.session.History) == 0 {
		return &EvaluationResult{
			Messages:     []MessageScore{},
			OverallScore: 0,
			Summary:      "Keine Funksprüche zum Auswerten.",
			Tips:         []string{},
		}
	}

	// Collect user messages
	var userMessages []string
	for _, msg := range c.session.History {
		if msg.Role == "user" {
			userMessages = append(userMessages, msg.Content)
		}
	}

	// Build conversation transcript for evaluation
	var transcript string
	for _, msg := range c.session.History {
		if msg.Role == "user" {
			transcript += "SCHÜLER: " + msg.Content + "\n"
		} else {
			transcript += "GEGENSTELLE: " + msg.Content + "\n"
		}
	}

	evalPrompt := `Du bist ein erfahrener BOS-Funk-Ausbilder für die Freiwillige Feuerwehr Bayern.
Analysiere die folgenden Funksprüche des Schülers anhand der FwDV 810 Funkregeln.

FUNKREGELN (FwDV 810) – DIESE REGELN SIND MASSGEBLICH:

1. ANRUF: "Empfänger von Sender" – z.B. "Leitstelle Roth von Florian Birkach 47/1"
2. ANTWORT/ANNAHME: Der Angerufene antwortet mit "Hier [eigener Rufname]" – z.B. "Hier Leitstelle Roth"
   WICHTIG: Die Annahme eines Anrufs erfolgt IMMER mit "Hier", NICHT mit "Empfänger von Sender"!
3. FRAGEN: Jede Frage MUSS mit dem Wort "Frage" eingeleitet werden – z.B. "Frage: Was ist euer Standort?"
   Das Wort "Frage" ist PFLICHT und NICHT überflüssig!
4. "KOMMEN": Am Ende eines Funkspruchs = Antwort wird erwartet
5. "ENDE": Beendet das Gespräch sofort, keine weitere Antwort
6. BESTÄTIGUNG: Einfache Meldungen mit "Verstanden", komplexe mit Wiederholung der Kernpunkte
7. ZAHLEN: Einzeln sprechen. "Zwo" statt "Zwei" (nur alleinstehend)
8. HÖFLICHKEITSFORMEN: Vermeiden (kein "Danke", "Bitte")
9. DISKRETION: Keine Personennamen
10. BUCHSTABIEREN: Bei schwierigen Wörtern mit Buchstabiertafel

BEWERTUNGSKRITERIEN:
1. ANRUF-STRUKTUR: Korrekte Reihenfolge "Empfänger von Sender" beim Anruf?
2. ANTWORT: Annahme mit "Hier [Rufname]"?
3. FRAGEN: Mit "Frage" eingeleitet? (Das ist PFLICHT, nicht optional!)
4. KOMMEN/ENDE: Korrekt verwendet?
5. KLARHEIT: Kurz, klar, eindeutig? Keine Umgangssprache?
6. RUFNAMEN: Korrekte Verwendung der Funkrufnamen?
7. MELDUNGSINHALT: Vollständig? Alle relevanten Infos enthalten?
8. ZAHLEN: Einzeln gesprochen? "Zwo" statt "Zwei"?
9. HÖFLICHKEITSFORMEN: Vermieden?
10. DISKRETION: Keine Personennamen?

WICHTIG: Antworte NUR mit validem JSON im folgenden Format:

{
  "messages": [
    {
      "number": 1,
      "text": "Der originale Funkspruch des Schülers",
      "score": 85,
      "correct": ["Was war korrekt - Punkt 1", "Was war korrekt - Punkt 2"],
      "improvements": ["Was kann verbessert werden"],
      "errors": ["Was war falsch"],
      "improved": "Der verbesserte Funkspruch"
    }
  ],
  "overall_score": 82,
  "summary": "Zusammenfassung in 2-3 Sätzen",
  "tips": ["Verbesserungstipp 1", "Verbesserungstipp 2", "Verbesserungstipp 3"]
}

REGELN FÜR DEN SCORE:
- 90-100%: Perfekt oder nahezu perfekt
- 70-89%: Gut, kleine Verbesserungen möglich
- 50-69%: Ausreichend, mehrere Verbesserungen nötig
- 0-49%: Mangelhaft, grundlegende Fehler

SZENARIO: ` + c.session.Scenario.Name + `

GESPRÄCHSVERLAUF:
` + transcript + `

Antworte NUR mit dem JSON, keine zusätzlichen Erklärungen.`

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Use empty history for evaluation (fresh context) with higher token limit
	response, err := c.geminiClient.SendTextLong(ctx, "", nil, evalPrompt)
	if err != nil {
		log.Printf("Evaluation error: %v", err)
		return &EvaluationResult{
			Messages:     []MessageScore{},
			OverallScore: 0,
			Summary:      "Auswertung konnte nicht erstellt werden: " + err.Error(),
			Tips:         []string{},
		}
	}

	// Try to parse JSON response
	var evalResult EvaluationResult
	
	// Clean up response - extract JSON from markdown code blocks if present
	cleanedResponse := response
	
	// Try to extract JSON from ```json ... ``` block
	if idx := strings.Index(cleanedResponse, "```json"); idx != -1 {
		cleanedResponse = cleanedResponse[idx+7:]
		if endIdx := strings.Index(cleanedResponse, "```"); endIdx != -1 {
			cleanedResponse = cleanedResponse[:endIdx]
		}
	} else if idx := strings.Index(cleanedResponse, "```"); idx != -1 {
		// Generic code block
		cleanedResponse = cleanedResponse[idx+3:]
		if endIdx := strings.Index(cleanedResponse, "```"); endIdx != -1 {
			cleanedResponse = cleanedResponse[:endIdx]
		}
	}
	
	// Also try to find JSON by looking for opening brace
	if startIdx := strings.Index(cleanedResponse, "{"); startIdx != -1 {
		// Find matching closing brace
		braceCount := 0
		endIdx := -1
		for i := startIdx; i < len(cleanedResponse); i++ {
			if cleanedResponse[i] == '{' {
				braceCount++
			} else if cleanedResponse[i] == '}' {
				braceCount--
				if braceCount == 0 {
					endIdx = i + 1
					break
				}
			}
		}
		if endIdx > startIdx {
			cleanedResponse = cleanedResponse[startIdx:endIdx]
		}
	}
	
	cleanedResponse = strings.TrimSpace(cleanedResponse)
	log.Printf("[%s] Cleaned JSON response (first 500 chars): %.500s", c.id, cleanedResponse)
	
	if err := json.Unmarshal([]byte(cleanedResponse), &evalResult); err != nil {
		log.Printf("[%s] Failed to parse evaluation JSON: %v", c.id, err)
		log.Printf("[%s] Raw response: %s", c.id, response)
		
		// Fallback: Create basic evaluation from user messages
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

	log.Printf("[%s] Evaluation parsed successfully: %d messages, overall score: %d%%", 
		c.id, len(evalResult.Messages), evalResult.OverallScore)
	
	return &evalResult
}

func (c *Client) sendJSON(msg OutgoingMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("[%s] JSON marshal error: %v", c.id, err)
		return
	}
	log.Printf("[%s] Sending message type=%s size=%d bytes", c.id, msg.Type, len(data))
	c.send <- data
}

func (c *Client) sendError(message string) {
	c.sendJSON(OutgoingMessage{
		Type:    "error",
		Message: message,
	})
}
