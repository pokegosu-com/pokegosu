package auth

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
	authapi "github.com/pokegosu-com/pokegosu/libs/go/auth"
)

func TestSettingsDefaultsToTheService(t *testing.T) {
	got, err := settings(&config.Config{}, "", "laptop")
	if err != nil {
		t.Fatalf("settings: %v", err)
	}
	if got.URL != defaultURL {
		t.Errorf("URL = %q, want the default %q", got.URL, defaultURL)
	}
}

// The service a machine was enrolled with wins over the default, and --url
// wins over both.
func TestSettingsPrefersTheFlagThenTheStoredService(t *testing.T) {
	stored := &config.Config{URL: "https://coder.self-hosted.example"}

	got, err := settings(stored, "", "laptop")
	if err != nil {
		t.Fatalf("settings: %v", err)
	}
	if got.URL != stored.URL {
		t.Errorf("URL = %q, want the stored service kept", got.URL)
	}

	got, err = settings(stored, "http://localhost:3002/", "laptop")
	if err != nil {
		t.Fatalf("settings: %v", err)
	}
	if got.URL != "http://localhost:3002" {
		t.Errorf("URL = %q, want the flag, without its trailing slash", got.URL)
	}
}

// A machine's id is made once and kept, so that settings rebuilt from scratch
// still describe the same machine rather than a new one.
func TestSettingsKeepsTheMachinesOwnId(t *testing.T) {
	stored := &config.Config{
		URL:        "https://coder.example.com",
		DeviceID:   "550e8400-e29b-41d4-a716-446655440000",
		DeviceName: "laptop",
	}

	got, err := settings(stored, "", "workstation")
	if err != nil {
		t.Fatalf("settings: %v", err)
	}
	if got.DeviceID != stored.DeviceID {
		t.Errorf("DeviceID = %q, want the stored id kept", got.DeviceID)
	}
	if got.URL != stored.URL {
		t.Errorf("URL = %q, want the stored service kept", got.URL)
	}
	if got.DeviceName != "workstation" {
		t.Errorf("DeviceName = %q, want the flag to win", got.DeviceName)
	}
	if stored.DeviceName != "laptop" {
		t.Error("settings modified the stored settings in place")
	}
}

func TestSettingsMakesAnIdWhenThereIsNone(t *testing.T) {
	got, err := settings(&config.Config{}, "https://coder.example.com", "laptop")
	if err != nil {
		t.Fatalf("settings: %v", err)
	}
	if got.DeviceID == "" {
		t.Error("DeviceID is empty; a machine has to name itself")
	}
}

func TestSettingsDefaultsTheNameToTheHostname(t *testing.T) {
	host, err := os.Hostname()
	if err != nil || host == "" {
		t.Skip("no hostname to default to")
	}

	got, err := settings(&config.Config{}, "https://coder.example.com", "")
	if err != nil {
		t.Fatalf("settings: %v", err)
	}
	if got.DeviceName != host {
		t.Errorf("DeviceName = %q, want the hostname %q", got.DeviceName, host)
	}
}

func TestSettingsRejectsAURLWithoutAScheme(t *testing.T) {
	_, err := settings(&config.Config{}, "example.supabase.co", "laptop")
	if err == nil {
		t.Fatal("a URL with no scheme was accepted")
	}
	if !strings.Contains(err.Error(), "scheme") {
		t.Errorf("error = %q, want it to say what is wrong with it", err)
	}
}

// login leaves an enrolled machine alone rather than minting a second key for
// it, so what counts as enrolled has to be all three: without any one of them
// a sync cannot run, and the machine is better off enrolling.
func TestEnrolledNeedsEverything(t *testing.T) {
	full := config.Config{
		URL:      "https://coder.example.com",
		APIURL:   "https://example.supabase.co",
		APIKey:   "pgt_secret",
		DeviceID: "550e8400-e29b-41d4-a716-446655440000",
	}
	if !enrolled(&full) {
		t.Error("enrolled() = false for complete settings")
	}

	for name, blank := range map[string]func(*config.Config){
		"no service": func(c *config.Config) { c.URL = "" },
		"no API":     func(c *config.Config) { c.APIURL = "" },
		"no key":     func(c *config.Config) { c.APIKey = "" },
		"no id":      func(c *config.Config) { c.DeviceID = "" },
	} {
		partial := full
		blank(&partial)
		if enrolled(&partial) {
			t.Errorf("%s: enrolled() = true", name)
		}
	}

	if enrolled(nil) {
		t.Error("enrolled(nil) = true")
	}
}

// A machine that is told to wait forever is a machine nobody will notice has
// stopped. The deadline the server gave is the end of it.
func TestWaitGivesUpWhenTheRequestRunsOut(t *testing.T) {
	asked := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked++
		w.WriteHeader(http.StatusAccepted)
		w.Write([]byte(`{"status":"waiting"}`))
	}))
	defer server.Close()

	pollInterval = time.Millisecond
	defer func() { pollInterval = 2 * time.Second }()

	var progress bytes.Buffer
	_, err := wait(
		context.Background(),
		authapi.New(server.URL),
		authapi.Enrollment{ClaimToken: "pge_token", ExpiresAt: time.Now().Add(5 * time.Millisecond)},
		&progress,
	)
	if err == nil {
		t.Fatal("wait returned without a key and without an error")
	}
	if !strings.Contains(err.Error(), "login again") {
		t.Errorf("error = %q, want it to say what to do", err)
	}
	if asked == 0 {
		t.Error("wait never asked")
	}
}

func TestWaitStopsAsWellAsAsking(t *testing.T) {
	approved := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !approved {
			approved = true
			w.WriteHeader(http.StatusAccepted)
			w.Write([]byte(`{"status":"waiting"}`))
			return
		}
		w.Write([]byte(`{"api_key":"pgt_minted","device_name":"laptop"}`))
	}))
	defer server.Close()

	pollInterval = time.Millisecond
	defer func() { pollInterval = 2 * time.Second }()

	var progress bytes.Buffer
	claim, err := wait(
		context.Background(),
		authapi.New(server.URL),
		authapi.Enrollment{ClaimToken: "pge_token", ExpiresAt: time.Now().Add(time.Minute)},
		&progress,
	)
	if err != nil {
		t.Fatalf("wait: %v", err)
	}
	if claim.APIKey != "pgt_minted" {
		t.Errorf("key = %q, want the one the server handed over", claim.APIKey)
	}
	// Somebody is watching this screen while they walk to their browser.
	if progress.Len() == 0 {
		t.Error("wait said nothing while it waited")
	}
}
