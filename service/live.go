package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
)

const (
	maxLiveFallbackPCMBytes = 32 << 20 // 32 MB cap (~17 min of 16kHz 16-bit mono PCM)
	defaultOrphanGrace      = 15 * time.Second
)

// LiveProxy handles bridging mobile clients with the Vertex AI Gemini 3.5 Transcribe Live WebSocket.
type LiveProxy struct {
	vertexAuth        *VertexAuth
	projectID         string
	location          string
	liveModel         string
	store             Store
	audioStore        AudioStore
	orphanGracePeriod time.Duration
	bgWg              sync.WaitGroup
}

func NewLiveProxy(auth *VertexAuth, projectID, location, liveModel string) *LiveProxy {
	if location == "" {
		location = "global"
	}
	if liveModel == "" {
		liveModel = "gemini-3.5-transcribe-live"
	}
	return &LiveProxy{
		vertexAuth:        auth,
		projectID:         projectID,
		location:          location,
		liveModel:         liveModel,
		orphanGracePeriod: defaultOrphanGrace,
	}
}

// SetPersistence attaches Store and AudioStore so LiveProxy can recover abandoned sessions
// when a mobile client disconnects without uploading audio.
func (lp *LiveProxy) SetPersistence(store Store, audioStore AudioStore) {
	lp.store = store
	lp.audioStore = audioStore
}

// WaitForFallbackJobs waits for any pending orphan-session recovery goroutines to finish.
func (lp *LiveProxy) WaitForFallbackJobs() {
	lp.bgWg.Wait()
}

// ClientAudioFrame is the simplified audio payload from the mobile app.
type ClientAudioFrame struct {
	Audio    string `json:"audio,omitempty"`
	MimeType string `json:"mimeType,omitempty"`
}

// ClientTranscriptEvent is the clean event returned to the mobile app.
type ClientTranscriptEvent struct {
	Type      string  `json:"type"` // "transcript", "ready", "error", "activity"
	Text      string  `json:"text,omitempty"`
	IsFinal   bool    `json:"isFinal,omitempty"`
	Timestamp float64 `json:"timestamp,omitempty"`
	SessionID string  `json:"sessionId,omitempty"`
	Error     string  `json:"error,omitempty"`
}

// BuildLiveSetupMessage constructs the setup payload sent to Vertex AI Multimodal Live WebSocket.
func BuildLiveSetupMessage(modelPath, modeParam, langParam string) map[string]any {
	inputAudioTranscription := map[string]any{}

	cleanMode := strings.ToUpper(strings.TrimSpace(modeParam))
	switch cleanMode {
	case "SMART", "VERBATIM":
		inputAudioTranscription["mode"] = cleanMode
	}

	cleanLang := strings.TrimSpace(langParam)
	// Vertex AI Live API rejects languageCodes when mode is SMART (closeCode=1007:
	// "Transcription mode SMART is incompatible with language_codes").
	if cleanLang != "" && cleanLang != "multi" && cleanMode != "SMART" {
		inputAudioTranscription["languageCodes"] = []string{mapLanguageToBCP47(cleanLang)}
	}

	return map[string]any{
		"setup": map[string]any{
			"model": modelPath,
			"generationConfig": map[string]any{
				"responseModalities": []string{"TEXT"},
			},
			"inputAudioTranscription": inputAudioTranscription,
		},
	}
}

func (lp *LiveProxy) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	if lp.vertexAuth == nil || lp.projectID == "" {
		http.Error(w, "Vertex AI credentials or GOOGLE_CLOUD_PROJECT not configured", http.StatusServiceUnavailable)
		return
	}

	modeParam := r.URL.Query().Get("mode")
	langParam := r.URL.Query().Get("lang")
	clientSessionID := r.URL.Query().Get("session")
	if !isValidSessionID(clientSessionID) {
		clientSessionID = ""
	}

	// 1. Upgrade client connection
	clientConn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: true,
		OriginPatterns:     []string{"*"},
	})
	if err != nil {
		log.Printf("[LiveProxy] Failed to accept client websocket: %v", err)
		return
	}
	defer func() { _ = clientConn.Close(websocket.StatusNormalClosure, "session closed") }()
	clientConn.SetReadLimit(1 << 20) // 1MB read limit for audio frames

	// 2. Fetch OAuth Token for Vertex
	token, err := lp.vertexAuth.Token(ctx)
	if err != nil {
		log.Printf("[LiveProxy] Failed to fetch Vertex OAuth token: %v", err)
		_ = writeClientJSON(ctx, clientConn, ClientTranscriptEvent{
			Type:  "error",
			Error: "Failed to authenticate with Vertex AI",
		})
		return
	}

	// 3. Connect upstream to Vertex AI Live API WebSocket
	vertexURL := VertexLiveWSURL()
	modelPath := VertexModelPath(lp.projectID, lp.location, lp.liveModel)

	dialOpts := &websocket.DialOptions{
		HTTPHeader: http.Header{
			"Authorization": []string{"Bearer " + token},
		},
	}

	dialCtx, dialCancel := context.WithTimeout(ctx, 15*time.Second)
	vertexConn, _, err := websocket.Dial(dialCtx, vertexURL, dialOpts)
	dialCancel()
	if err != nil {
		log.Printf("[LiveProxy] Failed to dial Vertex AI live endpoint (%s): %v", vertexURL, err)
		_ = writeClientJSON(ctx, clientConn, ClientTranscriptEvent{
			Type:  "error",
			Error: fmt.Sprintf("Failed to connect to Vertex Live API: %v", err),
		})
		return
	}
	defer func() { _ = vertexConn.Close(websocket.StatusNormalClosure, "closing upstream") }()
	vertexConn.SetReadLimit(1 << 20) // 1MB read limit for upstream Vertex messages

	log.Printf("[LiveProxy] Connected to Vertex AI Live API for model %s", modelPath)

	// 4. Send initial Setup frame to Vertex AI
	setupMsg := BuildLiveSetupMessage(modelPath, modeParam, langParam)
	log.Printf("[LiveProxy] Sending Live setup for model %s (mode=%q, lang=%q)", modelPath, modeParam, langParam)
	setupBytes, _ := json.Marshal(setupMsg)
	if err := vertexConn.Write(ctx, websocket.MessageText, setupBytes); err != nil {
		log.Printf("[LiveProxy] Failed to write setup message: %v", err)
		return
	}

	// 5. Wait for setupComplete from Vertex AI
	setupTimeoutCtx, setupTimeoutCancel := context.WithTimeout(ctx, 15*time.Second)
	_, respData, err := vertexConn.Read(setupTimeoutCtx)
	setupTimeoutCancel()
	if err != nil {
		log.Printf("[LiveProxy] Failed waiting for setupComplete: %v", err)
		return
	}

	var setupResp struct {
		SetupComplete *struct {
			SessionID string `json:"sessionId"`
		} `json:"setupComplete"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	_ = json.Unmarshal(respData, &setupResp)

	if setupResp.Error != nil {
		log.Printf("[LiveProxy] Vertex returned setup error: %s", setupResp.Error.Message)
		_ = writeClientJSON(ctx, clientConn, ClientTranscriptEvent{
			Type:  "error",
			Error: setupResp.Error.Message,
		})
		return
	}

	sessionID := ""
	if setupResp.SetupComplete != nil {
		sessionID = setupResp.SetupComplete.SessionID
	}
	log.Printf("[LiveProxy] Vertex setupComplete acknowledged (SessionID: %s)", sessionID)

	// Notify client ready
	_ = writeClientJSON(ctx, clientConn, ClientTranscriptEvent{
		Type:      "ready",
		SessionID: sessionID,
	})

	startTime := time.Now()

	// 6. Upstream relay: Vertex -> Client
	go func() {
		defer cancel()
		for {
			_, data, err := vertexConn.Read(ctx)
			if err != nil {
				return
			}

			var vMsg struct {
				ServerContent *struct {
					InputTranscription *struct {
						Text string `json:"text"`
					} `json:"inputTranscription"`
					InterimInputTranscription *struct {
						Text string `json:"text"`
					} `json:"interimInputTranscription"`
					GenerationComplete bool `json:"generationComplete"`
					TurnComplete       bool `json:"turnComplete"`
				} `json:"serverContent"`
				VoiceActivity *struct {
					Type        string `json:"type"`
					AudioOffset string `json:"audioOffset"`
				} `json:"voiceActivity"`
				Error *struct {
					Message string `json:"message"`
				} `json:"error"`
			}

			if err := json.Unmarshal(data, &vMsg); err != nil {
				continue
			}

			if vMsg.Error != nil {
				log.Printf("[LiveProxy] Upstream error: %s", vMsg.Error.Message)
				_ = writeClientJSON(ctx, clientConn, ClientTranscriptEvent{
					Type:  "error",
					Error: vMsg.Error.Message,
				})
				continue
			}

			if vMsg.VoiceActivity != nil {
				_ = writeClientJSON(ctx, clientConn, ClientTranscriptEvent{
					Type: "activity",
					Text: vMsg.VoiceActivity.Type,
				})
			}

			if vMsg.ServerContent != nil {
				sc := vMsg.ServerContent
				var text string
				var isFinal bool

				if sc.InputTranscription != nil && strings.TrimSpace(sc.InputTranscription.Text) != "" {
					text = strings.TrimSpace(sc.InputTranscription.Text)
					isFinal = true
				} else if sc.InterimInputTranscription != nil && strings.TrimSpace(sc.InterimInputTranscription.Text) != "" {
					text = strings.TrimSpace(sc.InterimInputTranscription.Text)
					isFinal = false
				}

				if text != "" {
					elapsed := time.Since(startTime).Seconds()
					_ = writeClientJSON(ctx, clientConn, ClientTranscriptEvent{
						Type:      "transcript",
						Text:      text,
						IsFinal:   isFinal,
						Timestamp: elapsed,
					})
				}
			}
		}
	}()

	// 7. Downstream relay: Client -> Vertex (with bounded PCM fallback buffer)
	var fallbackPCM bytes.Buffer
	for {
		_, clientData, err := clientConn.Read(ctx)
		if err != nil {
			break
		}

		// Try parsing simplified client frame first: {"audio": "<b64>"}
		var frame ClientAudioFrame
		if err := json.Unmarshal(clientData, &frame); err == nil && frame.Audio != "" {
			if clientSessionID != "" && fallbackPCM.Len() < maxLiveFallbackPCMBytes {
				if decoded, decErr := base64.StdEncoding.DecodeString(frame.Audio); decErr == nil && len(decoded) > 0 {
					remaining := maxLiveFallbackPCMBytes - fallbackPCM.Len()
					if len(decoded) > remaining {
						decoded = decoded[:remaining]
					}
					_, _ = fallbackPCM.Write(decoded)
				}
			}

			mimeType := frame.MimeType
			if mimeType == "" {
				mimeType = "audio/pcm;rate=16000"
			}
			realtimeInput := map[string]any{
				"realtimeInput": map[string]any{
					"mediaChunks": []map[string]any{
						{
							"mimeType": mimeType,
							"data":     frame.Audio,
						},
					},
				},
			}
			rtBytes, _ := json.Marshal(realtimeInput)
			if err := vertexConn.Write(ctx, websocket.MessageText, rtBytes); err != nil {
				break
			}
		} else {
			// Direct passthrough if already formatted
			if err := vertexConn.Write(ctx, websocket.MessageText, clientData); err != nil {
				break
			}
		}
	}

	log.Printf("[LiveProxy] Live session ended (session=%q, fallbackPCMBytes=%d).", clientSessionID, fallbackPCM.Len())

	// 8. Schedule orphan-session fallback check if the client drops without uploading audio
	if clientSessionID != "" && lp.store != nil {
		pcmCopy := append([]byte(nil), fallbackPCM.Bytes()...)
		grace := lp.orphanGracePeriod
		if grace <= 0 {
			grace = defaultOrphanGrace
		}
		lp.bgWg.Add(1)
		go func() {
			defer lp.bgWg.Done()
			timer := time.NewTimer(grace)
			defer timer.Stop()
			<-timer.C
			bgCtx, bgCancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer bgCancel()
			lp.recoverOrphanedSession(bgCtx, clientSessionID, pcmCopy)
		}()
	}
}

func (lp *LiveProxy) recoverOrphanedSession(ctx context.Context, sessionID string, pcmBytes []byte) {
	if lp.store == nil || sessionID == "" {
		return
	}
	session, err := lp.store.GetSession(ctx, sessionID)
	if err != nil {
		return
	}
	// If the mobile client already uploaded audio or finalized the session, do nothing.
	if session.Status != StatusRecording {
		return
	}

	now := time.Now().UTC()
	session.FinishedAt = &now
	session.Status = StatusFailed

	if len(pcmBytes) > 0 && lp.audioStore != nil {
		wavBytes := buildPCM16WAV(pcmBytes, 16000, 1)
		if uri, err := lp.audioStore.UploadWAV(ctx, sessionID, wavBytes); err != nil {
			log.Printf("[LiveProxy] Failed uploading fallback WAV for orphaned session %s: %v", sessionID, err)
			session.Summary = "Recording ended unexpectedly; fallback audio upload failed."
		} else {
			session.AudioURL = uri
			session.HasAudio = true
			session.DurationSeconds = float64(len(pcmBytes)) / float64(16000*2)
			session.Summary = "Recording interrupted — audio recovered on server. Use Retry Diarization to process."
			log.Printf("[LiveProxy] Recovered %d bytes of fallback audio for orphaned session %s -> %s", len(pcmBytes), sessionID, uri)
		}
	} else {
		session.Summary = "Recording ended unexpectedly without audio upload."
		log.Printf("[LiveProxy] Transitioned orphaned empty session %s from recording -> failed", sessionID)
	}

	if err := lp.store.SaveSession(ctx, session); err != nil {
		log.Printf("[LiveProxy] Failed saving recovered orphaned session %s: %v", sessionID, err)
	}
}

func buildPCM16WAV(pcm []byte, sampleRate, channels uint32) []byte {
	const bitsPerSample = 16
	dataSize := uint32(len(pcm))
	byteRate := sampleRate * channels * (bitsPerSample / 8)
	blockAlign := uint16(channels * (bitsPerSample / 8))

	wav := make([]byte, 44+len(pcm))
	copy(wav[0:4], "RIFF")
	binary.LittleEndian.PutUint32(wav[4:8], 36+dataSize)
	copy(wav[8:12], "WAVE")
	copy(wav[12:16], "fmt ")
	binary.LittleEndian.PutUint32(wav[16:20], 16)
	binary.LittleEndian.PutUint16(wav[20:22], 1)
	binary.LittleEndian.PutUint16(wav[22:24], uint16(channels))
	binary.LittleEndian.PutUint32(wav[24:28], sampleRate)
	binary.LittleEndian.PutUint32(wav[28:32], byteRate)
	binary.LittleEndian.PutUint16(wav[32:34], blockAlign)
	binary.LittleEndian.PutUint16(wav[34:36], bitsPerSample)
	copy(wav[36:40], "data")
	binary.LittleEndian.PutUint32(wav[40:44], dataSize)
	copy(wav[44:], pcm)
	return wav
}

func writeClientJSON(ctx context.Context, conn *websocket.Conn, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return conn.Write(ctx, websocket.MessageText, data)
}
