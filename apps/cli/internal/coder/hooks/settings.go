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

// settingsAgent is an agent that keeps its hooks as Claude Code does: a JSON
// file whose "hooks" object maps each event to groups of commands. Claude
// Code and Codex both do, so only where the file is and what each hook runs
// differ between them.
type settingsAgent struct {
	id, name string

	// settingsPath is the file the hooks are written to.
	settingsPath func() (string, error)

	// events is the agent's events a hook is installed on.
	events []string

	// hookFor is the hook each event runs.
	hookFor func(event, executable, log string) hook

	// afterInstall is what a person still has to do before the hooks run.
	afterInstall string
}

func (a settingsAgent) ID() string { return a.id }

func (a settingsAgent) Name() string { return a.name }

// SettingsPath implements Agent.
func (a settingsAgent) SettingsPath() (string, error) { return a.settingsPath() }

// Events implements Agent.
func (a settingsAgent) Events() []string { return a.events }

// AfterInstall implements Agent.
func (a settingsAgent) AfterInstall() string { return a.afterInstall }

// LogPath is where the hooks append how each sync went, beside pokegosu's
// settings.
func (a settingsAgent) LogPath() (string, error) {
	settings, err := config.Path()
	if err != nil {
		return "", err
	}
	return filepath.Join(filepath.Dir(settings), "hook."+a.id+".jsonl"), nil
}

// Present says whether the agent keeps its settings here: its directory
// exists once it has run.
func (a settingsAgent) Present() bool {
	path, err := a.SettingsPath()
	if err != nil {
		return false
	}
	info, err := os.Stat(filepath.Dir(path))
	return err == nil && info.IsDir()
}

// syncCommand is the sync every hook runs, appending how it went to log.
// Stop comes every turn, so it waits interval between syncs; the last event
// of a session is not held back, since it is the last chance the session has.
func syncCommand(event, executable, log string) string {
	command := shellQuote(executable) + " coder sync --jsonl --no-fail"
	if event == "Stop" {
		command += " --min-interval " + stopInterval
	}
	return command + " >> " + shellQuote(log)
}

// stopInterval is how long Stop waits between syncs. Usage is kept by the
// hour, so a sync every turn would only send the same hour over and over.
const stopInterval = "15m"

// ours says whether a hook command is one Install wrote, from this binary or
// from one installed somewhere else since: a sync appending to this agent's
// log.
func (a settingsAgent) ours(command string) bool {
	return strings.Contains(command, " coder sync ") &&
		strings.Contains(command, "hook."+a.id+".jsonl")
}

// Commands returns this program's hook command for each event that has one.
func (a settingsAgent) Commands() (map[string]string, error) {
	path, err := a.SettingsPath()
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
	for _, event := range a.events {
		groups, err := a.readGroups(hooks.get(event))
		if err != nil {
			return nil, err
		}
		for _, g := range groups {
			for _, h := range g.Hooks {
				if a.ours(h.Command) {
					found[event] = h.Command
				}
			}
		}
	}
	return found, nil
}

// Installed reports whether the settings hold any of this program's hooks.
func (a settingsAgent) Installed() (bool, error) {
	found, err := a.Commands()
	return len(found) > 0, err
}

// Install adds the hooks, replacing any this program wrote before, so that
// installing again after the binary moved points them at where it is now.
func (a settingsAgent) Install(executable string) (string, error) {
	log, err := a.LogPath()
	if err != nil {
		return "", err
	}
	// The shell opens the log before it runs sync, and cannot make a
	// directory for it; without one, the hook would fail before starting.
	if err := os.MkdirAll(filepath.Dir(log), 0o700); err != nil {
		return "", fmt.Errorf("creating %s: %w", filepath.Dir(log), err)
	}
	return a.edit(func(event string, groups []group) []group {
		groups = a.without(event, groups)
		return append(groups, group{Hooks: []hook{a.hookFor(event, executable, log)}})
	})
}

// Uninstall removes this program's hooks and nothing else.
func (a settingsAgent) Uninstall() (string, error) {
	return a.edit(a.without)
}

// without drops this program's hooks, and any group left empty by that.
func (a settingsAgent) without(_ string, groups []group) []group {
	var kept []group
	for _, g := range groups {
		var hooks []hook
		for _, h := range g.Hooks {
			if !a.ours(h.Command) {
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
func (a settingsAgent) edit(change func(event string, groups []group) []group) (string, error) {
	path, err := a.SettingsPath()
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

	for _, event := range a.events {
		groups, err := a.readGroups(hooks.get(event))
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

func (a settingsAgent) readGroups(raw json.RawMessage) ([]group, error) {
	if raw == nil {
		return nil, nil
	}
	var groups []group
	if err := json.Unmarshal(raw, &groups); err != nil {
		return nil, fmt.Errorf("the settings' hooks are not in the shape %s documents: %w", a.name, err)
	}
	return groups, nil
}

// writeSettings replaces the file whole, through a temporary file beside it,
// so that the agent never reads it half written. The file keeps its
// permissions; a new one is readable only by its owner, like the agents' own.
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

// shellQuote quotes a path for sh, which is what both agents run a hook's
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
