# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Common Changelog](https://common-changelog.org/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-08-29

### Added
- **Live Transcription Mode**: Added selector in Flutter app Settings (`Verbatim` vs `Smart`) to toggle real-time disfluency and filler-word removal on Gemini 3.5 Transcribe Live.
- **Live WebSocket Mode & Language Codes**: Updated Cloud Run Go live proxy (`/api/live`) to parse `mode` and `lang` query parameters and inject `inputAudioTranscription` configuration into Vertex AI setup frames.
- **BLE Device Retention & Auto-Reconnect**: Stored last paired Omi Bluetooth device ID and name in local storage (`SharedPreferences`) to enable automatic background reconnection on app launch with home screen visual feedback.
- **Unified Versioning**: Introduced unified semantic versioning across mobile app (`0.2.0+2` in `pubspec.yaml`), Go backend (`service/version.go`, Docker `-ldflags` build injection), and `/api/health` status response.

### Fixed
- **Diarized Turns in Session Detail**: Resolved missing speaker segments in Flutter app by re-fetching full `SessionDetail` via `GET /api/sessions/{id}` upon opening and updating local session cache.
- **Language Code Passthrough**: Fixed live proxy WebSocket setup to map and forward BCP-47 `languageCodes` in the Vertex AI live setup frame.

### Removed
- **Legacy API Key Gate**: Removed obsolete client-side `geminiApiKey` check on conversation start in favor of Cloud Run ADC authentication.

## [0.1.0] - 2026-08-29

_Initial release._

### Added
- Flutter companion app (`app/`) for Google Pixel 11 with BLE Opus audio streaming and decoding.
- Cloud Run Go backend (`service/`) with Vertex AI Live WebSocket proxy (`gemini-3.5-transcribe-live-preview`), batch diarization (`gemini-3.5-transcribe-preview`), title generation (`gemini-3.5-flash-lite`), and summary synthesis (`gemini-3.7-flash`).
- Firebase Authentication with Firestore `authorized_users` allowlist middleware and authenticated Single Page Application (SPA) web review dashboard.
- Google Cloud Storage session audio persistence and streaming playback endpoint (`GET /api/sessions/{id}/audio`).
- Audio playback cards with turn tap-to-seek synchronization on both mobile and web clients.
- Infrastructure automation scripts (`infra/`) and top-level `Makefile`.

[Unreleased]: https://github.com/ghchinoy/omi-pixel/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ghchinoy/omi-pixel/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ghchinoy/omi-pixel/releases/tag/v0.1.0
