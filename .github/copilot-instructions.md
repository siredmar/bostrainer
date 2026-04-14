# Copilot Instructions for BOSTrainer

## Project Overview

BOSTrainer is a voice-based interactive training simulator for German BOS (Behörden und Organisationen mit Sicherheitsaufgaben) radio communication, specifically for Bavarian volunteer fire departments. Users practice realistic radio scenarios via push-to-talk, with AI-powered counterparts (dispatch center, incident commander, crews) responding according to strict BOS radio protocols.

## Build, Test, and Lint

All Go commands run from the `server/` directory. The Makefile wraps these:

```bash
make build          # Build server binary
make test           # Run all Go tests: cd server && go test -v ./...
make lint           # Format + vet (+ golangci-lint if installed)
make fmt            # go fmt ./...
make vet            # go vet ./...
make tidy           # go mod tidy

# Run a single test
cd server && go test -v -run TestFunctionName ./internal/package/

# Docker
make docker-up      # docker-compose up --build (foreground)
make docker-up-d    # detached
make docker-down    # stop
```

**Note:** There are no Go tests yet. The test infrastructure exists but test files need to be created.

## Architecture

**Server (Go)** — `server/`: Handles all AI/TTS processing. Clients communicate via WebSocket on `/ws`. Static files served from `client/` on `/`.

- `cmd/server/main.go` — Entry point. Wires up Gemini client, TTS provider, scenario loader, and WebSocket hub.
- `internal/gemini/` — Gemini API client using raw HTTP REST (no SDK). Uses `gemini-2.5-flash` model, temperature 0.7.
- `internal/tts/` — TTS provider interface with two implementations: Google Translate TTS (`edge`) and Gemini TTS (`gemini`). Selected via `TTS_PROVIDER` env var.
- `internal/session/` — Per-client session state with mutex-protected conversation history.
- `internal/scenario/` — Scenario definitions (hardcoded in Go) and prompt file loading.
- `internal/websocket/` — Hub (client registry) + Client (message handling, audio pipeline).

**Client (HTML5)** — `client/`: Lightweight web app handling audio I/O only. Push-to-talk via MediaRecorder, audio sent as base64 over WebSocket.

**Legacy POC (Python)** — `src/`: Original CLI-based prototype. Kept for reference only.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GEMINI_API_KEY` | Yes | — | Google Gemini API key |
| `TTS_PROVIDER` | No | `edge` | TTS backend: `edge` (Google Translate) or `gemini` |
| `PORT` | No | `8080` | HTTP server port |
| `PROMPTS_DIR` | No | `../prompts` | Path to prompts directory |
| `CLIENT_DIR` | No | `../client` | Path to client static files |

## WebSocket Protocol

Client ↔ Server communication uses JSON messages:

```
Client → Server:  list_scenarios | start_session (scenario_key) | audio (base64 data) | end_session
Server → Client:  scenarios | session_started (briefing, user_role, ai_role) | response (transcript, reply, audio) | evaluation | status | error
```

## Key Conventions

### Gemini Audio Response Format
Gemini returns audio transcription + reply in a structured text format that gets parsed:
```
TRANSKRIPT: <verbatim transcription>
ANTWORT: <radio response>
```
This is parsed by `parseAudioResponse()` in `internal/gemini/client.go`.

### TTS Text Preprocessing
Before sending text to TTS, `PrepareTTSText()` in `internal/tts/service.go`:
1. Sanitizes markdown and control characters
2. Converts radio call signs (`47/1` → `47 1`, `47/1-1` → `47 1 1`) for natural speech
3. Fixes compound word pronunciation (e.g., `Angriffstrupp` → `Angriffs-Trupp`) because TTS engines mispronounce "strupp" as "schtrupp"

### Audio Format
All audio output: WAV format. Edge TTS returns MP3 (sent as-is). Gemini TTS returns raw PCM wrapped to WAV (24kHz, mono, 16-bit). Client sends browser-native format (typically WebM); Gemini auto-detects MIME type.

### Language
All user-facing strings, prompts, and radio content are in **German**. Code and comments in **English**.

### Scenario System
Scenarios are defined as Go structs in `internal/scenario/scenario.go` across three categories:
- **Einsatz-Szenarien** — Interactive fire operation scenarios (user plays a role)
- **DMO-Übungen** — 40 structured radio exercises for practice
- **Demos** — Listen-only scenarios where AI plays all roles

Some scenarios use **variant files** (e.g., `truppfuehrer_*.txt`) randomly selected at session start for replayability.

### Prompt Assembly
System prompts are assembled from files in `prompts/`:
1. Scenario-specific prompt (`scenarios/<file>.txt`)
2. Optional variant prompt (randomly chosen from `VariantFiles`)
3. Base rules (`base_rules.txt` — core BOS/FwDV 810 radio protocol)

## Domain Knowledge

### BOS Radio Rules (FwDV 810)
The `prompts/base_rules.txt` contains authoritative radio protocol rules:
- Call structure: "Empfänger von Sender" (recipient from sender)
- "kommen" = expecting response; no "kommen" or "Ende" = conversation finished
- Questions start with "Frage"
- Numbers spoken individually, "zwei" becomes "zwo"
- No names, no pleasantries

### Bavarian Call Signs
Format: `[Kennwort] [Ort] [Teilkennzahl]/[lfd. Nr.]`
- Example: `Florian Birkach 47/1` = MLF (medium fire engine) #1 from Birkach
- Handheld radios add suffix: `47/1-1` = squad leader's radio
- Reference: `data/funkrufnamen_bayern.md`
