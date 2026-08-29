# User Guide: Omi-Pixel on Google Pixel 11

This guide walks you through configuring, running, and deploying the Omi-Pixel companion app and Google Cloud Run backend for Omi wearable hardware (DevKit and CV1).

---

## 1. System Overview

Omi-Pixel connects your Omi hardware wearable directly to your Google Pixel phone, streaming low-latency linear PCM audio to Google Cloud for real-time live transcription, structured multi-speaker diarization, and cloud persistence:

- **Live Streaming Pass**: `gemini-3.5-transcribe-live-preview` (Vertex AI Live WebSocket proxy) for instantaneous visual transcription without conversational AI interference.
- **Batch Diarization Pass**: `gemini-3.5-transcribe-preview` (Vertex AI REST with word timestamps) for speaker separation (`Speaker 1`, `Speaker 2`).
- **Metadata & Synthesis**: `gemini-3.5-flash-lite` for conversation title generation and `gemini-3.7-flash` for summary synthesis.
- **Audio Persistence**: Google Cloud Storage (`gs://${GOOGLE_CLOUD_PROJECT}-omi-pixel-audio`).
- **Database**: Google Cloud Firestore named database (`omi-pixel`) with `authorized_users` allowlist security.

---

## 2. Prerequisites & Cloud Setup

1. **Google Cloud SDK**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project your-gcp-project-id
   ```
2. **Firebase Configuration**:
   - Enable Firebase Authentication on your project and enable the **Google** sign-in provider in the Firebase Console (Build > Authentication > Sign-in method).
   - In Firebase Console > Authentication > Settings > **Authorized domains**, add your deployed Cloud Run domain (and optional custom domain):
     - `omi-pixel-service-xyz.a.run.app`
     - `omi.example.com` (optional custom domain)
   - Run `make configure-firebase` (or `flutterfire configure` inside `app/`) to generate your local `firebase_options.dart` and `google-services.json`.
   - Copy the generated Web `apiKey`, `appId`, and `messagingSenderId` into `infra/.env` (`FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`).
3. **Hardware**: Omi DevKit or CV1 device powered on and charged, and Google Pixel 11 phone with Developer Options enabled.

---

## 3. Quick Start (Top-Level Makefile)

All common operations are automated via the root `Makefile`:

```bash
# 1. Authorize your Google account email in Firestore
make authorize EMAIL=you@gmail.com ADMIN=true

# 2. Start Go backend locally (with Firebase Auth active)
make run-local

# 3. In a separate terminal, forward port 8080 to your connected Pixel
make adb-reverse

# 4. Launch the Flutter companion app on your phone
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
| `make analyze` | Runs static analysis and linting checks on Go and Flutter |
| `make build-apk` | Builds release Android APK (`app-release.apk`) |
| `make icons` | Regenerates all Android and iOS launcher icons |

---

## 4. Deploying to Google Cloud Run

Deploy the backend service to Google Cloud Run:

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
   FIREBASE_MESSAGING_SENDER_ID=your-sender-id
   ```

2. **Execute Full Release**:
   ```bash
   make release
   ```

3. **Copy the Output Service URL**:
   Example: `https://omi-pixel-service-xyz.a.run.app`.

---

## 5. Installing on Google Pixel 11

### Option A: USB Tether (Standard Debug Run)
1. Connect Pixel 11 via USB with USB Debugging enabled.
2. Run `make run-app` or `flutter run`.

### Option B: Sideload APK (Standalone Run)
To keep the app installed permanently on your Pixel without needing an active terminal:
1. Build the APK:
   ```bash
   cd app && flutter build apk --debug
   ```
2. Install directly to phone:
   ```bash
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

### Option C: Wireless ADB (Untethered)
1. On your Pixel: **Settings** > **Developer options** > **Wireless debugging** > **Pair device with pairing code**.
2. On your computer:
   ```bash
   adb pair <ip>:<pairing-port>
   adb connect <ip>:<port>
   flutter run
   ```

---

## 6. App Usage & Workflow

1. **First Launch & Sign In**:
   - Open **Omi Pixel** on your phone.
   - Tap the **Settings** gear icon.
   - Sign in with your authorized Google account.
   - Enter your deployed Cloud Run Service URL (or `http://localhost:8080` if using `make adb-reverse`).
   - Tap **Test Connection** to confirm connectivity.
2. **Connect Wearable**:
   - On the Home screen, tap **Scan for Omi Device**.
   - Tap **Connect** next to your Omi wearable.
3. **Start Conversation**:
   - Tap **Start Conversation**.
   - Speak into the Omi wearable. Live verbatim transcripts will stream onto the screen in real-time.
4. **Finish & Diarize**:
   - Tap **Finish Recording & Diarize**.
   - The app uploads the session audio to Cloud Run and GCS.
   - The Conversation Details view opens, showing speaker turns, title, summary, and the **Audio Playback Card**.
   - Tap **Play** to listen to the 16kHz WAV recording, or tap any speaker turn card to seek directly to that segment.
5. **Web Review Dashboard & Audio Player**:
   - Open your deployed Cloud Run URL (or custom domain) in any web browser.
   - Sign in with your authorized Google account.
   - Browse your sessions, read AI summaries, and play back the synchronized WAV audio directly from Google Cloud Storage with turn tap-to-seek.

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
- Verify **Bluetooth** and **Location** permissions are enabled for Omi Pixel.

### Audio Recording Pauses When Screen Locks
- Go to Pixel **Settings** > **Apps** > **Omi Pixel** > **App battery usage** and set it to **Unrestricted**.
