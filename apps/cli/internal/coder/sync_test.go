package coder

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder/state"
	coderapi "github.com/pokegosu-com/pokegosu/libs/go/coder"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

func rollups(t *testing.T, count int) []usage.Rollup {
	t.Helper()

	start, err := time.Parse(time.RFC3339, "2025-05-12T00:00:00Z")
	if err != nil {
		t.Fatal(err)
	}

	made := make([]usage.Rollup, count)
	for i := range made {
		made[i] = usage.Rollup{
			Provider:   "claude_code",
			HourBucket: start.Add(time.Duration(i) * time.Hour),
			Tokens:     int64(i + 1),
		}
	}
	return made
}

// acceptingUntil answers like ingest for the first n requests and fails after.
func acceptingUntil(t *testing.T, n int) (*coderapi.Client, func() int) {
	t.Helper()

	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if requests > n {
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte(`{"error":{"code":"internal_error","message":"gone away"}}`))
			return
		}

		var body struct {
			Rollups []json.RawMessage `json:"rollups"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Errorf("ingest got a body it could not read: %v", err)
		}
		json.NewEncoder(w).Encode(map[string]int{"accepted": len(body.Rollups)})
	}))
	t.Cleanup(server.Close)

	return coderapi.New(server.URL, "pgt_key"),
		func() int { return requests }
}

// A first run can carry months, and the endpoint takes ten thousand rollups
// at a time.
func TestSendBatches(t *testing.T) {
	client, requests := acceptingUntil(t, 10)

	sent, err := send(client, rollups(t, maxPerRequest+1))
	if err != nil {
		t.Fatalf("send: %v", err)
	}

	if len(sent) != maxPerRequest+1 {
		t.Errorf("sent %d rollups, want them all", len(sent))
	}
	if requests() != 2 {
		t.Errorf("made %d requests, want 2", requests())
	}
}

// The rows are absolute, so a batch that landed before a later one failed is
// still correct — and saying so is what keeps the rest outstanding.
func TestSendReportsWhatLandedBeforeTheFailure(t *testing.T) {
	client, _ := acceptingUntil(t, 1)
	all := rollups(t, maxPerRequest+5)

	sent, err := send(client, all)
	if err == nil {
		t.Fatal("send succeeded although the server refused the second batch")
	}
	if len(sent) != maxPerRequest {
		t.Fatalf("reported %d rollups as sent, want the first batch", len(sent))
	}

	// What is recorded has to be what landed, so the next run sends the rest
	// rather than believing the whole ledger arrived.
	cache := &state.State{}
	cache.Forget()
	cache.Record(sent)

	// Well past the last bucket, so only what never landed counts as
	// outstanding rather than as recent (see state.RecentWindow).
	outstanding := cache.Changed(all, mustParseTime(t, "2026-01-01T00:00:00Z"))
	if len(outstanding) != 5 {
		t.Errorf("%d rollups are still outstanding, want the 5 that never landed", len(outstanding))
	}
}

func TestSendStopsAtTheFirstFailure(t *testing.T) {
	client, requests := acceptingUntil(t, 0)

	if _, err := send(client, rollups(t, maxPerRequest*3)); err == nil {
		t.Fatal("send succeeded although every request failed")
	}
	if requests() != 1 {
		t.Errorf("made %d requests, want it to stop after the first failure", requests())
	}
}

func mustParseTime(t *testing.T, at string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, at)
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

// A refused key and a gateway rejection send someone to different settings,
// so sync has to tell them apart rather than blame the key for both.
func TestExplainSyncSeparatesTheTwoRefusals(t *testing.T) {
	cases := []struct {
		name   string
		status int
		body   string
		says   string
		avoids string
	}{
		{
			name:   "our function refuses the key",
			status: 401,
			body:   `{"error":{"code":"unauthorized","message":"unknown or revoked API key"}}`,
			says:   "refused this machine's key",
			avoids: "before it reached",
		},
		{
			name:   "the gateway turns the request away",
			status: 401,
			body:   `{"message":"Invalid JWT"}`,
			says:   "before it reached coder",
			avoids: "refused this machine's key",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(c.status)
				w.Write([]byte(c.body))
			}))
			defer server.Close()

			client := coderapi.New(server.URL, "pgt_key")
			_, err := send(client, rollups(t, 1))
			if err == nil {
				t.Fatal("send succeeded although the server refused")
			}

			explained := explainSync(err).Error()
			if !strings.Contains(explained, c.says) {
				t.Errorf("said %q, want it to mention %q", explained, c.says)
			}
			if strings.Contains(explained, c.avoids) {
				t.Errorf("said %q, which points at the wrong setting", explained)
			}
		})
	}
}

// A sync says how it went, which is what --jsonl prints.
func TestSyncSaysHowItWent(t *testing.T) {
	t.Setenv("POKEGOSU_CONFIG_HOME", t.TempDir())

	result, err := Sync(SyncOptions{Quiet: true})
	if err == nil {
		t.Fatal("a sync with no settings succeeded")
	}
	if result.At.IsZero() || result.Outcome != Failed || result.Error != err.Error() {
		t.Errorf("result = %+v, want the failure %q", result, err)
	}
}

// --min-interval counts from the last sync that started, and skips quietly.
func TestSyncMinInterval(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("POKEGOSU_CONFIG_HOME", dir)
	runPath := state.RunPath(filepath.Join(dir, "config.json"))

	start := time.Date(2026, 9, 24, 12, 0, 0, 0, time.UTC)
	at := start
	now = func() time.Time { return at }
	t.Cleanup(func() { now = time.Now })

	opts := SyncOptions{Quiet: true, MinInterval: 15 * time.Minute}
	outcome := func() string {
		result, _ := Sync(opts)
		return result.Outcome
	}

	// No settings, so every sync that goes ahead fails.
	if got := outcome(); got != Failed {
		t.Fatalf("the first sync: %s", got)
	}

	at = start.Add(10 * time.Minute)
	if got := outcome(); got != Skipped {
		t.Errorf("a sync within the interval: %s", got)
	}
	if got := state.LoadRun(runPath).At; !got.Equal(start) {
		t.Errorf("a skipped sync moved the record to %v", got)
	}

	at = start.Add(15 * time.Minute)
	if got := outcome(); got != Failed {
		t.Errorf("a sync after the interval: %s", got)
	}

	// Without the flag nothing is skipped.
	at = start.Add(16 * time.Minute)
	opts.MinInterval = 0
	if got := outcome(); got != Failed {
		t.Errorf("a sync without --min-interval: %s", got)
	}
}
