package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// Message types (matching server)
type IncomingMessage struct {
	Type        string `json:"type"`
	ScenarioKey string `json:"scenario_key,omitempty"`
	Data        string `json:"data,omitempty"`
}

type OutgoingMessage struct {
	Type       string            `json:"type"`
	Briefing   string            `json:"briefing,omitempty"`
	UserRole   string            `json:"user_role,omitempty"`
	AIRole     string            `json:"ai_role,omitempty"`
	FirstHint  string            `json:"first_hint,omitempty"`
	Transcript string            `json:"transcript,omitempty"`
	Reply      string            `json:"reply,omitempty"`
	Audio      string            `json:"audio,omitempty"`
	Analysis   string            `json:"analysis,omitempty"`
	Evaluation *EvaluationResult `json:"evaluation,omitempty"`
	Message    string            `json:"message,omitempty"`
	Status     string            `json:"status,omitempty"`
	Progress   string            `json:"progress,omitempty"`
	Scenarios  []ScenarioInfo    `json:"scenarios,omitempty"`
	DemoLines  []DemoLine        `json:"demo_lines,omitempty"`
}

type EvaluationResult struct {
	Messages     []MessageScore `json:"messages"`
	OverallScore int            `json:"overall_score"`
	Summary      string         `json:"summary"`
	Tips         []string       `json:"tips"`
}

type MessageScore struct {
	Number       int      `json:"number"`
	Text         string   `json:"text"`
	Score        int      `json:"score"`
	Correct      []string `json:"correct"`
	Improvements []string `json:"improvements"`
	Errors       []string `json:"errors"`
	Improved     string   `json:"improved"`
}

type ScenarioInfo struct {
	Key         string `json:"key"`
	Name        string `json:"name"`
	Description string `json:"description"`
	UserRole    string `json:"user_role"`
	AIRole      string `json:"ai_role"`
	IsDemo      bool   `json:"is_demo"`
}

type DemoLine struct {
	Speaker string `json:"speaker"`
	Text    string `json:"text"`
	Audio   string `json:"audio,omitempty"`
}

var (
	serverURL = flag.String("url", "ws://localhost:8080/ws", "WebSocket server URL")
	verbose   = flag.Bool("v", false, "Verbose output")
)

func main() {
	flag.Parse()

	log.SetFlags(log.Ltime | log.Lmicroseconds)
	log.Printf("Connecting to %s...", *serverURL)

	conn, _, err := websocket.DefaultDialer.Dial(*serverURL, nil)
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer conn.Close()

	log.Println("Connected!")

	// Handle interrupt
	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)

	// Channel for received messages
	done := make(chan struct{})

	// Read messages from server
	go func() {
		defer close(done)
		for {
			_, message, err := conn.ReadMessage()
			if err != nil {
				log.Printf("Read error: %v", err)
				return
			}
			handleMessage(message)
		}
	}()

	// Interactive command loop
	go func() {
		reader := bufio.NewReader(os.Stdin)
		printHelp()

		for {
			fmt.Print("\n> ")
			input, err := reader.ReadString('\n')
			if err != nil {
				log.Printf("Input error: %v", err)
				return
			}

			input = strings.TrimSpace(input)
			if input == "" {
				continue
			}

			parts := strings.SplitN(input, " ", 2)
			cmd := strings.ToLower(parts[0])

			switch cmd {
			case "help", "h", "?":
				printHelp()

			case "scenarios", "list", "ls":
				// Request scenarios from server
				sendMessage(conn, IncomingMessage{
					Type: "list_scenarios",
				})

			case "start", "s":
				if len(parts) < 2 {
					log.Println("Usage: start <scenario_key>")
					continue
				}
				sendMessage(conn, IncomingMessage{
					Type:        "start_session",
					ScenarioKey: parts[1],
				})

			case "demo", "d":
				if len(parts) < 2 {
					log.Println("Usage: demo <scenario_key>")
					continue
				}
				sendMessage(conn, IncomingMessage{
					Type:        "start_demo",
					ScenarioKey: parts[1],
				})

			case "text", "t", "say":
				if len(parts) < 2 {
					log.Println("Usage: text <message>")
					continue
				}
				sendMessage(conn, IncomingMessage{
					Type: "text",
					Data: parts[1],
				})

			case "audio", "a":
				if len(parts) < 2 {
					log.Println("Usage: audio <base64_audio_data>")
					continue
				}
				sendMessage(conn, IncomingMessage{
					Type: "audio",
					Data: parts[1],
				})

			case "end", "e":
				sendMessage(conn, IncomingMessage{
					Type: "end_session",
				})

			case "ping":
				sendMessage(conn, IncomingMessage{
					Type: "ping",
				})

			case "raw":
				if len(parts) < 2 {
					log.Println("Usage: raw <json>")
					continue
				}
				if err := conn.WriteMessage(websocket.TextMessage, []byte(parts[1])); err != nil {
					log.Printf("Send error: %v", err)
				}

			case "quit", "q", "exit":
				log.Println("Bye!")
				conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
				time.Sleep(100 * time.Millisecond)
				os.Exit(0)

			default:
				log.Printf("Unknown command: %s", cmd)
				printHelp()
			}
		}
	}()

	// Wait for interrupt or connection close
	select {
	case <-done:
		log.Println("Connection closed")
	case <-interrupt:
		log.Println("Interrupted")
		conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
		select {
		case <-done:
		case <-time.After(time.Second):
		}
	}
}

func printHelp() {
	fmt.Println(`
Commands:
  list, ls           - List scenarios (received on connect)
  start <key>        - Start a training session
  demo <key>         - Start a demo
  end                - End current session
  audio <base64>     - Send audio data
  raw <json>         - Send raw JSON message
  quit, q            - Exit

Example:
  start leitstelle_brand
  demo demo1
  end
`)
}

func sendMessage(conn *websocket.Conn, msg IncomingMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Marshal error: %v", err)
		return
	}
	log.Printf(">>> Sending: %s", string(data))
	if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
		log.Printf("Send error: %v", err)
	}
}

func handleMessage(data []byte) {
	var msg OutgoingMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		log.Printf("<<< Raw: %s", string(data))
		return
	}

	log.Printf("<<< Received: type=%s", msg.Type)

	switch msg.Type {
	case "scenarios":
		fmt.Println("\n=== Available Scenarios ===")
		for _, s := range msg.Scenarios {
			demo := ""
			if s.IsDemo {
				demo = " [DEMO]"
			}
			fmt.Printf("  %-20s %s%s\n", s.Key, s.Name, demo)
			if *verbose {
				fmt.Printf("    %s\n", s.Description)
				fmt.Printf("    User: %s | AI: %s\n", s.UserRole, s.AIRole)
			}
		}

	case "session_started":
		fmt.Println("\n=== Session Started ===")
		fmt.Printf("Briefing: %s\n", msg.Briefing)
		fmt.Printf("Your role: %s\n", msg.UserRole)
		fmt.Printf("AI role: %s\n", msg.AIRole)
		if msg.FirstHint != "" {
			fmt.Printf("Hint: %s\n", msg.FirstHint)
		}

	case "demo_started":
		fmt.Println("\n=== Demo Started ===")
		fmt.Printf("Briefing: %s\n", msg.Briefing)

	case "demo_line":
		if len(msg.DemoLines) > 0 {
			line := msg.DemoLines[0]
			fmt.Printf("\n[%s]: %s\n", line.Speaker, line.Text)
			if line.Audio != "" {
				fmt.Printf("  (audio: %d bytes)\n", len(line.Audio))
			}
		}

	case "demo_complete":
		fmt.Println("\n=== Demo Complete ===")

	case "response":
		fmt.Println("\n=== Response ===")
		fmt.Printf("You said: %s\n", msg.Transcript)
		fmt.Printf("AI reply: %s\n", msg.Reply)
		if msg.Audio != "" {
			fmt.Printf("  (audio: %d bytes)\n", len(msg.Audio))
		}

	case "evaluation":
		fmt.Println("\n=== Evaluation ===")
		if msg.Evaluation != nil {
			fmt.Printf("\n📊 GESAMTSCORE: %d%%\n", msg.Evaluation.OverallScore)
			fmt.Printf("📝 %s\n", msg.Evaluation.Summary)
			
			if len(msg.Evaluation.Messages) > 0 {
				fmt.Println("\n--- Funksprüche ---")
				for _, m := range msg.Evaluation.Messages {
					fmt.Printf("\nFunkspruch %d [%d%%]: \"%s\"\n", m.Number, m.Score, m.Text)
					for _, c := range m.Correct {
						fmt.Printf("  ✅ %s\n", c)
					}
					for _, i := range m.Improvements {
						fmt.Printf("  ⚠️  %s\n", i)
					}
					for _, e := range m.Errors {
						fmt.Printf("  ❌ %s\n", e)
					}
					if m.Improved != "" {
						fmt.Printf("  💡 Besser: \"%s\"\n", m.Improved)
					}
				}
			}
			
			if len(msg.Evaluation.Tips) > 0 {
				fmt.Println("\n--- Tipps ---")
				for i, tip := range msg.Evaluation.Tips {
					fmt.Printf("  %d. %s\n", i+1, tip)
				}
			}
		} else if msg.Analysis != "" {
			fmt.Println(msg.Analysis)
		}

	case "status":
		status := msg.Status
		if msg.Progress != "" {
			status += fmt.Sprintf(" (%s)", msg.Progress)
		}
		fmt.Printf("Status: %s\n", status)

	case "error":
		fmt.Printf("\n!!! ERROR: %s\n", msg.Message)

	default:
		if *verbose {
			fmt.Printf("Unknown message type: %s\n", msg.Type)
			fmt.Printf("Full message: %s\n", string(data))
		}
	}
}
