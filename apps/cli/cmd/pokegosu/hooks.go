package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder"
	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder/hooks"
	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
)

func newHookCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "hook",
		Short: "Have your coding agents run sync for you",
		Long: `Hooks in a coding agent's settings that run sync for you: when a session
ends, and every fifteen minutes or so while one stays open. They work wherever
the agent runs, containers included, with no cron or systemd.

Agents: ` + agentList() + `.`,
	}
	cmd.AddCommand(newHookInstallCmd(), newHookUninstallCmd(), newHookLogsCmd(), newHookDoctorCmd())
	return cmd
}

func agentList() string {
	var ids []string
	for _, a := range hooks.Agents {
		ids = append(ids, a.ID()+" ("+a.Name()+")")
	}
	return strings.Join(ids, ", ")
}

// needAgent asks for at least one agent, and says which there are.
func needAgent(cmd *cobra.Command, args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("name the agent: %s", agentList())
	}
	return nil
}

func find(ids []string) ([]hooks.Agent, error) {
	var named []hooks.Agent
	for _, id := range ids {
		a, err := hooks.Find(id)
		if err != nil {
			return nil, err
		}
		named = append(named, a)
	}
	return named, nil
}

func newHookInstallCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "install <agent>...",
		Short: "Add the hooks to an agent's settings",
		Long: `Adds the hooks to an agent's settings, leaving everything else in them as it
was. Installing again replaces them, which is what to do after moving the
pokegosu binary: the hooks run it by its full path.`,
		Example: "  pokegosu coder hook install claude-code",
		Args:    needAgent,
		RunE: func(cmd *cobra.Command, args []string) error {
			return installHooks(args)
		},
	}
}

func installHooks(ids []string) error {
	agents, err := find(ids)
	if err != nil {
		return err
	}
	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("locating this binary: %w", err)
	}
	for _, a := range agents {
		path, err := a.Install(executable)
		if err != nil {
			return fmt.Errorf("%s: %w", a.Name(), err)
		}
		fmt.Printf("%s will run sync: hooks written to %s\n", a.Name(), path)
	}
	return nil
}

func newHookUninstallCmd() *cobra.Command {
	return &cobra.Command{
		Use:     "uninstall <agent>...",
		Short:   "Remove the hooks from an agent's settings, and nothing else",
		Example: "  pokegosu coder hook uninstall claude-code",
		Args:    needAgent,
		RunE: func(cmd *cobra.Command, args []string) error {
			agents, err := find(args)
			if err != nil {
				return err
			}
			for _, a := range agents {
				installed, err := a.Installed()
				if err != nil {
					return fmt.Errorf("%s: %w", a.Name(), err)
				}
				if !installed {
					fmt.Printf("%s: no hooks to remove\n", a.Name())
					continue
				}
				path, err := a.Uninstall()
				if err != nil {
					return fmt.Errorf("%s: %w", a.Name(), err)
				}
				fmt.Printf("%s: hooks removed from %s\n", a.Name(), path)
			}
			return nil
		},
	}
}

func newHookLogsCmd() *cobra.Command {
	var lines int

	cmd := &cobra.Command{
		Use:   "logs <agent>",
		Short: "Show the syncs an agent's hooks ran, and how each went",
		Long: `Shows the syncs an agent's hooks ran, newest last: when, and whether it sent
something, found nothing new, failed and why, or was skipped for coming too
soon after the last one.`,
		Example: "  pokegosu coder hook logs claude-code",
		Args:    cobra.MatchAll(needAgent, cobra.MaximumNArgs(1)),
		RunE: func(cmd *cobra.Command, args []string) error {
			a, err := hooks.Find(args[0])
			if err != nil {
				return err
			}

			shown, err := hookLog(a)
			if err != nil {
				return err
			}
			if len(shown) == 0 {
				fmt.Println("no syncs yet")
				return nil
			}
			if lines > 0 && len(shown) > lines {
				shown = shown[len(shown)-lines:]
			}
			for _, e := range shown {
				fmt.Printf("%s  %s\n", e.At.Local().Format(time.DateTime), describe(e))
			}
			return nil
		},
	}
	cmd.Flags().IntVarP(&lines, "lines", "n", 20, "show the last `N` syncs; 0 shows all")
	return cmd
}

// hookLog reads the results an agent's hooks appended, oldest first. Lines
// it cannot read, such as one cut short, are passed over.
func hookLog(a hooks.Agent) ([]coder.Result, error) {
	path, err := a.LogPath()
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var results []coder.Result
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		var r coder.Result
		if json.Unmarshal(scanner.Bytes(), &r) == nil && !r.At.IsZero() {
			results = append(results, r)
		}
	}
	return results, scanner.Err()
}

// describe says how a sync went, in a few words.
func describe(e coder.Result) string {
	switch e.Outcome {
	case coder.Sent:
		return fmt.Sprintf("sent %s", count(e.Buckets, "bucket", "buckets"))
	case coder.Nothing:
		return "nothing new to send"
	case coder.Skipped:
		return "skipped: too soon after the last sync"
	case coder.Failed:
		return "failed: " + e.Error
	default:
		return e.Outcome
	}
}

func count(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}

func newHookDoctorCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "doctor",
		Short: "Check that the hooks are installed, and say how to fix them if not",
		Long: `Checks that the folder the hooks log to is there, and, for every agent, that
a hook is installed on each of its events and runs a pokegosu binary that is
still there. When one is not, it says the command that fixes it, and exits
non-zero.

How the syncs themselves went is in "pokegosu coder hook logs".`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if !doctor() {
				return errSilent
			}
			return nil
		},
	}
}

// doctor prints the log folder and each agent's hooks, and reports whether
// all were fine.
func doctor() bool {
	// Every agent's log is in pokegosu's config folder, and the shell opens
	// the log before running anything: without the folder every hook fails
	// before sync starts, and logs nothing.
	settings, err := config.Path()
	if err != nil {
		fmt.Printf("Configuration\n  ✗ log folder: %v\n", err)
		return false
	}
	folder := filepath.Dir(settings)
	info, err := os.Stat(folder)
	folderOK := err == nil && info.IsDir()

	anyInstalled := false
	for _, a := range hooks.Agents {
		if installed, _ := a.Installed(); installed {
			anyInstalled = true
		}
	}
	fmt.Println("Configuration")
	switch {
	case folderOK:
		fmt.Printf("  ✓ log folder %s\n", tilde(folder))
	case anyInstalled:
		fmt.Printf("  ✗ log folder %s: not there, so the hooks fail before they start\n", tilde(folder))
	default:
		fmt.Printf("  - log folder %s: not there yet\n", tilde(folder))
	}

	healthy := folderOK || !anyInstalled
	for _, a := range hooks.Agents {
		if !checkAgent(a, folderOK) {
			healthy = false
		}
	}
	return healthy
}

func checkAgent(a hooks.Agent, folderOK bool) bool {
	fmt.Println()
	path, err := a.SettingsPath()
	if err != nil {
		fmt.Printf("%s\n  ✗ %v\n", a.Name(), err)
		return false
	}
	fmt.Printf("%s (%s)\n", a.Name(), tilde(path))
	if !a.Present() {
		fmt.Println("  - not found")
		return true
	}

	commands, err := a.Commands()
	if err != nil {
		fmt.Printf("  ✗ %v\n", err)
		return false
	}

	// A missing log folder is this agent's to fix if it has hooks: install
	// makes the folder again.
	healthy := folderOK || len(commands) == 0
	for _, event := range a.Events() {
		command, found := commands[event]
		switch {
		case !found:
			fmt.Printf("  ✗ hook on %s: not installed\n", event)
			healthy = false
		case !exists(hooks.Executable(command)):
			fmt.Printf("  ✗ hook on %s: runs %s, which is not there\n", event, hooks.Executable(command))
			healthy = false
		default:
			fmt.Printf("  ✓ hook on %s\n", event)
		}
	}
	if !healthy {
		fmt.Printf("  → pokegosu coder hook install %s\n", a.ID())
	}
	return healthy
}

// tilde shortens a path under the home directory the way people write it.
func tilde(path string) string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return path
	}
	if rest, ok := strings.CutPrefix(path, home+string(filepath.Separator)); ok {
		return filepath.Join("~", rest)
	}
	return path
}

func exists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
