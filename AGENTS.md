<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git
rtk git status          rtk git diff            rtk git log

# Files & Search
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>

# Build & Test
rtk cargo test          rtk go test ./...       rtk flutter test
rtk tsc                 rtk lint
```
<!-- /headroom:rtk-instructions -->

# Omi-Pixel Project Guidelines

## Overview
`omi-pixel` is a standalone, lightweight Flutter mobile companion app and Go Cloud Run backend for Omi hardware devices (DevKit & CV1) on Google Pixel (Android).

## Architecture
- **App (`app/`)**: Flutter app targeting Android (Pixel 11). Connects directly to Omi via BLE using `sdks/device/dart` (`omi_device`), decodes Opus audio to 16kHz PCM, streams live transcription via Cloud Run WebSocket proxy to Gemini 3.5 Transcribe Live (`gemini-3.5-transcribe-live-preview`), and uploads recorded session WAVs to Cloud Run.
- **Backend Service (`service/`)**: Go HTTP & WebSocket service deployed on Google Cloud Run. Proxies live audio to Vertex AI Multimodal Live WebSocket and performs Gemini 3.5 Transcribe batch diarization (`gemini-3.5-transcribe-preview`) on Vertex AI with native speaker diarization, persists sessions to Firestore, and serves a responsive Web Review UI.
- **Infrastructure (`infra/`)**: Shell automation for GCP project enablement, Firestore provisioning, Artifact Registry, and Cloud Run deployment.

## Code Standards
- Keep dependencies lean and minimal.
- Mobile app uses standard Firebase Auth & Google Sign-In for access tokens; zero Firestore/Storage client SDKs on device.
- Go backend uses standard library HTTP routing, official `cloud.google.com/go/firestore`, `cloud.google.com/go/storage`, and `firebase.google.com/go/v4` SDKs.
