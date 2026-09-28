package usage

import (
	"testing"
	"time"
)

func at(t *testing.T, s string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, s)
	if err != nil {
		t.Fatalf("bad timestamp %q in test: %v", s, err)
	}
	return parsed
}

func TestAddCountsAMessageOnce(t *testing.T) {
	a := NewAggregator()
	// The same message written three times, as Claude Code does.
	for _, ts := range []string{
		"2026-09-12T11:05:56.885Z",
		"2026-09-12T11:05:58.180Z",
		"2026-09-12T11:05:58.819Z",
	} {
		a.Add(Entry{Provider: "claude_code", MessageID: "msg_1", RequestID: "req_1", At: at(t, ts), Tokens: 44729})
	}

	if got := a.Messages(); got != 1 {
		t.Fatalf("Messages() = %d, want 1", got)
	}
	rollups := a.Rollups(time.Time{})
	if len(rollups) != 1 || rollups[0].Tokens != 44729 {
		t.Fatalf("Rollups() = %+v, want one bucket of 44729", rollups)
	}
}

// A message whose copies straddle an hour boundary has to land in the same
// bucket no matter which copy is read first, or two machines scanning the
// same log will disagree.
func TestAddPutsDuplicatesInTheEarliestHour(t *testing.T) {
	early := Entry{Provider: "claude_code", MessageID: "msg_1", RequestID: "req_1", At: at(t, "2026-09-12T11:59:58Z"), Tokens: 100}
	late := Entry{Provider: "claude_code", MessageID: "msg_1", RequestID: "req_1", At: at(t, "2026-09-12T12:00:03Z"), Tokens: 100}

	for _, order := range [][]Entry{{early, late}, {late, early}} {
		a := NewAggregator()
		for _, e := range order {
			a.Add(e)
		}

		rollups := a.Rollups(time.Time{})
		if len(rollups) != 1 {
			t.Fatalf("got %d buckets, want 1: %+v", len(rollups), rollups)
		}
		if want := at(t, "2026-09-12T11:00:00Z"); !rollups[0].HourBucket.Equal(want) {
			t.Errorf("bucket = %s, want %s", rollups[0].HourBucket.Format(time.RFC3339), want.Format(time.RFC3339))
		}
	}
}

func TestAddKeepsProvidersApart(t *testing.T) {
	a := NewAggregator()
	// Two providers could hand out the same message id.
	a.Add(Entry{Provider: "claude_code", MessageID: "msg_1", RequestID: "req_1", At: at(t, "2026-09-12T11:00:00Z"), Tokens: 10})
	a.Add(Entry{Provider: "codex", MessageID: "msg_1", RequestID: "req_1", At: at(t, "2026-09-12T11:00:00Z"), Tokens: 20})

	rollups := a.Rollups(time.Time{})
	if len(rollups) != 2 {
		t.Fatalf("got %d buckets, want 2: %+v", len(rollups), rollups)
	}
	// Same hour, so provider orders them.
	if rollups[0].Provider != "claude_code" || rollups[1].Provider != "codex" {
		t.Errorf("order = %s, %s; want claude_code, codex", rollups[0].Provider, rollups[1].Provider)
	}
}

func TestRollupsBucketByHourInUTC(t *testing.T) {
	a := NewAggregator()
	// A non-UTC timestamp still has to land in the right UTC hour.
	a.Add(Entry{Provider: "claude_code", MessageID: "a", RequestID: "req_a", At: at(t, "2026-09-12T20:30:00+09:00"), Tokens: 1})
	a.Add(Entry{Provider: "claude_code", MessageID: "b", RequestID: "req_b", At: at(t, "2026-09-12T11:59:59Z"), Tokens: 2})
	a.Add(Entry{Provider: "claude_code", MessageID: "c", RequestID: "req_c", At: at(t, "2026-09-12T12:00:00Z"), Tokens: 4})

	rollups := a.Rollups(time.Time{})
	want := []Rollup{
		{Provider: "claude_code", HourBucket: at(t, "2026-09-12T11:00:00Z"), Tokens: 3},
		{Provider: "claude_code", HourBucket: at(t, "2026-09-12T12:00:00Z"), Tokens: 4},
	}
	if len(rollups) != len(want) {
		t.Fatalf("got %+v, want %+v", rollups, want)
	}
	for i := range want {
		if !rollups[i].HourBucket.Equal(want[i].HourBucket) || rollups[i].Tokens != want[i].Tokens {
			t.Errorf("bucket %d = %+v, want %+v", i, rollups[i], want[i])
		}
	}
}

// Rollups are absolute values for a whole hour, so a --since inside an hour
// has to include that hour entire rather than a slice of it.
func TestRollupsSinceRoundsDownToTheHour(t *testing.T) {
	a := NewAggregator()
	a.Add(Entry{Provider: "claude_code", MessageID: "a", RequestID: "req_a", At: at(t, "2026-09-12T11:05:00Z"), Tokens: 1})
	a.Add(Entry{Provider: "claude_code", MessageID: "b", RequestID: "req_b", At: at(t, "2026-09-12T11:45:00Z"), Tokens: 2})
	a.Add(Entry{Provider: "claude_code", MessageID: "c", RequestID: "req_c", At: at(t, "2026-09-12T10:00:00Z"), Tokens: 4})

	rollups := a.Rollups(at(t, "2026-09-12T11:30:00Z"))
	if len(rollups) != 1 {
		t.Fatalf("got %d buckets, want 1: %+v", len(rollups), rollups)
	}
	if rollups[0].Tokens != 3 {
		t.Errorf("tokens = %d, want 3 (the whole 11:00 hour)", rollups[0].Tokens)
	}
}

func TestRollupsEmpty(t *testing.T) {
	if got := NewAggregator().Rollups(time.Time{}); len(got) != 0 {
		t.Errorf("Rollups() = %+v, want none", got)
	}
}

func entry(t *testing.T, msg, req, ts string, tokens int64, sidechain bool) Entry {
	t.Helper()
	return Entry{
		Provider: "claude_code", MessageID: msg, RequestID: req,
		IsSidechain: sidechain, At: at(t, ts), Tokens: tokens,
	}
}

// Without a request id the timestamp separates records, since nothing else
// says whether two lines describe the same call.
func TestAddWithoutRequestIDFallsBackToTimestamp(t *testing.T) {
	a := NewAggregator()
	a.Add(entry(t, "msg_1", "", "2026-09-12T11:10:00Z", 100, false))
	a.Add(entry(t, "msg_1", "", "2026-09-12T11:10:00Z", 100, false))
	if got := a.Messages(); got != 1 {
		t.Errorf("Messages() = %d, want 1: same timestamp is the same record", got)
	}

	a.Add(entry(t, "msg_1", "", "2026-09-12T11:10:05Z", 100, false))
	if got := a.Messages(); got != 2 {
		t.Errorf("Messages() = %d, want 2: a different timestamp is a different record", got)
	}
}

// A sub-agent transcript replays its parent's message under a new request id,
// so request id alone cannot separate them.
func TestAddMergesSidechainReplay(t *testing.T) {
	for _, order := range []string{"parent first", "sidechain first"} {
		t.Run(order, func(t *testing.T) {
			parent := entry(t, "msg_1", "req_parent", "2026-09-12T11:10:00Z", 100, false)
			replay := entry(t, "msg_1", "req_replay", "2026-09-12T11:10:30Z", 900, true)

			a := NewAggregator()
			if order == "parent first" {
				a.Add(parent)
				a.Add(replay)
			} else {
				a.Add(replay)
				a.Add(parent)
			}

			if got := a.Messages(); got != 1 {
				t.Fatalf("Messages() = %d, want 1", got)
			}
			if got := a.Rollups(time.Time{})[0].Tokens; got != 100 {
				t.Errorf("tokens = %d, want 100: the real message wins over its sidechain copy, "+
					"even though the copy reports more", got)
			}
		})
	}
}

// A line can be written before the response finished, so the larger total is
// the complete one.
func TestAddKeepsTheLargerTotal(t *testing.T) {
	for _, order := range [][]int64{{111, 1111}, {1111, 111}} {
		a := NewAggregator()
		for i, tokens := range order {
			a.Add(entry(t, "msg_1", "req_1",
				[]string{"2026-09-12T11:10:00Z", "2026-09-12T11:10:02Z"}[i], tokens, false))
		}
		if got := a.Rollups(time.Time{})[0].Tokens; got != 1111 {
			t.Errorf("order %v: tokens = %d, want 1111", order, got)
		}
	}
}
