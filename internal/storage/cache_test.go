package storage

import (
	"os"
	"path/filepath"
	"testing"
)

func TestContentHash(t *testing.T) {
	tmp, err := os.CreateTemp("", "cache-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(tmp.Name())
	tmp.WriteString("hello world")
	tmp.Close()

	hash, err := ContentHash(tmp.Name())
	if err != nil {
		t.Fatalf("ContentHash: %v", err)
	}
	if len(hash) != 16 {
		t.Fatalf("hash should be 16 hex chars, got %d: %s", len(hash), hash)
	}

	// Same content -> same hash
	tmp2, _ := os.CreateTemp("", "cache-test2-*")
	defer os.Remove(tmp2.Name())
	tmp2.WriteString("hello world")
	tmp2.Close()

	hash2, _ := ContentHash(tmp2.Name())
	if hash != hash2 {
		t.Fatalf("same content should produce same hash: %s != %s", hash, hash2)
	}
}

func TestContentHash_DifferentContent(t *testing.T) {
	tmp1, _ := os.CreateTemp("", "cache-test-*")
	defer os.Remove(tmp1.Name())
	tmp1.WriteString("content A")
	tmp1.Close()

	tmp2, _ := os.CreateTemp("", "cache-test-*")
	defer os.Remove(tmp2.Name())
	tmp2.WriteString("content B")
	tmp2.Close()

	h1, _ := ContentHash(tmp1.Name())
	h2, _ := ContentHash(tmp2.Name())
	if h1 == h2 {
		t.Fatal("different content should produce different hashes")
	}
}

func TestContentHash_FileNotFound(t *testing.T) {
	_, err := ContentHash(filepath.Join(os.TempDir(), "nonexistent-file-12345"))
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestValidateAliasName(t *testing.T) {
	tests := []struct {
		name    string
		wantErr bool
	}{
		{"nrf54h20", false},
		{"npm1300-pmic", false},
		{"my_alias.v2", false},
		{"", true},
		{"-starts-with-dash", true},
		{"has spaces", true},
		{"a1b2c3d4e5f60718", true},  // 16-char hex, ambiguous with content hashes
		{"a1b2c3d4e5f6071", false},  // 15-char hex is fine
		{"a1b2c3d4e5f6g7h8", false}, // contains 'g', not pure hex
	}

	for _, tt := range tests {
		err := ValidateAliasName(tt.name)
		if (err != nil) != tt.wantErr {
			t.Errorf("ValidateAliasName(%q): got err=%v, wantErr=%v", tt.name, err, tt.wantErr)
		}
	}
}

func TestParsePageSpec(t *testing.T) {
	tests := []struct {
		input   string
		want    []int
		wantErr bool
	}{
		{"29", []int{29}, false},
		{"1-5", []int{1, 2, 3, 4, 5}, false},
		{"29,143", []int{29, 143}, false},
		{"1-3,7,10-12", []int{1, 2, 3, 7, 10, 11, 12}, false},
		{"5,3,1", []int{1, 3, 5}, false},        // sorted output
		{"1,1,2,2", []int{1, 2}, false},          // deduplicated
		{"", nil, true},                           // empty
		{"abc", nil, true},                        // non-numeric
		{"5-3", nil, true},                        // reversed range
		{"0", nil, true},                          // page 0
		{"-1", nil, true},                         // negative
	}

	for _, tt := range tests {
		spec, err := ParsePageSpec(tt.input)
		if (err != nil) != tt.wantErr {
			t.Errorf("ParsePageSpec(%q): err=%v, wantErr=%v", tt.input, err, tt.wantErr)
			continue
		}
		if err != nil {
			continue
		}
		if len(spec.Pages) != len(tt.want) {
			t.Errorf("ParsePageSpec(%q): got %v, want %v", tt.input, spec.Pages, tt.want)
			continue
		}
		for i, p := range spec.Pages {
			if p != tt.want[i] {
				t.Errorf("ParsePageSpec(%q)[%d]: got %d, want %d", tt.input, i, p, tt.want[i])
			}
		}
	}
}
