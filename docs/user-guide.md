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

Run `make help` at any time for a summary. All targets automatically load variables from `infra/.env` when present (and any variable can be overridden on the command line, e.g. `PORT=9090 make run-local`).

#### Local Development
| Target | Parameters / Env Vars | Description |
|---|---|---|
| `make help` | — | Prints grouped CLI help for all targets |
| `make run-local` | `PORT=8080`, `GOOGLE_CLOUD_PROJECT`, `FIRESTORE_DATABASE`, `GCS_BUCKET`, `FIREBASE_*` | Starts Go backend locally with Firebase Auth + Vertex AI ADC active |
| `make run-local-noauth` | `PORT=8080`, `GOOGLE_CLOUD_PROJECT` | Starts Go backend locally with `AUTH_DISABLED=true` for offline/zero-config testing |
| `make adb-reverse` | `PORT=8080` | Forwards `tcp:<PORT>` from a USB-connected Pixel to your local dev server |
| `make run-app` | `FIREBASE_ANDROID_*` (from `infra/.env`) | Launches the Flutter companion app in debug mode on a connected Android device |
| `make configure-firebase` | `GOOGLE_CLOUD_PROJECT` | Runs `flutterfire configure` inside `app/` and auto-syncs keys to `infra/.env` |
| `make sync-firebase-env` | — | Extracts Web & Android keys from `app/lib/firebase_options.dart` into `infra/.env` |

#### User Authorization
| Target | Parameters / Env Vars | Description |
|---|---|---|
| `make authorize` | `EMAIL=user@domain.com` `[ADMIN=true]` | Adds an email to Firestore `authorized_users` allowlist (example: `make authorize EMAIL=you@gmail.com ADMIN=true`) |
| `make deauthorize` | `EMAIL=user@domain.com` | Removes an email from Firestore `authorized_users` allowlist |

#### Cloud Infrastructure & Deployment
| Target | Parameters / Env Vars | Description |
|---|---|---|
| `make setup` | `infra/.env` (`GOOGLE_CLOUD_PROJECT`, `GCP_REGION`, `FIRESTORE_DATABASE`, `GCS_BUCKET`) | Enables GCP APIs, creates `sa-omi-pixel` SA + IAM bindings, Firestore DB, GCS bucket, Artifact Registry, and seeds active user |
| `make preflight` | `infra/.env` | Read-only pre-deploy check: CLI tools, GCP project, APIs (`cloudbuild`, `aiplatform`, etc.), Firestore, GCS, Firebase Web keys, allowlist, SA |
| `make deploy` | `infra/.env` (`SUMMARY_MODEL`, `FIREBASE_*`, etc.) | Builds container from `service/` and deploys to Cloud Run (`--min-instances=0`) |
| `make postflight` | `infra/.env` (or `./infra/postflight.sh --url https://...`) | Verifies live `/api/health`, `/`, `401` auth enforcement, Firestore, and GCS bindings |
| `make release` | `infra/.env` | Runs the full deployment pipeline in sequence: `preflight` → `deploy` → `postflight` |

#### Quality, Build & Device Installation
| Target | Parameters / Env Vars | Description |
|---|---|---|
| `make test` | — | Runs Go backend unit tests (`go test -v ./...`) and Flutter unit/widget tests (`flutter test`) |
| `make analyze` | — | Runs Go static analysis (`go vet ./...`) and Flutter analyzer (`flutter analyze`) |
| `make doctor-app` | — | Verifies Flutter, ADB, connected Pixel devices, Firebase Android config, and signing readiness |
| `make build-apk` | `FIREBASE_ANDROID_*` (optional) | Builds standalone release Android APK (`app/build/app/outputs/flutter-apk/app-release.apk`) |
| `make install-apk` | `FIREBASE_ANDROID_*` (optional) | Runs `build-apk` and installs the release APK onto a connected Pixel via `adb install -r` |
| `make icons` | — | Regenerates Android/iOS/Web/macOS app launcher icons from `app/assets/icon/icon.png` |
| `make clean` | — | Runs `flutter clean` (clearing Gradle/Kotlin caches) and removes local Go binaries |

---

## 4. Deploying to Google Cloud Run (Clean GCP Project → Live Web SPA)

1. **Create `infra/.env` (only 1 required edit)**:
   ```bash
   cp infra/.env.template infra/.env
   # Set GOOGLE_CLOUD_PROJECT=your-gcp-project-id
   # (GCS_BUCKET auto-derives as <GOOGLE_CLOUD_PROJECT>-omi-pixel-audio when left blank)
   ```

2. **Provision Cloud Resources & Allowlist Your Account**:
   ```bash
   make setup
   ```
   Enables required APIs (`run`, `firestore`, `storage`, `aiplatform`, `identitytoolkit`, `artifactregistry`, `cloudbuild`), creates the dedicated least-privilege service account `sa-omi-pixel`, provisions the Firestore `omi-pixel` database and GCS audio bucket, and authorizes your active `gcloud` email.

3. **Enable Google Sign-In & Sync Firebase Keys (Zero Manual Copy-Paste)**:
   - Enable the **Google** sign-in provider in Firebase Console: `https://console.firebase.google.com/project/<your-project-id>/authentication/providers`
   - Run:
     ```bash
     make configure-firebase
     ```
     This generates `app/lib/firebase_options.dart` + `google-services.json` and automatically runs `make sync-firebase-env` to populate `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_ANDROID_*`, and `FIREBASE_MESSAGING_SENDER_ID` in `infra/.env`.

4. **Run Preflight, Deploy & Verify**:
   ```bash
   make release
   ```
   `preflight` validates APIs, Firestore, GCS, allowlist, and Firebase Web keys before deploying; `deploy` forwards all model settings (`SUMMARY_MODEL`, etc.) and prints your live Cloud Run URL (`https://omi-pixel-service-xyz.a.run.app`); `postflight` verifies `/api/health`, `/`, and `401` auth enforcement.

5. **Authorize Your Cloud Run Domain for Google Sign-In (One-Time)**:
   - Copy the hostname printed by `make release` (e.g. `omi-pixel-service-xyz.a.run.app`) and add it under **Firebase Console > Authentication > Settings > Authorized domains** (direct link printed at the end of `make deploy`).

---

## 5. Installing on Google Pixel

### Mobile Build Prerequisites (Fresh Standalone Clone)
`omi-pixel` is **100% standalone** — no sibling Omi repository is required.
- **Flutter `3.44+` / Dart `3.12+`**, **JDK 17**, and **Android SDK (`compileSdk 37`)**
- Optional: Run **`make doctor-app`** to verify your Flutter toolchain, connected Pixel ADB device, and Firebase config before building.
- **Firebase vs. Offline Mode**: `app/android/app/build.gradle.kts` conditionally applies the Google Services plugin only when `app/android/app/google-services.json` exists, so fresh clones can build and test offline (`make run-local-noauth`) immediately, then run `make configure-firebase` when ready for Google Sign-In.
- **Custom Release Signing / Bundle ID (Optional)**: Add `app/android/key.properties` to sign release APKs with your own keystore (otherwise debug signing is used automatically for personal sideloading), or pass `-PapplicationId=com.yourorg.omi_pixel` if using a custom Firebase package name.

### Option A: Pre-Built Universal APK (Zero Local Flutter Install)
1. Download `omi-pixel-vX.Y.Z.apk` from [GitHub Releases](https://github.com/ghchinoy/omi-pixel/releases) (or trigger the **CI & Release APK** GitHub Actions workflow on your fork).
2. Sideload onto your Pixel (`adb install -r omi-pixel-vX.Y.Z.apk` or open the `.apk` directly on-device).
3. Open **Settings**, paste your deployed Cloud Run Service URL, and tap **Test Connection** — the app automatically fetches your project's public Firebase configuration from `GET /api/client-config`, initializes Firebase at runtime, and signs in with Google via Chrome Custom Tabs (zero Android SHA-1 setup required).

### Option B: Build & Sideload Locally (`make install-apk`)
To install the standalone release build onto your Pixel over USB:
```bash
make install-apk
```
*(After Flutter/Firebase plugin upgrades, run `make clean && make install-apk` to avoid stale Gradle Kotlin incremental caches.)*

### Option C: USB Tether (Live Debug Run)
1. Connect your Pixel via USB with USB Debugging enabled.
2. Run `make run-app`.

### Option D: Wireless ADB (Untethered)
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
   - Under **Omi Hardware Button Control**, keep **Start & Finish via Omi Button** enabled (default on) for hands-free control and tap **Test Haptic** when connected to feel the wearable buzz.
2. **Connect Wearable**:
   - Tap **Scan for Omi Device** and connect your Omi DevKit or CV1. Once paired, Omi-Pixel remembers the device and automatically reconnects on future launches.
3. **Start & Control Recording (Screen or Hardware Button)**:
   - **Quick-Switch Live Mode**: **Long-press** **Start Conversation** on `HomeScreen` to toggle directly between **Verbatim** and **Smart (Inline Self-Corrections)** without opening Settings.
   - **Hands-Free Omi Hardware Button**:
     - **Single tap** the Omi button while idle (and Pixel unlocked) to **start recording** — Omi confirms with **1× medium haptic buzz (50ms)**.
     - **Double tap** the Omi button while recording to **finish & diarize in the background** — Omi confirms with **2× short haptic buzzes (20ms × 2)** (works even while your Pixel is locked or in another app).
     - *(Note: holding the Omi button for 3+ seconds triggers Omi's firmware power-off; per Android background best practices, starting a new recording via the hardware button requires your Pixel to be unlocked and Omi-Pixel set to Unrestricted battery.)*
   - **Live Screen & Minimize**: Tap **Start Conversation** (or single-tap Omi while in the app) to open **Live Recording**. A green **Audio active** pill confirms live decoded PCM bytes/packets. An ongoing `"Omi Recording Active"` Android notification keeps BLE & WebSocket streaming alive across app switches and lock screen. Tap the top-left `⌄` button (or press Back → **Minimize**) to return to `HomeScreen` while recording continues; tap the active **"Recording in Progress"** banner or the notification to return.
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

### Omi Hardware Button Does Not Start Recording
- Confirm **Settings** > **Omi Hardware Button Control** > **Start & Finish via Omi Button** is enabled and shows `Connected: Button Ready`.
- Ensure your Pixel screen is **unlocked** (starting a new recording while locked is intentionally blocked for privacy & Android background compliance) and **App battery usage** is set to **Unrestricted**.

### Gradle Build Fails After Dependency Upgrade (`Unresolved reference`)
- Run `make clean && make install-apk` to clear stale incremental Kotlin caches under `app/build/`.
