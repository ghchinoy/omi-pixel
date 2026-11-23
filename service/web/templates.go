package web

import (
	"html/template"
)

// WebConfig holds public client-side Firebase configuration injected via environment variables.
type WebConfig struct {
	APIKey            string
	AppID             string
	MessagingSenderID string
	ProjectID         string
	AuthDomain        string
	StorageBucket     string
	AuthDisabled      bool
}

var DefaultWebConfig = WebConfig{}

const spaTemplate = `<!doctype html>
<html lang="en" data-theme="system" class="lustrous-root">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Omi-Pixel Review</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🎙️</text></svg>" />

  <!-- Lustrous Design System (@ghchinoy/lustrous-lit@0.2.0) -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@ghchinoy/lustrous-lit@0.2.0/fonts/lustrous-fonts.css" />
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@ghchinoy/lustrous-lit@0.2.0/dist/lustrous-theme.css" />

  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background-color: var(--lustrous-color-background, #0b0f17);
      color: var(--lustrous-color-on-background, #e2e8f0);
      font-family: var(--lustrous-font-sans, system-ui, -apple-system, sans-serif);
    }
    .page-shell {
      max-width: 920px;
      margin: 0 auto;
      padding: var(--lustrous-space-xl, 20px) var(--lustrous-space-l, 16px) var(--lustrous-space-4xl, 48px);
    }
    .app-header {
      border-bottom: 1px solid var(--lustrous-color-outline-variant, #334155);
      padding-bottom: var(--lustrous-space-l, 16px);
      margin-bottom: var(--lustrous-space-2xl, 24px);
    }
    .brand-link {
      display: inline-flex;
      align-items: center;
      gap: var(--lustrous-space-s, 8px);
      background: transparent;
      border: 0;
      padding: 0;
      color: inherit;
      cursor: pointer;
      text-decoration: none;
    }
    .session-card,
    .turn-card {
      display: block;
      width: 100%;
      text-align: left;
    }
    .turn-card[data-active="true"] {
      outline: 2px solid var(--lustrous-color-primary, #60a5fa);
      outline-offset: -2px;
    }
    .meta-row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--lustrous-space-m, 12px);
      color: var(--lustrous-color-on-surface-variant, #94a3b8);
      font-size: 0.85rem;
    }
    .meta-item {
      display: inline-flex;
      align-items: center;
      gap: 4px;
    }
    audio {
      width: 100%;
      height: 40px;
      border-radius: var(--lustrous-radius-s, 6px);
    }
    .code-snippet {
      margin: 0;
      padding: var(--lustrous-space-m, 12px);
      border-radius: var(--lustrous-radius-m, 10px);
      background: var(--lustrous-color-code-background, #0d131f);
      color: var(--lustrous-color-code-primary-text, #f1f5f9);
      font-family: var(--lustrous-font-code, monospace);
      font-size: 0.82rem;
      overflow-x: auto;
      text-align: left;
    }
    .centered-state {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: var(--lustrous-space-4xl, 48px) var(--lustrous-space-l, 16px);
      gap: var(--lustrous-space-m, 12px);
    }
    .auth-shell {
      max-width: 480px;
      margin: var(--lustrous-space-3xl, 32px) auto;
    }
    .theme-switcher {
      min-width: 190px;
    }
  </style>

  <!-- Firebase App & Auth SDKs (Compat) -->
  <script src="https://www.gstatic.com/firebasejs/13.4.0/firebase-app-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/13.4.0/firebase-auth-compat.js"></script>
</head>
<body>
  <div class="page-shell">
    <header class="app-header">
      <lustrous-flex align="center" justify="space-between" gap="m" wrap="wrap">
        <button id="brand-home-btn" class="brand-link" type="button" aria-label="Omi-Pixel Review Home">
          <lustrous-icon name="mic" tone="primary" size="l"></lustrous-icon>
          <lustrous-text variant="title-large" heading="1">Omi-Pixel Review</lustrous-text>
        </button>

        <lustrous-flex align="center" gap="s" wrap="wrap">
          <lustrous-segmented-control
            id="theme-switcher"
            class="theme-switcher"
            label="Color theme"
            size="s"
          ></lustrous-segmented-control>
          <div id="header-actions"></div>
        </lustrous-flex>
      </lustrous-flex>
    </header>

    <main id="app-view">
      <div class="centered-state">
        <lustrous-spinner size="l"></lustrous-spinner>
        <lustrous-text variant="body-medium" muted>Initializing authentication…</lustrous-text>
      </div>
    </main>
  </div>

  <script type="module">
    import {
      readLustrousThemePreference,
      setLustrousTheme,
      showSnack,
    } from "https://esm.sh/@ghchinoy/lustrous-lit@0.2.0";

    // 1. Theme Initialization (Light / System / Dark)
    const THEME_STORAGE_KEY = "omi-pixel-theme";
    const initialTheme = readLustrousThemePreference(THEME_STORAGE_KEY, "system");
    setLustrousTheme(initialTheme, { storageKey: THEME_STORAGE_KEY });

    const themeSwitcher = document.getElementById("theme-switcher");
    if (themeSwitcher) {
      themeSwitcher.options = [
        { value: "light", label: "Light", icon: "lightMode" },
        { value: "system", label: "Auto", icon: "contrast" },
        { value: "dark", label: "Dark", icon: "darkMode" },
      ];
      themeSwitcher.value = initialTheme;
      themeSwitcher.addEventListener("lustrous-change", (e) => {
        const next = e.detail?.value || "system";
        setLustrousTheme(next, { storageKey: THEME_STORAGE_KEY });
      });
    }

    // 2. Firebase Auth Config
    const authDisabled = {{.AuthDisabled}};
    const firebaseConfig = {
      apiKey: "{{.APIKey}}",
      authDomain: "{{.AuthDomain}}",
      projectId: "{{.ProjectID}}",
      storageBucket: "{{.StorageBucket}}",
      messagingSenderId: "{{.MessagingSenderID}}",
      appId: "{{.AppID}}"
    };

    const SPEAKER_TONES = ["cobalt", "emerald", "amber", "rose", "violet", "teal"];
    let auth = null;
    let currentUser = null;
    let currentIdToken = null;
    let activePollTimer = null;
    let cachedSessions = [];
    let currentSearchQuery = "";

    document.getElementById("brand-home-btn")?.addEventListener("click", () => navigate("/"));

    if (authDisabled) {
      currentUser = { email: "dev-user@localhost", displayName: "Local Dev" };
      currentIdToken = "dev-bypass-token";
      renderHeaderUser(currentUser);
      routeView();
    } else if (!firebaseConfig.apiKey) {
      renderConfigMissing();
    } else {
      if (!firebase.apps.length) {
        firebase.initializeApp(firebaseConfig);
      }
      auth = firebase.auth();

      auth.onAuthStateChanged(async (user) => {
        currentUser = user;
        if (user) {
          try {
            currentIdToken = await user.getIdToken();
            renderHeaderUser(user);
            routeView();
          } catch (e) {
            console.error("Failed to get ID token", e);
            renderAuthGate("Failed to obtain authentication token: " + e.message);
          }
        } else {
          currentIdToken = null;
          renderHeaderGuest();
          renderAuthGate();
        }
      });
    }

    function renderHeaderUser(user) {
      const el = document.getElementById("header-actions");
      if (!el) return;
      const name = user.displayName || user.email;
      el.innerHTML =
        '<lustrous-flex align="center" gap="s" wrap="wrap">' +
        '<lustrous-text variant="label-medium" muted title="' + escapeHtml(user.email) + '">' + escapeHtml(name) + '</lustrous-text>' +
        '<lustrous-button id="nav-sessions-btn" variant="outline" size="s">Sessions</lustrous-button>' +
        '<lustrous-button id="sign-out-btn" variant="tonal" size="s">Sign Out</lustrous-button>' +
        '</lustrous-flex>';
      document.getElementById("nav-sessions-btn")?.addEventListener("click", () => navigate("/"));
      document.getElementById("sign-out-btn")?.addEventListener("click", signOut);
    }

    function renderHeaderGuest() {
      const el = document.getElementById("header-actions");
      if (el) el.innerHTML = "";
    }

    async function signInWithGoogle() {
      const provider = new firebase.auth.GoogleAuthProvider();
      try {
        await auth.signInWithPopup(provider);
      } catch (e) {
        console.error("Sign-in failed", e);
        renderAuthGate("Google Sign-In failed: " + e.message);
      }
    }

    async function signOut() {
      clearPollTimer();
      if (auth) {
        await auth.signOut();
      }
    }

    function renderConfigMissing() {
      const main = document.getElementById("app-view");
      main.innerHTML =
        '<div class="auth-shell">' +
        '<lustrous-box background="surface-bright" border border-radius="xl" shadow="1" padding="2xl">' +
        '<lustrous-flex direction="column" gap="m">' +
        '<lustrous-icon name="settings" tone="primary" size="xl"></lustrous-icon>' +
        '<lustrous-text variant="headline-small" heading="2">Firebase Web Config Required</lustrous-text>' +
        '<lustrous-text variant="body-medium" muted>Set your Firebase Web application parameters in <code>infra/.env</code> (or run <code>make run-local-noauth</code> for offline dev):</lustrous-text>' +
        '<pre class="code-snippet">FIREBASE_API_KEY=your-web-api-key\nFIREBASE_APP_ID=your-web-app-id\nFIREBASE_MESSAGING_SENDER_ID=your-sender-id</pre>' +
        '</lustrous-flex>' +
        '</lustrous-box>' +
        '</div>';
    }

    function renderAuthGate(errorMsg) {
      const main = document.getElementById("app-view");
      const errorHtml = errorMsg
        ? '<lustrous-banner variant="error" icon="warning">' + escapeHtml(errorMsg) + '</lustrous-banner>'
        : "";
      main.innerHTML =
        '<div class="auth-shell">' +
        '<lustrous-box background="surface-bright" border border-radius="xl" shadow="1" padding="2xl">' +
        '<lustrous-flex direction="column" align="center" gap="l" style="text-align:center;">' +
        '<lustrous-icon name="lock" tone="primary" size="xl"></lustrous-icon>' +
        '<lustrous-text variant="headline-small" heading="2">Authentication Required</lustrous-text>' +
        '<lustrous-text variant="body-medium" muted>Sign in with your authorized Google account to review Omi wearable conversations, diarized transcripts, and 16kHz WAV recordings.</lustrous-text>' +
        errorHtml +
        '<lustrous-button id="google-signin-btn" variant="accent" icon="lock">Sign in with Google</lustrous-button>' +
        '</lustrous-flex>' +
        '</lustrous-box>' +
        '</div>';
      document.getElementById("google-signin-btn")?.addEventListener("click", signInWithGoogle);
    }

    // 3. API Helpers
    async function apiRequest(endpoint, options = {}) {
      if (!currentIdToken) throw new Error("Unauthenticated");
      const makeHeaders = (tok) => Object.assign({}, options.headers || {}, {
        "Authorization": "Bearer " + tok,
      });
      let resp = await fetch(endpoint, Object.assign({}, options, { headers: makeHeaders(currentIdToken) }));
      if (resp.status === 401 && currentUser && typeof currentUser.getIdToken === "function") {
        currentIdToken = await currentUser.getIdToken(true);
        resp = await fetch(endpoint, Object.assign({}, options, { headers: makeHeaders(currentIdToken) }));
      }
      if (resp.status === 403) {
        throw new Error("ACCESS_DENIED");
      }
      if (!resp.ok) {
        throw new Error("API error: HTTP " + resp.status);
      }
      return resp;
    }

    async function apiFetch(endpoint) {
      const resp = await apiRequest(endpoint);
      return resp.json();
    }

    // 4. Views Routing
    function clearPollTimer() {
      if (activePollTimer) {
        clearTimeout(activePollTimer);
        activePollTimer = null;
      }
    }

    function navigate(path) {
      clearPollTimer();
      window.history.pushState({}, "", path);
      routeView();
    }

    window.addEventListener("popstate", routeView);

    function routeView() {
      clearPollTimer();
      if (!currentUser) return;
      const path = window.location.pathname;
      if (path.indexOf("/sessions/") === 0) {
        const id = path.substring(10);
        renderSessionDetail(id);
      } else {
        renderSessionList();
      }
    }

    function statusBadgeTone(status) {
      switch (status) {
        case "completed": return "positive";
        case "processing": return "warning";
        case "failed": return "error";
        case "recording": return "cobalt";
        default: return "default";
      }
    }

    // 5. Session List View
    async function renderSessionList(silent = false) {
      const main = document.getElementById("app-view");
      if (!silent) {
        main.innerHTML =
          '<div class="centered-state">' +
          '<lustrous-spinner size="l"></lustrous-spinner>' +
          '<lustrous-text variant="body-medium" muted>Loading conversations…</lustrous-text>' +
          '</div>';
      }

      try {
        cachedSessions = (await apiFetch("/api/sessions")) || [];
        paintSessionList();

        if (cachedSessions.some((item) => item.status === "processing")) {
          clearPollTimer();
          activePollTimer = setTimeout(() => {
            if (window.location.pathname === "/") {
              renderSessionList(true);
            }
          }, 8000);
        }
      } catch (e) {
        if (e.message === "ACCESS_DENIED") {
          renderAccessDenied();
        } else {
          main.innerHTML =
            '<lustrous-banner variant="error" icon="warning">Failed to load sessions: ' + escapeHtml(e.message) + '</lustrous-banner>';
        }
      }
    }

    function paintSessionList() {
      const main = document.getElementById("app-view");
      main.innerHTML =
        '<lustrous-flex direction="column" gap="l">' +
        '<lustrous-flex align="center" justify="space-between" gap="m" wrap="wrap">' +
        '<lustrous-flex direction="column" gap="xs">' +
        '<lustrous-text variant="headline-small" heading="2">Recorded Conversations</lustrous-text>' +
        '<lustrous-text id="sessions-count" variant="body-small" muted></lustrous-text>' +
        '</lustrous-flex>' +
        '<lustrous-flex align="center" gap="s">' +
        '<lustrous-search-bar id="session-search" variant="outlined" size="s" placeholder="Search sessions…" value="' + escapeHtml(currentSearchQuery) + '"></lustrous-search-bar>' +
        '<lustrous-button id="refresh-list-btn" variant="outline" size="s" icon="refresh">Refresh</lustrous-button>' +
        '</lustrous-flex>' +
        '</lustrous-flex>' +
        '<lustrous-flex id="sessions-cards" direction="column" gap="m"></lustrous-flex>' +
        '</lustrous-flex>';

      const searchEl = document.getElementById("session-search");
      if (searchEl) {
        searchEl.addEventListener("input", (e) => {
          currentSearchQuery = e.target.value || "";
          updateSessionCards();
        });
        searchEl.addEventListener("lustrous-search", (e) => {
          currentSearchQuery = e.detail?.value || "";
          updateSessionCards();
        });
        searchEl.addEventListener("lustrous-clear", () => {
          currentSearchQuery = "";
          updateSessionCards();
        });
      }
      document.getElementById("refresh-list-btn")?.addEventListener("click", () => renderSessionList());
      updateSessionCards();
    }

    function updateSessionCards() {
      const container = document.getElementById("sessions-cards");
      const countEl = document.getElementById("sessions-count");
      if (!container) return;

      const q = currentSearchQuery.trim().toLowerCase();
      const filtered = q
        ? cachedSessions.filter((s) =>
            (s.title || "").toLowerCase().includes(q) ||
            (s.summary || "").toLowerCase().includes(q) ||
            (s.device_id || "").toLowerCase().includes(q)
          )
        : cachedSessions;

      if (countEl) {
        countEl.textContent = filtered.length + " of " + cachedSessions.length + " session(s)";
      }

      let cardsHtml = "";
      if (cachedSessions.length === 0) {
        cardsHtml =
          '<lustrous-box background="surface-container" border border-radius="l" padding="2xl">' +
          '<div class="centered-state">' +
          '<lustrous-icon name="micOff" size="xl"></lustrous-icon>' +
          '<lustrous-text variant="title-medium" heading="3">No recorded sessions yet</lustrous-text>' +
          '<lustrous-text variant="body-medium" muted>Connect your Omi wearable on Pixel and record a conversation to review it here.</lustrous-text>' +
          '</div>' +
          '</lustrous-box>';
      } else if (filtered.length === 0) {
        cardsHtml =
          '<lustrous-box background="surface-container" border border-radius="l" padding="xl">' +
          '<div class="centered-state">' +
          '<lustrous-text variant="body-medium" muted>No conversations match "' + escapeHtml(currentSearchQuery) + '".</lustrous-text>' +
          '</div>' +
          '</lustrous-box>';
      } else {
        for (const s of filtered) {
          const ts = s.started_at || s.created_at;
          const dateStr = ts
            ? new Date(ts).toLocaleDateString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })
            : "-";
          const durStr = s.duration_seconds > 0 ? Math.round(s.duration_seconds) + "s" : "";
          const tone = statusBadgeTone(s.status);

          cardsHtml +=
            '<lustrous-pressable class="session-card" data-session-id="' + escapeHtml(s.id) + '" background="surface-bright" border border-radius="l" padding="l" shadow="1">' +
            '<lustrous-flex direction="column" gap="s">' +
            '<lustrous-flex align="center" justify="space-between" gap="m">' +
            '<lustrous-text variant="title-medium" max-lines="1">' + escapeHtml(s.title || "Untitled Conversation") + '</lustrous-text>' +
            '<lustrous-badge tone="' + tone + '">' + escapeHtml((s.status || "unknown").toUpperCase()) + '</lustrous-badge>' +
            '</lustrous-flex>' +
            (s.summary
              ? '<lustrous-text variant="body-medium" muted max-lines="2">' + escapeHtml(s.summary) + '</lustrous-text>'
              : "") +
            '<div class="meta-row">' +
            '<span class="meta-item"><lustrous-icon name="clock" size="xs"></lustrous-icon>' + escapeHtml(dateStr) + '</span>' +
            (durStr ? '<span class="meta-item">' + escapeHtml(durStr) + '</span>' : "") +
            (s.device_id ? '<span class="meta-item"><lustrous-icon name="smartphone" size="xs"></lustrous-icon>' + escapeHtml(s.device_id) + '</span>' : "") +
            (s.has_audio ? '<span class="meta-item"><lustrous-icon name="volumeUp" size="xs" tone="primary"></lustrous-icon>16kHz WAV</span>' : "") +
            '</div>' +
            '</lustrous-flex>' +
            '</lustrous-pressable>';
        }
      }

      container.innerHTML = cardsHtml;
      container.querySelectorAll(".session-card").forEach((card) => {
        card.addEventListener("click", () => {
          const sid = card.getAttribute("data-session-id");
          if (sid) navigate("/sessions/" + sid);
        });
      });
    }

    // 6. Session Detail View
    async function renderSessionDetail(sessionId, silent = false) {
      const main = document.getElementById("app-view");
      if (!silent) {
        main.innerHTML =
          '<div class="centered-state">' +
          '<lustrous-spinner size="l"></lustrous-spinner>' +
          '<lustrous-text variant="body-medium" muted>Loading conversation…</lustrous-text>' +
          '</div>';
      }

      try {
        const detail = await apiFetch("/api/sessions/" + sessionId);
        const s = detail.Session || detail;
        const segs = detail.segments || [];

        const ts = s.started_at || s.created_at;
        const dateStr = ts ? new Date(ts).toLocaleString() : "-";
        const durStr = s.duration_seconds > 0 ? s.duration_seconds.toFixed(1) + "s" : "";

        let statusBannerHtml = "";
        if (s.status === "processing") {
          statusBannerHtml =
            '<lustrous-banner variant="warning" heading="Diarizing in Background…">' +
            '<lustrous-flex align="center" gap="m">' +
            '<lustrous-spinner size="s"></lustrous-spinner>' +
            '<lustrous-text variant="body-medium">Gemini 3.5 Transcribe is separating speakers and generating a summary. This page refreshes automatically.</lustrous-text>' +
            '</lustrous-flex>' +
            '</lustrous-banner>';
        } else if (s.status === "failed" && s.has_audio) {
          statusBannerHtml =
            '<lustrous-banner id="retry-diarize-banner" variant="error" icon="warning" heading="Diarization Failed" primary-action="Retry Diarization">' +
            'Audio is safely stored in Cloud Storage. Retry diarization whenever ready.' +
            '</lustrous-banner>';
        }

        const summaryHtml = s.summary
          ? '<lustrous-banner variant="info" icon="chatSpark2" heading="AI Summary">' + escapeHtml(s.summary) + '</lustrous-banner>'
          : "";

        let turnsHtml = "";
        if (segs.length === 0) {
          turnsHtml =
            '<lustrous-box background="surface-container" border border-radius="l" padding="xl">' +
            '<div class="centered-state">' +
            '<lustrous-text variant="body-medium" muted>' +
            (s.status === "processing" ? "Waiting for diarized speaker turns…" : "No diarized segments available yet.") +
            '</lustrous-text>' +
            '</div>' +
            '</lustrous-box>';
        } else {
          for (const seg of segs) {
            const tone = SPEAKER_TONES[Math.abs(seg.speaker_id || 0) % SPEAKER_TONES.length];
            turnsHtml +=
              '<lustrous-pressable class="turn-card" data-start="' + seg.start + '" background="surface-bright" border border-radius="l" padding="l">' +
              '<lustrous-flex direction="column" gap="s">' +
              '<lustrous-flex align="center" justify="space-between" gap="m">' +
              '<lustrous-badge tone="' + tone + '">' + escapeHtml(seg.speaker) + '</lustrous-badge>' +
              '<span class="meta-item"><lustrous-icon name="playArrow" size="xs"></lustrous-icon>' + seg.start.toFixed(1) + 's – ' + seg.end.toFixed(1) + 's</span>' +
              '</lustrous-flex>' +
              '<lustrous-text variant="body-large">' + escapeHtml(seg.text) + '</lustrous-text>' +
              '</lustrous-flex>' +
              '</lustrous-pressable>';
          }
        }

        main.innerHTML =
          '<lustrous-flex direction="column" gap="l">' +
          '<lustrous-flex align="center" justify="space-between" gap="m" wrap="wrap">' +
          '<lustrous-button id="back-sessions-btn" variant="on-surface-variant" size="s" icon="arrowBack">Back to Sessions</lustrous-button>' +
          '<lustrous-flex align="center" gap="s">' +
          '<lustrous-button id="copy-transcript-btn" variant="outline" size="s" icon="copy">Copy</lustrous-button>' +
          '<lustrous-dialog id="delete-dialog" modal dismissible heading="Delete Conversation?" primary-action="Delete" secondary-action="Cancel">' +
          '<lustrous-button slot="trigger" variant="tonal" size="s" icon="delete">Delete</lustrous-button>' +
          'This permanently deletes the recording transcript, speaker turns, and stored 16kHz WAV audio.' +
          '</lustrous-dialog>' +
          '</lustrous-flex>' +
          '</lustrous-flex>' +

          '<lustrous-box background="surface-bright" border border-radius="xl" padding="xl" shadow="1">' +
          '<lustrous-flex direction="column" gap="s">' +
          '<lustrous-flex align="center" justify="space-between" gap="m" wrap="wrap">' +
          '<lustrous-text variant="headline-medium" heading="2">' + escapeHtml(s.title || "Conversation Session") + '</lustrous-text>' +
          '<lustrous-badge tone="' + statusBadgeTone(s.status) + '">' + escapeHtml((s.status || "unknown").toUpperCase()) + '</lustrous-badge>' +
          '</lustrous-flex>' +
          '<div class="meta-row">' +
          '<span class="meta-item"><lustrous-icon name="clock" size="xs"></lustrous-icon>' + escapeHtml(dateStr) + '</span>' +
          (durStr ? '<span class="meta-item">Duration: ' + escapeHtml(durStr) + '</span>' : "") +
          (s.language ? '<span class="meta-item">Language: ' + escapeHtml(s.language) + '</span>' : "") +
          '</div>' +
          '</lustrous-flex>' +
          '</lustrous-box>' +

          statusBannerHtml +

          '<lustrous-box id="audio-player-container" background="surface-container" border border-radius="l" padding="l">' +
          '<lustrous-flex direction="column" gap="s">' +
          '<lustrous-flex align="center" justify="space-between" gap="m">' +
          '<lustrous-flex align="center" gap="s">' +
          '<lustrous-icon name="volumeUp" tone="primary" size="s"></lustrous-icon>' +
          '<lustrous-text variant="title-small">Session Recording (16kHz WAV)</lustrous-text>' +
          '</lustrous-flex>' +
          '<lustrous-text id="audio-status-text" variant="body-small" muted>Click play or select any turn to listen</lustrous-text>' +
          '</lustrous-flex>' +
          '<audio id="session-audio-player" controls preload="metadata"></audio>' +
          '</lustrous-flex>' +
          '</lustrous-box>' +

          summaryHtml +

          '<lustrous-text variant="title-large" heading="3">Diarized Transcript (' + segs.length + ' turns)</lustrous-text>' +
          '<lustrous-flex id="transcript-turns" direction="column" gap="m">' + turnsHtml + '</lustrous-flex>' +
          '</lustrous-flex>';

        // Wire event listeners (zero inline onclick)
        document.getElementById("back-sessions-btn")?.addEventListener("click", () => navigate("/"));
        document.getElementById("copy-transcript-btn")?.addEventListener("click", () => {
          copyTranscriptToClipboard(s, segs);
        });
        document.getElementById("retry-diarize-banner")?.addEventListener("lustrous-action", (e) => {
          if (e.detail?.action === "primary") {
            reprocessSession(sessionId);
          }
        });
        document.getElementById("delete-dialog")?.addEventListener("lustrous-action", async (e) => {
          if (e.detail?.action === "primary") {
            await deleteSession(sessionId);
          }
        });
        main.querySelectorAll(".turn-card").forEach((card) => {
          card.addEventListener("click", () => {
            const start = parseFloat(card.getAttribute("data-start") || "0");
            seekAudio(start);
          });
        });

        loadAudioPlayer(sessionId);

        if (s.status === "processing") {
          clearPollTimer();
          activePollTimer = setTimeout(() => {
            if (window.location.pathname === "/sessions/" + sessionId) {
              renderSessionDetail(sessionId, true);
            }
          }, 5000);
        }
      } catch (e) {
        if (e.message === "ACCESS_DENIED") {
          renderAccessDenied();
        } else {
          main.innerHTML =
            '<lustrous-banner variant="error" icon="warning">Failed to load conversation: ' + escapeHtml(e.message) + '</lustrous-banner>';
        }
      }
    }

    async function copyTranscriptToClipboard(session, segs) {
      const lines = ["Title: " + (session.title || "Conversation")];
      if (session.summary) {
        lines.push("", "Summary:", session.summary, "");
      }
      lines.push("Transcript:");
      for (const seg of segs) {
        lines.push("[" + seg.start.toFixed(1) + "s] " + seg.speaker + ": " + seg.text);
      }
      try {
        await navigator.clipboard.writeText(lines.join("\n"));
        showSnack("Transcript copied to clipboard", { variant: "positive" });
      } catch (e) {
        showSnack("Failed to copy transcript", { variant: "error" });
      }
    }

    async function reprocessSession(sessionId) {
      try {
        await apiRequest("/api/sessions/" + sessionId + "/reprocess?async=true", { method: "POST" });
        showSnack("Re-diarization started in background", { variant: "positive" });
        renderSessionDetail(sessionId);
      } catch (e) {
        showSnack("Failed to retry diarization: " + e.message, { variant: "error" });
      }
    }

    async function deleteSession(sessionId) {
      try {
        await apiRequest("/api/sessions/" + sessionId, { method: "DELETE" });
        showSnack("Conversation deleted", { variant: "positive" });
        navigate("/");
      } catch (e) {
        showSnack("Failed to delete session: " + e.message, { variant: "error" });
      }
    }

    async function loadAudioPlayer(sessionId) {
      const player = document.getElementById("session-audio-player");
      const statusText = document.getElementById("audio-status-text");
      if (!player) return;

      try {
        const resp = await fetch("/api/sessions/" + sessionId + "/audio", {
          headers: { "Authorization": "Bearer " + currentIdToken },
        });

        if (resp.status === 404) {
          const container = document.getElementById("audio-player-container");
          if (container) container.style.display = "none";
          return;
        }

        if (!resp.ok) {
          if (statusText) statusText.textContent = "Audio unavailable (HTTP " + resp.status + ")";
          return;
        }

        const blob = await resp.blob();
        const blobUrl = URL.createObjectURL(blob);
        player.src = blobUrl;
        if (statusText) statusText.textContent = "Audio loaded (" + (blob.size / 1024 / 1024).toFixed(1) + " MB)";
      } catch (e) {
        console.error("Failed to load audio stream", e);
        if (statusText) statusText.textContent = "Audio stream error";
      }
    }

    function seekAudio(startTimeSec) {
      const player = document.getElementById("session-audio-player");
      if (player) {
        player.currentTime = startTimeSec;
        player.play();
      }
    }

    function renderAccessDenied() {
      const main = document.getElementById("app-view");
      const email = currentUser ? currentUser.email : "";
      main.innerHTML =
        '<div class="auth-shell">' +
        '<lustrous-box background="surface-bright" border border-radius="xl" shadow="1" padding="2xl">' +
        '<lustrous-flex direction="column" align="center" gap="m" style="text-align:center;">' +
        '<lustrous-icon name="warning" tone="error" size="xl"></lustrous-icon>' +
        '<lustrous-text variant="headline-small" heading="2">Access Denied</lustrous-text>' +
        '<lustrous-text variant="body-medium" muted>Your account (' + escapeHtml(email) + ') is authenticated, but is not on the authorized users allowlist.</lustrous-text>' +
        '<pre class="code-snippet">make authorize EMAIL=' + escapeHtml(email || "you@gmail.com") + '</pre>' +
        '<lustrous-button id="denied-signout-btn" variant="outline">Sign Out</lustrous-button>' +
        '</lustrous-flex>' +
        '</lustrous-box>' +
        '</div>';
      document.getElementById("denied-signout-btn")?.addEventListener("click", signOut);
    }

    function escapeHtml(str) {
      if (!str) return "";
      return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }
  </script>
</body>
</html>
`

// ParseTemplates returns the parsed SPA HTML template.
func ParseTemplates() (*template.Template, error) {
	return template.New("spa").Parse(spaTemplate)
}
