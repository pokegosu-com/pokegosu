package hooks

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// codexHome points Codex's hooks and pokegosu's settings at a temporary
// directory, and returns the hooks file.
func codexHome(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("CODEX_HOME", filepath.Join(dir, "codex"))
	t.Setenv("POKEGOSU_CONFIG_HOME", filepath.Join(dir, "pokegosu"))
	return filepath.Join(dir, "codex", "hooks.json")
}

func TestCodexInstallIntoNoHooks(t *testing.T) {
	path := codexHome(t)

	if _, err := codex.Install(binary); err != nil {
		t.Fatal(err)
	}
	log, _ := codex.LogPath()

	want := `{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/someone/.local/bin/pokegosu coder sync --jsonl --no-fail >> LOG 2>/dev/null </dev/null &",
            "timeout": 3
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/someone/.local/bin/pokegosu coder sync --jsonl --no-fail --min-interval 15m >> LOG",
            "timeout": 60,
            "async": true
          }
        ]
      }
    ]
  }
}
`
	want = strings.ReplaceAll(want, "LOG", log)
	if got := read(t, path); got != want {
		t.Errorf("hooks:\n%s\nwant:\n%s", got, want)
	}
}

// The hooks Codex's file already holds are the person's; install and
// uninstall touch only this program's, and leave the file's description.
func TestCodexKeepsOtherHooks(t *testing.T) {
	path := codexHome(t)
	original := `{
  "description": "mine",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "say done"
          }
        ]
      }
    ]
  }
}
`
	write(t, path, original)

	if _, err := codex.Install(binary); err != nil {
		t.Fatal(err)
	}
	if installed, err := codex.Installed(); err != nil || !installed {
		t.Fatalf("Installed() = %v, %v after install", installed, err)
	}
	if got := read(t, path); !strings.Contains(got, `"say done"`) || !strings.Contains(got, `"description": "mine"`) {
		t.Errorf("lost the person's hooks:\n%s", got)
	}

	if _, err := codex.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if got := read(t, path); got != original {
		t.Errorf("after uninstall:\n%s\nwant:\n%s", got, original)
	}
}

// Codex kills a SessionEnd hook after three seconds, with everything it
// started. The hook has to return at once and leave the sync running, and
// the sync has to hold none of the pipes Codex waits on.
func TestCodexSessionEndReturnsBeforeTheSyncEnds(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("no sh")
	}
	dir := t.TempDir()
	fake := filepath.Join(dir, "pokegosu")
	write(t, fake, "#!/bin/sh\nsleep 1\necho '{\"outcome\":\"sent\"}'\necho warning >&2\n")
	if err := os.Chmod(fake, 0o755); err != nil {
		t.Fatal(err)
	}
	log := filepath.Join(dir, "hook.codex.jsonl")

	cmd := exec.Command("sh", "-c", codexHook("SessionEnd", fake, log).Command)
	start := time.Now()
	// CombinedOutput waits for the pipes to close, as Codex does.
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("hook failed: %v: %s", err, out)
	}
	if took := time.Since(start); took > 500*time.Millisecond {
		t.Errorf("hook took %s, want it back before the sync ends", took)
	}

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if data, _ := os.ReadFile(log); strings.Contains(string(data), `"sent"`) {
			if strings.Contains(string(data), "warning") {
				t.Errorf("stderr reached the log:\n%s", data)
			}
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Error("the sync never wrote to the log")
}
