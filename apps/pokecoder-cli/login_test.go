package main

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/pokegosu-com/pokegosu/apps/pokecoder-cli/internal/config"
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
		APIKey:   "pkt_secret",
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

func TestReadCodePrefersAsking(t *testing.T) {
	var prompt bytes.Buffer

	got, err := readCode("", strings.NewReader("xptq-4f2k\n"), &prompt)
	if err != nil {
		t.Fatalf("readCode: %v", err)
	}
	if got != "xptq-4f2k" {
		t.Errorf("code = %q, want what was typed", got)
	}
	if prompt.Len() == 0 {
		t.Error("nothing was printed; somebody is waiting at a blank screen")
	}

	// A script has nobody to ask, so the flag wins and nothing is printed.
	prompt.Reset()
	got, err = readCode("  XPTQ-4F2K  ", strings.NewReader(""), &prompt)
	if err != nil {
		t.Fatalf("readCode: %v", err)
	}
	if got != "XPTQ-4F2K" {
		t.Errorf("code = %q, want it trimmed", got)
	}
	if prompt.Len() != 0 {
		t.Errorf("prompted anyway: %q", prompt.String())
	}
}

func TestReadCodeSaysWhereToFindOne(t *testing.T) {
	var prompt bytes.Buffer

	_, err := readCode("", strings.NewReader("\n"), &prompt)
	if err == nil {
		t.Fatal("an empty code was accepted")
	}
	if !strings.Contains(err.Error(), "add a machine") {
		t.Errorf("error = %q, want it to say where a code comes from", err)
	}
}
