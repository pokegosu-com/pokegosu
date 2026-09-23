// Package coder is the coder service's side of the command line: reading this
// machine's agent logs and uploading hourly totals. Enrolling the machine is
// the account's, in internal/account.
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

const usageText = `pokegosu coder collects coding agent token usage.

usage:
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
