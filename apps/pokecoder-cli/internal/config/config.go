// Package config stores what the client needs to reach the server.
//
// The file holds an API key, so it is written for the owner only and never
// printed back out. Everything in it comes from the user at login: the server
// address is not compiled in, so the same binary works against our service
// and against someone's own deployment.
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Config is the on-disk settings file.
type Config struct {
	// APIURL is the Supabase project the client talks to, without a
	// trailing slash: functions live under <APIURL>/functions/v1.
	APIURL string `json:"api_url"`

	// APIKey is this machine's credential: "pkt_" and 32 random bytes in
	// hex. It is not typed in — login trades an enrollment code for it —
	// and it is the only thing here worth stealing.
	APIKey string `json:"api_key"`

	// DeviceID identifies this machine. The client generates it once and
	// keeps it, so a machine's usage stays attached to one device across
	// re-installs of the config.
	DeviceID string `json:"device_id"`

	// DeviceName is what a person sees in the web UI.
	DeviceName string `json:"device_name"`
}

// Path returns the settings file location.
//
// POKECODER_CONFIG overrides it outright, which is what tests and containers
// use. Otherwise it follows XDG, so the file sits with everything else the
// user's tools keep.
func Path() (string, error) {
	if override := os.Getenv("POKECODER_CONFIG"); override != "" {
		return override, nil
	}

	dir := os.Getenv("XDG_CONFIG_HOME")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("locating the home directory: %w", err)
		}
		dir = filepath.Join(home, ".config")
	}
	return filepath.Join(dir, "pokecoder", "config.json"), nil
}

// Load reads the settings file. A missing file is not an error: it means the
// user has not logged in yet, and the caller says so better than this can.
func Load() (*Config, error) {
	path, err := Path()
	if err != nil {
		return nil, err
	}

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		// Saying only what the parser saw leaves the user stuck: login is
		// the command that would rewrite this file, and it is the one
		// refusing to run.
		return nil, fmt.Errorf("%s is not readable as settings (%w); "+
			"delete it and run login again", path, err)
	}
	return &cfg, nil
}

// Save writes the settings file readable only by its owner.
//
// The write goes to a temporary file first and is then renamed over the
// target, so an interrupted save leaves the previous settings intact rather
// than a half-written file that no longer parses.
func Save(cfg *Config) (string, error) {
	path, err := Path()
	if err != nil {
		return "", err
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("creating %s: %w", dir, err)
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return "", fmt.Errorf("encoding the settings: %w", err)
	}
	data = append(data, '\n')

	temp, err := os.CreateTemp(dir, ".config-*.json")
	if err != nil {
		return "", fmt.Errorf("creating a temporary file in %s: %w", dir, err)
	}
	tempName := temp.Name()
	defer os.Remove(tempName)

	if err := temp.Chmod(0o600); err != nil {
		temp.Close()
		return "", fmt.Errorf("setting permissions on %s: %w", tempName, err)
	}
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return "", fmt.Errorf("writing %s: %w", tempName, err)
	}
	if err := temp.Close(); err != nil {
		return "", fmt.Errorf("writing %s: %w", tempName, err)
	}
	if err := os.Rename(tempName, path); err != nil {
		return "", fmt.Errorf("saving %s: %w", path, err)
	}
	return path, nil
}

// NormalizeURL trims a trailing slash and insists on a scheme, so that a
// pasted address does not turn into a confusing request failure later.
func NormalizeURL(raw string) (string, error) {
	url := strings.TrimRight(strings.TrimSpace(raw), "/")
	if url == "" {
		return "", fmt.Errorf("the server URL is empty")
	}
	if !strings.HasPrefix(url, "http://") && !strings.HasPrefix(url, "https://") {
		return "", fmt.Errorf("the server URL needs a scheme: %s", raw)
	}
	return url, nil
}
