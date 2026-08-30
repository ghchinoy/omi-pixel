package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"omi-pixel-service/web"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	projectID := os.Getenv("GOOGLE_CLOUD_PROJECT")
	database := os.Getenv("FIRESTORE_DATABASE")
	location := os.Getenv("GOOGLE_CLOUD_LOCATION")
	if location == "" {
		location = "global"
	}
	geminiModel := os.Getenv("GEMINI_MODEL")
	if geminiModel == "" {
		geminiModel = "gemini-3.5-transcribe-preview"
	}
	liveModel := os.Getenv("GEMINI_LIVE_MODEL")
	if liveModel == "" {
		liveModel = "gemini-3.5-transcribe-live-preview"
	}
	titleModel := os.Getenv("TITLE_MODEL")
	if titleModel == "" {
		titleModel = "gemini-3.5-flash-lite"
	}
	summaryModel := os.Getenv("SUMMARY_MODEL")
	if summaryModel == "" {
		summaryModel = "gemini-3.7-flash"
	}

	gcsBucket := os.Getenv("GCS_BUCKET")

	ctx := context.Background()

	var store Store
	if projectID != "" {
		fsStore, err := NewFirestoreStore(ctx, projectID, database)
		if err != nil {
			log.Printf("Warning: Failed to initialize Firestore (%v). Falling back to in-memory store.", err)
			store = NewMemoryStore()
		} else {
			log.Printf("Initialized Google Cloud Firestore store for project '%s'", projectID)
			store = fsStore
		}
	} else {
		log.Println("GOOGLE_CLOUD_PROJECT not set. Using in-memory store.")
		store = NewMemoryStore()
	}
	defer store.Close()

	var audioStore AudioStore = &NoopAudioStore{}
	if gcsBucket != "" {
		gStore, err := NewGCSStore(ctx, gcsBucket)
		if err != nil {
			log.Printf("Warning: Failed to initialize GCS store (%v). Audio will be processed inline.", err)
		} else {
			log.Printf("Initialized Google Cloud Storage audio store (Bucket: %s)", gcsBucket)
			audioStore = gStore
			defer audioStore.Close()
		}
	} else {
		log.Println("GCS_BUCKET not set. Audio will be processed inline without bucket persistence.")
	}

	authDisabled := os.Getenv("AUTH_DISABLED") == "true" || os.Getenv("AUTH_DISABLED") == "1"
	authenticator, err := NewAuthenticator(ctx, projectID, store, authDisabled)
	if err != nil {
		log.Printf("Warning: Failed to initialize Firebase Auth (%v). Running with AUTH_DISABLED=true fallback.", err)
		authenticator, _ = NewAuthenticator(ctx, projectID, store, true)
	} else if !authDisabled {
		log.Printf("Firebase Authentication initialized (Project: %s, Allowlist Collection: authorized_users)", projectID)
	}

	vertexAuth, err := NewVertexAuth(ctx)
	if err != nil {
		log.Printf("Warning: Failed to initialize Vertex AI ADC credentials (%v). Live proxy and diarization will fail until ADC is available.", err)
	} else {
		log.Printf("Vertex AI ADC initialized (Project: %s, Location: %s)", projectID, location)
	}

	geminiClient := NewGeminiClient(vertexAuth, projectID, location, geminiModel, titleModel, summaryModel)
	liveProxy := NewLiveProxy(vertexAuth, projectID, location, liveModel)

	log.Printf("Gemini Transcribe configured: Batch=%s, Live=%s, Title=%s, Summary=%s (Vertex AI %s)",
		geminiModel, liveModel, titleModel, summaryModel, location)

	spaTmpl, err := web.ParseTemplates()
	if err != nil {
		log.Fatalf("Failed to parse HTML templates: %v", err)
	}

	webConfig := web.DefaultWebConfig
	webConfig.AuthDisabled = authDisabled
	if projectID != "" {
		webConfig.ProjectID = projectID
		webConfig.AuthDomain = fmt.Sprintf("%s.firebaseapp.com", projectID)
		webConfig.StorageBucket = fmt.Sprintf("%s.firebasestorage.app", projectID)
	}
	if v := os.Getenv("FIREBASE_API_KEY"); v != "" {
		webConfig.APIKey = v
	}
	if v := os.Getenv("FIREBASE_APP_ID"); v != "" {
		webConfig.AppID = v
	}
	if v := os.Getenv("FIREBASE_MESSAGING_SENDER_ID"); v != "" {
		webConfig.MessagingSenderID = v
	}
	if v := os.Getenv("FIREBASE_AUTH_DOMAIN"); v != "" {
		webConfig.AuthDomain = v
	}
	if v := os.Getenv("FIREBASE_STORAGE_BUCKET"); v != "" {
		webConfig.StorageBucket = v
	}

	server := NewServer(store, audioStore, geminiClient, liveProxy, authenticator, spaTmpl, webConfig)
	httpServer := &http.Server{
		Addr:         ":" + port,
		Handler:      server.Routes(),
		ReadTimeout:  60 * time.Second,
		WriteTimeout: 600 * time.Second, // Allow sufficient time for long Gemini audio processing
		IdleTimeout:  120 * time.Second,
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("Omi-Pixel Service v%s listening on port %s", Version, port)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server listen error: %v", err)
		}
	}()

	<-stop
	log.Println("Shutting down server...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited gracefully.")
}
