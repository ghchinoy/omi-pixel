package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"omi-pixel-service/web"
)

func TestServerHealthAndSessions(t *testing.T) {
	ctx := t.Context()
	store := NewMemoryStore()
	gemini := NewGeminiClient(nil, "test-proj", "global", "gemini-3.5-transcribe", "gemini-3.5-flash-lite", "gemini-4-hydrogen")
	liveProxy := NewLiveProxy(nil, "test-proj", "global", "gemini-3.5-transcribe-live")
	auth, err := NewAuthenticator(ctx, "test-proj", store, true)
	if err != nil {
		t.Fatalf("NewAuthenticator failed: %v", err)
	}
	spaTmpl, err := web.ParseTemplates()
	if err != nil {
		t.Fatalf("ParseTemplates failed: %v", err)
	}

	server := NewServer(store, &NoopAudioStore{}, gemini, liveProxy, auth, spaTmpl, web.DefaultWebConfig)
	handler := server.Routes()

	// 1. Test Health
	req := httptest.NewRequest(http.MethodGet, "/api/health", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("GET /api/health status = %d, want %d", rec.Code, http.StatusOK)
	}
	var healthResp map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&healthResp); err != nil {
		t.Fatalf("Decode(/api/health) error = %v", err)
	}
	if healthResp["version"] != Version {
		t.Errorf("GET /api/health version = %q, want %q", healthResp["version"], Version)
	}

	// 2. Test Create Session
	createReq := CreateSessionRequest{
		ID:        "test-session-123",
		DeviceID:  "omi-device-abc",
		Title:     "Team Architecture Discussion",
		Language:  "en",
		StartedAt: time.Now().UTC(),
	}
	body, _ := json.Marshal(createReq)
	req = httptest.NewRequest(http.MethodPost, "/api/sessions", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/sessions status = %d, want %d (body: %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}

	// 3. Test Save Segments
	saveSegReq := SaveSegmentsRequest{
		Title:   "Team Architecture Discussion",
		Summary: "Discussion about Omi-Pixel BLE and Gemini 3.5 diarization.",
		Segments: []Segment{
			{
				Speaker:   "Speaker 1",
				SpeakerID: 0,
				Text:      "Hello everyone, let's talk about the new streaming pipeline.",
				Start:     0.0,
				End:       3.5,
			},
			{
				Speaker:   "Speaker 2",
				SpeakerID: 1,
				Text:      "Sounds good, the Gemini 3.5 Transcribe Live integration works nicely.",
				Start:     3.8,
				End:       7.2,
			},
		},
	}
	body, _ = json.Marshal(saveSegReq)
	req = httptest.NewRequest(http.MethodPost, "/api/sessions/test-session-123/segments", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("POST /api/sessions/test-session-123/segments status = %d, want %d (body: %s)", rec.Code, http.StatusOK, rec.Body.String())
	}

	// 4. Test Get Session Detail
	req = httptest.NewRequest(http.MethodGet, "/api/sessions/test-session-123", nil)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/sessions/test-session-123 status = %d, want %d (body: %s)", rec.Code, http.StatusOK, rec.Body.String())
	}

	var detail SessionDetail
	if err := json.NewDecoder(rec.Body).Decode(&detail); err != nil {
		t.Fatalf("Decode(/api/sessions/test-session-123) error = %v", err)
	}

	if len(detail.Segments) != 2 {
		t.Errorf("len(detail.Segments) = %d, want 2", len(detail.Segments))
	}
	if detail.Segments[0].Speaker != "Speaker 1" {
		t.Errorf("detail.Segments[0].Speaker = %q, want %q", detail.Segments[0].Speaker, "Speaker 1")
	}

	// 5. Test Web Dashboard Render
	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("GET / status = %d, want %d", rec.Code, http.StatusOK)
	}

	// 6. Test Web Session Detail Render
	req = httptest.NewRequest(http.MethodGet, "/sessions/test-session-123", nil)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("GET /sessions/test-session-123 status = %d, want %d", rec.Code, http.StatusOK)
	}
}

func TestAuthMiddlewareEnforcement(t *testing.T) {
	ctx := t.Context()
	store := NewMemoryStore()
	auth, err := NewAuthenticator(ctx, "test-proj", store, false) // Auth enabled, no mock certs
	if err == nil {
		// If auth client could initialize, test that unauthenticated request gets 401
		apiMux := http.NewServeMux()
		apiMux.HandleFunc("GET /api/test", func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
		})
		handler := auth.Middleware(apiMux)

		req := httptest.NewRequest(http.MethodGet, "/api/test", nil)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Errorf("auth.Middleware(GET /api/test) status = %d, want %d", rec.Code, http.StatusUnauthorized)
		}
	}
}

func TestBuildLiveSetupMessage(t *testing.T) {
	modelPath := "projects/test-p/locations/global/publishers/google/models/gemini-3.5-transcribe-live"

	// 1. Default / Verbatim with english
	msg := BuildLiveSetupMessage(modelPath, "verbatim", "en")
	setup, ok := msg["setup"].(map[string]any)
	if !ok {
		t.Fatalf("BuildLiveSetupMessage(%q, %q, %q) missing setup map: %v", modelPath, "verbatim", "en", msg)
	}
	transcription, ok := setup["inputAudioTranscription"].(map[string]any)
	if !ok {
		t.Fatalf("BuildLiveSetupMessage(%q, %q, %q) missing inputAudioTranscription map: %v", modelPath, "verbatim", "en", setup)
	}
	if transcription["mode"] != "VERBATIM" {
		t.Errorf("BuildLiveSetupMessage(%q, %q, %q) mode = %v, want %q", modelPath, "verbatim", "en", transcription["mode"], "VERBATIM")
	}
	langCodes, ok := transcription["languageCodes"].([]string)
	if !ok || len(langCodes) != 1 || langCodes[0] != "en-US" {
		t.Errorf("BuildLiveSetupMessage(%q, %q, %q) languageCodes = %v, want [en-US]", modelPath, "verbatim", "en", transcription["languageCodes"])
	}

	// 2. Smart mode with Spanish (must omit languageCodes to avoid Vertex AI closeCode=1007)
	msg = BuildLiveSetupMessage(modelPath, "smart", "es")
	setup = msg["setup"].(map[string]any)
	transcription = setup["inputAudioTranscription"].(map[string]any)
	if transcription["mode"] != "SMART" {
		t.Errorf("BuildLiveSetupMessage(%q, %q, %q) mode = %v, want %q", modelPath, "smart", "es", transcription["mode"], "SMART")
	}
	if _, exists := transcription["languageCodes"]; exists {
		t.Errorf("BuildLiveSetupMessage(%q, %q, %q) languageCodes = %v, want omitted", modelPath, "smart", "es", transcription["languageCodes"])
	}

	// 3. Unset mode and multi-language
	msg = BuildLiveSetupMessage(modelPath, "", "multi")
	setup = msg["setup"].(map[string]any)
	transcription = setup["inputAudioTranscription"].(map[string]any)
	if _, exists := transcription["mode"]; exists {
		t.Errorf("BuildLiveSetupMessage(%q, %q, %q) mode = %v, want omitted", modelPath, "", "multi", transcription["mode"])
	}
	if _, exists := transcription["languageCodes"]; exists {
		t.Errorf("BuildLiveSetupMessage(%q, %q, %q) languageCodes = %v, want omitted", modelPath, "", "multi", transcription["languageCodes"])
	}
}

func TestSessionIDValidationAndNoopAudioStoreCap(t *testing.T) {
	if !isValidSessionID("sess_12345-abc") {
		t.Errorf("isValidSessionID(%q) = false, want true", "sess_12345-abc")
	}
	for _, badID := range []string{"../etc/passwd", "sess/../../bad", ""} {
		if isValidSessionID(badID) {
			t.Errorf("isValidSessionID(%q) = true, want false", badID)
		}
	}

	audioStore := &NoopAudioStore{}
	ctx := t.Context()
	for i := 0; i < maxInMemoryAudioSessions+5; i++ {
		id := "sess_" + string(rune('a'+i))
		_, err := audioStore.UploadWAV(ctx, id, []byte("RIFF0000WAVEfmt "))
		if err != nil {
			t.Fatalf("NoopAudioStore.UploadWAV(%q) error = %v", id, err)
		}
	}
	if len(audioStore.files) != maxInMemoryAudioSessions {
		t.Errorf("len(audioStore.files) = %d, want %d", len(audioStore.files), maxInMemoryAudioSessions)
	}
}

func TestSaveSegments_FailedStatusOnZeroAudio(t *testing.T) {
	ctx := t.Context()
	store := NewMemoryStore()
	auth, err := NewAuthenticator(ctx, "test-proj", store, true)
	if err != nil {
		t.Fatalf("NewAuthenticator(test-proj, disabled=true) error = %v", err)
	}
	spaTmpl, err := web.ParseTemplates()
	if err != nil {
		t.Fatalf("web.ParseTemplates() error = %v", err)
	}
	server := NewServer(store, &NoopAudioStore{}, nil, nil, auth, spaTmpl, web.DefaultWebConfig)
	handler := server.Routes()

	// Create session initially in recording status
	createBody, _ := json.Marshal(CreateSessionRequest{
		ID:       "sess-zero-audio",
		DeviceID: "omi-1",
		Title:    "Empty Capture",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/sessions", bytes.NewReader(createBody))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /api/sessions status = %d, want %d", rec.Code, http.StatusCreated)
	}

	// Finalize with 0 segments and status=failed
	failBody, _ := json.Marshal(SaveSegmentsRequest{
		Summary: "No audio was received from the Omi device.",
		Status:  StatusFailed,
	})
	req = httptest.NewRequest(http.MethodPost, "/api/sessions/sess-zero-audio/segments", bytes.NewReader(failBody))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /api/sessions/sess-zero-audio/segments status = %d, want %d", rec.Code, http.StatusOK)
	}

	session, err := store.GetSession(ctx, "sess-zero-audio")
	if err != nil {
		t.Fatalf("store.GetSession(sess-zero-audio) error = %v", err)
	}
	if session.Status != StatusFailed {
		t.Errorf("session.Status = %q, want %q", session.Status, StatusFailed)
	}
	if session.FinishedAt == nil {
		t.Errorf("session.FinishedAt = nil, want non-nil timestamp")
	}
}

func TestUploadAudio_AsyncAccepted(t *testing.T) {
	ctx := t.Context()
	store := NewMemoryStore()
	audioStore := &NoopAudioStore{}
	auth, err := NewAuthenticator(ctx, "test-proj", store, true)
	if err != nil {
		t.Fatalf("NewAuthenticator(test-proj, disabled=true) error = %v", err)
	}
	spaTmpl, err := web.ParseTemplates()
	if err != nil {
		t.Fatalf("web.ParseTemplates() error = %v", err)
	}
	server := NewServer(store, audioStore, nil, nil, auth, spaTmpl, web.DefaultWebConfig)
	handler := server.Routes()

	// Build minimal valid 44+ byte WAV payload
	wav := make([]byte, 128)
	copy(wav[0:4], "RIFF")
	copy(wav[8:12], "WAVE")

	req := httptest.NewRequest(http.MethodPost, "/api/sessions/sess-async-1/audio?async=true", bytes.NewReader(wav))
	req.Header.Set("Content-Type", "audio/wav")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusAccepted {
		t.Fatalf("POST /api/sessions/sess-async-1/audio?async=true status = %d, want %d (body: %s)", rec.Code, http.StatusAccepted, rec.Body.String())
	}

	var detail SessionDetail
	if err := json.NewDecoder(rec.Body).Decode(&detail); err != nil {
		t.Fatalf("Decode(202 response) error = %v", err)
	}
	if detail.Status != StatusProcessing {
		t.Errorf("202 response status = %q, want %q", detail.Status, StatusProcessing)
	}
	if !detail.HasAudio {
		t.Errorf("202 response has_audio = false, want true")
	}

	// Ensure background goroutine exits cleanly before test ends
	server.WaitForBackgroundJobs()
}

func TestResolveSummaryModel(t *testing.T) {
	tests := []struct {
		name      string
		requested string
		fallback  string
		want      string
	}{
		{name: "default_hydrogen", requested: "gemini-4-hydrogen", fallback: "gemini-3.8-flash", want: "gemini-4-hydrogen"},
		{name: "alternate_flash", requested: "gemini-3.8-flash", fallback: "gemini-4-hydrogen", want: "gemini-3.8-flash"},
		{name: "empty_uses_fallback", requested: "", fallback: "gemini-4-hydrogen", want: "gemini-4-hydrogen"},
		{name: "disallowed_uses_fallback", requested: "gemini-untrusted-model", fallback: "gemini-4-hydrogen", want: "gemini-4-hydrogen"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ResolveSummaryModel(tc.requested, tc.fallback)
			if got != tc.want {
				t.Errorf("ResolveSummaryModel(%q, %q) = %q, want %q", tc.requested, tc.fallback, got, tc.want)
			}
		})
	}
}

func TestExtractBearerToken_RejectsQueryParam(t *testing.T) {
	reqWithHeader := httptest.NewRequest(http.MethodGet, "/api/live?session=sess_1", nil)
	reqWithHeader.Header.Set("Authorization", "Bearer jwt-header-token")
	if got := extractBearerToken(reqWithHeader); got != "jwt-header-token" {
		t.Errorf("extractBearerToken(Authorization header) = %q, want %q", got, "jwt-header-token")
	}

	reqWithQuery := httptest.NewRequest(http.MethodGet, "/api/live?session=sess_1&access_token=leaked-jwt", nil)
	if got := extractBearerToken(reqWithQuery); got != "" {
		t.Errorf("extractBearerToken(query access_token) = %q, want empty string", got)
	}
}
