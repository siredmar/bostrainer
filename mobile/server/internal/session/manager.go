package session

import (
	"sync"

	"github.com/siredmar/bostrainer/mobile/server/internal/llm"
	"github.com/siredmar/bostrainer/mobile/server/internal/scenario"
)

// Session holds per-client training state.
type Session struct {
	ID           string
	Scenario     *scenario.Scenario
	SystemPrompt string
	History      []llm.Message
	mu           sync.Mutex
}

// NewSession creates a new training session.
func NewSession(id string, sc *scenario.Scenario, systemPrompt string) *Session {
	return &Session{
		ID:           id,
		Scenario:     sc,
		SystemPrompt: systemPrompt,
		History:      []llm.Message{},
	}
}

// AddMessage adds a message to the conversation history.
func (s *Session) AddMessage(role, content string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.History = append(s.History, llm.Message{Role: role, Content: content})
}

// GetHistory returns a copy of the conversation history.
func (s *Session) GetHistory() []llm.Message {
	s.mu.Lock()
	defer s.mu.Unlock()
	history := make([]llm.Message, len(s.History))
	copy(history, s.History)
	return history
}

// Manager manages all active sessions.
type Manager struct {
	sessions map[string]*Session
	mu       sync.RWMutex
}

// NewManager creates a new session manager.
func NewManager() *Manager {
	return &Manager{
		sessions: make(map[string]*Session),
	}
}

// Create creates and stores a new session.
func (m *Manager) Create(id string, sc *scenario.Scenario, systemPrompt string) *Session {
	m.mu.Lock()
	defer m.mu.Unlock()
	session := NewSession(id, sc, systemPrompt)
	m.sessions[id] = session
	return session
}

// Get retrieves a session by ID.
func (m *Manager) Get(id string) *Session {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.sessions[id]
}

// Delete removes a session.
func (m *Manager) Delete(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.sessions, id)
}
