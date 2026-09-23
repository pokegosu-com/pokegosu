package scan

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func line(id, timestamp string, tokens int64) string {
	return `{"type":"assistant","uuid":"` + id + timestamp +
		`","sessionId":"s1","requestId":"req_` + id +
		`","timestamp":"` + timestamp +
		`","message":{"id":"` + id + `","usage":{"input_tokens":` +
		itoa(tokens) + `,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}` + "\n"
}

func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	var digits []byte
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}

func logDir(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for name, content := range files {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

// Resuming a session rewrites earlier messages into a new file. The dedupe
// set spans the whole scan, so those repeats must not be counted again — this
// is the case a per-file set gets wrong.
func TestRunDeduplicatesAcrossFiles(t *testing.T) {
	first := line("msg_1", "2026-09-12T11:10:00Z", 100) + line("msg_2", "2026-09-12T11:20:00Z", 200)
	resumed := line("msg_1", "2026-09-12T11:40:00Z", 100) + // replayed
		line("msg_2", "2026-09-12T11:41:00Z", 200) + // replayed
		line("msg_3", "2026-09-12T11:45:00Z", 300) // new

	result, err := Run(Options{Roots: []string{logDir(t, map[string]string{
		"proj/session-a.jsonl": first,
		"proj/session-b.jsonl": resumed,
	})}})
	if err != nil {
		t.Fatal(err)
	}

	if result.Messages != 3 {
		t.Errorf("Messages = %d, want 3", result.Messages)
	}
	if got := result.Total(); got != 600 {
		t.Errorf("Total() = %d, want 600 (1100 means the replays were counted twice)", got)
	}
	if len(result.Rollups) != 1 {
		t.Fatalf("got %d buckets, want 1: %+v", len(result.Rollups), result.Rollups)
	}
	if result.Stats.Entries != 5 {
		t.Errorf("Stats.Entries = %d, want 5 records read before deduplication", result.Stats.Entries)
	}
}

func TestRunSince(t *testing.T) {
	root := logDir(t, map[string]string{"proj/s.jsonl": line("msg_1", "2026-09-11T23:00:00Z", 100) +
		line("msg_2", "2026-09-12T00:30:00Z", 200) +
		line("msg_3", "2026-09-12T01:00:00Z", 300)})

	since, _ := time.Parse(time.RFC3339, "2026-09-12T00:00:00Z")
	result, err := Run(Options{Roots: []string{root}, Since: since})
	if err != nil {
		t.Fatal(err)
	}

	if got := result.Total(); got != 500 {
		t.Errorf("Total() = %d, want 500", got)
	}
	// Messages counts what was read, not what survived the filter: sync needs
	// the whole dedupe set even when it only uploads recent buckets.
	if result.Messages != 3 {
		t.Errorf("Messages = %d, want 3", result.Messages)
	}
}

func TestRunEmptyRoot(t *testing.T) {
	result, err := Run(Options{Roots: []string{t.TempDir()}})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Rollups) != 0 || result.Total() != 0 {
		t.Errorf("result = %+v, want nothing", result)
	}
}

// A path the user typed is a typo when it does not exist, unlike a default
// location, which is simply an agent that is not installed.
func TestRunRejectsMissingNamedRoot(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "nope")
	if _, err := Run(Options{Roots: []string{missing}}); err == nil {
		t.Fatal("Run() succeeded, want an error naming the missing directory")
	}
}

func TestRunSkipsAbsentDefaultRoots(t *testing.T) {
	// Point the provider at a location that does not exist.
	t.Setenv("CLAUDE_CONFIG_DIR", filepath.Join(t.TempDir(), "absent"))

	result, err := Run(Options{})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if len(result.Roots) != 0 {
		t.Errorf("Roots = %v, want none scanned", result.Roots)
	}
	if len(result.Rollups) != 0 {
		t.Errorf("Rollups = %+v, want none", result.Rollups)
	}
}
