package codex

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// writeLog puts log files under a fresh temp dir, creating parent
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

func lines(ls ...string) string { return strings.Join(ls, "\n") + "\n" }

const (
	meta   = `{"timestamp":"2026-09-12T11:00:00.000Z","type":"session_meta","payload":{"id":"s1","source":"cli"}}`
	model  = `{"timestamp":"2026-09-12T11:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}`
	reply  = `{"timestamp":"2026-09-12T11:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"done"}]}}`
	first  = `{"timestamp":"2026-09-12T11:05:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50,"reasoning_output_tokens":20,"total_tokens":1050},"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50,"reasoning_output_tokens":20,"total_tokens":1050}}}}`
	again  = `{"timestamp":"2026-09-12T11:05:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50,"reasoning_output_tokens":20,"total_tokens":1050},"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":50,"reasoning_output_tokens":20,"total_tokens":1050}},"rate_limits":{"primary":{"used_percent":3}}}}`
	second = `{"timestamp":"2026-09-12T11:10:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000,"cached_input_tokens":2000,"output_tokens":150,"reasoning_output_tokens":60,"total_tokens":3150}}}}`
)

func TestParseCountsTheTurnNotTheRunningSum(t *testing.T) {
	entries, stats := parse(t, map[string]string{
		"2026/09/12/rollout-a.jsonl": lines(meta, model, reply, first, again, second),
	})

	if len(entries) != 2 {
		t.Fatalf("got %d entries, want 2: the repeated token_count is not a turn", len(entries))
	}
	// Cached input is inside input and reasoning inside output, so the total
	// is input plus output and nothing more.
	if got := entries[0].Tokens; got != 1050 {
		t.Errorf("first turn = %d, want 1050", got)
	}
	// Only a running sum: the previous one is taken off it.
	if got := entries[1].Tokens; got != 3150-1050 {
		t.Errorf("second turn = %d, want %d", got, 3150-1050)
	}
	if !strings.HasPrefix(entries[0].MessageID, "gpt-5-codex/") {
		t.Errorf("MessageID = %q, want it to carry the model", entries[0].MessageID)
	}
	if stats.Files != 1 || stats.Lines != 6 || stats.Entries != 2 {
		t.Errorf("stats = %+v, want 1 file, 6 lines, 2 entries", stats)
	}
}

func TestParseCountsBadLinesAndRecords(t *testing.T) {
	negative := `{"timestamp":"2026-09-12T11:20:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":-1,"output_tokens":1}}}}`
	undated := `{"timestamp":"yesterday","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"output_tokens":1}}}}`
	truncated := `{"timestamp":"2026-09-12T11:30:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_tok`

	entries, stats := parse(t, map[string]string{
		"rollout.jsonl": meta + "\n" + first + "\n" + negative + "\n" + undated + "\n" + truncated,
	})

	if len(entries) != 1 {
		t.Errorf("got %d entries, want 1", len(entries))
	}
	if stats.BadRecords != 2 || stats.BadLines != 1 {
		t.Errorf("stats = %+v, want 2 bad records and 1 bad line", stats)
	}
}

func TestParseSkipsWhatAForkReplays(t *testing.T) {
	child := func(id string, source string) string {
		return `{"timestamp":"2026-09-12T11:15:00.000Z","type":"session_meta","payload":{"id":"` + id + `",` + source + `}}`
	}
	own := `{"timestamp":"2026-09-12T11:20:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":5000,"output_tokens":7},"total_token_usage":{"input_tokens":8000,"cached_input_tokens":2800,"output_tokens":157,"reasoning_output_tokens":80,"total_tokens":8157}}}}`

	t.Run("against the parent's log", func(t *testing.T) {
		entries, _ := parse(t, map[string]string{
			"a/parent.jsonl": lines(meta, model, first, second),
			"b/child.jsonl":  lines(child("s2", `"forked_from_id":"s1"`), model, first, second, own),
		})
		if len(entries) != 3 {
			t.Fatalf("got %d entries, want the parent's two and the child's own one", len(entries))
		}
		if got := entries[2].Tokens; got != 5007 {
			t.Errorf("child's own turn = %d, want 5007", got)
		}
	})

	t.Run("a sub-agent, without the parent's log", func(t *testing.T) {
		// Codex rewrites the replayed history to the moment of the fork and
		// writes it in one go.
		burst1 := strings.Replace(first, "11:05:00.000", "11:15:00.010", 1)
		burst2 := strings.Replace(second, "11:10:00.000", "11:15:00.030", 1)
		entries, _ := parse(t, map[string]string{
			"child.jsonl": lines(
				child("s3", `"source":{"subagent":{"thread_spawn":{"parent_thread_id":"gone"}}}`),
				burst1, burst2, own),
		})
		if len(entries) != 1 || entries[0].Tokens != 5007 {
			t.Errorf("got %+v, want only the child's own turn", entries)
		}
	})

	t.Run("a session that was not forked keeps its opening burst", func(t *testing.T) {
		burst1 := strings.Replace(first, "11:05:00.000", "11:00:00.010", 1)
		burst2 := strings.Replace(second, "11:10:00.000", "11:00:00.030", 1)
		entries, _ := parse(t, map[string]string{
			"rollout.jsonl": lines(meta, burst1, burst2),
		})
		if len(entries) != 2 {
			t.Errorf("got %d entries, want 2", len(entries))
		}
	})
}

func TestRootsFollowCodexHome(t *testing.T) {
	t.Setenv("CODEX_HOME", "/somewhere/codex")
	roots, err := New().Roots()
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"/somewhere/codex/sessions", "/somewhere/codex/archived_sessions"}
	if len(roots) != 2 || roots[0] != want[0] || roots[1] != want[1] {
		t.Errorf("Roots() = %v, want %v", roots, want)
	}
}
