package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestPathPrefersTheOverride(t *testing.T) {
	t.Setenv("POKECODER_CONFIG", "/tmp/somewhere/else.json")
	t.Setenv("XDG_CONFIG_HOME", "/tmp/ignored")

	got, err := Path()
	if err != nil {
		t.Fatal(err)
	}
	if want := "/tmp/somewhere/else.json"; got != want {
		t.Errorf("Path() = %q, want %q", got, want)
	}
}

func TestPathFollowsXDG(t *testing.T) {
	t.Setenv("POKECODER_CONFIG", "")
	t.Setenv("XDG_CONFIG_HOME", "/tmp/xdg")

	got, err := Path()
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join("/tmp/xdg", "pokecoder", "config.json"); got != want {
		t.Errorf("Path() = %q, want %q", got, want)
	}
}

// A missing file means the user has not logged in, which the caller reports
// better than a read error can.
func TestLoadMissingFileIsNotAnError(t *testing.T) {
	t.Setenv("POKECODER_CONFIG", filepath.Join(t.TempDir(), "absent.json"))

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg != nil {
		t.Errorf("Load() = %+v, want nil", cfg)
	}
}

func TestSaveAndLoadRoundTrip(t *testing.T) {
	t.Setenv("POKECODER_CONFIG", filepath.Join(t.TempDir(), "nested", "config.json"))
	want := &Config{
		APIURL:     "https://example.supabase.co",
		APIKey:     "pkt_secret",
		DeviceID:   "550e8400-e29b-41d4-a716-446655440000",
		DeviceName: "laptop",
	}

	path, err := Save(want)
	if err != nil {
		t.Fatalf("Save: %v", err)
	}

	got, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got == nil || *got != *want {
		t.Errorf("Load() = %+v, want %+v", got, want)
	}

	// The file holds an API key, so nobody else on the machine may read it.
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Errorf("file mode = %o, want 600", perm)
	}
	dir, err := os.Stat(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if perm := dir.Mode().Perm(); perm != 0o700 {
		t.Errorf("directory mode = %o, want 700", perm)
	}
}

// Save writes through a temporary file. It must not leave one behind, or the
// config directory fills with half-written secrets.
func TestSaveLeavesNoTemporaryFiles(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("POKECODER_CONFIG", filepath.Join(dir, "config.json"))

	for i := 0; i < 3; i++ {
		if _, err := Save(&Config{APIKey: "pkt_secret"}); err != nil {
			t.Fatalf("Save: %v", err)
		}
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() != "config.json" {
			t.Errorf("left behind %q", entry.Name())
		}
	}
}

func TestSaveUsesTheDocumentedKeys(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	t.Setenv("POKECODER_CONFIG", path)

	if _, err := Save(&Config{APIKey: "pkt_secret"}); err != nil {
		t.Fatalf("Save: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("saved file is not JSON: %v", err)
	}
	// api_key is the name the design fixed; the rest travel with it.
	for _, key := range []string{"api_url", "api_key", "device_id", "device_name"} {
		if _, ok := raw[key]; !ok {
			t.Errorf("saved file has no %q key: %s", key, data)
		}
	}
}

func TestNormalizeURL(t *testing.T) {
	cases := []struct {
		in      string
		want    string
		wantErr bool
	}{
		{in: "https://x.supabase.co", want: "https://x.supabase.co"},
		{in: "https://x.supabase.co/", want: "https://x.supabase.co"},
		{in: "  http://127.0.0.1:54321//  ", want: "http://127.0.0.1:54321"},
		{in: "x.supabase.co", wantErr: true},
		{in: "", wantErr: true},
		{in: "   ", wantErr: true},
	}

	for _, c := range cases {
		got, err := NormalizeURL(c.in)
		if c.wantErr {
			if err == nil {
				t.Errorf("NormalizeURL(%q) = %q, want an error", c.in, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("NormalizeURL(%q): %v", c.in, err)
			continue
		}
		if got != c.want {
			t.Errorf("NormalizeURL(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestNewDeviceID(t *testing.T) {
	shape := regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

	seen := make(map[string]bool)
	for i := 0; i < 100; i++ {
		id, err := NewDeviceID()
		if err != nil {
			t.Fatalf("NewDeviceID: %v", err)
		}
		if !shape.MatchString(id) {
			t.Fatalf("NewDeviceID() = %q, want a version 4 UUID", id)
		}
		if seen[id] {
			t.Fatalf("NewDeviceID() repeated %q", id)
		}
		seen[id] = true
	}
}

// login is the command that would rewrite a broken settings file, so its
// error has to say that rather than only quoting the parser.
func TestLoadSaysWhatToDoAboutABrokenFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	t.Setenv("POKECODER_CONFIG", path)
	if err := os.WriteFile(path, []byte("not json"), 0o600); err != nil {
		t.Fatal(err)
	}

	_, err := Load()
	if err == nil {
		t.Fatal("Load accepted a file that is not settings")
	}
	if !strings.Contains(err.Error(), path) {
		t.Errorf("error %q does not name the file", err)
	}
	if !strings.Contains(err.Error(), "login") {
		t.Errorf("error %q does not say how to recover", err)
	}
}
