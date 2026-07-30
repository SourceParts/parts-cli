package commands

import (
	"strings"

	"github.com/SourceParts/parts-cli/internal/domain"
)

// resolveEndpoint returns an absolute API URL for endpoint.
//
// Two conventions are in use across this package. Most call sites pass a
// relative path ("/v1/eda/export"), but some pass a domain.Endpoint_* constant,
// which is already absolute — domain.V1Prefix expands to "https://" + API +
// "/v1". Prefixing an already-absolute constant produced URLs like
//
//	https://api.source.partshttps://api.source.parts/v1/manufacturing/placement
//
// which parse as a hostname and then fail DNS resolution, so those commands
// never reached the server at all.
//
// Accepting either form keeps both conventions correct and removes the trap.
func resolveEndpoint(endpoint string) string {
	if strings.HasPrefix(endpoint, "https://") || strings.HasPrefix(endpoint, "http://") {
		return endpoint
	}
	return "https://" + domain.API + endpoint
}
