package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/siredmar/bostrainer/mobile/server/internal/api"
	"github.com/siredmar/bostrainer/mobile/server/internal/llm"
	"github.com/siredmar/bostrainer/mobile/server/internal/scenario"
	"github.com/siredmar/bostrainer/mobile/server/internal/session"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Initialize Gemini client (text-only)
	geminiClient, err := llm.NewClient()
	if err != nil {
		log.Fatal(err)
	}
	log.Println("Gemini client initialized (text-only mode)")

	// Initialize scenario loader
	promptsDir := os.Getenv("PROMPTS_DIR")
	if promptsDir == "" {
		promptsDir = filepath.Join("..", "..", "prompts")
	}
	scenarioLoader := scenario.NewLoader(promptsDir)
	log.Printf("Scenario loader initialized (prompts: %s)", promptsDir)

	// Initialize session manager
	sessionManager := session.NewManager()

	// Set up HTTP routes
	mux := http.NewServeMux()
	handler := api.NewHandler(geminiClient, scenarioLoader, sessionManager)
	handler.RegisterRoutes(mux)

	// Health check
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})

	// Apply middleware
	var h http.Handler = mux
	h = api.CORSMiddleware(h)
	h = api.LoggingMiddleware(h)

	log.Printf("Bridge server starting on http://localhost:%s", port)
	if err := http.ListenAndServe(":"+port, h); err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}
