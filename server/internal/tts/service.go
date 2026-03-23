package tts

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// Provider defines the TTS interface.
type Provider interface {
	Synthesize(text string) ([]byte, error)
	Name() string
}

// NewProvider creates a TTS provider based on TTS_PROVIDER env var.
// Defaults to Edge TTS if not specified.
func NewProvider() (Provider, error) {
	provider := os.Getenv("TTS_PROVIDER")
	if provider == "" {
		provider = "edge" // Default to Edge TTS
	}

	switch provider {
	case "edge":
		return NewEdgeTTS()
	case "gemini":
		return NewGeminiTTS()
	default:
		return nil, fmt.Errorf("unknown TTS provider: %s (use 'edge' or 'gemini')", provider)
	}
}

// PrepareTTSText prepares text for TTS by converting radio call signs
// like "47/1" or "47/1-1" to spoken form "47 1" or "47 1 1".
// This prevents TTS from reading them as math equations.
func PrepareTTSText(text string) string {
	// Pattern for vehicle identifiers: number/number or number/number-number
	// Examples: 47/1, 47/1-1, 83/1, 10/43-1
	re := regexp.MustCompile(`(\d+)/(\d+)(?:-(\d+))?`)
	
	result := re.ReplaceAllStringFunc(text, func(match string) string {
		// Replace / and - with spaces for natural speech
		replaced := strings.ReplaceAll(match, "/", " ")
		replaced = strings.ReplaceAll(replaced, "-", " ")
		return replaced
	})
	
	return result
}

// pcmToWAV wraps raw PCM data in a WAV header.
func pcmToWAV(pcm []byte, sampleRate, channels, bitsPerSample int) []byte {
	byteRate := sampleRate * channels * bitsPerSample / 8
	blockAlign := channels * bitsPerSample / 8
	dataSize := len(pcm)
	fileSize := 36 + dataSize

	buf := new(bytes.Buffer)

	// RIFF header
	buf.WriteString("RIFF")
	binary.Write(buf, binary.LittleEndian, uint32(fileSize))
	buf.WriteString("WAVE")

	// fmt chunk
	buf.WriteString("fmt ")
	binary.Write(buf, binary.LittleEndian, uint32(16))          // chunk size
	binary.Write(buf, binary.LittleEndian, uint16(1))           // audio format (PCM)
	binary.Write(buf, binary.LittleEndian, uint16(channels))
	binary.Write(buf, binary.LittleEndian, uint32(sampleRate))
	binary.Write(buf, binary.LittleEndian, uint32(byteRate))
	binary.Write(buf, binary.LittleEndian, uint16(blockAlign))
	binary.Write(buf, binary.LittleEndian, uint16(bitsPerSample))

	// data chunk
	buf.WriteString("data")
	binary.Write(buf, binary.LittleEndian, uint32(dataSize))
	buf.Write(pcm)

	return buf.Bytes()
}
