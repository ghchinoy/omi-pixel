package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/coder/websocket"
)

// LiveProxy handles bridging mobile clients with the Vertex AI Gemini 3.5 Transcribe Live WebSocket.
type LiveProxy struct {
	vertexAuth *VertexAuth
	projectID  string
	location   string
	liveModel  string
}

func NewLiveProxy(auth *VertexAuth, projectID, location, liveModel string) *LiveProxy {
	if location == "" {
		location = "global"
	}
	if liveModel == "" {
		liveModel = "gemini-3.5-transcribe-live-preview"
	}
	return &LiveProxy{
		vertexAuth: auth,
		projectID:  projectID,
		location:   location,
		liveModel:  liveModel,
	}
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

func (lp *LiveProxy) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	if lp.vertexAuth == nil || lp.projectID == "" {
		http.Error(w, "Vertex AI credentials or GOOGLE_CLOUD_PROJECT not configured", http.StatusServiceUnavailable)
		return
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
	defer clientConn.Close(websocket.StatusNormalClosure, "session closed")

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
	defer vertexConn.Close(websocket.StatusNormalClosure, "closing upstream")

	log.Printf("[LiveProxy] Connected to Vertex AI Live API for model %s", modelPath)

	// 4. Send initial Setup frame to Vertex AI
	setupMsg := map[string]interface{}{
		"setup": map[string]interface{}{
			"model": modelPath,
			"generationConfig": map[string]interface{}{
				"responseModalities": []string{"TEXT"},
			},
			"inputAudioTranscription": map[string]interface{}{},
		},
	}
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

	// 7. Downstream relay: Client -> Vertex
	for {
		_, clientData, err := clientConn.Read(ctx)
		if err != nil {
			break
		}

		// Try parsing simplified client frame first: {"audio": "<b64>"}
		var frame ClientAudioFrame
		if err := json.Unmarshal(clientData, &frame); err == nil && frame.Audio != "" {
			mimeType := frame.MimeType
			if mimeType == "" {
				mimeType = "audio/pcm;rate=16000"
			}
			realtimeInput := map[string]interface{}{
				"realtimeInput": map[string]interface{}{
					"mediaChunks": []map[string]interface{}{
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

	log.Printf("[LiveProxy] Live session ended.")
}

func writeClientJSON(ctx context.Context, conn *websocket.Conn, v interface{}) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return conn.Write(ctx, websocket.MessageText, data)
}
