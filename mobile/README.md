# BOSTrainer Mobile POC

Cross-platform mobile app (Android + iOS) for BOS radio training with **on-device STT/TTS** and a **server-side LLM bridge**.

## Architecture

```
Mobile App (Flutter)         Bridge Server (Go REST API)
┌─────────────────┐         ┌──────────────────────┐
│ sherpa-onnx STT  │──text──▶│ Gemini LLM (text)    │
│ sherpa-onnx TTS  │◀─text──│ Scenarios + Sessions  │
│ PTT + Chat UI    │         │ Evaluation            │
└─────────────────┘         └──────────────────────┘
```

- **STT**: On-device whisper.cpp via sherpa-onnx (zero cloud cost)
- **TTS**: On-device Piper via sherpa-onnx (zero cloud cost)
- **LLM**: Cloud via bridge server (Gemini 2.5 Flash, text-only)

## Quick Start

### Bridge Server

```bash
# Set your Gemini API key
export GEMINI_API_KEY=your-key-here

# Run directly
cd mobile/server
go run ./cmd/bridge/

# Or with Docker
cd mobile
docker compose up --build
```

The bridge server runs on `http://localhost:8080` by default.

### Flutter App (Docker build — no local Flutter install needed)

```bash
# Release APK
make mobile-apk

# Debug APK
make mobile-apk-debug
```

The APK will be at `mobile/app/build/app/outputs/flutter-apk/`.

If you have Flutter installed locally:
```bash
cd mobile/app
flutter pub get
flutter run
```

### API Endpoints

```
GET  /api/scenarios                    - List all scenarios
POST /api/sessions                     - Create session { scenario_key }
POST /api/sessions/{id}/message        - Send message { text } → { reply }
POST /api/sessions/{id}/end            - End session → { evaluation }
DELETE /api/sessions/{id}              - Delete session
GET  /health                           - Health check
```

### Test with curl

```bash
# List scenarios
curl http://localhost:8080/api/scenarios | jq

# Create session
curl -X POST http://localhost:8080/api/sessions \
  -H 'Content-Type: application/json' \
  -d '{"scenario_key": "1"}' | jq

# Send message (replace SESSION_ID)
curl -X POST http://localhost:8080/api/sessions/SESSION_ID/message \
  -H 'Content-Type: application/json' \
  -d '{"text": "Leitstelle Roth von Florian Birkach 47/1, sind ausgerückt mit Staffelbesatzung, kommen"}' | jq

# End session
curl -X POST http://localhost:8080/api/sessions/SESSION_ID/end | jq
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GEMINI_API_KEY` | Yes | — | Google Gemini API key |
| `PORT` | No | `8080` | HTTP server port |
| `PROMPTS_DIR` | No | `../../prompts` | Path to prompts directory |
| `CORS_ORIGINS` | No | `*` | Allowed CORS origins |

## Project Structure

```
mobile/
├── app/                      # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/           # Data models
│   │   ├── screens/          # UI screens
│   │   ├── services/         # API, STT, TTS services
│   │   └── widgets/          # Reusable widgets
│   └── pubspec.yaml
├── server/                   # Bridge server (Go)
│   ├── cmd/bridge/main.go
│   ├── internal/
│   │   ├── api/              # REST handlers + middleware
│   │   ├── llm/              # Gemini text-only client
│   │   ├── scenario/         # Scenario definitions
│   │   └── session/          # Session management
│   ├── Dockerfile
│   └── go.mod
├── docker-compose.yml
└── README.md
```

## Implementation Status

- [x] **Phase 1**: Bridge Server (Go REST API)
- [x] **Phase 2**: Flutter App Shell (scenarios, chat, evaluation)
- [ ] **Phase 3**: On-Device STT (sherpa-onnx whisper) — stubs created
- [ ] **Phase 4**: On-Device TTS (sherpa-onnx Piper) — stubs + PrepareTTSText ported
- [ ] **Phase 5**: Polish (loading states, model downloads, offline detection)
