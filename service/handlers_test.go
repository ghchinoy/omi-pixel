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
	gemini := NewGeminiClient(nil, "test-proj", "global", "gemini-3.5-transcribe-preview", "gemini-3.5-flash-lite", "gemini-3.7-flash")
	liveProxy := NewLiveProxy(nil, "test-proj", "global", "gemini-3.5-transcribe-live-preview")
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
		t.Errorf("Expected status 200, got %d", rec.Code)
	}
	var healthResp map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&healthResp); err != nil {
		t.Fatalf("Failed to decode health response: %v", err)
	}
	if healthResp["version"] != Version {
		t.Errorf("Expected health version %q, got %q", Version, healthResp["version"])
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
		t.Fatalf("Expected status 201, got %d: %s", rec.Code, rec.Body.String())
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
		t.Fatalf("Expected status 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. Test Get Session Detail
	req = httptest.NewRequest(http.MethodGet, "/api/sessions/test-session-123", nil)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected status 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var detail SessionDetail
	if err := json.NewDecoder(rec.Body).Decode(&detail); err != nil {
		t.Fatalf("Failed to decode session detail: %v", err)
	}

	if len(detail.Segments) != 2 {
		t.Errorf("Expected 2 segments, got %d", len(detail.Segments))
	}
	if detail.Segments[0].Speaker != "Speaker 1" {
		t.Errorf("Expected Speaker 1, got %s", detail.Segments[0].Speaker)
	}

	// 5. Test Web Dashboard Render
	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected web index status 200, got %d", rec.Code)
	}

	// 6. Test Web Session Detail Render
	req = httptest.NewRequest(http.MethodGet, "/sessions/test-session-123", nil)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected web detail status 200, got %d", rec.Code)
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
			t.Errorf("Expected status 401 Unauthorized, got %d", rec.Code)
		}
	}
}

func TestBuildLiveSetupMessage(t *testing.T) {
	modelPath := "projects/test-p/locations/global/publishers/google/models/gemini-3.5-transcribe-live-preview"

	// 1. Default / Verbatim with english
	msg := BuildLiveSetupMessage(modelPath, "verbatim", "en")
	setup, ok := msg["setup"].(map[string]interface{})
	if !ok {
		t.Fatalf("Expected setup map in message: %v", msg)
	}
	transcription, ok := setup["inputAudioTranscription"].(map[string]interface{})
	if !ok {
		t.Fatalf("Expected inputAudioTranscription map in setup: %v", setup)
	}
	if transcription["mode"] != "VERBATIM" {
		t.Errorf("Expected mode VERBATIM, got %v", transcription["mode"])
	}
	langCodes, ok := transcription["languageCodes"].([]string)
	if !ok || len(langCodes) != 1 || langCodes[0] != "en-US" {
		t.Errorf("Expected languageCodes ['en-US'], got %v", transcription["languageCodes"])
	}

	// 2. Smart mode with Spanish
	msg = BuildLiveSetupMessage(modelPath, "smart", "es")
	setup = msg["setup"].(map[string]interface{})
	transcription = setup["inputAudioTranscription"].(map[string]interface{})
	if transcription["mode"] != "SMART" {
		t.Errorf("Expected mode SMART, got %v", transcription["mode"])
	}
	langCodes, ok = transcription["languageCodes"].([]string)
	if !ok || len(langCodes) != 1 || langCodes[0] != "es-ES" {
		t.Errorf("Expected languageCodes ['es-ES'], got %v", transcription["languageCodes"])
	}

	// 3. Unset mode and multi-language
	msg = BuildLiveSetupMessage(modelPath, "", "multi")
	setup = msg["setup"].(map[string]interface{})
	transcription = setup["inputAudioTranscription"].(map[string]interface{})
	if _, exists := transcription["mode"]; exists {
		t.Errorf("Expected mode not set when empty, got %v", transcription["mode"])
	}
	if _, exists := transcription["languageCodes"]; exists {
		t.Errorf("Expected languageCodes not set when 'multi', got %v", transcription["languageCodes"])
	}
}
