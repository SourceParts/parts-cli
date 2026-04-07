package auth

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

const (
	// Auth0 application (public values — no secret)
	Auth0Domain   = "auth.source.parts"
	Auth0ClientID = "JCV5GZjX9TAQ6vzTkEM8pzO2I976aNov"
	Auth0Audience = "https://auth.source.parts"
	Scopes        = "openid profile email offline_access"

	// Local callback server
	CallbackPort = 17429

	// Source Parts API proxy endpoints (hold the client secret server-side)
	tokenExchangeURL = "https://api.source.parts/v1/auth/token"
	tokenRefreshURL  = "https://api.source.parts/v1/auth/token/refresh"
)

// OAuthTokens holds Auth0 OAuth2 tokens and user identity.
type OAuthTokens struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	IDToken      string    `json:"id_token"`
	ExpiresAt    time.Time `json:"expires_at"`
	Sub          string    `json:"sub"`
	Email        string    `json:"email"`
}

// Login performs the PKCE Authorization Code browser flow and returns OAuth tokens.
// The client secret never leaves the server — code exchange is proxied through the API.
// Progress messages are written to out.
func Login(ctx context.Context, out io.Writer) (*OAuthTokens, error) {
	verifier, err := generateCodeVerifier()
	if err != nil {
		return nil, fmt.Errorf("failed to generate code verifier: %w", err)
	}
	challenge := computeCodeChallenge(verifier)

	state, err := generateState()
	if err != nil {
		return nil, fmt.Errorf("failed to generate state: %w", err)
	}

	redirectURI := fmt.Sprintf("http://localhost:%d/callback", CallbackPort)
	params := url.Values{
		"response_type":         {"code"},
		"client_id":             {Auth0ClientID},
		"redirect_uri":          {redirectURI},
		"scope":                 {Scopes},
		"audience":              {Auth0Audience},
		"code_challenge":        {challenge},
		"code_challenge_method": {"S256"},
		"state":                 {state},
	}
	authURL := fmt.Sprintf("https://%s/authorize?%s", Auth0Domain, params.Encode())

	codeCh := make(chan string, 1)
	errCh := make(chan error, 1)

	mux := http.NewServeMux()
	srv := &http.Server{Handler: mux}

	mux.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()

		if s := q.Get("state"); s != state {
			errCh <- fmt.Errorf("state mismatch in callback")
			w.Header().Set("Content-Type", "text/html")
			w.WriteHeader(http.StatusBadRequest)
			fmt.Fprintln(w, callbackErrorHTML("State Mismatch", "Authentication failed due to a state mismatch. Please try again.", "state"))
			return
		}

		if errMsg := q.Get("error"); errMsg != "" {
			desc := q.Get("error_description")
			errCh <- fmt.Errorf("%s: %s", errMsg, desc)
			w.Header().Set("Content-Type", "text/html")
			w.WriteHeader(http.StatusBadRequest)
			fmt.Fprintln(w, callbackErrorHTML("Authentication Failed", desc, errMsg))
			return
		}

		code := q.Get("code")
		if code == "" {
			errCh <- fmt.Errorf("no authorization code received")
			w.Header().Set("Content-Type", "text/html")
			w.WriteHeader(http.StatusBadRequest)
			fmt.Fprintln(w, callbackErrorHTML("No Authorization Code", "No authorization code was received. Please try again.", "no_code"))
			return
		}

		w.Header().Set("Content-Type", "text/html")
		fmt.Fprintln(w, callbackSuccessHTML())
		codeCh <- code
	})

	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", CallbackPort))
	if err != nil {
		return nil, fmt.Errorf("failed to start callback server on port %d: %w", CallbackPort, err)
	}

	go func() {
		if serveErr := srv.Serve(listener); serveErr != nil && serveErr != http.ErrServerClosed {
			select {
			case errCh <- serveErr:
			default:
			}
		}
	}()
	defer srv.Close()

	fmt.Fprintf(out, "Opening your browser for authentication...\n")
	fmt.Fprintf(out, "If the browser does not open automatically, visit:\n  %s\n\n", authURL)

	if err := openBrowser(authURL); err != nil {
		fmt.Fprintf(out, "Warning: could not open browser: %v\n", err)
	}

	timeoutCtx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()

	var code string
	select {
	case code = <-codeCh:
	case callbackErr := <-errCh:
		return nil, callbackErr
	case <-timeoutCtx.Done():
		return nil, fmt.Errorf("authentication timed out (90s); please try again")
	}

	fmt.Fprintf(out, "Exchanging authorization code for tokens...\n")
	return exchangeCode(ctx, code, verifier, redirectURI)
}

// Refresh exchanges a refresh token for new tokens via the Source Parts API proxy.
func Refresh(ctx context.Context, refreshToken string) (*OAuthTokens, error) {
	body, err := json.Marshal(map[string]string{
		"refresh_token": refreshToken,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to encode refresh request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenRefreshURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create refresh request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "parts-cli/auth")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to contact auth service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("token refresh failed (HTTP %d)", resp.StatusCode)
	}

	var tr tokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tr); err != nil {
		return nil, fmt.Errorf("failed to decode refresh response: %w", err)
	}

	return tokensFromResponse(tr), nil
}

// --- internal helpers ---

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	IDToken      string `json:"id_token"`
	ExpiresIn    int    `json:"expires_in"`
}

// exchangeCode sends the authorization code to the Source Parts API proxy,
// which performs the actual Auth0 token exchange using the server-side secret.
func exchangeCode(ctx context.Context, code, verifier, redirectURI string) (*OAuthTokens, error) {
	body, err := json.Marshal(map[string]string{
		"code":         code,
		"code_verifier": verifier,
		"redirect_uri": redirectURI,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to encode token request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenExchangeURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create token request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "parts-cli/auth")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to exchange authorization code: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errBody map[string]interface{}
		_ = json.NewDecoder(resp.Body).Decode(&errBody)
		return nil, fmt.Errorf("token exchange failed (HTTP %d): %v", resp.StatusCode, errBody)
	}

	var tr tokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tr); err != nil {
		return nil, fmt.Errorf("failed to decode token response: %w", err)
	}

	return tokensFromResponse(tr), nil
}

func tokensFromResponse(tr tokenResponse) *OAuthTokens {
	tokens := &OAuthTokens{
		AccessToken:  tr.AccessToken,
		RefreshToken: tr.RefreshToken,
		IDToken:      tr.IDToken,
		ExpiresAt:    time.Now().Add(time.Duration(tr.ExpiresIn) * time.Second),
	}
	if tr.IDToken != "" {
		tokens.Sub, tokens.Email, _ = extractIDTokenClaims(tr.IDToken)
	}
	return tokens
}

func generateCodeVerifier() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func computeCodeChallenge(verifier string) string {
	h := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(h[:])
}

func generateState() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func openBrowser(rawURL string) error {
	switch runtime.GOOS {
	case "darwin":
		return exec.Command("open", rawURL).Start()
	case "windows":
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", rawURL).Start()
	default:
		return exec.Command("xdg-open", rawURL).Start()
	}
}

// callbackPageCSS is the shared CSS for OAuth callback pages,
// matching the Source Parts / FastMCP branded page style.
const callbackPageCSS = `
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;
  background:#f9fafb;color:#0a0a0a;min-height:100vh;display:flex;align-items:center;justify-content:center}
.container{background:#fff;border:1px solid #e5e7eb;border-radius:1rem;padding:3rem 2.5rem;
  max-width:36rem;width:100%;text-align:center;box-shadow:0 4px 6px -1px rgba(0,0,0,.1),0 2px 4px -1px rgba(0,0,0,.06)}
.logo{width:64px;height:auto;margin:0 auto 1.5rem}
h1{font-size:1.5rem;font-weight:600;color:#111827;margin-bottom:1rem}
.message{color:#374151;font-size:1rem;line-height:1.6}
.icon{width:2rem;height:2rem;border-radius:.5rem;display:flex;align-items:center;
  justify-content:center;font-size:1.25rem;margin:0 auto 1rem}
.icon-success{background:rgba(16,185,129,.13);color:#10b981}
.icon-error{background:rgba(239,68,68,.13);color:#ef4444}
.info-box{background:#f0f9ff;border:1px solid #bae6fd;border-radius:.5rem;padding:1rem;
  margin-top:1.5rem;color:#374151;font-size:.875rem;line-height:1.5}
.error-box{background:#fef2f2;border:1px solid #fecaca;border-radius:.5rem;padding:1rem;
  margin-top:1.5rem;color:#991b1b;font-size:.875rem;line-height:1.5}
@media(max-width:640px){.container{padding:2rem 1.5rem}}
`

// iconURL returns the Source Parts icon URL for callback pages.
func iconURL(event, reason string) string {
	u := "https://source.parts/api/cli/icon?e=" + event + "&p=" + runtime.GOOS
	if reason != "" {
		u += "&r=" + reason
	}
	return u
}

// callbackSuccessHTML returns the branded success page shown after OAuth login.
func callbackSuccessHTML() string {
	return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Authentication Successful - Source Parts</title>
<style>` + callbackPageCSS + `</style></head>
<body><div class="container">
  <img class="logo" src="` + iconURL("success", "") + `" alt="Source Parts">
  <div class="icon icon-success">&#10003;</div>
  <h1>Authentication Successful</h1>
  <p class="message">You can close this tab and return to your terminal.</p>
  <div class="info-box">Your credentials have been saved securely to your system keychain.</div>
</div></body></html>`
}

// callbackErrorHTML returns a branded error page for failed OAuth callbacks.
func callbackErrorHTML(title, detail, reason string) string {
	return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Authentication Failed - Source Parts</title>
<style>` + callbackPageCSS + `</style></head>
<body><div class="container">
  <img class="logo" src="` + iconURL("error", reason) + `" alt="Source Parts">
  <div class="icon icon-error">&#10007;</div>
  <h1>` + title + `</h1>
  <p class="message">` + detail + `</p>
  <div class="error-box">Please return to your terminal and try again.</div>
</div></body></html>`
}

func extractIDTokenClaims(idToken string) (sub, email string, err error) {
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return "", "", fmt.Errorf("invalid JWT format")
	}

	payload, decodeErr := base64.RawURLEncoding.DecodeString(parts[1])
	if decodeErr != nil {
		payload, decodeErr = base64.URLEncoding.DecodeString(parts[1])
		if decodeErr != nil {
			return "", "", fmt.Errorf("failed to decode JWT payload: %w", decodeErr)
		}
	}

	var claims map[string]interface{}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return "", "", fmt.Errorf("failed to parse JWT claims: %w", err)
	}

	if s, ok := claims["sub"].(string); ok {
		sub = s
	}
	if e, ok := claims["email"].(string); ok {
		email = e
	}
	return sub, email, nil
}
