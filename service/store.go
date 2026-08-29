package main

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type SessionStatus string

const (
	StatusRecording  SessionStatus = "recording"
	StatusProcessing SessionStatus = "processing"
	StatusCompleted  SessionStatus = "completed"
	StatusFailed     SessionStatus = "failed"
)

type Segment struct {
	Speaker   string  `json:"speaker" firestore:"speaker"`
	SpeakerID int     `json:"speaker_id" firestore:"speaker_id"`
	Text      string  `json:"text" firestore:"text"`
	Start     float64 `json:"start" firestore:"start"`
	End       float64 `json:"end" firestore:"end"`
	IsUser    bool    `json:"is_user" firestore:"is_user"`
}

type Session struct {
	ID              string        `json:"id" firestore:"id"`
	DeviceID        string        `json:"device_id" firestore:"device_id"`
	Title           string        `json:"title" firestore:"title"`
	Summary         string        `json:"summary" firestore:"summary"`
	AudioURL        string        `json:"audio_url,omitempty" firestore:"audio_url,omitempty"`
	HasAudio        bool          `json:"has_audio" firestore:"-"`
	Status          SessionStatus `json:"status" firestore:"status"`
	Language        string        `json:"language" firestore:"language"`
	DurationSeconds float64       `json:"duration_seconds" firestore:"duration_seconds"`
	StartedAt       time.Time     `json:"started_at" firestore:"started_at"`
	FinishedAt      *time.Time    `json:"finished_at,omitempty" firestore:"finished_at,omitempty"`
	CreatedAt       time.Time     `json:"created_at" firestore:"created_at"`
	UpdatedAt       time.Time     `json:"updated_at" firestore:"updated_at"`
}

type SessionDetail struct {
	Session
	Segments []Segment `json:"segments"`
}

type Store interface {
	SaveSession(ctx context.Context, session *Session) error
	GetSession(ctx context.Context, id string) (*Session, error)
	ListSessions(ctx context.Context, limit int) ([]*Session, error)
	SaveSegments(ctx context.Context, sessionID string, segments []Segment) error
	GetSegments(ctx context.Context, sessionID string) ([]Segment, error)
	GetSessionDetail(ctx context.Context, id string) (*SessionDetail, error)
	IsAuthorizedUser(ctx context.Context, email string) (bool, error)
	Close() error
}

// MemoryStore provides an in-memory fallback
type MemoryStore struct {
	mu       sync.RWMutex
	sessions map[string]*Session
	segments map[string][]Segment
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		sessions: make(map[string]*Session),
		segments: make(map[string][]Segment),
	}
}

func (m *MemoryStore) SaveSession(_ context.Context, s *Session) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now().UTC()
	if s.CreatedAt.IsZero() {
		s.CreatedAt = now
	}
	s.UpdatedAt = now
	// Store copy
	clone := *s
	m.sessions[s.ID] = &clone
	return nil
}

func (m *MemoryStore) GetSession(_ context.Context, id string) (*Session, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	s, ok := m.sessions[id]
	if !ok {
		return nil, fmt.Errorf("session not found: %s", id)
	}
	clone := *s
	clone.HasAudio = clone.AudioURL != ""
	return &clone, nil
}

func (m *MemoryStore) ListSessions(_ context.Context, limit int) ([]*Session, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	list := make([]*Session, 0, len(m.sessions))
	for _, s := range m.sessions {
		clone := *s
		clone.HasAudio = clone.AudioURL != ""
		list = append(list, &clone)
	}
	// Sort newest first
	for i := 0; i < len(list); i++ {
		for j := i + 1; j < len(list); j++ {
			if list[i].CreatedAt.Before(list[j].CreatedAt) {
				list[i], list[j] = list[j], list[i]
			}
		}
	}
	if limit > 0 && len(list) > limit {
		list = list[:limit]
	}
	return list, nil
}

func (m *MemoryStore) SaveSegments(_ context.Context, sessionID string, segs []Segment) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	copied := make([]Segment, len(segs))
	copy(copied, segs)
	m.segments[sessionID] = copied
	return nil
}

func (m *MemoryStore) GetSegments(_ context.Context, sessionID string) ([]Segment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	segs, ok := m.segments[sessionID]
	if !ok {
		return []Segment{}, nil
	}
	copied := make([]Segment, len(segs))
	copy(copied, segs)
	return copied, nil
}

func (m *MemoryStore) GetSessionDetail(ctx context.Context, id string) (*SessionDetail, error) {
	session, err := m.GetSession(ctx, id)
	if err != nil {
		return nil, err
	}
	segments, err := m.GetSegments(ctx, id)
	if err != nil {
		return nil, err
	}
	return &SessionDetail{
		Session:  *session,
		Segments: segments,
	}, nil
}

func (m *MemoryStore) IsAuthorizedUser(_ context.Context, email string) (bool, error) {
	// In-memory store allows any non-empty email
	return strings.TrimSpace(email) != "", nil
}

func (m *MemoryStore) Close() error {
	return nil
}

// FirestoreStore provides Google Cloud Firestore persistence
type FirestoreStore struct {
	client *firestore.Client
}

func NewFirestoreStore(ctx context.Context, projectID, database string) (*FirestoreStore, error) {
	var client *firestore.Client
	var err error
	if database != "" && database != "(default)" {
		client, err = firestore.NewClientWithDatabase(ctx, projectID, database)
	} else {
		client, err = firestore.NewClient(ctx, projectID)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to create firestore client: %w", err)
	}
	return &FirestoreStore{client: client}, nil
}

func (f *FirestoreStore) SaveSession(ctx context.Context, s *Session) error {
	now := time.Now().UTC()
	if s.CreatedAt.IsZero() {
		s.CreatedAt = now
	}
	s.UpdatedAt = now
	_, err := f.client.Collection("omi_sessions").Doc(s.ID).Set(ctx, s)
	if err != nil {
		return fmt.Errorf("failed to save session to firestore: %w", err)
	}
	return nil
}

func (f *FirestoreStore) GetSession(ctx context.Context, id string) (*Session, error) {
	doc, err := f.client.Collection("omi_sessions").Doc(id).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get session %s from firestore: %w", id, err)
	}
	var session Session
	if err := doc.DataTo(&session); err != nil {
		return nil, fmt.Errorf("failed to parse session %s: %w", id, err)
	}
	session.HasAudio = session.AudioURL != ""
	return &session, nil
}

func (f *FirestoreStore) ListSessions(ctx context.Context, limit int) ([]*Session, error) {
	if limit <= 0 {
		limit = 50
	}
	iter := f.client.Collection("omi_sessions").
		OrderBy("created_at", firestore.Desc).
		Limit(limit).
		Documents(ctx)
	defer iter.Stop()

	var sessions []*Session
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error iterating sessions: %w", err)
		}
		var s Session
		if err := doc.DataTo(&s); err != nil {
			continue
		}
		s.HasAudio = s.AudioURL != ""
		sessions = append(sessions, &s)
	}
	return sessions, nil
}

func (f *FirestoreStore) SaveSegments(ctx context.Context, sessionID string, segs []Segment) error {
	col := f.client.Collection("omi_sessions").Doc(sessionID).Collection("segments")
	batch := f.client.Batch()
	for i, seg := range segs {
		docRef := col.Doc(fmt.Sprintf("%05d", i))
		batch.Set(docRef, seg)
	}
	if _, err := batch.Commit(ctx); err != nil {
		return fmt.Errorf("failed to batch write segments: %w", err)
	}
	return nil
}

func (f *FirestoreStore) GetSegments(ctx context.Context, sessionID string) ([]Segment, error) {
	iter := f.client.Collection("omi_sessions").Doc(sessionID).Collection("segments").
		OrderBy("start", firestore.Asc).
		Documents(ctx)
	defer iter.Stop()

	var segments []Segment
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error iterating segments: %w", err)
		}
		var seg Segment
		if err := doc.DataTo(&seg); err != nil {
			continue
		}
		segments = append(segments, seg)
	}
	return segments, nil
}

func (f *FirestoreStore) GetSessionDetail(ctx context.Context, id string) (*SessionDetail, error) {
	session, err := f.GetSession(ctx, id)
	if err != nil {
		return nil, err
	}
	segments, err := f.GetSegments(ctx, id)
	if err != nil {
		return nil, err
	}
	return &SessionDetail{
		Session:  *session,
		Segments: segments,
	}, nil
}

func (f *FirestoreStore) IsAuthorizedUser(ctx context.Context, email string) (bool, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return false, nil
	}
	doc, err := f.client.Collection("authorized_users").Doc(email).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return false, nil
		}
		return false, fmt.Errorf("failed to query authorized_users: %w", err)
	}
	return doc.Exists(), nil
}

func (f *FirestoreStore) Close() error {
	return f.client.Close()
}
