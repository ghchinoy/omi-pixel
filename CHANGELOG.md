# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Common Changelog](https://common-changelog.org/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-11-01

### Added
- **Settings Version Display & `install-apk` Target**: Added app and Cloud Run backend version readout (`App v0.3.0+3 • Backend v0.3.0`) to `SettingsScreen` and added `make install-apk` target to `Makefile`.

### Changed
- **Vertex AI GA Gemini Models**: Upgraded defaults from preview/deprecated models to latest Vertex AI GA releases (`gemini-3.5-transcribe-live`, `gemini-3.5-transcribe`, and `gemini-3.8-flash`).
- **Dependency Security Upgrades**: Upgraded Go backend to Go 1.26.0 and latest Cloud/Firebase/gRPC/crypto packages, Web SPA Firebase JS SDK to `13.1.0`, and Flutter app dependencies (`firebase_core ^5.1.0`, `firebase_auth ^7.0.1`, `google_sign_in ^7.2.0`, `flutter_blue_plus ^2.3.14`, `flutter_foreground_task ^11.0.3`, `permission_handler ^13.0.2`, `intl ^0.20.3`).
- **Backend Security & Reliability Hardening**: Added session ID validation, `http.MaxBytesReader` request limits, Firestore `SaveSegments` batch chunking, 1MB WebSocket read limits, bounded `NoopAudioStore` FIFO eviction, and filtered out internal `thought` parts in `GeminiClient.generateText`.

### Fixed
- **Device Local Timezone Display**: Converted RFC3339 UTC timestamps (`started_at`, `finished_at`, `created_at`) to local device time via `.toLocal()` in `Session.fromJson` and UI formatters so conversation times render in local time instead of UTC.
- **Multi-Language Auto-Detection in Batch Diarization**: Omitted `languageCodes` when `language == "multi"` in `DiarizeAudio` so Gemini 3.5 Transcribe auto-detects across 85+ spoken languages.
- **BLE Scan Permission Race**: Awaited `requestPermissions()` before starting BLE scan stream in `BleService.scanDevicesStream`.

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

[Unreleased]: https://github.com/ghchinoy/omi-pixel/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/ghchinoy/omi-pixel/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ghchinoy/omi-pixel/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ghchinoy/omi-pixel/releases/tag/v0.1.0
