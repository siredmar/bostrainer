package tts

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"os"
	"regexp"
	"strings"
	"unicode"
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

// sanitizeForTTS removes characters that cause TTS APIs to return errors.
// Strips control characters, markdown formatting, and other non-speech content.
func sanitizeForTTS(text string) string {
	// Remove markdown formatting (bold, italic, headers, etc.)
	text = regexp.MustCompile(`[*_#~` + "`" + `]+`).ReplaceAllString(text, "")

	// Remove control characters (ASCII 0-31 except tab, newline, carriage return)
	text = strings.Map(func(r rune) rune {
		if r == '\t' || r == '\n' || r == '\r' {
			return ' '
		}
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, text)

	// Collapse multiple spaces
	text = regexp.MustCompile(`\s{2,}`).ReplaceAllString(text, " ")

	return strings.TrimSpace(text)
}

// PrepareTTSText prepares text for TTS by converting radio call signs
// like "47/1" or "47/1-1" to spoken form "47 1" or "47 1 1".
// Also fixes pronunciation of compound words that TTS engines struggle with.
func PrepareTTSText(text string) string {
	// Remove characters that cause TTS APIs to return 400 errors
	text = sanitizeForTTS(text)

	// Pattern for vehicle identifiers: number/number or number/number-number
	// Examples: 47/1, 47/1-1, 83/1, 10/43-1
	re := regexp.MustCompile(`(\d+)/(\d+)(?:-(\d+))?`)

	result := re.ReplaceAllStringFunc(text, func(match string) string {
		// Replace / and - with spaces for natural speech
		replaced := strings.ReplaceAll(match, "/", " ")
		replaced = strings.ReplaceAll(replaced, "-", " ")
		return replaced
	})

	// Fix compound word pronunciation (TTS says "schtrupp" instead of "trupp")
	// Insert a slight pause via hyphen to help TTS pronounce correctly
	for _, pair := range ttsPronunciationFixes {
		result = strings.ReplaceAll(result, pair[0], pair[1])
	}
	// Case-insensitive replacements for start of sentence
	for _, pair := range ttsPronunciationFixes {
		titleCase := strings.ToUpper(pair[0][:1]) + pair[0][1:]
		titleRepl := strings.ToUpper(pair[1][:1]) + pair[1][1:]
		result = strings.ReplaceAll(result, titleCase, titleRepl)
	}

	return result
}

// ttsPronunciationFixes maps mispronounced compound words to TTS-friendly forms.
// TTS engines often mispronounce "strupp" as "schtrupp" in compound words.
var ttsPronunciationFixes = [][2]string{
	{"Angriffstrupp", "Angriffs-Trupp"},
	{"Wassertrupp", "Wasser-Trupp"},
	{"Schlauchtrupp", "Schlauch-Trupp"},
	{"Sicherheitstrupp", "Sicherheits-Trupp"},
	{"Rettungstrupp", "Rettungs-Trupp"},
	{"Angriffstruppführer", "Angriffs-Truppführer"},
	{"Wassertruppführer", "Wasser-Truppführer"},
	{"Schlauchtruppführer", "Schlauch-Truppführer"},
	{"Sicherheitstruppführer", "Sicherheits-Truppführer"},
	{"Rettungstruppführer", "Rettungs-Truppführer"},
	{"Angriffstruppmann", "Angriffs-Truppmann"},
	{"Wassertruppmann", "Wasser-Truppmann"},
	{"Schlauchtruppmann", "Schlauch-Truppmann"},
	{"Sicherheitstruppmann", "Sicherheits-Truppmann"},
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
	binary.Write(buf, binary.LittleEndian, uint32(16)) // chunk size
	binary.Write(buf, binary.LittleEndian, uint16(1))  // audio format (PCM)
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
