package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

type GeminiClient struct {
	vertexAuth      *VertexAuth
	projectID       string
	location        string
	transcribeModel string
	titleModel      string
	summaryModel    string
	httpClient      *http.Client
}

func NewGeminiClient(auth *VertexAuth, projectID, location, transcribeModel, titleModel, summaryModel string) *GeminiClient {
	if location == "" {
		location = "global"
	}
	if transcribeModel == "" {
		transcribeModel = "gemini-3.5-transcribe-preview"
	}
	if titleModel == "" {
		titleModel = "gemini-3.5-flash-lite"
	}
	if summaryModel == "" {
		summaryModel = "gemini-3.7-flash"
	}
	return &GeminiClient{
		vertexAuth:      auth,
		projectID:       projectID,
		location:        location,
		transcribeModel: transcribeModel,
		titleModel:      titleModel,
		summaryModel:    summaryModel,
		httpClient: &http.Client{
			Timeout: 240 * time.Second, // Long timeout for large audio files
		},
	}
}

type DiarizedResult struct {
	Title    string    `json:"title"`
	Summary  string    `json:"summary"`
	Segments []Segment `json:"segments"`
}

type vertexGenerateRequest struct {
	Contents         []vertexContent         `json:"contents"`
	GenerationConfig *vertexGenerationConfig `json:"generationConfig,omitempty"`
}

type vertexContent struct {
	Role  string       `json:"role,omitempty"`
	Parts []vertexPart `json:"parts"`
}

type vertexPart struct {
	Text       string            `json:"text,omitempty"`
	InlineData *vertexInlineData `json:"inlineData,omitempty"`
	FileData   *vertexFileData   `json:"fileData,omitempty"`
}

type vertexInlineData struct {
	MimeType string `json:"mimeType"`
	Data     string `json:"data"`
}

type vertexFileData struct {
	MimeType string `json:"mimeType"`
	FileURI  string `json:"fileUri"`
}

type vertexGenerationConfig struct {
	AudioTranscriptionConfig *vertexAudioTranscriptionConfig `json:"audioTranscriptionConfig,omitempty"`
}

type vertexAudioTranscriptionConfig struct {
	Diarization   bool     `json:"diarization"`
	WordTimestamp bool     `json:"wordTimestamp"`
	LanguageCodes []string `json:"languageCodes,omitempty"`
}

type vertexGenerateResponse struct {
	Candidates []struct {
		Content struct {
			Role  string `json:"role"`
			Parts []struct {
				Text               string `json:"text"`
				AudioTranscription *struct {
					Text         string `json:"text"`
					SpeakerLabel string `json:"speakerLabel"`
					Words        []struct {
						Word        string `json:"word"`
						StartOffset string `json:"startOffset"`
						EndOffset   string `json:"endOffset"`
					} `json:"words"`
				} `json:"audioTranscription"`
			} `json:"parts"`
		} `json:"content"`
		FinishReason string `json:"finishReason"`
	} `json:"candidates"`
	Error *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Status  string `json:"status"`
	} `json:"error,omitempty"`
}

// DiarizeAudio performs Vertex AI Gemini 3.5 Transcribe audio transcription & speaker diarization,
// accepting either a gcsURI (gs://bucket/path) or raw WAV bytes (inlineData fallback),
// followed by AI title (gemini-3.5-flash-lite) and optional AI summary (gemini-3.7-flash).
func (g *GeminiClient) DiarizeAudio(ctx context.Context, audioWavBytes []byte, gcsURI string, language string, generateSummary bool) (*DiarizedResult, error) {
	if g.vertexAuth == nil {
		return nil, fmt.Errorf("vertex auth credentials not initialized")
	}
	if g.projectID == "" {
		return nil, fmt.Errorf("GOOGLE_CLOUD_PROJECT is not configured")
	}

	token, err := g.vertexAuth.Token(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to obtain vertex oauth token: %w", err)
	}

	langCodes := []string{"en-US"}
	if language != "" && language != "multi" {
		langCodes = []string{mapLanguageToBCP47(language)}
	}

	var audioPart vertexPart
	if gcsURI != "" {
		audioPart = vertexPart{
			FileData: &vertexFileData{
				MimeType: "audio/wav",
				FileURI:  gcsURI,
			},
		}
	} else {
		encodedAudio := base64.StdEncoding.EncodeToString(audioWavBytes)
		audioPart = vertexPart{
			InlineData: &vertexInlineData{
				MimeType: "audio/wav",
				Data:     encodedAudio,
			},
		}
	}

	reqBody := vertexGenerateRequest{
		Contents: []vertexContent{
			{
				Role:  "user",
				Parts: []vertexPart{audioPart},
			},
		},
		GenerationConfig: &vertexGenerationConfig{
			AudioTranscriptionConfig: &vertexAudioTranscriptionConfig{
				Diarization:   true,
				WordTimestamp: true,
				LanguageCodes: langCodes,
			},
		},
	}

	payloadBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal vertex request: %w", err)
	}

	endpoint := VertexBatchRESTURL(g.projectID, g.location, g.transcribeModel)

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payloadBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create http request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+token)

	resp, err := g.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("vertex http request failed: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read vertex response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("vertex api error (HTTP %d): %s", resp.StatusCode, string(respBytes))
	}

	var vResp vertexGenerateResponse
	if err := json.Unmarshal(respBytes, &vResp); err != nil {
		return nil, fmt.Errorf("failed to parse vertex json response: %w", err)
	}

	if vResp.Error != nil {
		return nil, fmt.Errorf("vertex error: %s (code %d)", vResp.Error.Message, vResp.Error.Code)
	}

	if len(vResp.Candidates) == 0 || len(vResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("no transcription candidates returned by vertex")
	}

	var segments []Segment
	var fullTranscript strings.Builder
	currentOffset := 0.0

	for _, part := range vResp.Candidates[0].Content.Parts {
		var text string
		var rawSpeaker string
		var startSec, endSec float64

		if part.AudioTranscription != nil {
			text = strings.TrimSpace(part.AudioTranscription.Text)
			rawSpeaker = part.AudioTranscription.SpeakerLabel

			words := part.AudioTranscription.Words
			if len(words) > 0 {
				startSec = ParseOffsetSeconds(words[0].StartOffset)
				endSec = ParseOffsetSeconds(words[len(words)-1].EndOffset)
				if endSec < startSec {
					endSec = startSec + 1.0
				}
				currentOffset = endSec
			} else {
				startSec = currentOffset
				endSec = currentOffset + 2.0
				currentOffset = endSec
			}
		}

		if text == "" {
			text = strings.TrimSpace(part.Text)
		}

		if text == "" {
			continue
		}

		speakerLabel, speakerID := ParseSpeakerLabel(rawSpeaker)

		segments = append(segments, Segment{
			Speaker:   speakerLabel,
			SpeakerID: speakerID,
			Text:      text,
			Start:     startSec,
			End:       endSec,
		})

		if fullTranscript.Len() > 0 {
			fullTranscript.WriteString(" ")
		}
		fullTranscript.WriteString(text)
	}

	// Build speaker-labeled transcript text for title & summary generation
	var speakerFormatted strings.Builder
	for _, seg := range segments {
		speakerFormatted.WriteString(fmt.Sprintf("%s: %s\n", seg.Speaker, seg.Text))
	}
	transcriptBody := strings.TrimSpace(speakerFormatted.String())

	// 1. Generate Title with gemini-3.5-flash-lite
	title := ""
	if transcriptBody != "" && g.titleModel != "" {
		titlePrompt := fmt.Sprintf("Read this conversation transcript and return ONLY a concise 3 to 6 word title summarizing the topic. No quotes, no intro.\n\nTranscript:\n%s", transcriptBody)
		t, err := g.generateText(ctx, g.titleModel, titlePrompt, "")
		if err == nil && t != "" {
			title = strings.Trim(t, `"'`)
		} else {
			log.Printf("[GeminiClient] Title generation with %s failed: %v", g.titleModel, err)
		}
	}
	if title == "" {
		title = deriveTitleFromTranscript(fullTranscript.String())
	}

	// 2. Generate Summary with gemini-3.7-flash if requested
	summary := ""
	if generateSummary && transcriptBody != "" && g.summaryModel != "" {
		summaryPrompt := fmt.Sprintf("Provide a clear, concise 2 to 4 sentence summary of the key discussion points and takeaways from this conversation transcript.\n\nTranscript:\n%s", transcriptBody)
		s, err := g.generateText(ctx, g.summaryModel, summaryPrompt, "LOW")
		if err == nil && s != "" {
			summary = s
		} else {
			log.Printf("[GeminiClient] Summary generation with %s failed: %v", g.summaryModel, err)
		}
	}

	return &DiarizedResult{
		Title:    title,
		Summary:  summary,
		Segments: segments,
	}, nil
}

func (g *GeminiClient) generateText(ctx context.Context, model, prompt, thinkingLevel string) (string, error) {
	if g.vertexAuth == nil || g.projectID == "" {
		return "", fmt.Errorf("vertex credentials not configured")
	}

	token, err := g.vertexAuth.Token(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to obtain vertex token: %w", err)
	}

	reqBody := map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"role": "user",
				"parts": []map[string]interface{}{
					{"text": prompt},
				},
			},
		},
	}

	if thinkingLevel != "" {
		reqBody["generationConfig"] = map[string]interface{}{
			"thinkingConfig": map[string]interface{}{
				"thinkingLevel": thinkingLevel,
			},
		}
	}

	payloadBytes, err := json.Marshal(reqBody)
	if err != nil {
		return "", err
	}

	endpoint := VertexBatchRESTURL(g.projectID, g.location, model)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payloadBytes))
	if err != nil {
		return "", err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+token)

	resp, err := g.httpClient.Do(httpReq)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("vertex text generation error (HTTP %d): %s", resp.StatusCode, string(respBytes))
	}

	var vResp struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}

	if err := json.Unmarshal(respBytes, &vResp); err != nil {
		return "", err
	}

	if len(vResp.Candidates) == 0 {
		return "", fmt.Errorf("no candidates returned")
	}

	// Concatenate all text parts (handles models with thinking/thought parts)
	var sb strings.Builder
	for _, p := range vResp.Candidates[0].Content.Parts {
		if t := strings.TrimSpace(p.Text); t != "" {
			if sb.Len() > 0 {
				sb.WriteString(" ")
			}
			sb.WriteString(t)
		}
	}

	return strings.TrimSpace(sb.String()), nil
}

func deriveTitleFromTranscript(text string) string {
	cleaned := strings.TrimSpace(text)
	if cleaned == "" {
		return "Recorded Session"
	}

	words := strings.Fields(cleaned)
	if len(words) <= 7 {
		return cleaned
	}
	return strings.Join(words[:7], " ") + "..."
}

func mapLanguageToBCP47(code string) string {
	switch strings.ToLower(strings.TrimSpace(code)) {
	case "en", "english":
		return "en-US"
	case "es", "spanish":
		return "es-ES"
	case "fr", "french":
		return "fr-FR"
	case "de", "german":
		return "de-DE"
	case "ja", "japanese":
		return "ja-JP"
	case "zh", "chinese":
		return "cmn-Hans-CN"
	case "it", "italian":
		return "it-IT"
	case "pt", "portuguese":
		return "pt-BR"
	case "hi", "hindi":
		return "hi-IN"
	default:
		return "en-US"
	}
}
