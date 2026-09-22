package state

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/usage"
)

func mustParse(t *testing.T, at string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, at)
	if err != nil {
		t.Fatalf("bad time %q in test: %v", at, err)
	}
	return parsed
}

func rollup(t *testing.T, hour string, tokens int64) usage.Rollup {
	t.Helper()
	at, err := time.Parse(time.RFC3339, hour)
	if err != nil {
		t.Fatalf("bad hour %q in test: %v", hour, err)
	}
	return usage.Rollup{Provider: "claude_code", HourBucket: at, Tokens: tokens}
}

func TestChanged(t *testing.T) {
	// Long after the buckets, so only a moved value counts as changed.
	now := mustParse(t, "2026-09-20T00:00:00Z")

	sent := &State{Sent: []usage.Rollup{
		rollup(t, "2026-09-12T14:00:00Z", 100),
		rollup(t, "2026-09-12T15:00:00Z", 200),
	}}

	current := []usage.Rollup{
		rollup(t, "2026-09-12T14:00:00Z", 100), // unchanged
		rollup(t, "2026-09-12T15:00:00Z", 999), // grew
		rollup(t, "2026-09-12T16:00:00Z", 1),   // new
	}

	changed := sent.Changed(current, now)
	if len(changed) != 2 {
		t.Fatalf("Changed() = %+v, want the grown and the new bucket", changed)
	}
	if changed[0].Tokens != 999 || changed[1].Tokens != 1 {
		t.Errorf("Changed() = %+v, want 999 then 1", changed)
	}
}

// A bucket going down is a change like any other: logs are re-read, and the
// client's word is the absolute value (§3).
func TestChangedIncludesBucketsThatShrank(t *testing.T) {
	sent := &State{Sent: []usage.Rollup{rollup(t, "2026-09-12T14:00:00Z", 900)}}

	changed := sent.Changed([]usage.Rollup{rollup(t, "2026-09-12T14:00:00Z", 100)}, mustParse(t, "2026-09-20T00:00:00Z"))
	if len(changed) != 1 || changed[0].Tokens != 100 {
		t.Errorf("Changed() = %+v, want the smaller value", changed)
	}
}

// A bucket the server holds but the scan no longer reports is left alone: the
// log went away, the usage did not (§9).
func TestChangedIgnoresBucketsThatVanished(t *testing.T) {
	sent := &State{Sent: []usage.Rollup{
		rollup(t, "2026-09-12T14:00:00Z", 100),
		rollup(t, "2026-09-12T15:00:00Z", 200),
	}}

	changed := sent.Changed([]usage.Rollup{rollup(t, "2026-09-12T14:00:00Z", 100)}, mustParse(t, "2026-09-20T00:00:00Z"))
	if len(changed) != 0 {
		t.Errorf("Changed() = %+v, want nothing", changed)
	}
}

func TestChangedSeparatesProviders(t *testing.T) {
	same := rollup(t, "2026-09-12T14:00:00Z", 100)
	other := same
	other.Provider = "codex"

	sent := &State{Sent: []usage.Rollup{same}}
	changed := sent.Changed([]usage.Rollup{same, other}, mustParse(t, "2026-09-20T00:00:00Z"))

	if len(changed) != 1 || changed[0].Provider != "codex" {
		t.Errorf("Changed() = %+v, want only the other provider", changed)
	}
}

func TestRecordReplacesAndKeeps(t *testing.T) {
	s := &State{Sent: []usage.Rollup{
		rollup(t, "2026-09-12T14:00:00Z", 100),
		rollup(t, "2026-09-12T15:00:00Z", 200),
	}}

	s.Record([]usage.Rollup{
		rollup(t, "2026-09-12T15:00:00Z", 999), // replaces
		rollup(t, "2026-09-12T16:00:00Z", 1),   // adds
	})

	if len(s.Sent) != 3 {
		t.Fatalf("Sent = %+v, want three buckets", s.Sent)
	}
	// Ordered by hour, which keeps the file readable and diffs small.
	want := []int64{100, 999, 1}
	for i, tokens := range want {
		if s.Sent[i].Tokens != tokens {
			t.Errorf("Sent[%d] = %d, want %d", i, s.Sent[i].Tokens, tokens)
		}
	}
}

func TestSaveAndLoadRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sent.json")
	s := &State{Server: "https://x.co", DeviceID: "d1", Sent: []usage.Rollup{
		rollup(t, "2026-09-12T14:00:00Z", 100),
	}}

	if err := Save(path, s); err != nil {
		t.Fatalf("Save: %v", err)
	}

	loaded := Load(path, "https://x.co", "d1")
	if len(loaded.Sent) != 1 || loaded.Sent[0].Tokens != 100 {
		t.Errorf("Load() = %+v, want the saved bucket", loaded)
	}
}

// The cache describes one server's idea of one machine. Pointed elsewhere, it
// describes somebody else's ledger, and sending only the difference against
// it would leave the new server missing rows.
func TestLoadDiscardsAnotherServerOrDevice(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sent.json")
	if err := Save(path, &State{Server: "https://x.co", DeviceID: "d1",
		Sent: []usage.Rollup{rollup(t, "2026-09-12T14:00:00Z", 100)}}); err != nil {
		t.Fatal(err)
	}

	for _, c := range []struct{ server, device string }{
		{"https://other.co", "d1"},
		{"https://x.co", "d2"},
	} {
		loaded := Load(path, c.server, c.device)
		if len(loaded.Sent) != 0 {
			t.Errorf("Load(%s, %s) kept %+v, want nothing", c.server, c.device, loaded.Sent)
		}
	}
}

// Losing the cache costs one large upload and nothing else, so a file that
// cannot be read must not stop a sync.
func TestLoadSurvivesAMissingOrBrokenFile(t *testing.T) {
	dir := t.TempDir()

	missing := Load(filepath.Join(dir, "absent.json"), "https://x.co", "d1")
	if len(missing.Sent) != 0 || missing.Server != "https://x.co" {
		t.Errorf("Load() of a missing file = %+v", missing)
	}

	broken := filepath.Join(dir, "broken.json")
	if err := os.WriteFile(broken, []byte("not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if loaded := Load(broken, "https://x.co", "d1"); len(loaded.Sent) != 0 {
		t.Errorf("Load() of a broken file = %+v", loaded)
	}
}

// What this cache holds is what one process asked for, not what the server
// ended up with. Two syncs overlapping can leave the two disagreeing, and a
// closed hour never differs from the cache again — so the recent past is
// restated every run and the disagreement heals (§9).
func TestChangedAlwaysResendsTheRecentPast(t *testing.T) {
	now := mustParse(t, "2026-09-12T18:00:00Z")
	unchanged := rollup(t, "2026-09-12T17:00:00Z", 100)

	sent := &State{Sent: []usage.Rollup{unchanged}}

	changed := sent.Changed([]usage.Rollup{unchanged}, now)
	if len(changed) != 1 {
		t.Fatalf("Changed() = %+v, want the recent bucket resent", changed)
	}
}

func TestChangedLeavesTheSettledPastAlone(t *testing.T) {
	now := mustParse(t, "2026-09-12T18:00:00Z")
	// An hour older than the window, holding the value the cache expects.
	settled := rollup(t, "2026-09-10T17:00:00Z", 100)

	sent := &State{Sent: []usage.Rollup{settled}}

	if changed := sent.Changed([]usage.Rollup{settled}, now); len(changed) != 0 {
		t.Errorf("Changed() = %+v, want nothing", changed)
	}
}

// Restating the whole ledger has to start from nothing known, or a run that
// fails half way records the batches that landed against a cache that
// already claimed them and the rest is never sent again.
func TestForget(t *testing.T) {
	s := &State{Sent: []usage.Rollup{rollup(t, "2026-09-12T14:00:00Z", 100)}}

	s.Forget()
	if len(s.Sent) != 0 {
		t.Fatalf("Sent = %+v, want nothing", s.Sent)
	}

	// What lands after that is the whole of what the cache knows, so an
	// interrupted run leaves the remainder outstanding.
	s.Record([]usage.Rollup{rollup(t, "2026-09-12T14:00:00Z", 100)})
	if len(s.Sent) != 1 {
		t.Errorf("Sent = %+v, want only what landed", s.Sent)
	}
}

// Two settings files in one directory would otherwise share one cache and
// evict each other, turning every sync into a full upload.
func TestPathIsNamedAfterTheSettings(t *testing.T) {
	first := Path("/home/someone/.config/pokecoder/config.json")
	second := Path("/home/someone/.config/pokecoder/work.json")

	if first == second {
		t.Errorf("both settings share the cache %q", first)
	}
	if filepath.Dir(first) != "/home/someone/.config/pokecoder" {
		t.Errorf("Path() = %q, want it beside the settings", first)
	}
}
