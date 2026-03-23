# Copilot Instructions for BOSTrainer

## Project Overview

BOSTrainer is a voice-based interactive training simulator for German BOS (Behörden und Organisationen mit Sicherheitsaufgaben) radio communication, specifically for Bavarian volunteer fire departments. Users practice realistic radio scenarios via push-to-talk, with AI-powered counterparts (dispatch center, incident commander, crews) responding according to strict BOS radio protocols.

## Architecture

The project has two main components:

### Server (Go) - `server/`
Handles all AI/TTS processing. Clients communicate via WebSocket.

```
server/
├── cmd/server/main.go      # Entry point
└── internal/
    ├── gemini/             # Gemini API client (audio + text)
    ├── tts/                # Edge TTS wrapper
    ├── session/            # Per-client session state
    ├── scenario/           # Scenario loading
    └── websocket/          # WebSocket handler + protocol
```

### Client (HTML5) - `client/`
Lightweight web app handling audio I/O only.

```
client/
├── index.html              # UI structure
├── app.js                  # WebSocket + MediaRecorder
└── style.css               # Styling
```

### Legacy POC (Python) - `src/`
Original CLI-based prototype. Kept for reference.

## Running the Application

### Option 1: Docker (recommended)
```bash
export GEMINI_API_KEY="your-key"
docker-compose up --build
# Open http://localhost:8080
```

### Option 2: Local Development
```bash
# Server (requires Go 1.22+, ffmpeg, edge-tts)
cd server
pip install edge-tts  # or: pipx install edge-tts
export GEMINI_API_KEY="your-key"
go run ./cmd/server

# Open http://localhost:8080
```

### Option 3: Legacy Python POC
```bash
pip install -r requirements.txt
export GEMINI_API_KEY="your-key"
python src/main.py
```

## WebSocket Protocol

Client ↔ Server communication:

```json
// Client → Server
{ "type": "list_scenarios" }
{ "type": "start_session", "scenario_key": "1" }
{ "type": "audio", "data": "<base64 audio>" }
{ "type": "end_session" }

// Server → Client  
{ "type": "scenarios", "scenarios": [...] }
{ "type": "session_started", "briefing": "...", "user_role": "...", "ai_role": "..." }
{ "type": "response", "transcript": "...", "reply": "...", "audio": "<base64 WAV>" }
{ "type": "evaluation", "analysis": "..." }
{ "type": "error", "message": "..." }
```

## Prompt System

Prompts are assembled from multiple files in `prompts/`:
- `base_rules.txt` – Core BOS radio rules (FwDV 810)
- `scenarios/*.txt` – Scenario-specific context (roles, typical flow)
- Variant files for randomized scenarios (e.g., `truppfuehrer_*.txt`)

Assembly order: `scenario_prompt + [variant_prompt] + base_rules`

## Code Conventions

### Audio Format
All audio: 16kHz sample rate, mono, 16-bit signed integer (WAV).

### German Language
All user-facing strings, prompts, and radio content are in German. Code and comments in English.

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
