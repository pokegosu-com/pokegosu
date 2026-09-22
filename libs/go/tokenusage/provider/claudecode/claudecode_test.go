package claudecode

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/usage"
)

// writeLog puts a log file at path under a fresh temp dir, creating parent
// directories, and returns the root. Content is written verbatim so a test
// can leave the last line unterminated.
func writeLog(t *testing.T, files map[string]string) string {
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

func parse(t *testing.T, files map[string]string) ([]usage.Entry, provider.Stats) {
	t.Helper()
	var entries []usage.Entry
	stats, err := New().Parse(writeLog(t, files), func(e usage.Entry) {
		entries = append(entries, e)
	})
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return entries, stats
}

// The four token fields, one line. Cache reads dominate real logs, so a
// parser that drops them is off by two orders of magnitude rather than a
// little.
const oneMessage = `{"type":"assistant","uuid":"u1","sessionId":"s1","requestId":"req_1","isSidechain":false,"timestamp":"2026-09-12T11:05:56.885Z","message":{"id":"msg_1","role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":12483,"cache_read_input_tokens":32017,"output_tokens":227}}}`

func TestParseSumsAllFourTokenFields(t *testing.T) {
	entries, stats := parse(t, map[string]string{"a/session.jsonl": oneMessage + "\n"})

	if len(entries) != 1 {
		t.Fatalf("got %d entries, want 1", len(entries))
	}
	got := entries[0]
	if want := int64(2 + 12483 + 32017 + 227); got.Tokens != want {
		t.Errorf("Tokens = %d, want %d", got.Tokens, want)
	}
	if got.MessageID != "msg_1" {
		t.Errorf("MessageID = %q, want msg_1 (the message id, not the line uuid)", got.MessageID)
	}
	if got.SessionID != "s1" || got.RequestID != "req_1" {
		t.Errorf("SessionID/RequestID = %q/%q, want s1/req_1: both sit at the top level of the line",
			got.SessionID, got.RequestID)
	}
	if got.Provider != ID {
		t.Errorf("Provider = %q, want %q", got.Provider, ID)
	}
	if want, _ := time.Parse(time.RFC3339, "2026-09-12T11:05:56.885Z"); !got.At.Equal(want) {
		t.Errorf("At = %s, want %s", got.At, want)
	}
	if stats.Files != 1 || stats.Lines != 1 || stats.Entries != 1 {
		t.Errorf("stats = %+v, want 1 file, 1 line, 1 entry", stats)
	}
}

// iterations repeats the top-level usage fields. Adding it in would double
// every message that has one.
func TestParseIgnoresIterations(t *testing.T) {
	line := `{"timestamp":"2026-09-12T11:00:00Z","message":{"id":"msg_1","usage":{` +
		`"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4,` +
		`"iterations":[{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}]}}}`

	entries, _ := parse(t, map[string]string{"s.jsonl": line + "\n"})
	if len(entries) != 1 || entries[0].Tokens != 10 {
		t.Fatalf("entries = %+v, want one of 10 tokens", entries)
	}
}

// Fields we have never seen are the normal case as the log format moves.
func TestParseIgnoresUnknownFields(t *testing.T) {
	line := `{"timestamp":"2026-09-12T11:00:00Z","brandNewField":{"nested":[1,2,3]},"message":` +
		`{"id":"msg_1","model":"claude-opus-5","usage":{"input_tokens":1,"cache_creation_input_tokens":2,` +
		`"cache_read_input_tokens":3,"output_tokens":4,"service_tier":"standard","speed":"fast",` +
		`"cache_creation":{"ephemeral_5m_input_tokens":2},"output_tokens_details":{}}}}`

	entries, stats := parse(t, map[string]string{"s.jsonl": line + "\n"})
	if len(entries) != 1 || entries[0].Tokens != 10 {
		t.Fatalf("entries = %+v, want one of 10 tokens", entries)
	}
	if stats.BadLines != 0 || stats.BadRecords != 0 {
		t.Errorf("stats = %+v, want no complaints", stats)
	}
}

func TestParseSkipsLinesWithoutUsage(t *testing.T) {
	content := `{"type":"user","timestamp":"2026-09-12T11:00:00Z","message":{"role":"user","content":"hi"}}` + "\n" +
		`{"type":"file-history-snapshot","timestamp":"2026-09-12T11:00:01Z"}` + "\n" +
		oneMessage + "\n"

	entries, stats := parse(t, map[string]string{"s.jsonl": content})
	if len(entries) != 1 {
		t.Fatalf("got %d entries, want 1", len(entries))
	}
	if stats.Lines != 3 {
		t.Errorf("Lines = %d, want 3", stats.Lines)
	}
	if stats.BadLines != 0 || stats.BadRecords != 0 {
		t.Errorf("stats = %+v, want no complaints: a line without usage is not a problem", stats)
	}
}

// A log being appended to right now ends mid-write. Everything before the cut
// still has to count.
func TestParseTruncatedLastLine(t *testing.T) {
	content := oneMessage + "\n" + `{"timestamp":"2026-09-12T11:06:00Z","message":{"id":"msg_2","usa`

	entries, stats := parse(t, map[string]string{"s.jsonl": content})
	if len(entries) != 1 {
		t.Fatalf("got %d entries, want the one complete message", len(entries))
	}
	if stats.BadLines != 1 {
		t.Errorf("BadLines = %d, want 1", stats.BadLines)
	}
}

func TestParseEmptyFile(t *testing.T) {
	entries, stats := parse(t, map[string]string{"empty.jsonl": "", "blank.jsonl": "\n\n  \n"})
	if len(entries) != 0 {
		t.Fatalf("got %d entries, want none", len(entries))
	}
	if stats.Files != 2 || stats.Lines != 0 {
		t.Errorf("stats = %+v, want 2 files and no lines", stats)
	}
	if stats.BadLines != 0 {
		t.Errorf("BadLines = %d, want 0: a blank line is not malformed", stats.BadLines)
	}
}

// Without an id a message cannot be deduplicated, and the log holds two or
// three copies of it, so counting it would inflate the total.
func TestParseSkipsRecordsItCannotDeduplicate(t *testing.T) {
	content := `{"timestamp":"2026-09-12T11:00:00Z","message":{"usage":{"input_tokens":5,"output_tokens":5}}}` + "\n" +
		`{"message":{"id":"msg_2","usage":{"input_tokens":5,"output_tokens":5}}}` + "\n" +
		`{"timestamp":"not a date","message":{"id":"msg_3","usage":{"input_tokens":5,"output_tokens":5}}}` + "\n" +
		`{"timestamp":"2026-09-12T11:00:00Z","message":{"id":"msg_4","usage":{"input_tokens":-5,"output_tokens":5}}}` + "\n"

	entries, stats := parse(t, map[string]string{"s.jsonl": content})
	if len(entries) != 0 {
		t.Fatalf("entries = %+v, want none", entries)
	}
	if stats.BadRecords != 4 {
		t.Errorf("BadRecords = %d, want 4", stats.BadRecords)
	}
}

func TestParseReadsNestedDirectoriesAndOnlyJSONL(t *testing.T) {
	entries, stats := parse(t, map[string]string{
		"-home-me-a/one.jsonl":       oneMessage + "\n",
		"-home-me-b/deep/two.jsonl":  oneMessage + "\n",
		"-home-me-b/notes.txt":       "ignore me",
		"-home-me-b/other.jsonl.bak": oneMessage + "\n",
	})
	if len(entries) != 2 {
		t.Fatalf("got %d entries, want 2", len(entries))
	}
	if stats.Files != 2 {
		t.Errorf("Files = %d, want 2", stats.Files)
	}
}

func TestParseMissingRoot(t *testing.T) {
	// WalkDir reports the missing root itself; the scan should not die on it.
	stats, err := New().Parse(filepath.Join(t.TempDir(), "nope"), func(usage.Entry) {})
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if stats.Unreadable != 1 {
		t.Errorf("Unreadable = %d, want 1", stats.Unreadable)
	}
}

func TestRootsHonorsConfigDirOverride(t *testing.T) {
	t.Setenv("CLAUDE_CONFIG_DIR", filepath.Join("/tmp", "one")+string(os.PathListSeparator)+filepath.Join("/tmp", "two"))

	roots, err := New().Roots()
	if err != nil {
		t.Fatal(err)
	}
	want := []string{filepath.Join("/tmp", "one", "projects"), filepath.Join("/tmp", "two", "projects")}
	if len(roots) != len(want) {
		t.Fatalf("Roots() = %v, want %v", roots, want)
	}
	for i := range want {
		if roots[i] != want[i] {
			t.Errorf("Roots()[%d] = %q, want %q", i, roots[i], want[i])
		}
	}
}

func TestRootsDefault(t *testing.T) {
	t.Setenv("CLAUDE_CONFIG_DIR", "")

	roots, err := New().Roots()
	if err != nil {
		t.Fatal(err)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip("no home directory")
	}
	want := filepath.Join(home, ".claude", "projects")
	for _, root := range roots {
		if root == want {
			return
		}
	}
	t.Errorf("Roots() = %v, want it to include %q", roots, want)
}
