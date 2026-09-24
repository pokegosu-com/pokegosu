package hooks

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
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
type claudeCode struct{}

func (claudeCode) ID() string { return "claude-code" }

func (claudeCode) Name() string { return "Claude Code" }

var claudeCodeEvents = []string{"SessionEnd", "Stop"}

// stopInterval is how long Stop waits between syncs. Usage is kept by the
// hour, so a sync every turn would only send the same hour over and over.
// SessionEnd is not held back: it is the last chance a session has.
const stopInterval = "15m"

// LogPath is where the hooks append how each sync went, beside pokegosu's
// settings.
func (c claudeCode) LogPath() (string, error) {
	settings, err := config.Path()
	if err != nil {
		return "", err
	}
	return filepath.Join(filepath.Dir(settings), "hook."+c.ID()+".jsonl"), nil
}

// hookFor is the hook each event runs.
//
// Stop runs in the background ("async"), so a sync never holds up the next
// prompt. SessionEnd waits for it: Claude Code is closing, and a sync left
// running behind it could be cut off with the container it ran in. Claude
// Code gives all of SessionEnd's hooks 1.5 seconds together unless one asks
// for longer, and a sync reads the logs and makes a request, which can take
// longer than that; the timeout asks for it, and is for a network that has
// gone quiet rather than for the sync.
func (c claudeCode) hookFor(event, executable, log string) hook {
	command := shellQuote(executable) + " coder sync --jsonl --no-fail"
	if event == "Stop" {
		command += " --min-interval " + stopInterval
	}
	command += " >> " + shellQuote(log)

	if event == "Stop" {
		h := hook{Type: "command", Command: command, Timeout: 60}
		h.Rest.set("async", mustJSON(true))
		return h
	}
	return hook{Type: "command", Command: command, Timeout: 30}
}

// SettingsPath is Claude Code's user settings, which apply in every project.
// CLAUDE_CONFIG_DIR moves them, as it moves the logs.
func (claudeCode) SettingsPath() (string, error) {
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

// Present says whether Claude Code keeps its settings here: its directory
// exists once it has run.
func (c claudeCode) Present() bool {
	path, err := c.SettingsPath()
	if err != nil {
		return false
	}
	info, err := os.Stat(filepath.Dir(path))
	return err == nil && info.IsDir()
}

// ours says whether a hook command is one Install wrote, from this binary or
// from one installed somewhere else since: a sync appending to this agent's
// log.
func (c claudeCode) ours(command string) bool {
	return strings.Contains(command, " coder sync ") &&
		strings.Contains(command, "hook."+c.ID()+".jsonl")
}

// Events implements Agent.
func (claudeCode) Events() []string { return claudeCodeEvents }

// Commands returns this program's hook command for each event that has one.
func (c claudeCode) Commands() (map[string]string, error) {
	path, err := c.SettingsPath()
	if err != nil {
		return nil, err
	}
	settings, err := readSettings(path)
	if err != nil {
		return nil, err
	}
	hooks, err := readHooks(settings)
	if err != nil {
		return nil, err
	}
	found := map[string]string{}
	for _, event := range claudeCodeEvents {
		groups, err := readGroups(hooks.get(event))
		if err != nil {
			return nil, err
		}
		for _, g := range groups {
			for _, h := range g.Hooks {
				if c.ours(h.Command) {
					found[event] = h.Command
				}
			}
		}
	}
	return found, nil
}

// Installed reports whether the settings hold any of this program's hooks.
func (c claudeCode) Installed() (bool, error) {
	found, err := c.Commands()
	return len(found) > 0, err
}

// Install adds the hooks, replacing any this program wrote before, so that
// installing again after the binary moved points them at where it is now.
func (c claudeCode) Install(executable string) (string, error) {
	log, err := c.LogPath()
	if err != nil {
		return "", err
	}
	// The shell opens the log before it runs sync, and cannot make a
	// directory for it; without one, the hook would fail before starting.
	if err := os.MkdirAll(filepath.Dir(log), 0o700); err != nil {
		return "", fmt.Errorf("creating %s: %w", filepath.Dir(log), err)
	}
	return c.edit(func(event string, groups []group) []group {
		groups = c.without(event, groups)
		return append(groups, group{Hooks: []hook{c.hookFor(event, executable, log)}})
	})
}

// Uninstall removes this program's hooks and nothing else.
func (c claudeCode) Uninstall() (string, error) {
	return c.edit(c.without)
}

// without drops this program's hooks, and any group left empty by that.
func (c claudeCode) without(_ string, groups []group) []group {
	var kept []group
	for _, g := range groups {
		var hooks []hook
		for _, h := range g.Hooks {
			if !c.ours(h.Command) {
				hooks = append(hooks, h)
			}
		}
		if len(hooks) == 0 && len(g.Hooks) > 0 {
			continue
		}
		g.Hooks = hooks
		kept = append(kept, g)
	}
	return kept
}

// edit applies change to each event's hooks and writes the settings back,
// leaving every other key where and as it was.
func (c claudeCode) edit(change func(event string, groups []group) []group) (string, error) {
	path, err := c.SettingsPath()
	if err != nil {
		return "", err
	}
	settings, err := readSettings(path)
	if err != nil {
		return "", err
	}
	hooks, err := readHooks(settings)
	if err != nil {
		return "", err
	}

	for _, event := range claudeCodeEvents {
		groups, err := readGroups(hooks.get(event))
		if err != nil {
			return "", err
		}
		groups = change(event, groups)
		if len(groups) == 0 {
			hooks.remove(event)
			continue
		}
		encoded, err := marshal(groups)
		if err != nil {
			return "", err
		}
		hooks.set(event, encoded)
	}

	if len(hooks) == 0 {
		settings.remove("hooks")
	} else {
		encoded, err := marshal(hooks)
		if err != nil {
			return "", err
		}
		settings.set("hooks", encoded)
	}
	return path, writeSettings(path, settings)
}

// group is one entry of an event's list: an optional matcher, and the hooks
// it runs. Fields this program does not know are kept as they were.
type group struct {
	Matcher string `json:"matcher,omitempty"`
	Hooks   []hook `json:"hooks"`
	Rest    object `json:"-"`
}

type hook struct {
	Type    string `json:"type"`
	Command string `json:"command,omitempty"`
	Timeout int    `json:"timeout,omitempty"`
	Rest    object `json:"-"`
}

func (g *group) UnmarshalJSON(data []byte) error {
	var all object
	if err := json.Unmarshal(data, &all); err != nil {
		return err
	}
	for _, m := range all {
		var err error
		switch m.Key {
		case "matcher":
			err = json.Unmarshal(m.Value, &g.Matcher)
		case "hooks":
			err = json.Unmarshal(m.Value, &g.Hooks)
		default:
			g.Rest = append(g.Rest, m)
		}
		if err != nil {
			return fmt.Errorf("%q: %w", m.Key, err)
		}
	}
	return nil
}

func (g group) MarshalJSON() ([]byte, error) {
	var out object
	if g.Matcher != "" {
		out.set("matcher", mustJSON(g.Matcher))
	}
	hooks, err := marshal(g.Hooks)
	if err != nil {
		return nil, err
	}
	out.set("hooks", hooks)
	out = append(out, g.Rest...)
	return marshal(out)
}

func (h *hook) UnmarshalJSON(data []byte) error {
	var all object
	if err := json.Unmarshal(data, &all); err != nil {
		return err
	}
	for _, m := range all {
		var err error
		switch m.Key {
		case "type":
			err = json.Unmarshal(m.Value, &h.Type)
		case "command":
			err = json.Unmarshal(m.Value, &h.Command)
		case "timeout":
			err = json.Unmarshal(m.Value, &h.Timeout)
		default:
			h.Rest = append(h.Rest, m)
		}
		if err != nil {
			return fmt.Errorf("%q: %w", m.Key, err)
		}
	}
	return nil
}

func (h hook) MarshalJSON() ([]byte, error) {
	var out object
	out.set("type", mustJSON(h.Type))
	if h.Command != "" {
		out.set("command", mustJSON(h.Command))
	}
	if h.Timeout != 0 {
		out.set("timeout", mustJSON(h.Timeout))
	}
	out = append(out, h.Rest...)
	return marshal(out)
}

func mustJSON(v any) json.RawMessage {
	data, err := marshal(v)
	if err != nil {
		panic(err)
	}
	return data
}

// readSettings reads a settings file; a missing one is empty settings.
func readSettings(path string) (object, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return object{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return object{}, nil
	}
	var settings object
	if err := json.Unmarshal(data, &settings); err != nil {
		// Written back, a file this could not read would lose whatever made
		// it unreadable, so it is left for the person to look at.
		return nil, fmt.Errorf("%s is not readable as JSON (%v); fix it and try again", path, err)
	}
	return settings, nil
}

func readHooks(settings object) (object, error) {
	raw := settings.get("hooks")
	if raw == nil {
		return object{}, nil
	}
	var hooks object
	if err := json.Unmarshal(raw, &hooks); err != nil {
		return nil, fmt.Errorf(`"hooks" in the settings is not an object: %w`, err)
	}
	return hooks, nil
}

func readGroups(raw json.RawMessage) ([]group, error) {
	if raw == nil {
		return nil, nil
	}
	var groups []group
	if err := json.Unmarshal(raw, &groups); err != nil {
		return nil, fmt.Errorf("the settings' hooks are not in the shape Claude Code documents: %w", err)
	}
	return groups, nil
}

// writeSettings replaces the file whole, through a temporary file beside it,
// so that Claude Code never reads it half written. The file keeps its
// permissions; a new one is readable only by its owner, like Claude Code's.
func writeSettings(path string, settings object) error {
	compact, err := marshal(settings)
	if err != nil {
		return err
	}
	var out bytes.Buffer
	if err := json.Indent(&out, compact, "", "  "); err != nil {
		return err
	}
	out.WriteByte('\n')

	// Settings kept in a dotfiles repository are often a link to it; the
	// file is replaced where it really is, so the link stays a link.
	if real, err := filepath.EvalSymlinks(path); err == nil {
		path = real
	}
	mode := os.FileMode(0o600)
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("creating %s: %w", dir, err)
	}
	temp, err := os.CreateTemp(dir, ".settings-*.json")
	if err != nil {
		return fmt.Errorf("creating a temporary file in %s: %w", dir, err)
	}
	defer os.Remove(temp.Name())
	if err := temp.Chmod(mode); err != nil {
		temp.Close()
		return err
	}
	if _, err := temp.Write(out.Bytes()); err != nil {
		temp.Close()
		return fmt.Errorf("writing %s: %w", temp.Name(), err)
	}
	if err := temp.Close(); err != nil {
		return err
	}
	if err := os.Rename(temp.Name(), path); err != nil {
		return fmt.Errorf("saving %s: %w", path, err)
	}
	return nil
}

// shellQuote quotes a path for sh, which is what Claude Code runs a hook's
// command with.
func shellQuote(s string) string {
	if s != "" && strings.IndexFunc(s, func(r rune) bool {
		return !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' ||
			strings.ContainsRune("/._-+", r))
	}) < 0 {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// Executable returns the program a hook command runs: its first word, with
// the quoting shellQuote adds taken off.
func Executable(command string) string {
	if !strings.HasPrefix(command, "'") {
		first, _, _ := strings.Cut(command, " ")
		return first
	}
	var b strings.Builder
	rest := command[1:]
	for {
		i := strings.IndexByte(rest, '\'')
		if i < 0 {
			b.WriteString(rest)
			return b.String()
		}
		b.WriteString(rest[:i])
		rest = rest[i+1:]
		// '\'' is a quote inside a quoted word.
		if strings.HasPrefix(rest, `\''`) {
			b.WriteByte('\'')
			rest = rest[3:]
			continue
		}
		return b.String()
	}
}
