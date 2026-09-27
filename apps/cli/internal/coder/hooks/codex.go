package hooks

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// codex keeps sync in Codex's user hooks, ~/.codex/hooks.json, which Codex
// reads in the shape Claude Code's settings use, on the same two events: Stop
// after every turn, SessionEnd as a session closes. Everything said about
// claudeCode holds, except for two things Codex does its own way.
//
// Codex runs a hook from a user's file only once the user trusts it. The
// next time Codex starts it lists the new hooks and asks; until then they do
// not run. That is the user's decision, so install writes the hooks and says
// so, and leaves the trusting to Codex.
//
// Codex gives SessionEnd no more than three seconds, and ends a hook that
// runs longer, sync and all. See codexHook.
var codex = settingsAgent{
	id:           "codex",
	name:         "Codex",
	settingsPath: codexSettings,
	events:       []string{"SessionEnd", "Stop"},
	hookFor:      codexHook,
	afterInstall: "the next time Codex starts, it asks you to trust the new hooks; they run once you do",
}

// codexHook is the hook each event runs.
//
// Stop runs in the background ("async"), as it does in Claude Code.
//
// SessionEnd starts the sync in the background of its own shell and returns
// at once. A sync reads the logs and makes a request, which can take longer
// than the three seconds Codex allows, and a hook that overruns is killed
// with everything it started. One that returns in time is left alone,
// children included, so the sync carries on after Codex has gone. Its output
// goes to the log and its warnings nowhere: nothing may hold the pipes Codex
// waits on, and the JSON line in the log already says how the sync went.
func codexHook(event, executable, log string) hook {
	command := syncCommand(event, executable, log)
	if event == "Stop" {
		h := hook{Type: "command", Command: command, Timeout: 60}
		h.Rest.set("async", mustJSON(true))
		return h
	}
	return hook{Type: "command", Command: command + " 2>/dev/null </dev/null &", Timeout: 3}
}

// codexSettings is Codex's user hooks file. CODEX_HOME moves it, as it moves
// the logs.
func codexSettings() (string, error) {
	if dir := strings.TrimSpace(os.Getenv("CODEX_HOME")); dir != "" {
		return filepath.Join(dir, "hooks.json"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("locating the home directory: %w", err)
	}
	return filepath.Join(home, ".codex", "hooks.json"), nil
}
