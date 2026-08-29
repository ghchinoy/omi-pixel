package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
)

type contextKey string

const (
	userEmailContextKey contextKey = "user_email"
	userUIDContextKey   contextKey = "user_uid"
)

// Authenticator validates Firebase ID tokens and checks user authorization allowlist.
type Authenticator struct {
	authClient *auth.Client
	store      Store
	disabled   bool

	mu        sync.RWMutex
	cache     map[string]bool
	lastFlush time.Time
}

// NewAuthenticator initializes Firebase Auth using ADC credentials.
func NewAuthenticator(ctx context.Context, projectID string, store Store, disabled bool) (*Authenticator, error) {
	if disabled {
		log.Println("⚠️  WARNING: Firebase Authentication is DISABLED via AUTH_DISABLED=true.")
		return &Authenticator{store: store, disabled: true, cache: make(map[string]bool)}, nil
	}

	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID})
	if err != nil {
		return nil, fmt.Errorf("failed to initialize Firebase app: %w", err)
	}

	authClient, err := app.Auth(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize Firebase Auth client: %w", err)
	}

	return &Authenticator{
		authClient: authClient,
		store:      store,
		disabled:   false,
		cache:      make(map[string]bool),
		lastFlush:  time.Now(),
	}, nil
}

// VerifyToken verifies a Firebase JWT ID token and returns the email and UID.
func (a *Authenticator) VerifyToken(ctx context.Context, idToken string) (string, string, error) {
	if a.disabled {
		return "dev-user@localhost", "dev-user-uid", nil
	}

	if idToken == "" {
		return "", "", fmt.Errorf("missing token")
	}

	token, err := a.authClient.VerifyIDToken(ctx, idToken)
	if err != nil {
		return "", "", fmt.Errorf("invalid token: %w", err)
	}

	email, _ := token.Claims["email"].(string)
	return email, token.UID, nil
}

// IsAuthorized checks if the user's email is on the Firestore authorized_users allowlist.
func (a *Authenticator) IsAuthorized(ctx context.Context, email string) (bool, error) {
	if a.disabled {
		return true, nil
	}
	if email == "" {
		return false, nil
	}

	email = strings.ToLower(strings.TrimSpace(email))

	// Check short-lived memory cache (60s TTL)
	a.mu.RLock()
	if time.Since(a.lastFlush) < 60*time.Second {
		if authz, found := a.cache[email]; found {
			a.mu.RUnlock()
			return authz, nil
		}
	}
	a.mu.RUnlock()

	// Check store
	isAuthz, err := a.store.IsAuthorizedUser(ctx, email)
	if err != nil {
		return false, err
	}

	a.mu.Lock()
	if time.Since(a.lastFlush) >= 60*time.Second {
		a.cache = make(map[string]bool)
		a.lastFlush = time.Now()
	}
	a.cache[email] = isAuthz
	a.mu.Unlock()

	return isAuthz, nil
}

// Middleware enforces Firebase Authentication on HTTP handlers.
func (a *Authenticator) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if a.disabled {
			ctx := context.WithValue(r.Context(), userEmailContextKey, "dev-user@localhost")
			ctx = context.WithValue(ctx, userUIDContextKey, "dev-user-uid")
			next.ServeHTTP(w, r.WithContext(ctx))
			return
		}

		// 1. Extract token from Header or Query Param (for WebSocket handshakes)
		token := ""
		authHeader := r.Header.Get("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		} else if qToken := r.URL.Query().Get("access_token"); qToken != "" {
			token = qToken
		}

		if token == "" {
			respondJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "Unauthorized: missing Bearer token in Authorization header or access_token query param",
			})
			return
		}

		// 2. Verify Firebase ID Token
		email, uid, err := a.VerifyToken(r.Context(), token)
		if err != nil {
			respondJSON(w, http.StatusUnauthorized, map[string]string{
				"error": fmt.Sprintf("Unauthorized: %v", err),
			})
			return
		}

		// 3. Check Authorized Users Allowlist
		authorized, err := a.IsAuthorized(r.Context(), email)
		if err != nil {
			log.Printf("[Auth] Error checking allowlist for %s: %v", email, err)
			respondJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "Failed to verify authorization allowlist",
			})
			return
		}

		if !authorized {
			log.Printf("[Auth] Access denied for authenticated email '%s' (not in authorized_users)", email)
			respondJSON(w, http.StatusForbidden, map[string]string{
				"error": fmt.Sprintf("Forbidden: account '%s' is not on the authorized users allowlist", email),
			})
			return
		}

		ctx := context.WithValue(r.Context(), userEmailContextKey, email)
		ctx = context.WithValue(ctx, userUIDContextKey, uid)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
