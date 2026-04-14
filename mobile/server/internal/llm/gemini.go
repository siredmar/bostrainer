package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

const (
	baseURL       = "https://generativelanguage.googleapis.com/v1beta/models"
	primaryModel  = "gemini-2.5-flash-lite"
	fallbackModel = "gemini-2.5-flash"
)

// Client is a text-only Gemini API client for the mobile bridge server.
type Client struct {
	apiKey     string
	httpClient *http.Client
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

// Message represents a conversation message.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// SendText sends a text message to Gemini.
func (c *Client) SendText(ctx context.Context, systemPrompt string, history []Message, text string) (string, error) {
	contents := buildContents(history)
	contents = append(contents, content{
		Role:  "user",
		Parts: []part{{Text: text}},
	})

	return c.generate(ctx, systemPrompt, contents, 2048)
}

// SendTextLong sends a text message with higher token limit (for evaluations).
func (c *Client) SendTextLong(ctx context.Context, systemPrompt string, history []Message, text string) (string, error) {
	contents := buildContents(history)
	contents = append(contents, content{
		Role:  "user",
		Parts: []part{{Text: text}},
	})

	return c.generate(ctx, systemPrompt, contents, 8192)
}

type content struct {
	Role  string `json:"role"`
	Parts []part `json:"parts"`
}

type part struct {
	Text string `json:"text,omitempty"`
}

type generateRequest struct {
	Contents          []content         `json:"contents"`
	SystemInstruction *content          `json:"system_instruction,omitempty"`
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

func buildContents(history []Message) []content {
	contents := make([]content, 0, len(history))
	for _, msg := range history {
		role := "user"
		if msg.Role == "assistant" {
			role = "model"
		}
		contents = append(contents, content{
			Role:  role,
			Parts: []part{{Text: msg.Content}},
		})
	}
	return contents
}

func (c *Client) generate(ctx context.Context, systemPrompt string, contents []content, maxTokens int) (string, error) {
	result, err := c.generateWithModel(ctx, primaryModel, systemPrompt, contents, maxTokens)
	if err != nil {
		log.Printf("Primary model (%s) failed: %v — trying fallback (%s)", primaryModel, err, fallbackModel)
		result, err = c.generateWithModel(ctx, fallbackModel, systemPrompt, contents, maxTokens)
		if err != nil {
			return "", fmt.Errorf("both models failed: %w", err)
		}
		log.Printf("Fallback model (%s) succeeded", fallbackModel)
	}
	return result, nil
}

func (c *Client) generateWithModel(ctx context.Context, modelName string, systemPrompt string, contents []content, maxTokens int) (string, error) {
	req := generateRequest{
		Contents: contents,
		GenerationConfig: &generationConfig{
			Temperature:     0.7,
			MaxOutputTokens: maxTokens,
		},
	}

	if systemPrompt != "" {
		req.SystemInstruction = &content{
			Parts: []part{{Text: systemPrompt}},
		}
	}

	body, err := json.Marshal(req)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	url := fmt.Sprintf("%s/%s:generateContent?key=%s", baseURL, modelName, c.apiKey)
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

// ExtractJSON extracts JSON from a response that may contain markdown code blocks.
func ExtractJSON(response string) string {
	cleaned := response

	if idx := strings.Index(cleaned, "```json"); idx != -1 {
		cleaned = cleaned[idx+7:]
		if endIdx := strings.Index(cleaned, "```"); endIdx != -1 {
			cleaned = cleaned[:endIdx]
		}
	} else if idx := strings.Index(cleaned, "```"); idx != -1 {
		cleaned = cleaned[idx+3:]
		if endIdx := strings.Index(cleaned, "```"); endIdx != -1 {
			cleaned = cleaned[:endIdx]
		}
	}

	if startIdx := strings.Index(cleaned, "{"); startIdx != -1 {
		braceCount := 0
		endIdx := -1
		for i := startIdx; i < len(cleaned); i++ {
			if cleaned[i] == '{' {
				braceCount++
			} else if cleaned[i] == '}' {
				braceCount--
				if braceCount == 0 {
					endIdx = i + 1
					break
				}
			}
		}
		if endIdx > startIdx {
			cleaned = cleaned[startIdx:endIdx]
		}
	}

	return strings.TrimSpace(cleaned)
}
