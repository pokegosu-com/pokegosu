package state

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

func TestMessagesRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "coder.messages.json")
	// Nanoseconds matter: without a request id the time is part of the key.
	at := mustParse(t, "2026-09-12T11:10:00Z").Add(123456789 * time.Nanosecond)

	want := Messages{Records: []usage.Record{
		{Provider: "claude_code", MessageID: "msg_1", RequestID: "req_1", At: at, Tokens: 100,
			Sources: []string{"/logs/a.jsonl", "/logs/b.jsonl"}},
		{Provider: "claude_code", MessageID: "msg_2", IsSidechain: true, At: at, Tokens: 200,
			Sources: []string{"/logs/b.jsonl"}},
	}}
	if err := SaveMessages(path, want); err != nil {
		t.Fatal(err)
	}

	got, err := LoadMessages(path)
	if err != nil {
		t.Fatal(err)
	}
	for i := range got.Records {
		got.Records[i].At = got.Records[i].At.UTC()
		want.Records[i].At = want.Records[i].At.UTC()
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("LoadMessages = %+v\nwant %+v", got, want)
	}
}

func TestLoadMessagesMissingIsEmpty(t *testing.T) {
	got, err := LoadMessages(filepath.Join(t.TempDir(), "absent.json"))
	if err != nil || len(got.Records) != 0 {
		t.Errorf("LoadMessages = %+v, %v; want empty, nil", got, err)
	}
}

// A file that cannot be read is an error, not an empty record: sync then
// leaves it alone instead of overwriting the only count of deleted logs.
func TestLoadMessagesDamagedIsAnError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "coder.messages.json")
	for _, content := range []string{`{"version":1,"files":[],"messages":[`, `{"version":99}`,
		`{"version":1,"files":[],"messages":[{"provider":"claude_code","id":"m","at":"2026-09-12T11:10:00Z","tokens":1,"files":[3]}]}`} {
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := LoadMessages(path); err == nil {
			t.Errorf("LoadMessages(%s) succeeded, want an error", content)
		}
	}
}

func TestKeep(t *testing.T) {
	enrolled := mustParse(t, "2026-09-12T11:30:00Z")
	records := []usage.Record{
		{Provider: "claude_code", MessageID: "before", At: mustParse(t, "2026-09-12T10:59:00Z")},
		{Provider: "claude_code", MessageID: "same hour", At: mustParse(t, "2026-09-12T11:05:00Z")},
		{Provider: "codex", MessageID: "codex", At: mustParse(t, "2026-09-12T12:00:00Z")},
	}

	got := Keep(records, enrolled)
	if len(got.Records) != 1 || got.Records[0].MessageID != "same hour" {
		t.Errorf("Keep = %+v, want only the Claude Code message from the enrolment hour on", got.Records)
	}
}
