package main

import (
	"context"
	"fmt"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// VertexConfig holds project and location details for Google Cloud Vertex AI.
type VertexConfig struct {
	ProjectID string
	Location  string
}

// VertexAuth handles Google Cloud ADC token generation and caching.
type VertexAuth struct {
	tokenSource oauth2.TokenSource
	mu          sync.Mutex
}

// NewVertexAuth creates an OAuth2 token source using Application Default Credentials (ADC).
func NewVertexAuth(ctx context.Context) (*VertexAuth, error) {
	ts, err := google.DefaultTokenSource(ctx, "https://www.googleapis.com/auth/cloud-platform")
	if err != nil {
		return nil, fmt.Errorf("failed to get default token source (ADC): %w", err)
	}
	return &VertexAuth{tokenSource: ts}, nil
}

// Token returns a valid OAuth Bearer token, refreshing automatically if expired.
func (va *VertexAuth) Token(ctx context.Context) (string, error) {
	if va == nil || va.tokenSource == nil {
		return "", fmt.Errorf("vertex auth token source is uninitialized")
	}
	va.mu.Lock()
	defer va.mu.Unlock()

	tok, err := va.tokenSource.Token()
	if err != nil {
		return "", fmt.Errorf("failed to fetch oauth token: %w", err)
	}
	return tok.AccessToken, nil
}

// VertexLiveWSURL returns the WebSocket URL for Vertex Multimodal Live / BidiGenerateContent.
func VertexLiveWSURL() string {
	return "wss://aiplatform.googleapis.com/ws/google.cloud.aiplatform.v1.LlmBidiService/BidiGenerateContent"
}

// VertexBatchRESTURL returns the REST endpoint for batch generateContent.
func VertexBatchRESTURL(projectID, location, model string) string {
	if location == "" {
		location = "global"
	}
	if model == "" {
		model = "gemini-3.5-transcribe-preview"
	}
	return fmt.Sprintf(
		"https://aiplatform.googleapis.com/v1/projects/%s/locations/%s/publishers/google/models/%s:generateContent",
		projectID,
		location,
		model,
	)
}

// VertexModelPath returns the full resource name for the model.
func VertexModelPath(projectID, location, model string) string {
	if location == "" {
		location = "global"
	}
	if model == "" {
		model = "gemini-3.5-transcribe-live-preview"
	}
	return fmt.Sprintf("projects/%s/locations/%s/publishers/google/models/%s", projectID, location, model)
}

// ParseOffsetSeconds parses seconds strings like "0.400s", "3.44s", or "12s" into float64.
func ParseOffsetSeconds(offsetStr string) float64 {
	if offsetStr == "" {
		return 0.0
	}
	var sec float64
	_, err := fmt.Sscanf(offsetStr, "%fs", &sec)
	if err != nil {
		// Try without trailing 's'
		_, _ = fmt.Sscanf(offsetStr, "%f", &sec)
	}
	return sec
}

// ParseSpeakerLabel maps "spk:0", "spk:1" to "Speaker 1", "Speaker 2".
func ParseSpeakerLabel(rawLabel string) (string, int) {
	if rawLabel == "" {
		return "Speaker 1", 0
	}
	var id int
	if n, _ := fmt.Sscanf(rawLabel, "spk:%d", &id); n == 1 {
		return fmt.Sprintf("Speaker %d", id+1), id
	}
	if n, _ := fmt.Sscanf(rawLabel, "speaker_%d", &id); n == 1 {
		return fmt.Sprintf("Speaker %d", id+1), id
	}
	return rawLabel, 0
}

// FormatDuration returns mm:ss format.
func FormatDuration(seconds float64) string {
	d := time.Duration(seconds * float64(time.Second))
	m := int(d.Minutes())
	s := int(d.Seconds()) % 60
	return fmt.Sprintf("%02d:%02d", m, s)
}
