package auth

import (
	"errors"
	"fmt"
	"os"
)

const usageText = `pokegosu auth enrols this machine with your account.

usage:
  pokegosu auth login [flags]   trade a code from the web for this machine's key

A machine is enrolled once, whatever services it goes on to use.

run "pokegosu auth login -h" for the flags.
`

// Run dispatches one of auth's commands.
func Run(args []string) error {
	if len(args) == 0 {
		fmt.Fprint(os.Stderr, usageText)
		return errors.New("no command given")
	}

	switch cmd := args[0]; cmd {
	case "login":
		return runLogin(args[1:])
	case "-h", "--help", "help":
		fmt.Print(usageText)
		return nil
	default:
		fmt.Fprint(os.Stderr, usageText)
		return fmt.Errorf("unknown command %q", cmd)
	}
}
