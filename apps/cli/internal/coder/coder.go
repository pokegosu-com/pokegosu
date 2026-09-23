// Package coder is the coder service's side of the command line: enrolling a
// machine, reading its agents' logs, and uploading hourly totals.
//
// The parsing itself lives in libs/go/coder, which clients in other languages
// match through tests/coder. What is here is the part only a CLI has: flags,
// settings on disk, and talking to the server.
package coder

import (
	"errors"
	"fmt"
	"os"
)

// defaultURL is the service login uses when told no other. Set at build time
// for a build meant for another deployment; --url overrides it either way.
var defaultURL = "https://coder.pokegosu.com"

const usageText = `pokegosu coder collects coding agent token usage.

usage:
  pokegosu coder login [flags]   save settings and register this machine
  pokegosu coder scan [flags]    parse local logs and print hourly rollups
  pokegosu coder sync [flags]    upload what has changed since the last run

run "pokegosu coder <command> -h" for the flags.
`

// Run dispatches one of coder's commands.
func Run(args []string) error {
	if len(args) == 0 {
		fmt.Fprint(os.Stderr, usageText)
		return errors.New("no command given")
	}

	switch cmd := args[0]; cmd {
	case "login":
		return runLogin(args[1:])
	case "scan":
		return runScan(args[1:])
	case "sync":
		return runSync(args[1:])
	case "-h", "--help", "help":
		fmt.Print(usageText)
		return nil
	default:
		fmt.Fprint(os.Stderr, usageText)
		return fmt.Errorf("unknown command %q", cmd)
	}
}
