package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"sync"

	"cloud.google.com/go/storage"
)

// AudioStore defines the interface for persisting and retrieving recorded session WAV audio.
type AudioStore interface {
	UploadWAV(ctx context.Context, sessionID string, wavBytes []byte) (string, error)
	DownloadWAV(ctx context.Context, sessionID string) (io.ReadCloser, int64, error)
	Close() error
}

// GCSStore persists session audio to a Google Cloud Storage bucket.
type GCSStore struct {
	client *storage.Client
	bucket string
}

// NewGCSStore creates a new GCS-backed audio store.
func NewGCSStore(ctx context.Context, bucket string) (*GCSStore, error) {
	if bucket == "" {
		return nil, fmt.Errorf("gcs bucket name is empty")
	}

	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize gcs client: %w", err)
	}

	return &GCSStore{
		client: client,
		bucket: bucket,
	}, nil
}

// UploadWAV uploads WAV audio to gs://{bucket}/sessions/{sessionID}/audio.wav
func (g *GCSStore) UploadWAV(ctx context.Context, sessionID string, wavBytes []byte) (string, error) {
	if g == nil || g.client == nil {
		return "", fmt.Errorf("gcs store is not initialized")
	}

	objectPath := fmt.Sprintf("sessions/%s/audio.wav", sessionID)
	obj := g.client.Bucket(g.bucket).Object(objectPath)

	w := obj.NewWriter(ctx)
	w.ContentType = "audio/wav"
	w.Metadata = map[string]string{
		"session_id": sessionID,
	}

	if _, err := w.Write(wavBytes); err != nil {
		_ = w.Close()
		return "", fmt.Errorf("failed writing to gcs object %s: %w", objectPath, err)
	}

	if err := w.Close(); err != nil {
		return "", fmt.Errorf("failed closing gcs object %s: %w", objectPath, err)
	}

	gsURI := fmt.Sprintf("gs://%s/%s", g.bucket, objectPath)
	log.Printf("[GCSStore] Uploaded %d bytes to %s", len(wavBytes), gsURI)
	return gsURI, nil
}

// DownloadWAV opens a reader for gs://{bucket}/sessions/{sessionID}/audio.wav
func (g *GCSStore) DownloadWAV(ctx context.Context, sessionID string) (io.ReadCloser, int64, error) {
	if g == nil || g.client == nil {
		return nil, 0, fmt.Errorf("gcs store is not initialized")
	}

	objectPath := fmt.Sprintf("sessions/%s/audio.wav", sessionID)
	obj := g.client.Bucket(g.bucket).Object(objectPath)

	attrs, err := obj.Attrs(ctx)
	if err != nil {
		return nil, 0, fmt.Errorf("audio object not found: %w", err)
	}

	reader, err := obj.NewReader(ctx)
	if err != nil {
		return nil, 0, fmt.Errorf("failed creating reader for %s: %w", objectPath, err)
	}

	return reader, attrs.Size, nil
}

func (g *GCSStore) Close() error {
	if g != nil && g.client != nil {
		return g.client.Close()
	}
	return nil
}

// NoopAudioStore provides an in-memory fallback audio store when GCS is not configured.
type NoopAudioStore struct {
	mu    sync.RWMutex
	files map[string][]byte
}

func (n *NoopAudioStore) UploadWAV(_ context.Context, sessionID string, wavBytes []byte) (string, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.files == nil {
		n.files = make(map[string][]byte)
	}
	copied := make([]byte, len(wavBytes))
	copy(copied, wavBytes)
	n.files[sessionID] = copied
	return fmt.Sprintf("memory://sessions/%s/audio.wav", sessionID), nil
}

func (n *NoopAudioStore) DownloadWAV(_ context.Context, sessionID string) (io.ReadCloser, int64, error) {
	n.mu.RLock()
	defer n.mu.RUnlock()
	if n.files != nil {
		if data, ok := n.files[sessionID]; ok {
			return io.NopCloser(bytes.NewReader(data)), int64(len(data)), nil
		}
	}
	return nil, 0, fmt.Errorf("audio not found in memory store")
}

func (n *NoopAudioStore) Close() error {
	return nil
}
