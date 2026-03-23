package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/siredmar/bostrainer/server/internal/gemini"
	"github.com/siredmar/bostrainer/server/internal/scenario"
	"github.com/siredmar/bostrainer/server/internal/tts"
	"github.com/siredmar/bostrainer/server/internal/websocket"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Initialize Gemini client
	geminiClient, err := gemini.NewClient()
	if err != nil {
		log.Fatal(err)
	}
	log.Println("Gemini client initialized")

	// Initialize TTS provider (defaults to Edge TTS)
	ttsProvider, err := tts.NewProvider()
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("TTS initialized: %s", ttsProvider.Name())

	// Initialize scenario loader
	promptsDir := os.Getenv("PROMPTS_DIR")
	if promptsDir == "" {
		// Default: prompts directory relative to server
		promptsDir = filepath.Join("..", "prompts")
	}
	scenarioLoader := scenario.NewLoader(promptsDir)
	log.Printf("Scenario loader initialized (prompts: %s)", promptsDir)

	// Initialize WebSocket hub
	hub := websocket.NewHub()
	go hub.Run()

	// Serve static files from client directory
	clientDir := os.Getenv("CLIENT_DIR")
	if clientDir == "" {
		clientDir = "../client"
	}
	http.Handle("/", http.FileServer(http.Dir(clientDir)))

	// WebSocket endpoint
	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		websocket.ServeWs(hub, geminiClient, ttsProvider, scenarioLoader, w, r)
	})

	log.Printf("Server starting on :%s", port)
	log.Printf("Open http://localhost:%s in your browser", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}
