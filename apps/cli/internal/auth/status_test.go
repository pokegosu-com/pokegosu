package auth

import (
	"strings"
	"testing"
	"time"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
)

func TestStatusSaysWhatTheMachineIsEnrolledWith(t *testing.T) {
	t.Setenv("POKEGOSU_CONFIG_HOME", t.TempDir())
	if _, err := config.Save(&config.Config{
		URL:        "https://coder.example.com",
		APIURL:     "https://example.supabase.co",
		APIKey:     "pgt_secret",
		DeviceID:   "550e8400-e29b-41d4-a716-446655440000",
		DeviceName: "laptop",
		EnrolledAt: time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Fatal(err)
	}

	var out strings.Builder
	if err := Status(&out); err != nil {
		t.Fatalf("Status: %v", err)
	}
	for _, want := range []string{`"laptop"`, "https://coder.example.com", "550e8400-e29b-41d4-a716-446655440000"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output does not say %s:\n%s", want, out.String())
		}
	}
	if strings.Contains(out.String(), "pgt_secret") {
		t.Errorf("output prints the key:\n%s", out.String())
	}
}

// Not being enrolled fails, so a script can tell from the exit status, and
// says what to run.
func TestStatusFailsWhenNotEnrolled(t *testing.T) {
	t.Setenv("POKEGOSU_CONFIG_HOME", t.TempDir())

	err := Status(&strings.Builder{})
	if err == nil {
		t.Fatal("Status succeeded with no settings")
	}
	if !strings.Contains(err.Error(), "auth login") {
		t.Errorf("error = %q, want it to say what to run", err)
	}

	// Settings that login would redo are not enrolled either.
	if _, err := config.Save(&config.Config{URL: "https://coder.example.com", DeviceID: "x"}); err != nil {
		t.Fatal(err)
	}
	if err := Status(&strings.Builder{}); err == nil {
		t.Error("Status succeeded with settings that have no key")
	}
}
