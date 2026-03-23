package gemini

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

const (
	baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
	model   = "gemini-2.5-flash"
)

// Client is a Gemini API client.
type Client struct {
	apiKey     string
	httpClient *http.Client
}

// Response holds the LLM response.
type Response struct {
	Transcript string
	Reply      string
}

// NewClient creates a new Gemini client.
func NewClient() (*Client, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY environment variable is required")
	}
	return &Client{
		apiKey:     apiKey,
		httpClient: &http.Client{},
	}, nil
}

// audioInstruction is the prompt for audio transcription and response.
const audioInstruction = `Der Nutzer sendet dir eine Audio-Aufnahme eines BOS-Funkspruchs. 
Antworte im folgenden Format:
TRANSKRIPT: <wortgetreue Transkription der Audio-Aufnahme>
ANTWORT: <deine Funk-Antwort>`

// SendAudio sends audio to Gemini and returns transcript + reply.
// Supports WAV, WebM, OGG, MP3 formats.
func (c *Client) SendAudio(ctx context.Context, systemPrompt string, history []Message, audioData []byte, mimeType string) (*Response, error) {
	contents := buildContents(history)

	// Detect MIME type if not provided
	if mimeType == "" {
		mimeType = detectAudioMimeType(audioData)
	}

	// Add audio message
	contents = append(contents, Content{
		Role: "user",
		Parts: []Part{
			{InlineData: &InlineData{MimeType: mimeType, Data: audioData}},
			{Text: audioInstruction},
		},
	})

	resp, err := c.generate(ctx, systemPrompt, contents, 2048)
	if err != nil {
		return nil, err
	}

	return parseAudioResponse(resp), nil
}

// SendText sends a text message to Gemini.
func (c *Client) SendText(ctx context.Context, systemPrompt string, history []Message, text string) (string, error) {
	contents := buildContents(history)
	contents = append(contents, Content{
		Role:  "user",
		Parts: []Part{{Text: text}},
	})

	return c.generate(ctx, systemPrompt, contents, 2048)
}

// SendTextLong sends a text message with higher token limit (for evaluations).
func (c *Client) SendTextLong(ctx context.Context, systemPrompt string, history []Message, text string) (string, error) {
	contents := buildContents(history)
	contents = append(contents, Content{
		Role:  "user",
		Parts: []Part{{Text: text}},
	})

	return c.generate(ctx, systemPrompt, contents, 8192)
}

// Message represents a conversation message.
type Message struct {
	Role    string
	Content string
}

// Content represents a Gemini content block.
type Content struct {
	Role  string `json:"role"`
	Parts []Part `json:"parts"`
}

// Part represents a content part.
type Part struct {
	Text       string      `json:"text,omitempty"`
	InlineData *InlineData `json:"inline_data,omitempty"`
}

// InlineData represents inline binary data.
type InlineData struct {
	MimeType string `json:"mime_type"`
	Data     []byte `json:"data"`
}

type generateRequest struct {
	Contents          []Content         `json:"contents"`
	SystemInstruction *Content          `json:"system_instruction,omitempty"`
	GenerationConfig  *generationConfig `json:"generationConfig,omitempty"`
}

type generationConfig struct {
	Temperature     float64 `json:"temperature"`
	MaxOutputTokens int     `json:"maxOutputTokens"`
}

type generateResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func buildContents(history []Message) []Content {
	contents := make([]Content, 0, len(history))
	for _, msg := range history {
		role := "user"
		if msg.Role == "assistant" {
			role = "model"
		}
		contents = append(contents, Content{
			Role:  role,
			Parts: []Part{{Text: msg.Content}},
		})
	}
	return contents
}

func (c *Client) generate(ctx context.Context, systemPrompt string, contents []Content, maxTokens int) (string, error) {
	req := generateRequest{
		Contents: contents,
		GenerationConfig: &generationConfig{
			Temperature:     0.7,
			MaxOutputTokens: maxTokens,
		},
	}

	if systemPrompt != "" {
		req.SystemInstruction = &Content{
			Parts: []Part{{Text: systemPrompt}},
		}
	}

	body, err := json.Marshal(req)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	url := fmt.Sprintf("%s/%s:generateContent?key=%s", baseURL, model, c.apiKey)
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("send request: %w", err)
	}
	defer httpResp.Body.Close()

	respBody, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	var resp generateResponse
	if err := json.Unmarshal(respBody, &resp); err != nil {
		return "", fmt.Errorf("unmarshal response: %w", err)
	}

	if resp.Error != nil {
		return "", fmt.Errorf("API error: %s", resp.Error.Message)
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("empty response from API")
	}

	return resp.Candidates[0].Content.Parts[0].Text, nil
}

func parseAudioResponse(raw string) *Response {
	resp := &Response{
		Transcript: "(nicht erkannt)",
		Reply:      raw,
	}

	for _, line := range strings.Split(raw, "\n") {
		upper := strings.ToUpper(strings.TrimSpace(line))
		if strings.HasPrefix(upper, "TRANSKRIPT:") {
			resp.Transcript = strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		} else if strings.HasPrefix(upper, "ANTWORT:") {
			resp.Reply = strings.TrimSpace(strings.SplitN(line, ":", 2)[1])
		}
	}

	return resp
}

// detectAudioMimeType detects the MIME type from audio data.
func detectAudioMimeType(data []byte) string {
	if len(data) < 12 {
		return "audio/wav"
	}

	// WAV: starts with "RIFF"
	if string(data[:4]) == "RIFF" {
		return "audio/wav"
	}

	// WebM: starts with 0x1A 0x45 0xDF 0xA3
	if data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3 {
		return "audio/webm"
	}

	// OGG: starts with "OggS"
	if string(data[:4]) == "OggS" {
		return "audio/ogg"
	}

	// MP3: starts with ID3 or 0xFF 0xFB
	if string(data[:3]) == "ID3" || (data[0] == 0xFF && (data[1]&0xE0) == 0xE0) {
		return "audio/mp3"
	}

	// Default to WebM (common browser format)
	return "audio/webm"
}
