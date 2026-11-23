# User Guide: Omi-Pixel on Google Pixel

This guide walks you through configuring, running, and deploying the Omi-Pixel companion app and Google Cloud Run backend for **[Omi](https://www.omi.me/)** wearable hardware (DevKit and CV1).

---

## 1. System Overview

Omi-Pixel connects your [Omi](https://www.omi.me/) wearable directly to your Google Pixel phone, streaming low-latency linear PCM audio to Google Cloud for real-time live transcription, non-blocking multi-speaker diarization, Smart self-corrected transcripts, and cloud persistence:

- **Live Streaming Pass**: `gemini-3.5-transcribe-live` (Vertex AI Live WebSocket proxy over `Authorization: Bearer`) for instantaneous visual transcription in **Verbatim** or **Smart** (inline verbal self-corrections & disfluency cleanup) mode.
- **Batch Diarization & Smart Pass**: `gemini-3.5-transcribe` (Vertex AI REST) runs speaker separation (`Speaker 1`, `Speaker 2`, …) with word timestamps, plus a parallel standalone Smart-mode pass when recorded in Smart mode so you get both tap-to-seek speaker turns and clean self-corrected prose.
- **Metadata & Synthesis**: `gemini-3.5-flash-lite` for concise titles and `gemini-4-hydrogen` (default, or `gemini-3.8-flash` selectable in Settings) for plain-text AI summaries.
- **Resilient Local Persistence**: Decoded PCM chunks stream directly to on-device storage (`omi_recordings/`) under an Android `ForegroundService` (`connectedDevice`) with a durable retryable upload queue so recordings survive app switching, lock screens, and network drops.
- **Cloud Storage & Database**: Raw 16kHz WAV files persist in Google Cloud Storage (`gs://${GOOGLE_CLOUD_PROJECT}-omi-pixel-audio`) and structured transcripts live in Google Cloud Firestore (`omi-pixel`) behind your `authorized_users` allowlist.
- **Lustrous UI (Mobile & Web)**: Both the Flutter companion app and the Cloud Run Web Review SPA (`@ghchinoy/lustrous-lit`) support **Light (Mineral Slate)**, **Auto (System)**, and **Dark (Obsidian Slate)** themes.

---

## 2. Prerequisites & Cloud Setup

1. **Google Cloud SDK & Tooling**:
   - Install `gcloud`, Go `1.26.10+`, Flutter, and `adb` (optional, for USB/wireless Pixel sideloading).
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project your-gcp-project-id
   ```
2. **Firebase Configuration**:
   - Enable Firebase Authentication on your project and turn on the **Google** sign-in provider in Firebase Console (Build > Authentication > Sign-in method).
   - In Firebase Console > Authentication > Settings > **Authorized domains**, add your deployed Cloud Run domain (and optional custom domain):
     - `omi-pixel-service-xyz.a.run.app`
     - `omi.example.com` (optional custom domain)
   - Run `make configure-firebase` (or `flutterfire configure` inside `app/`) to generate `app/lib/firebase_options.dart` and `app/android/app/google-services.json`.
   - Copy the Web and Android Firebase keys into `infra/.env` (`FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`).
3. **Hardware**: An [Omi](https://www.omi.me/) DevKit or CV1 wearable powered on and charged, and a Google Pixel phone with Developer Options / USB Debugging enabled.

---

## 3. Quick Start (Top-Level Makefile)

All common operations are automated via the root `Makefile`:

```bash
# 1. Provision GCP APIs, Service Account, Firestore DB, and GCS bucket
make setup

# 2. Authorize your Google account email in Firestore
make authorize EMAIL=you@gmail.com ADMIN=true

# 3. Start Go backend locally (with Firebase Auth active)
make run-local

# 4. In a separate terminal, forward port 8080 to your connected Pixel
make adb-reverse

# 5. Launch the Flutter companion app on your phone
make run-app
```

### Makefile Target Reference

| Target | Description |
|---|---|
| `make run-local` | Runs Go backend locally with Firebase Auth and Vertex AI ADC |
| `make run-local-noauth` | Runs Go backend with `AUTH_DISABLED=true` (offline local testing) |
| `make run-app` | Runs Flutter companion app on connected Android device |
| `make adb-reverse` | Forwards `tcp:8080` from Pixel to your development machine |
| `make configure-firebase` | Generates platform Firebase configs via `flutterfire configure` |
| `make authorize EMAIL=...` | Adds user email to Firestore `authorized_users` allowlist (`ADMIN=true` optional) |
| `make deauthorize EMAIL=...` | Removes user email from Firestore allowlist |
| `make setup` | Provisions GCP APIs, dedicated Service Account, Firestore DB, and GCS bucket |
| `make preflight` | Executes automated pre-deployment validation checks |
| `make deploy` | Builds and deploys Go backend container to Google Cloud Run |
| `make postflight` | Verifies deployed Cloud Run health, Firestore, and GCS bindings |
| `make release` | Runs full deployment pipeline: `preflight` -> `deploy` -> `postflight` |
| `make test` | Runs unit tests across Go backend and Flutter app |
| `make analyze` | Runs static analysis and linting checks on Go (`go vet`) and Flutter (`flutter analyze`) |
| `make build-apk` | Builds release Android APK (`app/build/app/outputs/flutter-apk/app-release.apk`) |
| `make install-apk` | Builds release APK and installs onto connected Pixel via ADB |
| `make clean` | Cleans Flutter/Gradle build caches (recommended after plugin upgrades) |
| `make icons` | Regenerates all Android and iOS launcher icons |

---

## 4. Deploying to Google Cloud Run

1. **Verify Environment**:
   Ensure `infra/.env` contains your project parameters:
   ```bash
   GOOGLE_CLOUD_PROJECT=your-gcp-project-id
   GCP_REGION=us-central1
   SERVICE_NAME=omi-pixel-service
   SERVICE_ACCOUNT_NAME=sa-omi-pixel
   FIRESTORE_DATABASE=omi-pixel
   GCS_BUCKET=your-gcp-project-id-omi-pixel-audio
   GOOGLE_CLOUD_LOCATION=global
   FIREBASE_API_KEY=your-web-api-key
   FIREBASE_APP_ID=your-web-app-id
   FIREBASE_ANDROID_API_KEY=your-android-api-key
   FIREBASE_ANDROID_APP_ID=your-android-app-id
   FIREBASE_MESSAGING_SENDER_ID=your-sender-id
   ```

2. **Execute Full Release**:
   ```bash
   make release
   ```

3. **Copy the Output Service URL**:
   Example: `https://omi-pixel-service-xyz.a.run.app`.

---

## 5. Installing on Google Pixel

### Option A: Release APK Sideload (Recommended)
To install the standalone release build onto your Pixel over USB:
```bash
make install-apk
```
*(After Flutter/Firebase plugin upgrades, run `make clean && make install-apk` to avoid stale Gradle Kotlin incremental caches.)*

### Option B: USB Tether (Live Debug Run)
1. Connect your Pixel via USB with USB Debugging enabled.
2. Run `make run-app`.

### Option C: Wireless ADB (Untethered)
1. On your Pixel: **Settings** > **Developer options** > **Wireless debugging** > **Pair device with pairing code**.
2. On your computer:
   ```bash
   adb pair <ip>:<pairing-port>
   adb connect <ip>:<port>
   make install-apk
   ```

---

## 6. App Usage & Workflow

1. **First Launch & Settings**:
   - Open **Omi Pixel** and tap the **Settings** gear icon.
   - Sign in with your authorized Google account.
   - Enter your deployed Cloud Run Service URL (or `http://localhost:8080` via `make adb-reverse`) and tap **Test Connection** (displays both App and Backend versions at the bottom of Settings).
   - Configure **Summary Generation Model** (`Gemini 4 Hydrogen (Default)` or `Gemini 3.8 Flash (Faster)`), **Appearance** (`Light` / `Auto` / `Dark`), **Live Transcription Mode** (`Verbatim` or `Smart`), and **Spoken Language**.
   - Under **Background Recording Reliability**, if battery optimization is restricted, tap **Allow** to grant unrestricted background execution on Pixel.
2. **Connect Wearable**:
   - Tap **Scan for Omi Device** and connect your Omi DevKit or CV1. Once paired, Omi-Pixel remembers the device and automatically reconnects on future launches.
3. **Quick-Switch Live Mode & Record**:
   - **Long-press** **Start Conversation** to toggle directly between **Verbatim** and **Smart (Inline Self-Corrections)** without opening Settings.
   - Tap **Start Conversation** to open **Live Recording**. A green **Audio active** pill confirms live decoded PCM bytes/packets from your wearable.
   - While recording, an ongoing `"Omi Recording Active"` Android notification keeps BLE & WebSocket streaming alive when you switch apps or lock your screen. Tap the top-left `⌄` button (or press Back → **Minimize**) to return to `HomeScreen` while recording continues; tap the active **"Recording in Progress"** banner or the Android notification to return to `LiveScreen`.
4. **Non-Blocking Finish & Background Diarization**:
   - Tap **Finish Recording & Diarize**. The WAV is saved immediately to on-device storage and you return to `HomeScreen` right away while diarization runs in the background (`DIARIZING` badge).
   - If the phone is offline or an upload fails, the WAV stays safely queued on device and appears in an amber **Retry Upload** banner until uploaded successfully (expired Firebase tokens are refreshed automatically on HTTP `401`).
5. **Review, Seek, Copy & Delete (Mobile & Web)**:
   - Open any completed conversation on Pixel or in the **Lustrous Web Review Dashboard** (your Cloud Run URL).
   - Sessions recorded in Smart mode display a **`SMART`** badge and a switcher between **Smart Transcript** (self-corrected prose) and **Diarized Turns** (tap any turn to seek the 16kHz WAV player).
   - Use **Copy** to export the summary + transcript(s) or **Delete** (with confirmation dialog) to permanently remove a session and its GCS WAV.

---

## 7. Troubleshooting

### Access Denied (403 Forbidden)
- Confirm your Google account email is on the allowlist:
  ```bash
  make authorize EMAIL=you@gmail.com
  ```
- Cloud Run caches the allowlist in memory for 60 seconds. Wait 60s or restart the service.

### Omi Wearable Not Discovered
- Ensure the Omi device is charged and not connected to another laptop or phone (Omi supports one active BLE link at a time).
- Verify **Bluetooth**, **Location**, and **Notifications** permissions are granted for Omi Pixel.

### Audio Recording Pauses When Screen Locks
- Open **Settings** inside Omi Pixel and tap **Allow** under **Background Recording Reliability**, or go to Android **Settings** > **Apps** > **Omi Pixel** > **App battery usage** and set it to **Unrestricted**.

### Gradle Build Fails After Dependency Upgrade (`Unresolved reference`)
- Run `make clean && make install-apk` to clear stale incremental Kotlin caches under `app/build/`.
