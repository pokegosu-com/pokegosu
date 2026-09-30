package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRetireSpeaksWithTheMachinesKey(t *testing.T) {
	var gotKey, gotPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("x-api-key")
		gotPath = r.URL.Path
		w.Write([]byte(`{"device_name":"laptop"}`))
	}))
	defer server.Close()

	name, err := New(server.URL).Retire(context.Background(), "pgt_secret")
	if err != nil {
		t.Fatalf("Retire: %v", err)
	}
	if name != "laptop" {
		t.Errorf("name = %q, want the one the account knew", name)
	}
	if gotKey != "pgt_secret" {
		t.Errorf("x-api-key = %q, want the machine's key", gotKey)
	}
	if gotPath != "/functions/v1/retire-device" {
		t.Errorf("path = %q", gotPath)
	}
}

// A key already retired in the web reads as refused, which logout takes as
// done; a gateway's 401 must not, or logout would throw away a working key.
func TestRetireTellsARefusedKeyFromAGateway(t *testing.T) {
	for name, tc := range map[string]struct {
		body    string
		refused bool
	}{
		"ours":    {`{"error":{"code":"unauthorized","message":"unknown or revoked API key"}}`, true},
		"gateway": {`{"code":401,"message":"Invalid JWT"}`, false},
	} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte(tc.body))
		}))

		_, err := New(server.URL).Retire(context.Background(), "pgt_secret")
		server.Close()
		if err == nil {
			t.Fatalf("%s: Retire succeeded on a 401", name)
		}
		if KeyRefused(err) != tc.refused {
			t.Errorf("%s: KeyRefused = %v, want %v", name, !tc.refused, tc.refused)
		}
	}
}
