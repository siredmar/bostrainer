package tts

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	geminiTTSModel   = "gemini-2.5-flash-preview-tts"
	geminiTTSBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"
	geminiMaxRetries = 3
	geminiRetryDelay = 2 * time.Second
)

// GeminiTTS implements Provider using Google Gemini TTS API.
type GeminiTTS struct {
	apiKey string
	voice  string
}

// NewGeminiTTS creates a new Gemini TTS provider.
func NewGeminiTTS() (*GeminiTTS, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY environment variable is required for Gemini TTS")
	}
	return &GeminiTTS{
		apiKey: apiKey,
		voice:  "Kore", // German-compatible voice
	}, nil
}

func (g *GeminiTTS) Name() string {
	return "Gemini TTS"
}

// Synthesize converts text to WAV audio bytes.
func (g *GeminiTTS) Synthesize(text string) ([]byte, error) {
	// Prepare text for TTS (convert vehicle IDs like 47/1 to "47 1")
	text = PrepareTTSText(text)
	
	pcmData, err := g.generatePCM(text)
	if err != nil {
		return nil, err
	}
	return pcmToWAV(pcmData, 24000, 1, 16), nil
}

type geminiTTSRequest struct {
	Contents         []geminiTTSContent  `json:"contents"`
	GenerationConfig *geminiTTSGenConfig `json:"generationConfig,omitempty"`
}

type geminiTTSContent struct {
	Parts []geminiTTSPart `json:"parts"`
}

type geminiTTSPart struct {
	Text string `json:"text,omitempty"`
}

type geminiTTSGenConfig struct {
	ResponseModalities []string            `json:"responseModalities"`
	SpeechConfig       *geminiSpeechConfig `json:"speechConfig,omitempty"`
}

type geminiSpeechConfig struct {
	VoiceConfig *geminiVoiceConfig `json:"voiceConfig,omitempty"`
}

type geminiVoiceConfig struct {
	PrebuiltVoiceConfig *geminiPrebuiltVoiceConfig `json:"prebuiltVoiceConfig,omitempty"`
}

type geminiPrebuiltVoiceConfig struct {
	VoiceName string `json:"voiceName"`
}

type geminiTTSResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				InlineData *struct {
					MimeType string `json:"mimeType"`
					Data     []byte `json:"data"`
				} `json:"inlineData,omitempty"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func (g *GeminiTTS) generatePCM(text string) ([]byte, error) {
	var lastErr error

	for attempt := 0; attempt < geminiMaxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(geminiRetryDelay)
		}

		data, err := g.doGeneratePCM(text)
		if err == nil {
			return data, nil
		}

		lastErr = err
		// Only retry on internal errors
		if !strings.Contains(err.Error(), "internal error") &&
			!strings.Contains(err.Error(), "Internal") {
			return nil, err
		}
	}

	return nil, fmt.Errorf("after %d retries: %w", geminiMaxRetries, lastErr)
}

func (g *GeminiTTS) doGeneratePCM(text string) ([]byte, error) {
	req := geminiTTSRequest{
		Contents: []geminiTTSContent{
			{Parts: []geminiTTSPart{{Text: text}}},
		},
		GenerationConfig: &geminiTTSGenConfig{
			ResponseModalities: []string{"AUDIO"},
			SpeechConfig: &geminiSpeechConfig{
				VoiceConfig: &geminiVoiceConfig{
					PrebuiltVoiceConfig: &geminiPrebuiltVoiceConfig{
						VoiceName: g.voice,
					},
				},
			},
		},
	}

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	url := fmt.Sprintf("%s/%s:generateContent?key=%s", geminiTTSBaseURL, geminiTTSModel, g.apiKey)
	httpReq, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	httpResp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer httpResp.Body.Close()

	respBody, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	var resp geminiTTSResponse
	if err := json.Unmarshal(respBody, &resp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	if resp.Error != nil {
		return nil, fmt.Errorf("API error: %s", resp.Error.Message)
	}

	if len(resp.Candidates) == 0 ||
		len(resp.Candidates[0].Content.Parts) == 0 ||
		resp.Candidates[0].Content.Parts[0].InlineData == nil {
		return nil, fmt.Errorf("no audio data in response")
	}

	return resp.Candidates[0].Content.Parts[0].InlineData.Data, nil
}
