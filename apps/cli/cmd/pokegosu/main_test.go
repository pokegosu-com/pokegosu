package main

import (
	"strings"
	"testing"
)

// The words and flags below are what the README and the web tell people to
// type. A rename here without them is a command that no longer exists.
func TestTheTreeHasTheWordsPeopleAreToldToType(t *testing.T) {
	root := newRoot()

	cases := map[string][]string{
		"auth login":  {"url", "device-name"},
		"auth logout": nil,
		"auth status": nil,
		"coder scan":  {"since", "format", "path", "provider"},
		"coder sync":  {"all", "quiet", "jsonl", "no-fail", "min-interval", "path", "provider"},
		// "coder hook install" writes "coder sync --jsonl --no-fail
		// --min-interval" into agents' settings, so renaming any of those
		// breaks every hook already installed.
		"coder hook install":   nil,
		"coder hook uninstall": nil,
		"coder hook logs":      {"lines"},
		"coder hook doctor":    nil,
		"version":              nil,
	}
	for path, flags := range cases {
		cmd, rest, err := root.Find(strings.Fields(path))
		if err != nil || len(rest) != 0 || cmd.CommandPath() != "pokegosu "+path {
			t.Errorf("%q: found %q (rest %v, err %v)", path, cmd.CommandPath(), rest, err)
			continue
		}
		for _, name := range flags {
			if cmd.Flags().Lookup(name) == nil {
				t.Errorf("%q has no --%s", path, name)
			}
		}
	}
}

// Shell completion is most of why this uses cobra. cobra adds the command as
// it runs rather than when the tree is built, so it is checked by running it.
func TestCompletionScriptsAreThere(t *testing.T) {
	for _, shell := range []string{"bash", "zsh", "fish", "powershell"} {
		root := newRoot()
		var out strings.Builder
		root.SetArgs([]string{"completion", shell})
		root.SetOut(&out)

		if err := root.Execute(); err != nil {
			t.Errorf("%s: %v", shell, err)
			continue
		}
		if !strings.Contains(out.String(), "pokegosu") {
			t.Errorf("%s: the script does not name the command", shell)
		}
	}
}

// Every command that does something takes no arguments, so a stray word is
// a mistake to report rather than something to ignore.
func TestCommandsRefuseStrayArguments(t *testing.T) {
	for _, path := range []string{"auth login", "auth logout", "coder scan", "coder sync", "version"} {
		root := newRoot()
		root.SetArgs(append(strings.Fields(path), "stray"))
		root.SetOut(new(strings.Builder))
		root.SetErr(new(strings.Builder))

		if err := root.Execute(); err == nil {
			t.Errorf("%q accepted a stray argument", path)
		}
	}
}

// A group word on its own is somebody looking for what is under it.
func TestGroupsShowTheirCommands(t *testing.T) {
	for _, group := range []string{"auth", "coder"} {
		root := newRoot()
		var out strings.Builder
		root.SetArgs([]string{group})
		root.SetOut(&out)

		if err := root.Execute(); err != nil {
			t.Fatalf("%q: %v", group, err)
		}
		cmd, _, _ := root.Find([]string{group})
		for _, sub := range cmd.Commands() {
			if !sub.IsAvailableCommand() {
				continue
			}
			if !strings.Contains(out.String(), sub.Name()) {
				t.Errorf("%q help does not mention %q", group, sub.Name())
			}
		}
	}
}
