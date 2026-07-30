package commands

import "net/http"

// setAuthHeader applies the credential in Client to req.
//
// The API authenticates with "Authorization: Bearer <token>", the same scheme
// client.newAuthenticatedRequest uses. Commands that build their own
// http.Request (multipart uploads, ad-hoc JSON posts) must go through this
// helper rather than setting a header themselves, so there is one place where
// the scheme is defined.
//
// Client.APIKey holds either a raw API key or an OAuth access token —
// auth.go stores tokens.AccessToken there after a browser login — so both
// login paths work without the caller needing to know which is in play.
func setAuthHeader(req *http.Request) {
	if req == nil {
		return
	}
	if apiKey := Client.GetAPIKey(); apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}
}
