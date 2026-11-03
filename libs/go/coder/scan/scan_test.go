package scan

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider/claudecode"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider/codex"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
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

// Claude Code deletes sessions after thirty days, and the server overwrites
// each hour with what is sent last, so a deleted log would lower hours
// already counted. What an earlier scan read keeps counting.
func TestRunKeepsMessagesWhoseLogsAreGone(t *testing.T) {
	root := logDir(t, map[string]string{
		"proj/old.jsonl": line("msg_1", "2026-09-12T11:10:00Z", 100) + line("msg_2", "2026-09-12T11:20:00Z", 200),
		"proj/new.jsonl": line("msg_3", "2026-09-12T11:30:00Z", 300),
	})

	first, err := Run(Options{Roots: []string{root}})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(root, "proj/old.jsonl")); err != nil {
		t.Fatal(err)
	}

	second, err := Run(Options{Roots: []string{root}, Kept: first.Records})
	if err != nil {
		t.Fatal(err)
	}
	if got := second.Total(); got != 600 {
		t.Errorf("Total() = %d, want 600: the deleted log's 300 still happened", got)
	}
	if second.Restored != 2 {
		t.Errorf("Restored = %d, want 2", second.Restored)
	}
	if len(second.Records) != 3 {
		t.Errorf("Records = %d, want 3, so the next scan keeps them too", len(second.Records))
	}

	// And on the scan after that, from what this one kept.
	third, err := Run(Options{Roots: []string{root}, Kept: second.Records})
	if err != nil {
		t.Fatal(err)
	}
	if got := third.Total(); got != 600 {
		t.Errorf("third Total() = %d, want 600", got)
	}
}

// A message whose log is still there is as the log says, so a count that a
// newer parser reads differently can fall.
func TestRunTrustsLogsThatAreThere(t *testing.T) {
	root := logDir(t, map[string]string{"proj/s.jsonl": line("msg_1", "2026-09-12T11:10:00Z", 100)})
	path := filepath.Join(root, "proj/s.jsonl")
	at, _ := time.Parse(time.RFC3339, "2026-09-12T11:10:00Z")

	kept := []usage.Record{
		// Counted higher before.
		{Provider: "claude_code", MessageID: "msg_1", RequestID: "req_msg_1", At: at, Tokens: 999, Sources: []string{path}},
		// Read from this file before, but no longer read from it.
		{Provider: "claude_code", MessageID: "msg_gone", RequestID: "req_gone", At: at, Tokens: 50, Sources: []string{path}},
	}

	result, err := Run(Options{Roots: []string{root}, Kept: kept})
	if err != nil {
		t.Fatal(err)
	}
	if got := result.Total(); got != 100 {
		t.Errorf("Total() = %d, want 100", got)
	}
	if result.Restored != 0 {
		t.Errorf("Restored = %d, want 0", result.Restored)
	}
}

// A message is not restored while any copy of it is left: a resumed session
// holds the earlier ones again.
func TestRunCountsAMessageOnceWhileACopyIsLeft(t *testing.T) {
	root := logDir(t, map[string]string{
		"proj/a.jsonl": line("msg_1", "2026-09-12T11:10:00Z", 100),
		"proj/b.jsonl": line("msg_1", "2026-09-12T11:40:00Z", 100) + line("msg_2", "2026-09-12T11:45:00Z", 200),
	})
	first, err := Run(Options{Roots: []string{root}})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(root, "proj/a.jsonl")); err != nil {
		t.Fatal(err)
	}

	second, err := Run(Options{Roots: []string{root}, Kept: first.Records})
	if err != nil {
		t.Fatal(err)
	}
	if got := second.Total(); got != 300 {
		t.Errorf("Total() = %d, want 300, not 400", got)
	}
	if second.Restored != 0 {
		t.Errorf("Restored = %d, want 0: b.jsonl still holds msg_1", second.Restored)
	}
}

// A scan of one agent leaves what was kept for another as it was.
func TestRunPassesOtherProvidersThrough(t *testing.T) {
	at, _ := time.Parse(time.RFC3339, "2026-09-12T11:10:00Z")
	other := usage.Record{Provider: "other", MessageID: "x", At: at, Tokens: 7, Sources: []string{"/nowhere/x.jsonl"}}

	result, err := Run(Options{
		Roots:     []string{t.TempDir()},
		Providers: []provider.Provider{claudecode.New()},
		Kept:      []usage.Record{other},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Total() != 0 || result.Restored != 0 {
		t.Errorf("result = %+v, want nothing counted", result)
	}
	if len(result.Records) != 1 || result.Records[0].MessageID != "x" {
		t.Errorf("Records = %+v, want the other provider's message kept", result.Records)
	}
}

// codexCase copies one file of a shared Codex case into dir.
func codexCase(t *testing.T, dir, caseName, file string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "tests", "coder-scan-codex", "cases", caseName, "logs", "2025", "05", "12", file))
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, file)
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func codexOnly() []provider.Provider { return []provider.Provider{codex.New()} }

// A Codex turn has no id, and is kept under its time and what it spent.
func TestRunKeepsCodexTurnsWhoseLogsAreGone(t *testing.T) {
	root := t.TempDir()
	plain := codexCase(t, root, "normal-session", "rollout-2025-05-12T14-00-00-s1.jsonl")

	first, err := Run(Options{Roots: []string{root}, Providers: codexOnly()})
	if err != nil {
		t.Fatal(err)
	}
	if got := first.Total(); got != 330 {
		t.Fatalf("first Total() = %d, want 330", got)
	}
	if err := os.Remove(plain); err != nil {
		t.Fatal(err)
	}

	second, err := Run(Options{Roots: []string{root}, Providers: codexOnly(), Kept: first.Records})
	if err != nil {
		t.Fatal(err)
	}
	if got := second.Total(); got != 330 {
		t.Errorf("Total() = %d, want 330", got)
	}
	if second.Restored != first.Messages {
		t.Errorf("Restored = %d, want all %d turns", second.Restored, first.Messages)
	}
}

// Codex compresses a week-old log and deletes the plain one. The turns are
// read from the compressed file, so the kept ones do not count again.
func TestRunDoesNotRestoreCodexTurnsACompressedLogHolds(t *testing.T) {
	root := t.TempDir()
	plain := codexCase(t, root, "normal-session", "rollout-2025-05-12T14-00-00-s1.jsonl")

	first, err := Run(Options{Roots: []string{root}, Providers: codexOnly()})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(plain); err != nil {
		t.Fatal(err)
	}
	codexCase(t, root, "compressed-session", "rollout-2025-05-12T14-00-00-s1.jsonl.zst")

	second, err := Run(Options{Roots: []string{root}, Providers: codexOnly(), Kept: first.Records})
	if err != nil {
		t.Fatal(err)
	}
	if got := second.Total(); got != 330 {
		t.Errorf("Total() = %d, want 330, not 660", got)
	}
	if second.Restored != 0 {
		t.Errorf("Restored = %d, want 0", second.Restored)
	}
}
