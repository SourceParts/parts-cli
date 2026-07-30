package commands

import (
	"go/ast"
	"go/parser"
	"go/token"
	"net/http"
	"path/filepath"
	"strings"
	"testing"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeClient stubs domain.Client by embedding the interface. The embedded value
// is nil, so any method other than GetAPIKey panics if called — which is the
// point: these tests must not depend on anything else.
type fakeClient struct {
	domain.Client
	apiKey string
}

func (f *fakeClient) GetAPIKey() string { return f.apiKey }

// withClient swaps the package-level Client for the duration of a test.
// Client is global mutable state, so tests using it must not run in parallel.
func withClient(t *testing.T, apiKey string) {
	t.Helper()
	orig := Client
	Client = &fakeClient{apiKey: apiKey}
	t.Cleanup(func() { Client = orig })
}

func TestSetAuthHeader(t *testing.T) {
	tests := []struct {
		name       string
		apiKey     string
		wantHeader string
	}{
		{
			name:       "raw api key",
			apiKey:     "sp_live_abc123",
			wantHeader: "Bearer sp_live_abc123",
		},
		{
			// Client.APIKey holds an OAuth access token after a browser login
			// (auth.go calls Client.SetAPIKey(tokens.AccessToken)), so the same
			// path must carry a JWT unmodified.
			name:       "oauth access token",
			apiKey:     "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.sig",
			wantHeader: "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.sig",
		},
		{
			name:       "no credential leaves header unset",
			apiKey:     "",
			wantHeader: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			withClient(t, tt.apiKey)

			req, err := http.NewRequest(http.MethodGet, "https://example.invalid/v1/x", nil)
			require.NoError(t, err)

			setAuthHeader(req)

			if tt.wantHeader == "" {
				assert.Empty(t, req.Header.Get("Authorization"))
			} else {
				assert.Equal(t, tt.wantHeader, req.Header.Get("Authorization"))
			}

			// The dead header this whole change exists to remove must never
			// come back.
			assert.Empty(t, req.Header.Get("X-API-Key"))
		})
	}
}

func TestSetAuthHeaderNilRequest(t *testing.T) {
	withClient(t, "sp_live_abc123")
	assert.NotPanics(t, func() { setAuthHeader(nil) })
}

// TestSetAuthHeaderPreservesOtherHeaders pins the invariant the multipart call
// sites depend on: setAuthHeader must not disturb headers set before it. The
// eda ctrl upload path sets Content-Type and X-PCB-Hash around the auth call,
// and the fab paths reassign req.Body afterwards.
func TestSetAuthHeaderPreservesOtherHeaders(t *testing.T) {
	withClient(t, "sp_live_abc123")

	req, err := http.NewRequest(http.MethodPost, "https://example.invalid/v1/x", nil)
	require.NoError(t, err)

	req.Header.Set("Content-Type", "multipart/form-data; boundary=abc")
	req.Header.Set("User-Agent", "parts-cli/test")
	req.Header.Set("X-PCB-Hash", "deadbeef")

	setAuthHeader(req)

	assert.Equal(t, "multipart/form-data; boundary=abc", req.Header.Get("Content-Type"))
	assert.Equal(t, "parts-cli/test", req.Header.Get("User-Agent"))
	assert.Equal(t, "deadbeef", req.Header.Get("X-PCB-Hash"))
	assert.Equal(t, "Bearer sp_live_abc123", req.Header.Get("Authorization"))
}

func TestResolveEndpoint(t *testing.T) {
	tests := []struct {
		name     string
		endpoint string
		want     string
	}{
		{
			name:     "relative path is prefixed",
			endpoint: "/v1/eda/export",
			want:     "https://" + domain.API + "/v1/eda/export",
		},
		{
			// The bug this guards: domain.Endpoint_* constants are already
			// absolute, and prefixing them again produced
			// https://api.source.partshttps://api.source.parts/v1/...
			name:     "absolute endpoint constant is returned unchanged",
			endpoint: domain.Endpoint_ManufacturingPlacement,
			want:     domain.Endpoint_ManufacturingPlacement,
		},
		{
			name:     "http scheme is also left alone",
			endpoint: "http://localhost:8080/v1/x",
			want:     "http://localhost:8080/v1/x",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := resolveEndpoint(tt.endpoint)
			assert.Equal(t, tt.want, got)
			assert.False(t, strings.Contains(strings.TrimPrefix(got, "https://"), "https://"),
				"endpoint was double-prefixed: %s", got)
		})
	}
}

// unauthenticatedRequestAllowlist names functions that build an http.Request
// without calling setAuthHeader, and why. Anything not listed here must
// authenticate. Keyed by "file:function".
var unauthenticatedRequestAllowlist = map[string]string{
	"auth.go:fetchPlan":     "uses a local accessToken parameter before Client.SetAPIKey has run",
	"auth.go:fetchUserRole": "uses a local accessToken parameter before Client.SetAPIKey has run",
	"github.go:postWebhook": "sends the separate x-github-api-key credential to a webhook endpoint",
}

// TestNoHandRolledAuthHeaders is the regression fence for the bug this package
// had: 23 call sites set "X-API-Key", a header the API ignores, leaving those
// commands unauthenticated on the wire.
//
// It is a source-level check rather than a behavioural one because the API host
// is a compile-time constant (domain.API), so these paths cannot be pointed at
// an httptest server without a wider refactor.
func TestNoHandRolledAuthHeaders(t *testing.T) {
	fset := token.NewFileSet()
	pkgs, err := parser.ParseDir(fset, ".", nil, 0)
	require.NoError(t, err)

	pkg, ok := pkgs["commands"]
	require.True(t, ok, "commands package not found")

	seenAllowlisted := map[string]bool{}

	for path, file := range pkg.Files {
		base := filepath.Base(path)
		if strings.HasSuffix(base, "_test.go") {
			continue
		}

		// 1. The dead header must not reappear anywhere in the package.
		ast.Inspect(file, func(n ast.Node) bool {
			lit, ok := n.(*ast.BasicLit)
			if !ok || lit.Kind != token.STRING {
				return true
			}
			assert.NotEqual(t, `"X-API-Key"`, lit.Value,
				"%s: X-API-Key is not read by the API — call setAuthHeader(req) instead",
				fset.Position(lit.Pos()))
			return true
		})

		// 2. Every declaration that builds a request must authenticate it, and
		// 3. only authheader.go and allowlisted declarations may set
		//    Authorization directly.
		//
		// Both func declarations and package-level vars are scanned. The var
		// case is essential, not incidental: most commands here are declared as
		// `var xCmd = &cobra.Command{RunE: func(...){...}}`, so the request is
		// built inside a function literal hanging off a GenDecl, which a
		// FuncDecl-only walk would miss entirely.
		for _, decl := range file.Decls {
			name, node := declTarget(decl)
			if node == nil {
				continue
			}
			key := base + ":" + name

			buildsRequest, callsSetAuth, setsAuthDirectly := scanRequestUsage(node)

			if reason, allowed := unauthenticatedRequestAllowlist[key]; allowed {
				seenAllowlisted[key] = true
				assert.True(t, buildsRequest,
					"%s is allowlisted (%s) but no longer builds a request — remove the entry",
					key, reason)
				continue
			}

			if buildsRequest {
				assert.True(t, callsSetAuth,
					"%s builds an http.Request but never calls setAuthHeader(req). "+
						"Either authenticate it, or add %q to unauthenticatedRequestAllowlist with a reason.",
					key, key)
			}

			if base != "authheader.go" {
				assert.False(t, setsAuthDirectly,
					"%s sets the Authorization header directly; use setAuthHeader(req) so the scheme stays in one place",
					key)
			}
		}
	}

	// The allowlist must not rot: every entry has to still exist.
	for key, reason := range unauthenticatedRequestAllowlist {
		assert.True(t, seenAllowlisted[key],
			"allowlist entry %q (%s) no longer matches any function — remove it", key, reason)
	}
}

// declTarget returns a name and the AST subtree to scan for a top-level
// declaration, or a nil node if the declaration cannot contain a request.
//
// Function declarations scan their body. Package-level var declarations scan the
// whole spec, which is how `var xCmd = &cobra.Command{RunE: func(...){...}}` —
// the shape most commands in this package use — gets covered.
func declTarget(decl ast.Decl) (string, ast.Node) {
	switch d := decl.(type) {
	case *ast.FuncDecl:
		if d.Body == nil {
			return "", nil
		}
		return d.Name.Name, d.Body
	case *ast.GenDecl:
		if d.Tok != token.VAR {
			return "", nil
		}
		for _, spec := range d.Specs {
			vs, ok := spec.(*ast.ValueSpec)
			if !ok || len(vs.Names) == 0 || len(vs.Values) == 0 {
				continue
			}
			return vs.Names[0].Name, vs
		}
	}
	return "", nil
}

// scanRequestUsage reports whether a subtree constructs an http.Request, whether
// it calls setAuthHeader, and whether it sets the Authorization header itself.
// Nested function literals (cobra RunE closures) are included.
func scanRequestUsage(node ast.Node) (buildsRequest, callsSetAuth, setsAuthDirectly bool) {
	ast.Inspect(node, func(n ast.Node) bool {
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}

		switch fun := call.Fun.(type) {
		case *ast.Ident:
			if fun.Name == "setAuthHeader" {
				callsSetAuth = true
			}
		case *ast.SelectorExpr:
			pkgIdent, ok := fun.X.(*ast.Ident)
			if ok && pkgIdent.Name == "http" &&
				(fun.Sel.Name == "NewRequest" || fun.Sel.Name == "NewRequestWithContext") {
				buildsRequest = true
			}
			// req.Header.Set("Authorization", ...)
			if fun.Sel.Name == "Set" && len(call.Args) > 0 {
				if lit, ok := call.Args[0].(*ast.BasicLit); ok &&
					strings.EqualFold(lit.Value, `"Authorization"`) {
					setsAuthDirectly = true
				}
			}
		}
		return true
	})
	return buildsRequest, callsSetAuth, setsAuthDirectly
}
