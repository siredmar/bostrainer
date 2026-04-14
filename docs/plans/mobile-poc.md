# Mobile POC Plan: BOSTrainer App

## Overview

Cross-platform mobile app (Android + iOS) for BOS radio training with **on-device STT/TTS** and a **server-side LLM bridge**. The app lives in `mobile/` at the repository root.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Mobile App (Flutter)                  │
│                  Android + iOS + (Web)                   │
│                                                         │
│  ┌────────────────┐          ┌────────────────────────┐ │
│  │ whisper.cpp     │          │ Piper TTS              │ │
│  │ via sherpa-onnx │          │ via sherpa-onnx         │ │
│  │ (on-device STT) │          │ (on-device TTS)        │ │
│  │ ~140MB model    │          │ ~30MB German voice      │ │
│  └──────┬─────────┘          └──────────▲─────────────┘ │
│         │ text (user transcript)        │ text (AI reply)│
│         ▼                               │               │
│  ┌──────────────────────────────────────┘             │ │
│  │          REST/WebSocket to Bridge Server            │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          │ text only
                          ▼
┌─────────────────────────────────────────────────────────┐
│              Bridge Server (Go, REST API)                │
│                   mobile/server/                         │
│                                                         │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐ │
│  │ Scenarios │  │ Sessions  │  │ Gemini LLM Client    │ │
│  │ + Prompts │  │ Manager   │  │ (text-only, no audio)│ │
│  └──────────┘  └───────────┘  └──────────────────────┘ │
│                                                         │
│  Future: Auth, billing, rate limiting, usage tracking    │
└─────────────────────────────────────────────────────────┘
```

### Why This Split

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **STT** | On-device (whisper.cpp/sherpa-onnx) | Zero cloud cost, works offline, short radio messages are ideal |
| **TTS** | On-device (Piper/sherpa-onnx) | Zero cloud cost, low latency, German voices available |
| **LLM** | Cloud via bridge server | Radio protocol intelligence requires large model; Gemini 2.5 Flash is cheap ($0.0005/interaction text-only) |
| **Bridge server** | Separate Go service | Enables future auth, billing, rate limiting, usage analytics; hides API key from client |
| **Framework** | Flutter | Single codebase for Android + iOS; sherpa-onnx has official Flutter bindings |

## Directory Structure

```
mobile/
├── app/                          # Flutter app
│   ├── android/
│   ├── ios/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── scenario_list.dart    # Scenario selection
│   │   │   ├── training_session.dart # PTT + conversation UI
│   │   │   └── evaluation.dart       # Post-session evaluation
│   │   ├── services/
│   │   │   ├── stt_service.dart      # sherpa-onnx whisper wrapper
│   │   │   ├── tts_service.dart      # sherpa-onnx piper wrapper
│   │   │   └── api_service.dart      # Bridge server REST client
│   │   ├── models/
│   │   │   ├── scenario.dart
│   │   │   ├── session.dart
│   │   │   └── evaluation.dart
│   │   └── widgets/
│   │       ├── ptt_button.dart       # Push-to-talk button
│   │       ├── transcript_list.dart  # Conversation log
│   │       └── audio_player.dart     # TTS playback
│   ├── assets/
│   │   └── models/                   # Bundled or downloaded on first launch
│   │       ├── whisper-base/         # ~140MB (download on first launch)
│   │       └── piper-de-thorsten/    # ~30MB (download on first launch)
│   └── pubspec.yaml
│
├── server/                       # Bridge server (Go)
│   ├── cmd/bridge/main.go
│   ├── internal/
│   │   ├── api/
│   │   │   ├── handlers.go       # REST handlers
│   │   │   └── middleware.go     # CORS, logging, (future: auth)
│   │   ├── llm/
│   │   │   └── gemini.go         # Gemini text-only client (reuse from server/)
│   │   ├── session/
│   │   │   └── manager.go        # Session state + conversation history
│   │   └── scenario/
│   │       └── loader.go         # Reuse scenario definitions from server/
│   ├── go.mod
│   └── go.sum
│
├── docker-compose.yml            # Bridge server containerized
└── README.md
```

## Bridge Server REST API

The bridge server is **text-only** — no audio processing. This makes it lightweight and cheap to run.

### Endpoints

```
GET  /api/scenarios
  Response: [{ key, name, description, user_role, ai_role, category, is_demo }]

POST /api/sessions
  Body: { scenario_key: "1" }
  Response: { session_id, briefing, user_role, ai_role, first_hint, system_prompt_hash }

POST /api/sessions/{id}/message
  Body: { text: "Leitstelle Roth von Florian Birkach 47/1, sind ausgerückt..." }
  Response: { reply: "Hier Leitstelle Roth, verstanden..." }

POST /api/sessions/{id}/end
  Response: { evaluation: { messages: [...], overall_score, summary, tips } }

DELETE /api/sessions/{id}
  Response: 204
```

### Key Design Decisions

1. **REST instead of WebSocket**: Simpler for mobile clients; each radio message is a discrete request/response. No streaming needed since TTS runs on-device.
2. **Session state on server**: Server holds conversation history and system prompt — the mobile app only sends the transcribed text.
3. **No audio over the wire**: All audio processing happens on-device. Only short text strings travel to/from the server → minimal bandwidth, low latency.

## Mobile App Flow

### 1. First Launch
1. Download STT model (whisper ggml-base, ~140MB) and TTS model (Piper de-thorsten, ~30MB)
2. Store in app-local storage
3. Show progress bar during download

### 2. Scenario Selection
1. `GET /api/scenarios` → display grouped list (Einsatz / DMO / Demo)
2. User taps a scenario

### 3. Training Session
1. `POST /api/sessions` → get briefing, roles
2. Display briefing card with user/AI roles
3. **Loop:**
   - User holds PTT button → record audio via microphone
   - Release → whisper.cpp transcribes on-device (1-2s for 5s audio)
   - Show transcript in chat bubble
   - `POST /api/sessions/{id}/message` with text → get AI reply
   - Piper TTS synthesizes reply on-device
   - Play audio, show reply in chat bubble
4. User taps "End Session" (or says "Ende" detected locally)

### 4. Evaluation
1. `POST /api/sessions/{id}/end` → structured evaluation (same JSON as current web app)
2. Display per-message scores, improvements, overall score
3. Option to retry scenario

## Technology Choices

### Mobile: Flutter + sherpa-onnx

| Component | Package | Notes |
|-----------|---------|-------|
| **Framework** | Flutter (Dart) | Single codebase, native performance |
| **STT** | `sherpa_onnx` Flutter package | whisper-tiny or whisper-base model, ONNX Runtime |
| **TTS** | `sherpa_onnx` Flutter package | Piper VITS model (`de_DE-thorsten-medium`) |
| **Audio recording** | `record` or `audio_session` | 16kHz PCM capture for whisper |
| **Audio playback** | `just_audio` or raw PCM via sherpa | Play TTS output |
| **HTTP client** | `http` or `dio` | REST calls to bridge server |
| **State management** | `provider` or `riverpod` | Simple, well-known |

### STT Model Selection

| Model | Size | Speed (phone) | German WER | Recommendation |
|-------|------|---------------|------------|----------------|
| whisper-tiny | ~40MB | <1s / 5s audio | Higher | Dev/testing |
| whisper-base | ~140MB | 1-2s / 5s audio | Good | **Production default** |
| whisper-small | ~460MB | 3-5s / 5s audio | Best | Optional download |

Start with **whisper-base** — good balance of accuracy and speed for German radio messages.

### TTS Voice

Use **Piper `de_DE-thorsten-medium`** (~30MB):
- Male German voice, natural sounding
- VITS architecture, real-time on mobile
- Available from sherpa-onnx model releases

### Bridge Server

- **Language**: Go (same as existing server)
- **LLM**: Gemini 2.5 Flash via REST API (text-only, reuse `internal/gemini` client)
- **Scenarios + Prompts**: Reuse from `server/internal/scenario/` and `prompts/`
- **Deployment**: Docker container, can run on any small VPS or even free tier

## What We Reuse from Existing Codebase

| Component | Source | How |
|-----------|--------|-----|
| Scenario definitions | `server/internal/scenario/scenario.go` | Copy or import as Go module |
| Prompt files | `prompts/` | Mount/copy into bridge server |
| Base rules | `prompts/base_rules.txt` | Same |
| Gemini client (text parts) | `server/internal/gemini/client.go` | Extract `SendText`/`SendTextLong`, drop `SendAudio` |
| Evaluation logic | `server/internal/websocket/client.go` (`generateStructuredEvaluation`) | Extract into bridge server handler |
| Session management | `server/internal/session/session.go` | Reuse directly |
| TTS text preprocessing | `server/internal/tts/service.go` (`PrepareTTSText`) | Port to Dart for on-device use |

## Implementation Phases

### Phase 1: Bridge Server (Go) — ~2 days
1. Set up `mobile/server/` with Go module
2. Implement REST API (scenarios, sessions, message, evaluation)
3. Reuse Gemini text client, scenario loader, session manager
4. Add CORS middleware for mobile clients
5. Dockerize
6. Test with curl/httpie

### Phase 2: Flutter App Shell — ~2 days
1. Set up Flutter project in `mobile/app/`
2. Scenario list screen (fetches from bridge server)
3. Basic training session screen with chat UI
4. Text-only mode first (type messages, no audio yet)
5. Evaluation display screen

### Phase 3: On-Device STT Integration — ~2 days
1. Integrate sherpa-onnx Flutter package
2. Model download manager (first-launch download from HuggingFace)
3. Audio recording (16kHz PCM)
4. whisper transcription on recorded audio
5. PTT button UX (hold to record, release to transcribe)

### Phase 4: On-Device TTS Integration — ~1 day
1. Piper model download (de_DE-thorsten)
2. TTS synthesis of AI replies
3. Audio playback of synthesized speech
4. Port `PrepareTTSText` to Dart (callsign normalization)

### Phase 5: Polish — ~1 day
1. Loading states, error handling
2. Model download progress UI
3. Offline detection (show warning if no server connection)
4. App icon, splash screen

## Environment Variables (Bridge Server)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GEMINI_API_KEY` | Yes | — | Google Gemini API key |
| `PORT` | No | `8080` | HTTP server port |
| `PROMPTS_DIR` | No | `../../prompts` | Path to prompts directory |
| `CORS_ORIGINS` | No | `*` | Allowed CORS origins |

## Model Distribution Strategy

Models are NOT bundled in the app binary (would make APK/IPA too large). Instead:

1. **First launch**: App checks for models in local storage
2. **If missing**: Show download screen with progress bars
3. **Download from**: HuggingFace model hub (sherpa-onnx releases)
4. **Storage**: App-internal directory (~170MB total)
5. **Future**: Option to select model quality (tiny/base/small)

## Cost Analysis (Production)

| Component | Cost |
|-----------|------|
| STT (on-device) | $0 |
| TTS (on-device) | $0 |
| LLM (Gemini 2.5 Flash, text-only) | ~$0.0005 / interaction |
| Bridge server (Hetzner CX22, 2 vCPU) | ~€3.79/month |
| **Total for 1000 sessions/month** | **~€14/month** |

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| whisper-base German accuracy insufficient for radio jargon | Medium | Fall back to whisper-small (larger download); fine-tune if needed |
| Piper German voice quality too robotic for radio feel | Low | Multiple Piper voices available; Kokoro-82M via sherpa-onnx as alternative |
| sherpa-onnx Flutter package stability | Medium | Package is actively maintained (11.5k stars); fallback: native Kotlin/Swift + platform channels |
| Model download size deters users (~170MB) | Low | Show clear progress; offer "lite" mode with tiny model; download over WiFi only |
| Gemini API latency on slow mobile connections | Medium | Text-only requests are tiny (~1KB); show typing indicator; timeout + retry |

## Open Questions

1. **Model updates**: How to push updated whisper/piper models without app update?
   → Use remote config to point to latest model URLs
2. **Offline LLM**: Should we support a small on-device LLM for fully offline mode?
   → Out of scope for POC; Gemini is needed for quality radio protocol responses
3. **Demo mode**: Should demos also use on-device TTS or still be server-generated?
   → On-device TTS for consistency; server generates dialogue text, app synthesizes
