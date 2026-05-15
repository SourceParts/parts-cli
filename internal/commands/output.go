package commands

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

// Render emits the API response either as JSON (when jsonOutput is true) or
// as a best-effort human-readable rendering. It parses the standard
// {"status", "data", "error", "message"} envelope and prints the `data`
// payload key-by-key. Use this for commands that don't have a hand-rolled
// typed formatter — it replaces the old `io.Copy(w, res.Body)` pattern that
// leaked raw JSON to stdout.
//
// headline is an optional one-line summary printed above the data. Pass "".
func Render(body []byte, jsonOutput bool, headline string) {
	if jsonOutput {
		writeJSON(body)
		return
	}

	var env struct {
		Status  string      `json:"status"`
		Data    interface{} `json:"data"`
		Error   string      `json:"error,omitempty"`
		Message string      `json:"message,omitempty"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		// Fall back to indented JSON so callers still see structured output
		// rather than the malformed raw bytes the old code leaked.
		fmt.Fprintf(os.Stderr, "Warning: response did not match expected envelope: %v\n", err)
		writeJSON(body)
		return
	}

	if env.Error != "" {
		fmt.Fprintf(os.Stderr, "API error: %s\n", env.Error)
		return
	}

	if headline != "" {
		fmt.Println(headline)
	}
	if env.Message != "" {
		fmt.Println(env.Message)
	}

	renderValue(env.Data, "")
}

// writeJSON pretty-prints raw bytes if they parse as JSON, falling back to
// the raw payload when they don't. Matches the search/price command pattern
// of trailing newline.
func writeJSON(body []byte) {
	var pretty bytes.Buffer
	if err := json.Indent(&pretty, body, "", "  "); err == nil {
		os.Stdout.Write(pretty.Bytes())
	} else {
		os.Stdout.Write(body)
	}
	fmt.Println()
}

// renderValue walks a decoded JSON value and prints it as indented key/value
// pairs. Map keys are sorted for stable output.
func renderValue(v interface{}, indent string) {
	switch x := v.(type) {
	case nil:
		return
	case string:
		if x != "" {
			fmt.Printf("%s%s\n", indent, x)
		}
	case float64:
		if x == float64(int64(x)) {
			fmt.Printf("%s%d\n", indent, int64(x))
		} else {
			fmt.Printf("%s%v\n", indent, x)
		}
	case bool:
		fmt.Printf("%s%v\n", indent, x)
	case map[string]interface{}:
		keys := make([]string, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			val := x[k]
			label := strings.ReplaceAll(k, "_", " ")
			switch vv := val.(type) {
			case map[string]interface{}:
				if len(vv) == 0 {
					continue
				}
				fmt.Printf("%s%s:\n", indent, label)
				renderValue(vv, indent+"  ")
			case []interface{}:
				if len(vv) == 0 {
					continue
				}
				fmt.Printf("%s%s:\n", indent, label)
				renderValue(vv, indent+"  ")
			case nil:
				continue
			case string:
				if vv == "" {
					continue
				}
				fmt.Printf("%s%s: %s\n", indent, label, vv)
			case float64:
				if vv == float64(int64(vv)) {
					fmt.Printf("%s%s: %d\n", indent, label, int64(vv))
				} else {
					fmt.Printf("%s%s: %v\n", indent, label, vv)
				}
			default:
				fmt.Printf("%s%s: %v\n", indent, label, vv)
			}
		}
	case []interface{}:
		for i, el := range x {
			switch el.(type) {
			case map[string]interface{}, []interface{}:
				fmt.Printf("%s[%d]\n", indent, i)
				renderValue(el, indent+"  ")
			default:
				fmt.Printf("%s- ", indent)
				renderValue(el, "")
			}
		}
	default:
		fmt.Printf("%s%v\n", indent, x)
	}
}
