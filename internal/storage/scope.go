package storage

import (
	"crypto/sha256"
	"fmt"
	"path/filepath"
)

// Scope defines user/team/project isolation for storage paths.
type Scope struct {
	UserHash  string // SHA256(username)[0:12]
	Team      string // hashed team slug (t_{sha256[:12]}) or empty
	ProjectID string // project identifier
}

// NewScope creates a Scope by hashing the username and (optionally) the team name.
func NewScope(username, team, projectID string) *Scope {
	uh := sha256.Sum256([]byte(username))
	s := &Scope{
		UserHash:  fmt.Sprintf("%x", uh[:6]), // first 12 hex chars
		ProjectID: projectID,
	}
	if team != "" {
		th := sha256.Sum256([]byte(team))
		s.Team = fmt.Sprintf("t_%x", th[:6])
	}
	return s
}

// DatasheetPath builds a scoped remote path for a datasheet file.
//
//	private/u_{user_hash}/{team}/{project}/datasheets/sha256_{content_hash}/{filename}
func (s *Scope) DatasheetPath(contentHash, filename string) string {
	base := fmt.Sprintf("private/u_%s", s.UserHash)
	if s.Team != "" {
		base += "/" + s.Team
	}
	return filepath.ToSlash(fmt.Sprintf(
		"%s/%s/datasheets/sha256_%s/%s",
		base, s.ProjectID, contentHash, filename,
	))
}
