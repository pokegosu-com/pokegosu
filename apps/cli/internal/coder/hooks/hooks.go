// Package hooks has coding agents run sync for coder, as hooks in their own
// settings, instead of a scheduler.
//
// The agent is what writes the logs sync reads, and it runs wherever there is
// usage to report: on a laptop, on a server, in a container with no cron or
// systemd. So the agent is the one to say when to sync — as a session ends,
// and every so often while one stays open. When no agent runs there is
// nothing new to send, and nothing runs.
//
// An agent here is one whose logs coder can read; a hook on an agent coder
// cannot read would sync nothing. Claude Code and Codex are the ones there
// are.
package hooks

import "fmt"

// Agent is a coding agent whose settings can hold hooks.
type Agent interface {
	// ID is the word for it on the command line, such as claude-code.
	ID() string

	// Name is what a person calls it.
	Name() string

	// SettingsPath is the file the hooks are written to.
	SettingsPath() (string, error)

	// LogPath is the file the hooks append each sync's result to.
	LogPath() (string, error)

	// Present says whether the agent looks set up on this machine, which is
	// when installing for every agent includes it.
	Present() bool

	// Events is the agent's events a hook is installed on.
	Events() []string

	// Commands returns this program's hook command for each event that has
	// one.
	Commands() (map[string]string, error)

	// Installed says whether that file holds any of this program's hooks.
	Installed() (bool, error)

	// Install writes hooks that run executable, replacing any this program
	// wrote before, and returns the file it wrote.
	Install(executable string) (string, error)

	// Uninstall removes this program's hooks, and only those, and returns
	// the file it wrote.
	Uninstall() (string, error)

	// AfterInstall is what a person still has to do before the hooks run,
	// or nothing.
	AfterInstall() string
}

// Agents is every agent hooks can be installed in.
var Agents = []Agent{claudeCode, codex}

// Find returns the agent with this ID.
func Find(id string) (Agent, error) {
	for _, a := range Agents {
		if a.ID() == id {
			return a, nil
		}
	}
	return nil, fmt.Errorf("unknown agent %q: want one of %s", id, ids())
}

func ids() string {
	var s string
	for i, a := range Agents {
		if i > 0 {
			s += ", "
		}
		s += a.ID()
	}
	return s
}
