package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestWhoamiAsksWithTheKey(t *testing.T) {
	var gotKey string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("x-api-key")
		w.Write([]byte(`{"device_id":"d1","device_name":"laptop","display_name":"Ash"}`))
	}))
	defer server.Close()

	client := New(server.URL)
	got, err := client.Whoami(context.Background(), "pgt_key")
	if err != nil {
		t.Fatalf("Whoami: %v", err)
	}
	if want := (Identity{DeviceID: "d1", DeviceName: "laptop", DisplayName: "Ash"}); got != want {
		t.Errorf("Whoami = %+v, want %+v", got, want)
	}
	if gotKey != "pgt_key" {
		t.Errorf("x-api-key = %q, want the machine's key", gotKey)
	}

	// The key is for that call alone; the calls made before there is one
	// must still go without.
	if client.transport.APIKey != "" {
		t.Error("Whoami left its key on the client")
	}
}

// An account that has not picked a handle has no name yet.
func TestWhoamiWithNoName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"device_id":"d1","device_name":"laptop","display_name":null}`))
	}))
	defer server.Close()

	got, err := New(server.URL).Whoami(context.Background(), "pgt_key")
	if err != nil {
		t.Fatalf("Whoami: %v", err)
	}
	if got.DisplayName != "" {
		t.Errorf("DisplayName = %q, want none", got.DisplayName)
	}
}

func TestWhoamiRefusedKey(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error":{"code":"unauthorized","message":"unknown or revoked API key"}}`))
	}))
	defer server.Close()

	_, err := New(server.URL).Whoami(context.Background(), "pgt_old")
	if !KeyRefused(err) {
		t.Errorf("KeyRefused() = false for %v", err)
	}
	if GatewayRefused(err) {
		t.Error("our own refusal read as the gateway's")
	}
}

func TestWhoamiForeignSuccessIsNotSuccess(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{}`))
	}))
	defer server.Close()

	if _, err := New(server.URL).Whoami(context.Background(), "pgt_key"); err == nil {
		t.Error("an empty answer was taken for a machine")
	}
}
