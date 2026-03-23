package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/siredmar/bostrainer/server/internal/gemini"
	"github.com/siredmar/bostrainer/server/internal/scenario"
	"github.com/siredmar/bostrainer/server/internal/tlscert"
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

	// TLS setup: generate self-signed cert for HTTPS (required for microphone on non-localhost)
	certDir := os.Getenv("CERT_DIR")
	if certDir == "" {
		certDir = filepath.Join("..", ".certs")
	}

	tlsConfig, err := tlscert.GenerateOrLoad(certDir)
	if err != nil {
		log.Printf("TLS setup failed: %v – falling back to HTTP", err)
		log.Printf("⚠️  Microphone access will only work on localhost!")
		log.Printf("Server starting on http://localhost:%s", port)
		if err := http.ListenAndServe(":"+port, nil); err != nil {
			log.Fatal("ListenAndServe: ", err)
		}
		return
	}

	server := &http.Server{
		Addr:      ":" + port,
		TLSConfig: tlsConfig,
	}

	log.Printf("Server starting on https://localhost:%s (HTTPS)", port)
	log.Printf("📱 Smartphone: Open https://<your-ip>:%s and accept the certificate warning", port)
	if err := server.ListenAndServeTLS("", ""); err != nil {
		log.Fatal("ListenAndServeTLS: ", err)
	}
}
