package commands

import (
	"testing"

	"github.com/SourceParts/parts-cli/internal/types"
)

func TestParseECNFrontmatter(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantID  string
		wantErr bool
		checkFn func(t *testing.T, fm *types.ECNFrontmatter)
	}{
		{
			name: "valid ECN frontmatter",
			input: `---
id: ECN-047
title: "EVT2 Storage GPIO Mapping"
type: Schematic Change
severity: HIGH
status: IN REVIEW
disposition: APPROVAL REQUIRED
author: "Parts Studio"
updated_date: 2026-03-27
thread_id: "custom-thread-id"
cross_references: [ECN-026, ECN-032]
---

## Summary

Some body content here.`,
			wantID: "ECN-047",
			checkFn: func(t *testing.T, fm *types.ECNFrontmatter) {
				if fm.Title != "EVT2 Storage GPIO Mapping" {
					t.Errorf("title = %q, want %q", fm.Title, "EVT2 Storage GPIO Mapping")
				}
				if fm.Type != "Schematic Change" {
					t.Errorf("type = %q, want %q", fm.Type, "Schematic Change")
				}
				if fm.Severity != "HIGH" {
					t.Errorf("severity = %q, want %q", fm.Severity, "HIGH")
				}
				if fm.Status != "IN REVIEW" {
					t.Errorf("status = %q, want %q", fm.Status, "IN REVIEW")
				}
				if fm.Disposition != "APPROVAL REQUIRED" {
					t.Errorf("disposition = %q, want %q", fm.Disposition, "APPROVAL REQUIRED")
				}
				if fm.Author != "Parts Studio" {
					t.Errorf("author = %q, want %q", fm.Author, "Parts Studio")
				}
				if fm.UpdatedDate != "2026-03-27" {
					t.Errorf("updated_date = %q, want %q", fm.UpdatedDate, "2026-03-27")
				}
				if fm.ThreadID != "custom-thread-id" {
					t.Errorf("thread_id = %q, want %q", fm.ThreadID, "custom-thread-id")
				}
				if len(fm.CrossReferences) != 2 {
					t.Errorf("cross_references len = %d, want 2", len(fm.CrossReferences))
				}
			},
		},
		{
			name: "empty thread_id returns empty string",
			input: `---
id: ECN-003
title: "Test"
thread_id: ""
---

Body.`,
			wantID: "ECN-003",
			checkFn: func(t *testing.T, fm *types.ECNFrontmatter) {
				if fm.ThreadID != "" {
					t.Errorf("thread_id = %q, want empty", fm.ThreadID)
				}
			},
		},
		{
			name:    "missing frontmatter delimiters",
			input:   "# Just a markdown file\n\nNo frontmatter here.",
			wantErr: true,
		},
		{
			name: "missing id field",
			input: `---
title: "No ID"
severity: HIGH
---

Body.`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fm, body, err := parseECNFrontmatter(tt.input)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if fm.ID != tt.wantID {
				t.Errorf("id = %q, want %q", fm.ID, tt.wantID)
			}
			if body == "" {
				t.Error("body should not be empty")
			}
			if tt.checkFn != nil {
				tt.checkFn(t, fm)
			}
		})
	}
}
