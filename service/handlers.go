package main

import (
	"context"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"omi-pixel-service/web"
)

const (
	maxJSONBodyBytes  = 5 << 20  // 5 MB
	maxAudioBodyBytes = 50 << 20 // 50 MB
)

var validSessionIDRe = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,64}$`)

func isValidSessionID(id string) bool {
	return validSessionIDRe.MatchString(id)
}

type Server struct {
	store      Store
	audioStore AudioStore
	gemini     *GeminiClient
	liveProxy  *LiveProxy
	auth       *Authenticator
	spaTmpl    *template.Template
	webConfig  web.WebConfig
	bgWg       sync.WaitGroup
}

// WaitForBackgroundJobs blocks until any in-flight async diarization jobs finish.
func (s *Server) WaitForBackgroundJobs() {
	s.bgWg.Wait()
}

func NewServer(store Store, audioStore AudioStore, gemini *GeminiClient, liveProxy *LiveProxy, auth *Authenticator, spaTmpl *template.Template, webConfig web.WebConfig) *Server {
	if audioStore == nil {
		audioStore = &NoopAudioStore{}
	}
	return &Server{
		store:      store,
		audioStore: audioStore,
		gemini:     gemini,
		liveProxy:  liveProxy,
		auth:       auth,
		spaTmpl:    spaTmpl,
		webConfig:  webConfig,
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	// 1. Public Endpoints (SPA Shell & Liveness)
	mux.HandleFunc("GET /{$}", s.handleWebSPA)
	mux.HandleFunc("GET /sessions/{id}", s.handleWebSPA)
	mux.HandleFunc("GET /api/health", s.handleHealth)

	// 2. Protected API Endpoints (wrapped with Firebase Auth + Allowlist Middleware)
	apiMux := http.NewServeMux()
	apiMux.HandleFunc("POST /api/sessions", s.handleCreateSession)
	apiMux.HandleFunc("GET /api/sessions", s.handleListSessions)
	apiMux.HandleFunc("GET /api/sessions/{id}", s.handleGetSession)
	apiMux.HandleFunc("DELETE /api/sessions/{id}", s.handleDeleteSession)
	apiMux.HandleFunc("POST /api/sessions/{id}/audio", s.handleUploadAudio)
	apiMux.HandleFunc("GET /api/sessions/{id}/audio", s.handleDownloadAudio)
	apiMux.HandleFunc("POST /api/sessions/{id}/reprocess", s.handleReprocessSession)
	apiMux.HandleFunc("POST /api/sessions/{id}/segments", s.handleSaveSegments)
	apiMux.HandleFunc("GET /api/live", s.handleLiveWS)

	var protectedAPI http.Handler = apiMux
	if s.auth != nil {
		protectedAPI = s.auth.Middleware(apiMux)
	}

	// Mount protected API routes on main mux
	mux.Handle("/api/sessions", protectedAPI)
	mux.Handle("/api/sessions/", protectedAPI)
	mux.Handle("/api/live", protectedAPI)

	return withCORS(mux)
}

func (s *Server) handleLiveWS(w http.ResponseWriter, r *http.Request) {
	if s.liveProxy == nil {
		http.Error(w, "Live transcription proxy not available", http.StatusServiceUnavailable)
		return
	}
	s.liveProxy.HandleWebSocket(w, r)
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	respondJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"service": "omi-pixel",
		"version": Version,
	})
}

type CreateSessionRequest struct {
	ID                string    `json:"id"`
	DeviceID          string    `json:"device_id"`
	Title             string    `json:"title"`
	Language          string    `json:"language"`
	TranscriptionMode string    `json:"transcription_mode,omitempty"`
	StartedAt         time.Time `json:"started_at"`
}

func (s *Server) handleCreateSession(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBodyBytes)
	var req CreateSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("invalid request body: %v", err), http.StatusBadRequest)
		return
	}

	if req.ID == "" {
		req.ID = fmt.Sprintf("sess_%d", time.Now().UnixNano())
	} else if !isValidSessionID(req.ID) {
		http.Error(w, "invalid session id format", http.StatusBadRequest)
		return
	}
	if req.StartedAt.IsZero() {
		req.StartedAt = time.Now().UTC()
	}
	req.StartedAt = req.StartedAt.UTC()

	session := &Session{
		ID:                req.ID,
		DeviceID:          req.DeviceID,
		Title:             req.Title,
		Language:          req.Language,
		TranscriptionMode: NormalizeTranscriptionMode(req.TranscriptionMode),
		Status:            StatusRecording,
		StartedAt:         req.StartedAt,
	}

	if err := s.store.SaveSession(r.Context(), session); err != nil {
		log.Printf("Failed to save session: %v", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusCreated, session)
}

func (s *Server) handleListSessions(w http.ResponseWriter, r *http.Request) {
	sessions, err := s.store.ListSessions(r.Context(), 50)
	if err != nil {
		log.Printf("Failed to list sessions: %v", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	if sessions == nil {
		sessions = []*Session{}
	}
	respondJSON(w, http.StatusOK, sessions)
}

func (s *Server) handleGetSession(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidSessionID(id) {
		http.Error(w, "missing or invalid session id", http.StatusBadRequest)
		return
	}

	detail, err := s.store.GetSessionDetail(r.Context(), id)
	if err != nil {
		http.Error(w, fmt.Sprintf("session not found: %v", err), http.StatusNotFound)
		return
	}

	respondJSON(w, http.StatusOK, detail)
}

func (s *Server) handleDeleteSession(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidSessionID(id) {
		http.Error(w, "missing or invalid session id", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	if s.audioStore != nil {
		if err := s.audioStore.DeleteWAV(ctx, id); err != nil {
			log.Printf("[handleDeleteSession] Warning: failed deleting WAV for session %s: %v", id, err)
		}
	}

	if err := s.store.DeleteSession(ctx, id); err != nil {
		log.Printf("[handleDeleteSession] Failed deleting session %s: %v", id, err)
		http.Error(w, "failed to delete session", http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusOK, map[string]any{
		"status": "deleted",
		"id":     id,
	})
}

func (s *Server) handleUploadAudio(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidSessionID(id) {
		http.Error(w, "missing or invalid session id", http.StatusBadRequest)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxAudioBodyBytes)
	ctx := r.Context()

	// 1. Read existing session or create placeholder
	session, err := s.store.GetSession(ctx, id)
	if err != nil {
		session = &Session{
			ID:        id,
			Status:    StatusProcessing,
			StartedAt: time.Now().UTC(),
		}
	}

	session.Status = StatusProcessing
	_ = s.store.SaveSession(ctx, session)

	// 2. Extract WAV audio bytes from request body
	var audioBytes []byte
	contentType := r.Header.Get("Content-Type")

	if strings.HasPrefix(contentType, "multipart/form-data") {
		if err := r.ParseMultipartForm(maxAudioBodyBytes); err != nil {
			http.Error(w, "failed to parse multipart form", http.StatusBadRequest)
			return
		}
		file, _, err := r.FormFile("audio")
		if err != nil {
			http.Error(w, "missing 'audio' file part in form", http.StatusBadRequest)
			return
		}
		defer func() { _ = file.Close() }()
		audioBytes, err = io.ReadAll(file)
		if err != nil {
			http.Error(w, "failed to read audio file", http.StatusInternalServerError)
			return
		}
	} else {
		// Assume raw WAV body
		var err error
		audioBytes, err = io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "failed to read raw audio body", http.StatusRequestEntityTooLarge)
			return
		}
	}

	if len(audioBytes) < 44 { // minimum WAV header size
		http.Error(w, "audio payload is too small to be a valid WAV", http.StatusBadRequest)
		return
	}

	// 3. Check query params for summary preference, summary model, and transcription mode
	generateSummary := true
	if summaryParam := r.URL.Query().Get("summary"); summaryParam != "" {
		generateSummary = (summaryParam == "true" || summaryParam == "1")
	}
	summaryModelOverride := ResolveSummaryModel(r.URL.Query().Get("summary_model"), "")
	if modeParam := r.URL.Query().Get("mode"); modeParam != "" {
		session.TranscriptionMode = NormalizeTranscriptionMode(modeParam)
	} else if session.TranscriptionMode == "" {
		session.TranscriptionMode = "verbatim"
	}

	// 4. Optionally upload to GCS (or local in-memory audio store)
	var gcsURI string
	if s.audioStore != nil {
		uri, err := s.audioStore.UploadWAV(ctx, id, audioBytes)
		if err != nil {
			log.Printf("[handleUploadAudio] Audio store upload failed (%v), falling back to inline audio", err)
		} else if uri != "" {
			session.AudioURL = uri
			session.HasAudio = true
			if strings.HasPrefix(uri, "gs://") {
				gcsURI = uri
			}
		}
	}

	if err := s.store.SaveSession(ctx, session); err != nil {
		log.Printf("[handleUploadAudio] Failed to persist processing session %s: %v", id, err)
	}

	asyncMode := r.URL.Query().Get("async") == "true" || r.URL.Query().Get("async") == "1"
	if asyncMode {
		sessionCopy := *session
		audioCopy := append([]byte(nil), audioBytes...)
		s.bgWg.Add(1)
		go func() {
			defer s.bgWg.Done()
			bgCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Minute)
			defer cancel()
			if _, err := s.runDiarizationAndPersist(bgCtx, &sessionCopy, audioCopy, gcsURI, generateSummary, summaryModelOverride); err != nil {
				log.Printf("[handleUploadAudio] Async diarization failed for session %s: %v", sessionCopy.ID, err)
			}
		}()

		respondJSON(w, http.StatusAccepted, &SessionDetail{
			Session:  *session,
			Segments: []Segment{},
		})
		return
	}

	// 5. Perform synchronous Gemini 3.5 Transcribe structured diarization & AI title/summary
	detail, err := s.runDiarizationAndPersist(ctx, session, audioBytes, gcsURI, generateSummary, summaryModelOverride)
	if err != nil {
		http.Error(w, fmt.Sprintf("diarization failed: %v", err), http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusOK, detail)
}

func (s *Server) runDiarizationAndPersist(
	ctx context.Context,
	session *Session,
	audioBytes []byte,
	gcsURI string,
	generateSummary bool,
	summaryModelOverride string,
) (*SessionDetail, error) {
	if s.gemini == nil {
		session.Status = StatusFailed
		_ = s.store.SaveSession(ctx, session)
		return nil, fmt.Errorf("gemini client is not configured")
	}

	log.Printf("Running Gemini 3.5 diarization for session %s (gcs=%s, bytes=%d, summary=%v, summaryModel=%q, mode=%q)...", session.ID, gcsURI, len(audioBytes), generateSummary, summaryModelOverride, session.TranscriptionMode)
	diarized, err := s.gemini.DiarizeAudio(ctx, audioBytes, gcsURI, session.Language, generateSummary, summaryModelOverride, session.TranscriptionMode)
	if err != nil {
		log.Printf("Gemini diarization failed for session %s: %v", session.ID, err)
		session.Status = StatusFailed
		_ = s.store.SaveSession(ctx, session)
		return nil, err
	}

	now := time.Now().UTC()
	session.Status = StatusCompleted
	session.FinishedAt = &now
	if diarized.Title != "" {
		session.Title = diarized.Title
	}
	if diarized.Summary != "" {
		session.Summary = diarized.Summary
	}
	if diarized.SmartTranscript != "" {
		session.SmartTranscript = diarized.SmartTranscript
	}
	if len(diarized.Segments) > 0 {
		lastSeg := diarized.Segments[len(diarized.Segments)-1]
		session.DurationSeconds = lastSeg.End
	}

	if err := s.store.SaveSession(ctx, session); err != nil {
		log.Printf("Failed to update session %s: %v", session.ID, err)
	}

	if err := s.store.SaveSegments(ctx, session.ID, diarized.Segments); err != nil {
		log.Printf("Failed to save segments for session %s: %v", session.ID, err)
	}

	return &SessionDetail{
		Session:  *session,
		Segments: diarized.Segments,
	}, nil
}

func (s *Server) handleReprocessSession(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidSessionID(id) {
		http.Error(w, "missing or invalid session id", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	session, err := s.store.GetSession(ctx, id)
	if err != nil {
		http.Error(w, fmt.Sprintf("session not found: %v", err), http.StatusNotFound)
		return
	}

	reader, _, err := s.audioStore.DownloadWAV(ctx, id)
	if err != nil {
		http.Error(w, fmt.Sprintf("stored audio not found for reprocessing: %v", err), http.StatusNotFound)
		return
	}
	audioBytes, err := io.ReadAll(io.LimitReader(reader, maxAudioBodyBytes))
	_ = reader.Close()
	if err != nil || len(audioBytes) < 44 {
		http.Error(w, "stored audio is invalid or unreadable", http.StatusInternalServerError)
		return
	}

	generateSummary := true
	if summaryParam := r.URL.Query().Get("summary"); summaryParam != "" {
		generateSummary = (summaryParam == "true" || summaryParam == "1")
	}
	summaryModelOverride := ResolveSummaryModel(r.URL.Query().Get("summary_model"), "")
	if modeParam := r.URL.Query().Get("mode"); modeParam != "" {
		session.TranscriptionMode = NormalizeTranscriptionMode(modeParam)
	}

	var gcsURI string
	if strings.HasPrefix(session.AudioURL, "gs://") {
		gcsURI = session.AudioURL
	}

	session.Status = StatusProcessing
	_ = s.store.SaveSession(ctx, session)

	asyncMode := r.URL.Query().Get("async") == "true" || r.URL.Query().Get("async") == "1"
	if asyncMode {
		sessionCopy := *session
		s.bgWg.Add(1)
		go func() {
			defer s.bgWg.Done()
			bgCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Minute)
			defer cancel()
			if _, err := s.runDiarizationAndPersist(bgCtx, &sessionCopy, audioBytes, gcsURI, generateSummary, summaryModelOverride); err != nil {
				log.Printf("[handleReprocessSession] Async reprocess failed for %s: %v", sessionCopy.ID, err)
			}
		}()

		respondJSON(w, http.StatusAccepted, &SessionDetail{
			Session:  *session,
			Segments: []Segment{},
		})
		return
	}

	detail, err := s.runDiarizationAndPersist(ctx, session, audioBytes, gcsURI, generateSummary, summaryModelOverride)
	if err != nil {
		http.Error(w, fmt.Sprintf("reprocess diarization failed: %v", err), http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusOK, detail)
}

type SaveSegmentsRequest struct {
	Segments []Segment     `json:"segments"`
	Title    string        `json:"title,omitempty"`
	Summary  string        `json:"summary,omitempty"`
	Status   SessionStatus `json:"status,omitempty"`
}

func (s *Server) handleSaveSegments(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidSessionID(id) {
		http.Error(w, "missing or invalid session id", http.StatusBadRequest)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBodyBytes)
	var req SaveSegmentsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	targetStatus := StatusCompleted
	if req.Status == StatusFailed {
		targetStatus = StatusFailed
	}

	ctx := r.Context()
	session, err := s.store.GetSession(ctx, id)
	if err != nil {
		session = &Session{
			ID:        id,
			Status:    targetStatus,
			StartedAt: time.Now().UTC(),
		}
	}

	if req.Title != "" {
		session.Title = req.Title
	}
	if req.Summary != "" {
		session.Summary = req.Summary
	}
	session.Status = targetStatus
	now := time.Now().UTC()
	session.FinishedAt = &now

	if len(req.Segments) > 0 {
		session.DurationSeconds = req.Segments[len(req.Segments)-1].End
	}

	if err := s.store.SaveSession(ctx, session); err != nil {
		log.Printf("Failed to save session %s: %v", id, err)
		http.Error(w, "failed to save session", http.StatusInternalServerError)
		return
	}
	if err := s.store.SaveSegments(ctx, id, req.Segments); err != nil {
		log.Printf("Failed to save segments for session %s: %v", id, err)
		http.Error(w, "failed to save segments", http.StatusInternalServerError)
		return
	}

	respondJSON(w, http.StatusOK, map[string]any{
		"status": session.Status,
		"count":  len(req.Segments),
	})
}

func (s *Server) handleDownloadAudio(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidSessionID(id) {
		http.Error(w, "missing or invalid session id", http.StatusBadRequest)
		return
	}

	reader, size, err := s.audioStore.DownloadWAV(r.Context(), id)
	if err != nil {
		http.Error(w, fmt.Sprintf("audio not found: %v", err), http.StatusNotFound)
		return
	}
	defer func() { _ = reader.Close() }()

	w.Header().Set("Content-Type", "audio/wav")
	w.Header().Set("Accept-Ranges", "bytes")
	if size > 0 {
		w.Header().Set("Content-Length", fmt.Sprintf("%d", size))
	}
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, reader)
}

func (s *Server) handleWebSPA(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := s.spaTmpl.Execute(w, s.webConfig); err != nil {
		log.Printf("Template render error: %v", err)
	}
}

func respondJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}
