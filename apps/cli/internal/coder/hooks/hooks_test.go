package hooks

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// claudeHome points Claude Code's settings and pokegosu's at a temporary
// directory, and returns the settings file.
func claudeHome(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("CLAUDE_CONFIG_DIR", filepath.Join(dir, "claude"))
	t.Setenv("POKEGOSU_CONFIG_HOME", filepath.Join(dir, "pokegosu"))
	return filepath.Join(dir, "claude", "settings.json")
}

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

const binary = "/home/someone/.local/bin/pokegosu"

func TestInstallIntoNoSettings(t *testing.T) {
	path := claudeHome(t)

	if _, err := claudeCode.Install(binary); err != nil {
		t.Fatal(err)
	}
	// The log's directory is there for the shell to open the log in.
	log, _ := claudeCode.LogPath()
	if info, err := os.Stat(filepath.Dir(log)); err != nil || !info.IsDir() {
		t.Errorf("no directory for %s", log)
	}

	want := `{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/someone/.local/bin/pokegosu coder sync --jsonl --no-fail >> LOG",
            "timeout": 30
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
		t.Errorf("settings:\n%s\nwant:\n%s", got, want)
	}
}

// The file is the person's and Claude Code's. Only this program's hooks
// change; every other key stays where it was, in the order it was.
func TestInstallKeepsEverythingElse(t *testing.T) {
	path := claudeHome(t)
	write(t, path, `{
  "model": "opus",
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "notify-send done && beep"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard", "extra": 1}]}]
  },
  "permissions": {"allow": ["Bash(ls)"]}
}`)

	if _, err := claudeCode.Install(binary); err != nil {
		t.Fatal(err)
	}
	got := read(t, path)

	for _, want := range []string{`"notify-send done && beep"`, `"guard"`, `"extra": 1`, `"matcher": "Bash"`, `"Bash(ls)"`} {
		if !strings.Contains(got, want) {
			t.Errorf("lost %s:\n%s", want, got)
		}
	}
	order := []string{`"model"`, `"hooks"`, `"Stop"`, `"notify-send done && beep"`, binary, `"PreToolUse"`, `"SessionEnd"`, `"permissions"`}
	last := -1
	for _, key := range order {
		at := strings.Index(got, key)
		if at < last {
			t.Errorf("%s moved:\n%s", key, got)
		}
		last = at
	}
}

// Installing again, as after moving the binary, leaves one set of hooks
// pointing at the new place.
func TestInstallAgainReplaces(t *testing.T) {
	path := claudeHome(t)
	c := claudeCode

	if _, err := c.Install("/old/place/pokegosu"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Install(binary); err != nil {
		t.Fatal(err)
	}
	got := read(t, path)

	if strings.Contains(got, "/old/place") {
		t.Errorf("the old hooks are still there:\n%s", got)
	}
	if n := strings.Count(got, "coder sync"); n != 2 {
		t.Errorf("%d hooks, want one per event:\n%s", n, got)
	}
}

func TestUninstallTakesOnlyItsOwn(t *testing.T) {
	path := claudeHome(t)
	write(t, path, `{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "notify-send done"}]}]}}`)
	c := claudeCode

	if _, err := c.Install(binary); err != nil {
		t.Fatal(err)
	}
	if installed, _ := c.Installed(); !installed {
		t.Fatal("Installed() = false after Install")
	}
	if _, err := c.Uninstall(); err != nil {
		t.Fatal(err)
	}
	got := read(t, path)

	if strings.Contains(got, "pokegosu") || strings.Contains(got, "SessionEnd") {
		t.Errorf("uninstall left some of its own behind:\n%s", got)
	}
	if !strings.Contains(got, "notify-send done") {
		t.Errorf("uninstall took somebody else's hook:\n%s", got)
	}
	if installed, _ := c.Installed(); installed {
		t.Error("Installed() = true after Uninstall")
	}
}

// Taking the last hook out takes out the "hooks" it made, too.
func TestUninstallLeavesNoEmptyHooks(t *testing.T) {
	path := claudeHome(t)
	write(t, path, `{"model": "opus"}`)
	c := claudeCode

	if _, err := c.Install(binary); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Uninstall(); err != nil {
		t.Fatal(err)
	}
	if got := read(t, path); got != "{\n  \"model\": \"opus\"\n}\n" {
		t.Errorf("settings: %s", got)
	}
}

// A file this cannot read is not rewritten, since writing it back would drop
// whatever made it unreadable.
func TestBrokenSettingsAreLeftAlone(t *testing.T) {
	path := claudeHome(t)
	write(t, path, `{"model": "opus",`)

	if _, err := claudeCode.Install(binary); err == nil {
		t.Fatal("Install accepted settings it could not read")
	}
	if got := read(t, path); got != `{"model": "opus",` {
		t.Errorf("the file was changed: %s", got)
	}
}

// Settings kept in a dotfiles repository are usually a link to it.
func TestALinkStaysALink(t *testing.T) {
	path := claudeHome(t)
	real := filepath.Join(t.TempDir(), "dotfiles-settings.json")
	write(t, real, `{"model": "opus"}`)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, path); err != nil {
		t.Fatal(err)
	}

	if _, err := claudeCode.Install(binary); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Lstat(path); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Errorf("the link was replaced by a file")
	}
	if !strings.Contains(read(t, real), "coder sync") {
		t.Error("the hooks did not reach the file the link points to")
	}
}

func TestPathsWithSpacesAreQuoted(t *testing.T) {
	c := claudeCode
	got := c.hookFor("SessionEnd", "/Users/some one/bin/pokegosu", "/Users/some one/.config/pokegosu/hook.claude-code.jsonl").Command
	want := "'/Users/some one/bin/pokegosu' coder sync --jsonl --no-fail >> '/Users/some one/.config/pokegosu/hook.claude-code.jsonl'"
	if got != want {
		t.Errorf("command = %q, want %q", got, want)
	}
	if !c.ours(got) {
		t.Error("a quoted command is not recognised as ours")
	}
}

// A sync somebody put in by hand is theirs; uninstall leaves it.
func TestAHandWrittenSyncIsNotOurs(t *testing.T) {
	if claudeCode.ours("pokegosu coder sync --jsonl >> ~/my-sync.jsonl") {
		t.Error("a plain sync was taken for one Install wrote")
	}
}

// doctor checks the binary a hook runs, so it has to read it back out of
// the command, quotes and all.
func TestExecutableReadsBackWhatWasWritten(t *testing.T) {
	c := claudeCode
	for _, path := range []string{binary, "/Users/some one/bin/pokegosu", "/tmp/it's/pokegosu"} {
		for _, event := range claudeCode.events {
			if got := Executable(c.hookFor(event, path, "/tmp/log.jsonl").Command); got != path {
				t.Errorf("Executable(%s hook for %q) = %q", event, path, got)
			}
		}
	}
}
