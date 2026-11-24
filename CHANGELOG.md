# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Common Changelog](https://common-changelog.org/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.4] - 2026-11-24

### Changed
- **Flutter 3.50.1 Stable, AGP 9.3.1 / Gradle 9.5.0 & `package:material_ui` Migration**: Upgraded local & CI Flutter toolchains to `3.50.1` (`Dart 3.14.0`), upgraded Android Gradle Plugin (`8.11.1` → `9.3.1`), Gradle wrapper (`8.14.2` → `9.5.0`), Kotlin Gradle Plugin (`2.4.20`), and GitHub Actions JDK (`17` → `21`), added an `afterEvaluate` subproject `compileSdk` floor (`36`) for legacy plugins (`opus_flutter_android`) under AGP 9 AAR metadata checks, and migrated all 9 `package:flutter/material.dart` imports to `package:material_ui/material_ui.dart` (`material_ui: ^1.1.0`) with zero strict analyzer issues and smaller release APKs (`62.9 MB`) `[omi-pixel-4pd]`.

## [0.4.3] - 2026-11-23

### Added
- **Universal Pre-Built APK & Runtime Firebase Bootstrap**: Added public `GET /api/client-config` on the Go backend returning non-secret public Firebase client config, runtime `FirebaseOptions` discovery + persistence in `AuthService.configureFromBackend()` (triggered automatically by **Settings → Test Connection**), and browser OAuth fallback via `FirebaseAuth.signInWithProvider(GoogleAuthProvider())` so a single pre-built GitHub Release APK works against any self-hosted Cloud Run backend with zero local Flutter install or Android SHA-1 setup `[omi-pixel-gnq, omi-pixel-88n]`.
- **GitHub Actions CI & Automated Release APK Builds**: Added `.github/workflows/ci-and-release-apk.yml` (Node 24 action majors, pinned Flutter `3.47.9` matching AGP 8.11 / Gradle 8.14) running Go `vet`/`-race`/build and Flutter `analyze`/`test`/standalone release APK build on every push, PR, manual `workflow_dispatch`, and `v*` tag release — automatically attaching `omi-pixel-vX.Y.Z.apk` and `.sha256` checksums to GitHub Releases `[omi-pixel-08o]`.
- **Standalone Flutter Onboarding & `make doctor-app`**: Replaced the sibling `../../omi` path dependency with a self-contained `OmiBleTransport` (`app/lib/services/omi_ble_protocol.dart`) over `flutter_blue_plus`, made `com.google.gms.google-services` conditional in `app/android/app/build.gradle.kts`, added optional `app/android/key.properties` release signing + `-PapplicationId` override, added `make doctor-app`, and switched `app/lib/firebase_options.dart` to a clean `--dart-define` template `[omi-pixel-661]`.
- **Cloud Run & Web SPA Onboarding Automation**: Added `infra/sync-firebase-env.sh` (`make sync-firebase-env`, auto-chained into `make configure-firebase`) to extract Web & Android Firebase keys from `firebase_options.dart` into `infra/.env`, and hardened `infra/preflight.sh` to validate `cloudbuild`, `aiplatform`, `firestore`, `storage` APIs and Firebase Web keys before deploy `[omi-pixel-3ad]`.
- **Flutter Widget Tree Diagrams (Dark & Light)**: Added `docs/diagrams/flutter-widget-tree.dot` / `-light.dot` (`.webp` assets) and Developer Guide Section 5 documenting the Flutter companion widget hierarchy and service bindings `[omi-pixel-lfu]`.

### Changed
- **Expanded Makefile Target Reference**: Audited all 21 `.PHONY` targets, added `make clean` to `make help`, organized `docs/user-guide.md` into 4 categorized tables with parameters and examples, and documented the pre-built universal APK install flow in `README.md`, `docs/user-guide.md`, and `docs/developer-guide.md` `[omi-pixel-aj3]`.

## [0.4.2] - 2026-11-23

### Added
- **Hands-Free Omi Hardware Button & Haptic Control**: Subscribed to the Omi BLE Button GATT service (`23ba7924` / `23ba7925`) and Haptic GATT service (`cab1ab95` / `cab1ab96`) with native Android `KeyguardManager.isKeyguardLocked` lock-screen protection (`MainActivity.kt`) and 1.5s debounce. Single-tap when idle (Pixel unlocked) starts recording with a 1× 50ms haptic buzz; double-tap while recording finishes & diarizes in the background with 2× 20ms buzzes (works even while locked). Added a permanent Settings toggle, **Test Haptic** button, live `deviceStream` updates, and clear Android background/unlock disclosure `[omi-pixel-8nh, omi-pixel-gka]`.
- **Mineral Slate Light Mode Diagrams**: Added `docs/diagrams/architecture-light.dot` / `.webp` and `docs/diagrams/dataflow-light.dot` / `.webp` (plus updated dark diagrams for hardware button & haptic GATT) and wired adaptive `<picture>` `prefers-color-scheme` sources in `README.md` and `docs/developer-guide.md`.

### Changed
- **Updated User & Developer Guides**: Added hands-free Omi hardware button instructions, Android lock/background disclosure, troubleshooting, and Button/Haptic GATT protocol documentation to `docs/user-guide.md` and `docs/developer-guide.md`.

## [0.4.1] - 2026-11-23

### Added
- **Smart-Mode Corrected Transcript Persistence & View Switcher**: Added `transcription_mode` and `smart_transcript` to `Session` (Firestore + JSON API + Flutter model), launched a parallel standalone batch `SMART` pass (`diarization=false, wordTimestamp=false, mode="SMART"`) alongside batch diarization when recorded in Smart mode (feeding corrected wording into title & `gemini-4-hydrogen` summaries), and added cobalt **`SMART`** badges plus a **Smart Transcript** ↔ **Diarized Turns** segmented view switcher in both the Web Review SPA and Flutter `SessionDetailScreen` `[omi-pixel-dcy, omi-pixel-60o]`.
- **Refreshed Lustrous Dark & Light Mode Visuals**: Captured updated v0.4 Obsidian Slate dark and Mineral Slate light `.webp` screenshots for the Web Review SPA and Pixel app (plus regenerated `live-demo.gif`) and wired adaptive `<picture>` `prefers-color-scheme` sources in `README.md` `[omi-pixel-5nm, omi-pixel-8np]`.

### Changed
- **Documentation & Omi Hardware Links**: Updated `docs/user-guide.md` and `docs/developer-guide.md` for v0.4+ architecture (ForegroundService, disk PCM/WAV queue, non-blocking diarization, Bearer-header `/api/live`, orphan recovery, Smart mode, and Lustrous UI), added links to [Omi](https://www.omi.me/) in `README.md`, and shortened the Web search placeholder to `"Search sessions…"` `[omi-pixel-fso, omi-pixel-5d6]`.

## [0.4.0] - 2026-11-23

### Added
- **Lustrous Web Review SPA (`@ghchinoy/lustrous-lit@0.2.0`)**: Migrated `service/web/templates.go` to the Lustrous Design System via pinned CDN (`jsDelivr` CSS + bundled OFL-1.1 Google Sans Flex/Code fonts + single `esm.sh` root bundle), featuring a persisted Light/Auto/Dark `<lustrous-segmented-control>` theme switcher, focus-preserving `<lustrous-search-bar>` session filter, `<lustrous-pressable>` cards, semantic `<lustrous-badge>` statuses, 6 WCAG 2.1 AA dual-theme categorical speaker pills, `<lustrous-banner>` processing/summary/retry states, modal `<lustrous-dialog>` delete confirmation, and `<lustrous-snackbar>` toasts `[omi-pixel-0xm.1, omi-pixel-0xm.2]`.
- **Lustrous Flutter Theme & Light/Auto/Dark Mode**: Added `app/lib/theme/lustrous_theme.dart` (`LustrousTheme.light()` Mineral Slate, `LustrousTheme.dark()` Obsidian Slate, and `LustrousColors` `ThemeExtension` with semantic containers and 6 WCAG-AA speaker color pairs), a live Light/Auto/Dark switcher in `SettingsScreen`, and replaced hardcoded colors across all 5 mobile screens `[omi-pixel-0xm.3, omi-pixel-0xm.4]`.
- **Long-Press Verbatim ↔ Smart Mode Switcher**: Long-pressing `"Start Conversation"` on `HomeScreen` now opens a bottom sheet to quick-switch between **Verbatim** and **Smart (Inline Self-Corrections)** with haptic feedback and a live mode indicator beneath the CTA `[omi-pixel-0xm.5]`.

### Changed
- **Refreshed Architecture & Dataflow Diagrams**: Updated `docs/diagrams/architecture.dot` and `docs/diagrams/dataflow.dot` with the Lustrous Obsidian Slate palette and v0.4.0 pipeline (ForegroundService, disk PCM/WAV upload queue, Bearer-header `/api/live`, orphan PCM recovery, Gemini 4 Hydrogen default summary, and Lustrous Web/Mobile UI) and regenerated `.webp` assets `[omi-pixel-0wl]`.

### Fixed
- **Narrow-Screen HomeScreen Overflow**: Wrapped and shortened the Start Conversation mode caption (`Mode: Verbatim/Smart • Hold to switch`), constrained HomeScreen header/device rows with ellipsis, and made the live mode bottom sheet scrollable for zero overflow at 360dp width `[omi-pixel-qhm]`.

## [0.3.4] - 2026-11-23

### Added
- **Gemini 4 Hydrogen Summary Model & Settings Selector**: Switched default `SUMMARY_MODEL` to `gemini-4-hydrogen` (`thinkingLevel: LOW` with plain-text guidance), added a **Summary Generation Model** selector in `SettingsScreen` (`Gemini 4 Hydrogen (Default)` / `Gemini 3.8 Flash (Faster)`), and added server-side allowlist validation (`ResolveSummaryModel`) for optional `?summary_model=...` overrides on upload and reprocess endpoints `[omi-pixel-m6s, omi-pixel-na4]`.
- **LiveProxy Orphan PCM Recovery & Session Deletion**: Added a 32 MB-capped fallback PCM buffer in `LiveProxy` that recovers interrupted recordings to GCS WAV and transitions abandoned sessions out of `recording`, plus authenticated `DELETE /api/sessions/{id}` (deleting Firestore doc, segments subcollection via `BulkWriter`, and GCS WAV) exposed in both the Web Review SPA and Flutter `SessionDetailScreen` `[omi_pixel-zhl]`.

### Fixed
- **Auto-Dismiss Diarization SnackBars**: Set `persist: false` and `clearSnackBars()` on action SnackBars in `LiveScreen` and `HomeScreen` so background diarization notifications auto-dismiss cleanly after 5 seconds instead of staying pinned.

### Security
- **Eliminated Firebase JWT Leak in `/api/live` Query String**: Moved Firebase ID token authentication on `/api/live` from `?access_token=<jwt>` to the `Authorization: Bearer` WebSocket upgrade header in `GeminiLiveService` and removed query-string token acceptance in `service/auth.go` so JWTs are never logged in Cloud Run HTTP request logs `[omi_pixel-p4l]`.

## [0.3.3] - 2026-11-23

### Added
- **Non-Blocking Background Diarization & Auto-Refresh**: Stopping a recording now finalizes the local WAV and returns immediately to `HomeScreen` while audio uploads and diarizes in the background (keeping the Android foreground notification active until complete). Added live `DIARIZING` badges, completion SnackBar with `"View"` action, auto-polling in `SessionDetailScreen` and the Web Review SPA, optional `?async=true` (`202 Accepted` with graceful shutdown drain) on `POST /api/sessions/{id}/audio`, and `POST /api/sessions/{id}/reprocess` for retrying stored GCS audio `[omi-pixel-6hb.2, omi-pixel-6hb.3]`.
- **Disk-Backed PCM/WAV Persistence & Retryable Upload Queue**: Added `RecordingFileStore` to stream decoded PCM chunks directly to `<ApplicationDocumentsDirectory>/omi_recordings` (removing unbounded RAM buffering), finalize durable WAVs on stop, recover orphaned `.pcm` files on startup, keep WAVs on disk until HTTP `200`/`202`, and expose one-tap **Retry Upload** banners in `HomeScreen` and `SessionDetailScreen` `[omi_pixel-2er]`.
- **Active vs. Idle Recording UX, Minimize Flow & Battery Check**: Updated `HomeScreen` to show an active **"Recording in Progress"** banner with live timer and **"Return to Live Recording"** CTA while recording, added a **Minimize (keep recording)** flow in `LiveScreen`, wired Android notification taps directly back to `LiveScreen` (`/live`), and added an Android battery-optimization status check in `SettingsScreen` `[omi-pixel-6hb.1]`.

### Fixed
- **LiveScreen Back Guard, BLE Disconnect Detection & 0-Audio Finalization**: Wrapped `LiveScreen` in `PopScope(canPop: false)` with a 3-way dialog (`Stay` / `Minimize` / `Finish & Diarize`), added `BluetoothDevice.connectionState` disconnect monitoring + live PCM audio health/stall pill in `LiveScreen`, and updated 0-audio `stopRecording()` to persist live segments (`completed`) or mark `failed` via `POST /api/sessions/{id}/segments` so Firestore never stays stuck in `status='recording'` `[omi_pixel-a85]`.
- **Expired Token Upload Recovery**: Added automatic single retry with `forceRefresh: true` on HTTP `401` in `ApiClient.uploadAudioDetailed()` so expired Firebase ID tokens do not cause audio loss after long recordings `[omi_pixel-2er]`.

## [0.3.2] - 2026-11-23

### Fixed
- **Android Background Recording Foreground Service**: Registered `com.pravera.flutter_foreground_task.service.ForegroundService` (`connectedDevice|microphone`, `exported="false"`) in `AndroidManifest.xml`, started the service explicitly with `ForegroundServiceTypes.connectedDevice` at runtime (holding WakeLock + WifiLock without requiring phone `RECORD_AUDIO` for BLE capture), requested notification permission on startup, and surfaced foreground service startup failures via `SessionManager.warningStream` and an inline warning banner in `LiveScreen` instead of swallowing errors `[omi_pixel-2yv]`.

## [0.3.1] - 2026-11-23

### Changed
- **Android Build Toolchain**: Upgraded Kotlin Gradle plugin to `2.4.21` and Android `compileSdk` to `37`.
- **Go & Flutter Dependency Freshness**: Upgraded Go backend modules (`cloud.google.com/go/storage v1.71.0`, `firebase.google.com/go/v4 v4.23.0`, `golang.org/x/oauth2 v0.38.0`, `google.golang.org/api v0.316.0`, `golang.org/x/crypto v0.59.0`, `golang.org/x/net v0.63.0`), Web SPA Firebase JS SDK (`13.4.0`), and Flutter companion dependencies (`firebase_core ^5.2.0`, `firebase_auth ^7.1.0`, `flutter_blue_plus ^2.3.15`).
- **Firestore Segment Persistence & Go Code Health**: Migrated `FirestoreStore.SaveSegments` from deprecated `WriteBatch` to `BulkWriter`, resolved all `golangci-lint` (`errcheck`/`staticcheck`) issues, and modernized Go idioms (`any`, `%q` formatting, and Google Go test failure formatting).

### Security
- **Go Stdlib & Container Hardening**: Raised `service/go.mod` floor from `go 1.26.0` to `go 1.26.10` to enforce patched stdlib resolution under `GOTOOLCHAIN=auto`, upgraded `service/Dockerfile` runtime from `alpine:3.21` to `alpine:3.24` with `apk upgrade --no-cache` in both stages, and added `service/.gcloudignore` for clean Cloud Build source uploads.

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

[Unreleased]: https://github.com/ghchinoy/omi-pixel/compare/v0.4.4...HEAD
[0.4.4]: https://github.com/ghchinoy/omi-pixel/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/ghchinoy/omi-pixel/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/ghchinoy/omi-pixel/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/ghchinoy/omi-pixel/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/ghchinoy/omi-pixel/compare/v0.3.4...v0.4.0
[0.3.4]: https://github.com/ghchinoy/omi-pixel/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/ghchinoy/omi-pixel/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/ghchinoy/omi-pixel/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/ghchinoy/omi-pixel/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ghchinoy/omi-pixel/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ghchinoy/omi-pixel/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ghchinoy/omi-pixel/releases/tag/v0.1.0
