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

const spaTemplate = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Omi-Pixel Review</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🎙️</text></svg>">
  <style>
    :root {
      --bg: #0f172a;
      --card-bg: #1e293b;
      --border: #334155;
      --text: #f8fafc;
      --text-muted: #94a3b8;
      --primary: #38bdf8;
      --accent: #6366f1;
      --success: #22c55e;
      --warning: #eab308;
      --danger: #ef4444;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      line-height: 1.5;
      padding: 1.5rem;
      min-height: 100vh;
    }
    .container {
      max-width: 900px;
      margin: 0 auto;
    }
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-bottom: 1.25rem;
      border-bottom: 1px solid var(--border);
      margin-bottom: 2rem;
    }
    .logo {
      font-size: 1.5rem;
      font-weight: 700;
      color: var(--text);
      display: flex;
      align-items: center;
      gap: 0.5rem;
      text-decoration: none;
      cursor: pointer;
    }
    .badge {
      font-size: 0.75rem;
      padding: 0.2rem 0.6rem;
      border-radius: 9999px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .badge-completed { background: rgba(34, 197, 94, 0.2); color: var(--success); }
    .badge-processing { background: rgba(234, 179, 8, 0.2); color: var(--warning); }
    .badge-failed { background: rgba(239, 68, 68, 0.2); color: var(--danger); }
    .badge-recording { background: rgba(56, 189, 248, 0.2); color: var(--primary); }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 0.75rem;
      padding: 1.25rem;
      margin-bottom: 1rem;
      transition: transform 0.15s ease, border-color 0.15s ease;
      text-decoration: none;
      color: inherit;
      display: block;
      cursor: pointer;
    }
    .card:hover {
      border-color: var(--primary);
      transform: translateY(-2px);
    }
    .card-title {
      font-size: 1.15rem;
      font-weight: 600;
      margin-bottom: 0.5rem;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .meta {
      font-size: 0.85rem;
      color: var(--text-muted);
      display: flex;
      gap: 1.25rem;
      flex-wrap: wrap;
    }
    .summary-box {
      background: rgba(56, 189, 248, 0.08);
      border-left: 4px solid var(--primary);
      padding: 1rem;
      border-radius: 0.375rem;
      margin: 1.5rem 0;
      font-size: 0.95rem;
    }
    .turn {
      margin-bottom: 1.25rem;
      padding: 1rem;
      background: rgba(30, 41, 59, 0.6);
      border-radius: 0.5rem;
      border: 1px solid var(--border);
      cursor: pointer;
      transition: border-color 0.15s ease, background 0.15s ease;
    }
    .turn:hover {
      border-color: var(--primary);
      background: rgba(30, 41, 59, 0.9);
    }
    .turn-header {
      display: flex;
      justify-content: space-between;
      margin-bottom: 0.5rem;
      font-size: 0.85rem;
    }
    .speaker-pill {
      font-weight: 700;
      padding: 0.15rem 0.5rem;
      border-radius: 0.25rem;
      background: rgba(255,255,255,0.1);
    }
    .turn-time {
      color: var(--text-muted);
      display: flex;
      align-items: center;
      gap: 0.3rem;
    }
    .turn-text {
      font-size: 1rem;
      line-height: 1.6;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      background: var(--primary);
      color: #0f172a;
      font-weight: 600;
      padding: 0.5rem 1rem;
      border-radius: 0.375rem;
      text-decoration: none;
      border: none;
      cursor: pointer;
      font-size: 0.9rem;
    }
    .btn:hover {
      filter: brightness(1.1);
    }
    .btn-secondary {
      background: var(--card-bg);
      color: var(--text);
      border: 1px solid var(--border);
    }
    .btn-secondary:hover {
      background: var(--border);
    }
    .btn-danger {
      background: rgba(239, 68, 68, 0.2);
      color: var(--danger);
      border: 1px solid rgba(239, 68, 68, 0.4);
    }
    .btn-danger:hover {
      background: rgba(239, 68, 68, 0.3);
    }
    .empty-state {
      text-align: center;
      padding: 4rem 1rem;
      color: var(--text-muted);
    }
    .auth-card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 1rem;
      padding: 3rem 2rem;
      text-align: center;
      max-width: 480px;
      margin: 4rem auto;
    }
    .user-pill {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      font-size: 0.85rem;
      color: var(--text-muted);
    }
    .audio-player-card {
      background: rgba(15, 23, 42, 0.8);
      border: 1px solid var(--border);
      border-radius: 0.75rem;
      padding: 1rem 1.25rem;
      margin: 1.5rem 0;
      display: flex;
      flex-direction: column;
      gap: 0.75rem;
    }
    .audio-player-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 0.85rem;
      color: var(--text-muted);
    }
    audio {
      width: 100%;
      height: 40px;
      border-radius: 0.375rem;
      outline: none;
    }
    .loading-spinner {
      display: inline-block;
      width: 20px;
      height: 20px;
      border: 2px solid rgba(255,255,255,0.2);
      border-radius: 50%;
      border-top-color: var(--primary);
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  </style>

  <!-- Firebase App & Auth SDKs (Compat) -->
  <script src="https://www.gstatic.com/firebasejs/10.8.0/firebase-app-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.8.0/firebase-auth-compat.js"></script>
</head>
<body>
  <div class="container">
    <header>
      <a class="logo" onclick="navigate('/')">
        <span>🎙️</span>
        <span>Omi-Pixel Review</span>
      </a>
      <div id="header-actions">
        <!-- Injected via JS -->
      </div>
    </header>

    <main id="app-view">
      <div class="empty-state">
        <div class="loading-spinner" style="width:32px; height:32px;"></div>
        <p style="margin-top:1rem;">Initializing authentication...</p>
      </div>
    </main>
  </div>

  <script>
    // 1. Initialize Firebase (or local AUTH_DISABLED bypass)
    const authDisabled = {{.AuthDisabled}};
    const firebaseConfig = {
      apiKey: "{{.APIKey}}",
      authDomain: "{{.AuthDomain}}",
      projectId: "{{.ProjectID}}",
      storageBucket: "{{.StorageBucket}}",
      messagingSenderId: "{{.MessagingSenderID}}",
      appId: "{{.AppID}}"
    };

    let auth = null;
    let currentUser = null;
    let currentIdToken = null;

    if (authDisabled) {
      currentUser = { email: "dev-user@localhost", displayName: "Local Dev (Auth Disabled)" };
      currentIdToken = "dev-bypass-token";
      window.addEventListener("DOMContentLoaded", function() {
        renderHeaderUser(currentUser);
        routeView();
      });
    } else if (!firebaseConfig.apiKey) {
      window.addEventListener("DOMContentLoaded", function() {
        renderConfigMissing();
      });
    } else {
      if (!firebase.apps.length) {
        firebase.initializeApp(firebaseConfig);
      }
      auth = firebase.auth();

      // 2. Auth State Observer
      auth.onAuthStateChanged(async function(user) {
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
      const name = user.displayName || user.email;
      el.innerHTML = '<div class="user-pill">' +
        '<span title="' + escapeHtml(user.email) + '">' + escapeHtml(name) + '</span>' +
        '<button class="btn btn-secondary" style="padding:0.35rem 0.75rem;" onclick="navigate(\'/\')">Sessions</button>' +
        '<button class="btn btn-danger" style="padding:0.35rem 0.75rem;" onclick="signOut()">Sign Out</button>' +
        '</div>';
    }

    function renderHeaderGuest() {
      const el = document.getElementById("header-actions");
      el.innerHTML = "";
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
      if (auth) {
        await auth.signOut();
      }
    }

    function renderConfigMissing() {
      const main = document.getElementById("app-view");
      main.innerHTML = '<div class="auth-card">' +
        '<div style="font-size:3rem; margin-bottom:1rem;">⚙️</div>' +
        '<h2 style="margin-bottom:0.75rem;">Firebase Web Config Required</h2>' +
        '<p style="color:var(--text-muted); margin-bottom:1.25rem; font-size:0.95rem;">' +
        'Set your Firebase Web application parameters in <code>infra/.env</code> (or run <code>make run-local-noauth</code> for offline mode):' +
        '</p>' +
        '<pre style="text-align:left; background:#0f172a; padding:0.75rem; border-radius:0.5rem; font-size:0.8rem; color:var(--primary); overflow-x:auto;">' +
        'FIREBASE_API_KEY=your-web-api-key\nFIREBASE_APP_ID=your-web-app-id\nFIREBASE_MESSAGING_SENDER_ID=your-sender-id</pre>' +
        '</div>';
    }

    function renderAuthGate(errorMsg) {
      const main = document.getElementById("app-view");
      let errorHtml = "";
      if (errorMsg) {
        errorHtml = '<div style="color:var(--danger); margin-bottom:1.5rem; font-size:0.9rem; padding:0.75rem; background:rgba(239,68,68,0.1); border-radius:0.5rem; border:1px solid rgba(239,68,68,0.3);">' + escapeHtml(errorMsg) + '</div>';
      }
      main.innerHTML = '<div class="auth-card">' +
        '<div style="font-size:3rem; margin-bottom:1rem;">🔒</div>' +
        '<h2 style="margin-bottom:0.75rem;">Authentication Required</h2>' +
        '<p style="color:var(--text-muted); margin-bottom:2rem; font-size:0.95rem;">' +
        'Sign in with your authorized Google account to view recorded Omi wearable conversations, transcripts, and audio recordings.' +
        '</p>' +
        errorHtml +
        '<button class="btn" style="width:100%; justify-content:center; padding:0.75rem 1.5rem; font-size:1rem;" onclick="signInWithGoogle()">' +
        '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12.545,10.239v3.821h5.445c-0.712,2.315-2.647,3.972-5.445,3.972c-3.332,0-6.033-2.701-6.033-6.032s2.701-6.032,6.033-6.032c1.498,0,2.866,0.549,3.921,1.453l2.814-2.814C17.503,2.988,15.139,2,12.545,2C7.021,2,2.543,6.477,2.543,12s4.478,10,10.002,10c8.396,0,10.249-7.85,9.426-11.761H12.545z"/></svg>' +
        ' Sign in with Google' +
        '</button>' +
        '</div>';
    }

    // 3. API Helpers
    async function apiFetch(endpoint) {
      if (!currentIdToken) throw new Error("Unauthenticated");
      const resp = await fetch(endpoint, {
        headers: { "Authorization": "Bearer " + currentIdToken }
      });
      if (resp.status === 401) {
        // Try refresh token once
        currentIdToken = await currentUser.getIdToken(true);
        const retry = await fetch(endpoint, {
          headers: { "Authorization": "Bearer " + currentIdToken }
        });
        if (!retry.ok) throw new Error("API error: HTTP " + retry.status);
        return retry.json();
      }
      if (resp.status === 403) {
        throw new Error("ACCESS_DENIED");
      }
      if (!resp.ok) {
        throw new Error("API error: HTTP " + resp.status);
      }
      return resp.json();
    }

    // 4. Views Routing
    function navigate(path) {
      window.history.pushState({}, "", path);
      routeView();
    }

    window.addEventListener("popstate", routeView);

    function routeView() {
      if (!currentUser) return;
      const path = window.location.pathname;
      if (path.indexOf("/sessions/") === 0) {
        const id = path.substring(10);
        renderSessionDetail(id);
      } else {
        renderSessionList();
      }
    }

    // 5. List View
    async function renderSessionList() {
      const main = document.getElementById("app-view");
      main.innerHTML = '<div class="empty-state"><div class="loading-spinner"></div><p style="margin-top:1rem;">Loading conversations...</p></div>';

      try {
        const sessions = await apiFetch("/api/sessions");
        if (!sessions || sessions.length === 0) {
          main.innerHTML = '<div class="empty-state">' +
            '<p style="font-size: 1.25rem; margin-bottom: 0.5rem;">No recorded sessions yet.</p>' +
            '<p>Connect your Omi device on Pixel 11 and record a conversation to view it here.</p>' +
            '</div>';
          return;
        }

        let html = '<div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.5rem;">' +
          '<h2>Recorded Conversations</h2>' +
          '<span style="color:var(--text-muted); font-size:0.9rem;">' + sessions.length + ' session(s)</span>' +
          '</div>';

        for (let i = 0; i < sessions.length; i++) {
          const s = sessions[i];
          const dateStr = s.created_at ? new Date(s.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }) : "-";
          const durStr = s.duration_seconds > 0 ? Math.round(s.duration_seconds) + "s" : "";
          html += '<div class="card" onclick="navigate(\'/sessions/' + escapeHtml(s.id) + '\')">' +
            '<div class="card-title">' +
            '<span>' + escapeHtml(s.title || "Untitled Conversation") + '</span>' +
            '<span class="badge badge-' + escapeHtml(s.status) + '">' + escapeHtml(s.status) + '</span>' +
            '</div>' +
            (s.summary ? '<p style="color:var(--text-muted); font-size:0.9rem; margin-bottom:0.75rem; line-height:1.4;">' + escapeHtml(s.summary) + '</p>' : '') +
            '<div class="meta">' +
            '<span>🕒 ' + dateStr + '</span>' +
            (durStr ? '<span>⏱️ ' + durStr + '</span>' : '') +
            (s.device_id ? '<span>📱 ' + escapeHtml(s.device_id) + '</span>' : '') +
            (s.has_audio ? '<span style="color:var(--primary);">🎵 Audio Stored</span>' : '') +
            '</div>' +
            '</div>';
        }
        main.innerHTML = html;
      } catch (e) {
        if (e.message === "ACCESS_DENIED") {
          renderAccessDenied();
        } else {
          main.innerHTML = '<div class="empty-state" style="color:var(--danger);"><p>Failed to load sessions: ' + escapeHtml(e.message) + '</p></div>';
        }
      }
    }

    // 6. Detail View with Audio Playback & Turn Seeking
    async function renderSessionDetail(sessionId) {
      const main = document.getElementById("app-view");
      main.innerHTML = '<div class="empty-state"><div class="loading-spinner"></div><p style="margin-top:1rem;">Loading session...</p></div>';

      try {
        const detail = await apiFetch("/api/sessions/" + sessionId);
        const s = detail.Session || detail;
        const segs = detail.segments || [];

        const dateStr = s.created_at ? new Date(s.created_at).toLocaleString() : "-";
        const durStr = s.duration_seconds > 0 ? s.duration_seconds.toFixed(1) + "s" : "";

        let html = '<div style="margin-bottom: 1.5rem;">' +
          '<a onclick="navigate(\'/\')" style="color:var(--primary); text-decoration:none; font-size:0.9rem; cursor:pointer;">← Back to Sessions</a>' +
          '<div style="display:flex; justify-content:space-between; align-items:flex-start; margin-top:0.75rem;">' +
          '<div>' +
          '<h1 style="font-size: 1.75rem; margin-bottom:0.25rem;">' + escapeHtml(s.title || "Conversation Session") + '</h1>' +
          '<div class="meta">' +
          '<span>Recorded: ' + dateStr + '</span>' +
          (durStr ? '<span>Duration: ' + durStr + '</span>' : '') +
          (s.language ? '<span>Language: ' + escapeHtml(s.language) + '</span>' : '') +
          '</div>' +
          '</div>' +
          '<span class="badge badge-' + escapeHtml(s.status) + '">' + escapeHtml(s.status) + '</span>' +
          '</div>' +
          '</div>';

        // Audio Player Card
        html += '<div class="audio-player-card" id="audio-player-container">' +
          '<div class="audio-player-header">' +
          '<span>🎵 Session Recording (16kHz WAV)</span>' +
          '<span id="audio-status-text">Click play or tap any turn to listen</span>' +
          '</div>' +
          '<audio id="session-audio-player" controls preload="metadata"></audio>' +
          '</div>';

        if (s.summary) {
          html += '<div class="summary-box">' +
            '<strong>✨ Gemini 3.7 Flash Summary</strong>' +
            '<p style="margin-top:0.5rem; line-height:1.5;">' + escapeHtml(s.summary) + '</p>' +
            '</div>';
        }

        html += '<h3 style="margin-bottom: 1rem;">Diarized Transcript (' + segs.length + ' turns)</h3>';

        if (segs.length === 0) {
          html += '<div class="empty-state"><p>No diarized segments available yet.</p></div>';
        } else {
          html += '<div id="transcript-turns">';
          const colors = ["#38bdf8", "#10b981", "#f59e0b", "#ec4899", "#8b5cf6", "#06b6d4"];
          for (let i = 0; i < segs.length; i++) {
            const seg = segs[i];
            const spkColor = colors[Math.abs(seg.speaker_id || 0) % colors.length];
            html += '<div class="turn" onclick="seekAudio(' + seg.start + ')">' +
              '<div class="turn-header">' +
              '<span class="speaker-pill" style="color:' + spkColor + '; border:1px solid ' + spkColor + '66;">' + escapeHtml(seg.speaker) + '</span>' +
              '<span class="turn-time">▶ ' + seg.start.toFixed(1) + 's - ' + seg.end.toFixed(1) + 's</span>' +
              '</div>' +
              '<div class="turn-text">' + escapeHtml(seg.text) + '</div>' +
              '</div>';
          }
          html += '</div>';
        }

        main.innerHTML = html;

        // Load Audio Stream into Player with Auth Bearer
        loadAudioPlayer(sessionId);

      } catch (e) {
        if (e.message === "ACCESS_DENIED") {
          renderAccessDenied();
        } else {
          main.innerHTML = '<div class="empty-state" style="color:var(--danger);"><p>Failed to load conversation: ' + escapeHtml(e.message) + '</p></div>';
        }
      }
    }

    async function loadAudioPlayer(sessionId) {
      const player = document.getElementById("session-audio-player");
      const statusText = document.getElementById("audio-status-text");
      if (!player) return;

      try {
        const audioUrl = "/api/sessions/" + sessionId + "/audio";
        const resp = await fetch(audioUrl, {
          headers: { "Authorization": "Bearer " + currentIdToken }
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
      const email = currentUser ? currentUser.email : '';
      main.innerHTML = '<div class="auth-card" style="border-color:rgba(239,68,68,0.4);">' +
        '<div style="font-size:3rem; margin-bottom:1rem;">🚫</div>' +
        '<h2 style="margin-bottom:0.75rem; color:var(--danger);">Access Denied</h2>' +
        '<p style="color:var(--text-muted); margin-bottom:1.5rem; font-size:0.95rem;">' +
        'Your account (<strong>' + escapeHtml(email) + '</strong>) is authenticated, but is not on the authorized users allowlist.' +
        '</p>' +
        '<p style="color:var(--text-muted); font-size:0.85rem; margin-bottom:2rem;">' +
        'To grant access, run:<br>' +
        '<code style="background:#0f172a; padding:0.25rem 0.5rem; border-radius:0.25rem; display:inline-block; margin-top:0.5rem;">make authorize EMAIL=' + (email || 'you@gmail.com') + '</code>' +
        '</p>' +
        '<button class="btn btn-secondary" onclick="signOut()">Sign Out</button>' +
        '</div>';
    }

    function escapeHtml(str) {
      if (!str) return "";
      return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }
  </script>
</body>
</html>
`

func ParseTemplates() (*template.Template, error) {
	tmpl, err := template.New("spa").Parse(spaTemplate)
	if err != nil {
		return nil, err
	}
	return tmpl, nil
}
