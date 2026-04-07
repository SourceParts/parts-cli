package storage

import (
	"testing"
)

func TestNewScope(t *testing.T) {
	s := NewScope("parts", "sourceparts", "nrf54h20-main-board")
	if s.UserHash == "" {
		t.Fatal("UserHash should not be empty")
	}
	if len(s.UserHash) != 12 {
		t.Fatalf("UserHash should be 12 hex chars, got %d: %s", len(s.UserHash), s.UserHash)
	}
	wantTeam := "t_c3aba3fa0c0c"
	if s.Team != wantTeam {
		t.Fatalf("Team = %q, want %q (hashed)", s.Team, wantTeam)
	}
	if s.ProjectID != "nrf54h20-main-board" {
		t.Fatalf("ProjectID = %q, want nrf54h20-main-board", s.ProjectID)
	}
}

func TestNewScope_EmptyTeam(t *testing.T) {
	s := NewScope("parts", "", "proj")
	if s.Team != "" {
		t.Fatalf("Team should be empty, got %q", s.Team)
	}
}

func TestNewScope_Deterministic(t *testing.T) {
	a := NewScope("parts", "t", "p")
	b := NewScope("parts", "t", "p")
	if a.UserHash != b.UserHash {
		t.Fatalf("same username should produce same hash: %s != %s", a.UserHash, b.UserHash)
	}
	if a.Team != b.Team {
		t.Fatalf("same team should produce same hash: %s != %s", a.Team, b.Team)
	}
}

func TestNewScope_DifferentUsers(t *testing.T) {
	a := NewScope("alice", "t", "p")
	b := NewScope("bob", "t", "p")
	if a.UserHash == b.UserHash {
		t.Fatal("different usernames should produce different hashes")
	}
}

func TestDatasheetPath(t *testing.T) {
	s := NewScope("parts", "sourceparts", "nrf54h20-main-board")
	path := s.DatasheetPath("a1b2c3d4e5f6g7h8", "nPM1300_page_29.png")

	expected := "private/u_" + s.UserHash + "/t_c3aba3fa0c0c/nrf54h20-main-board/datasheets/sha256_a1b2c3d4e5f6g7h8/nPM1300_page_29.png"
	if path != expected {
		t.Fatalf("DatasheetPath =\n  %s\nwant\n  %s", path, expected)
	}
}

func TestDatasheetPath_NoTeam(t *testing.T) {
	s := NewScope("parts", "", "nrf54h20-main-board")
	path := s.DatasheetPath("a1b2c3d4e5f6g7h8", "nPM1300_page_29.png")

	expected := "private/u_" + s.UserHash + "/nrf54h20-main-board/datasheets/sha256_a1b2c3d4e5f6g7h8/nPM1300_page_29.png"
	if path != expected {
		t.Fatalf("DatasheetPath (no team) =\n  %s\nwant\n  %s", path, expected)
	}
}
