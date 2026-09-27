package hooks

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// claudeCode keeps sync in Claude Code's user settings, as hooks on two of
// its events:
//
//   - SessionEnd, when a session closes, so that what a session spent is sent
//     before the machine, or the container it ran in, goes away.
//   - Stop, each time Claude finishes answering, so that a session left open
//     for a day still reports as it goes. It comes every turn, so it asks
//     sync to wait stopInterval between runs.
//
// Both sync with --no-fail: a hook that fails shows up in the middle of
// somebody's session, and a sync that could not reach the server tries again
// at the next event anyway. Each appends how it went, with --jsonl, to a log
// of its own, which `pokegosu coder hook logs claude-code` shows.
var claudeCode = settingsAgent{
	id:           "claude-code",
	name:         "Claude Code",
	settingsPath: claudeCodeSettings,
	events:       []string{"SessionEnd", "Stop"},
	hookFor:      claudeCodeHook,
}

// claudeCodeHook is the hook each event runs.
//
// Stop runs in the background ("async"), so a sync never holds up the next
// prompt. SessionEnd waits for it: Claude Code is closing, and a sync left
// running behind it could be cut off with the container it ran in. Claude
// Code gives all of SessionEnd's hooks 1.5 seconds together unless one asks
// for longer, and a sync reads the logs and makes a request, which can take
// longer than that; the timeout asks for it, and is for a network that has
// gone quiet rather than for the sync.
func claudeCodeHook(event, executable, log string) hook {
	command := syncCommand(event, executable, log)
	if event == "Stop" {
		h := hook{Type: "command", Command: command, Timeout: 60}
		h.Rest.set("async", mustJSON(true))
		return h
	}
	return hook{Type: "command", Command: command, Timeout: 30}
}

// claudeCodeSettings is Claude Code's user settings, which apply in every
// project. CLAUDE_CONFIG_DIR moves them, as it moves the logs.
func claudeCodeSettings() (string, error) {
	if dir := os.Getenv("CLAUDE_CONFIG_DIR"); dir != "" {
		// The parser accepts a list there, since logs can be read from
		// several places; settings are written to one, the first.
		first := strings.TrimSpace(filepath.SplitList(dir)[0])
		return filepath.Join(first, "settings.json"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("locating the home directory: %w", err)
	}
	return filepath.Join(home, ".claude", "settings.json"), nil
}
