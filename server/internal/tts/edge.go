package tts

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

const (
	edgeVoice = "de-DE-ConradNeural" // For future use
)

// EdgeTTS implements Provider using Google Translate TTS (free, fast fallback).
// Note: This uses Google Translate TTS as Edge TTS WebSocket is unreliable.
type EdgeTTS struct {
	voice string
	lang  string
}

// NewEdgeTTS creates a new Edge TTS provider.
func NewEdgeTTS() (*EdgeTTS, error) {
	return &EdgeTTS{
		voice: edgeVoice,
		lang:  "de",
	}, nil
}

func (e *EdgeTTS) Name() string {
	return "Google Translate TTS"
}

// Synthesize converts text to MP3 audio bytes.
func (e *EdgeTTS) Synthesize(text string) ([]byte, error) {
	// Prepare text for TTS (convert vehicle IDs like 47/1 to "47 1")
	text = PrepareTTSText(text)
	
	// Split long text into chunks (Google TTS has a limit of ~200 chars)
	chunks := splitText(text, 200)
	
	var allAudio []byte
	for _, chunk := range chunks {
		audio, err := e.synthesizeChunk(chunk)
		if err != nil {
			return nil, err
		}
		allAudio = append(allAudio, audio...)
	}
	
	return allAudio, nil
}

func (e *EdgeTTS) synthesizeChunk(text string) ([]byte, error) {
	// Google Translate TTS endpoint
	ttsURL := fmt.Sprintf(
		"https://translate.google.com/translate_tts?ie=UTF-8&tl=%s&client=tw-ob&q=%s",
		e.lang,
		url.QueryEscape(text),
	)

	req, err := http.NewRequest("GET", ttsURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	// Required headers to avoid 403
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://translate.google.com/")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("TTS error %d: %s", resp.StatusCode, string(body))
	}

	audioData, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if len(audioData) == 0 {
		return nil, fmt.Errorf("empty audio response")
	}

	return audioData, nil
}

// splitText splits text into chunks at sentence/word boundaries
func splitText(text string, maxLen int) []string {
	if len(text) <= maxLen {
		return []string{text}
	}

	var chunks []string
	words := strings.Fields(text)
	var current strings.Builder

	for _, word := range words {
		if current.Len()+len(word)+1 > maxLen {
			if current.Len() > 0 {
				chunks = append(chunks, current.String())
				current.Reset()
			}
		}
		if current.Len() > 0 {
			current.WriteString(" ")
		}
		current.WriteString(word)
	}

	if current.Len() > 0 {
		chunks = append(chunks, current.String())
	}

	return chunks
}

// GermanVoices - for API compatibility
var GermanVoices = map[string]string{
	"conrad":    "de-DE-ConradNeural",
	"katja":     "de-DE-KatjaNeural",
}

// SetVoice - for API compatibility (Google Translate TTS has no voice selection)
func (e *EdgeTTS) SetVoice(name string) error {
	return nil
}
