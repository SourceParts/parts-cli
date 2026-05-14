package auth

import "strings"

// CleanCredential strips surrounding quotes and newline-like artifacts from a
// credential value so that values copied straight from a .env file (where the
// API key is often stored as `KEY="abc\n"`) still match server-side comparison
// byte-for-byte.
//
// Mirrors the cleanEnvVar function in source-parts-landing-page's
// lib/utils/clean-env.ts — that runtime cleans the same artifacts on the
// server side, so any client that doesn't clean here ends up sending a
// longer-than-expected header and silently 401s.
//
// Order matters: real and literal newlines/CRs are stripped FIRST so that
// trailing whitespace doesn't hide the closing quote from the quote-strip
// pass. The function is idempotent — calling it twice is a no-op.
func CleanCredential(v string) string {
	// Strip literal two-character escape sequences (\n, \r) that appear when a
	// shell or editor preserved the backslash-escape rather than a real newline.
	v = strings.ReplaceAll(v, `\n`, "")
	v = strings.ReplaceAll(v, `\r`, "")
	// Strip real newlines and carriage returns.
	v = strings.ReplaceAll(v, "\n", "")
	v = strings.ReplaceAll(v, "\r", "")
	// Trim leading/trailing whitespace so quotes are exposed at the boundaries.
	v = strings.TrimSpace(v)
	// Strip a single layer of matching surrounding quotes.
	if len(v) >= 2 {
		first, last := v[0], v[len(v)-1]
		if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
			v = v[1 : len(v)-1]
		}
	}
	// The inner value may itself have padding — e.g. `"  abc  "` → `  abc  ` → `abc`.
	return strings.TrimSpace(v)
}
