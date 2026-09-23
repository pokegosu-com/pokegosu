// Command pokegosu is the command line to pokegosu's services. Each service
// is a word of its own: `pokegosu coder sync` is coder's.
//
// The services themselves live in internal/, one package each, so a new one
// is a package and a line here.
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/auth"
	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder"
)

// version is set at build time from the git tag, the same version every app
// in the repository shows. A plain go build says dev.
var version = "dev"

const usageText = `pokegosu is the command line to pokegosu.

usage:
  pokegosu auth <command>    enrol this machine with your account
  pokegosu coder <command>   coding agent token usage
  pokegosu version           print this build's version

A machine is enrolled once, with the account, and every service speaks with
the key that enrolment leaves behind.

run "pokegosu auth -h" or "pokegosu coder -h" for what each can do.
`

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "pokegosu: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		fmt.Fprint(os.Stderr, usageText)
		return errors.New("no service given")
	}

	switch name := args[0]; name {
	case "auth":
		return auth.Run(args[1:])
	case "coder":
		return coder.Run(args[1:])
	case "version", "--version":
		fmt.Println(version)
		return nil
	case "-h", "--help", "help":
		fmt.Print(usageText)
		return nil
	default:
		fmt.Fprint(os.Stderr, usageText)
		return fmt.Errorf("unknown service %q", name)
	}
}
