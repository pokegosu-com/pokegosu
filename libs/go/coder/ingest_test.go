package coder

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// oneRollup is the smallest thing a machine can send, for the tests that are
// about the call rather than about the payload.
func oneRollup() []usage.Rollup {
	return []usage.Rollup{{Provider: "claude_code", Tokens: 1}}
}

func TestIngestSendsOnlyTheMachinesKey(t *testing.T) {
	var gotAuth, gotProject, gotKey, gotBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("authorization")
		gotProject = r.Header.Get("apikey")
		gotKey = r.Header.Get("x-api-key")
		body := make([]byte, r.ContentLength)
		r.Body.Read(body)
		gotBody = string(body)
		w.Write([]byte(`{"accepted":1}`))
	}))
	defer server.Close()

	if _, _, err := New(server.URL, "pgt_secret").Ingest(context.Background(), oneRollup()); err != nil {
		t.Fatalf("Ingest: %v", err)
	}

	// One credential, and it is ours. The project's own key used to ride
	// along because the platform's gateway demanded it; the endpoints that
	// machines call no longer ask.
	if gotKey != "pgt_secret" {
		t.Errorf("x-api-key = %q, want this machine's key", gotKey)
	}
	if gotProject != "" || gotAuth != "" {
		t.Errorf("apikey = %q, authorization = %q, want neither sent", gotProject, gotAuth)
	}
	// Which machine these belong to is the key's business, not the body's.
	if strings.Contains(gotBody, "device_id") {
		t.Errorf("body = %q, want no device id in it", gotBody)
	}
}

func TestOurUnauthorizedIsAKeyRefusal(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error":{"code":"unauthorized","message":"unknown or revoked API key"}}`))
	}))
	defer server.Close()

	fresh := New(server.URL, "pgt_secret")
	_, _, err := fresh.Ingest(context.Background(), oneRollup())
	if !KeyRefused(err) {
		t.Errorf("KeyRefused() = false for %v", err)
	}
}
