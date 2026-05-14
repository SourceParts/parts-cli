package auth

import "testing"

func TestCleanCredential(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain", "abc123", "abc123"},
		{"double-quoted", `"abc123"`, "abc123"},
		{"single-quoted", `'abc123'`, "abc123"},
		{"quoted with literal escape-n", `"abc123\n"`, "abc123"},
		{"quoted with literal escape-n and trailing newline", "\"abc123\\n\"\n", "abc123"},
		{"trailing real newline only", "abc123\n", "abc123"},
		{"trailing CR+LF", "abc123\r\n", "abc123"},
		{"surrounding whitespace", "  abc123  ", "abc123"},
		{"inner padded then quoted", `"  abc123  "`, "abc123"},
		{"empty quoted", `""`, ""},
		{"single char unquoted", "x", "x"},
		{"single quote unbalanced left", `"abc`, `"abc`},
		{"single quote unbalanced right", `abc"`, `abc"`},
		{"GITHUB_API_KEY shape from .env.production", "\"1d65b46e5ebfd312b7196e9d9d93ba586312bb4b1b511ed206648ed66ec2b2249\\n\"\n", "1d65b46e5ebfd312b7196e9d9d93ba586312bb4b1b511ed206648ed66ec2b2249"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := CleanCredential(c.in)
			if got != c.want {
				t.Errorf("CleanCredential(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestCleanCredentialIdempotent(t *testing.T) {
	inputs := []string{
		`"abc123\n"`,
		"\"abc123\\n\"\n",
		"  abc123  ",
		"abc123",
	}
	for _, in := range inputs {
		once := CleanCredential(in)
		twice := CleanCredential(once)
		if once != twice {
			t.Errorf("not idempotent for %q: once=%q twice=%q", in, once, twice)
		}
	}
}
