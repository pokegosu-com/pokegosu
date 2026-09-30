package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
)

// enrolAt writes settings for a machine enrolled with the API at apiURL.
func enrolAt(t *testing.T, apiURL string) {
	t.Helper()
	t.Setenv("POKEGOSU_CONFIG_HOME", t.TempDir())
	if _, err := config.Save(&config.Config{
		URL:        "https://coder.example.com",
		APIURL:     apiURL,
		APIKey:     "pgt_secret",
		DeviceID:   "550e8400-e29b-41d4-a716-446655440000",
		DeviceName: "laptop",
	}); err != nil {
		t.Fatal(err)
	}
}

func TestStatusSaysWhichMachineAndWhose(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"device_id":"550e8400-e29b-41d4-a716-446655440000","device_name":"laptop","display_name":"Ash"}`))
	}))
	defer server.Close()
	enrolAt(t, server.URL)

	var out strings.Builder
	if err := Status(context.Background(), &out); err != nil {
		t.Fatalf("Status: %v", err)
	}
	for _, want := range []string{"550e8400-e29b-41d4-a716-446655440000", "Ash"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output does not say %s:\n%s", want, out.String())
		}
	}
	if strings.Contains(out.String(), "pgt_secret") {
		t.Errorf("output prints the key:\n%s", out.String())
	}
}

// A machine retired in the web still has its settings; only the server knows
// the key is dead, and the person is told how to start over.
func TestStatusFailsWhenTheKeyIsRefused(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error":{"code":"unauthorized","message":"unknown or revoked API key"}}`))
	}))
	defer server.Close()
	enrolAt(t, server.URL)

	err := Status(context.Background(), &strings.Builder{})
	if err == nil || !strings.Contains(err.Error(), "auth login") {
		t.Errorf("error = %v, want it to say what to run", err)
	}
}

// Not being enrolled fails, so a script can tell from the exit status, and
// says what to run. There is nothing to ask a server with.
func TestStatusFailsWhenNotEnrolled(t *testing.T) {
	t.Setenv("POKEGOSU_CONFIG_HOME", t.TempDir())

	err := Status(context.Background(), &strings.Builder{})
	if err == nil || !strings.Contains(err.Error(), "auth login") {
		t.Errorf("error = %v, want it to say what to run", err)
	}

	// Settings that login would redo are not enrolled either.
	if _, err := config.Save(&config.Config{URL: "https://coder.example.com", DeviceID: "x"}); err != nil {
		t.Fatal(err)
	}
	if err := Status(context.Background(), &strings.Builder{}); err == nil {
		t.Error("Status succeeded with settings that have no key")
	}
}
