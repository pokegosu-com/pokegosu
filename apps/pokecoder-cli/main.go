// Command pokecoder collects coding agent token usage from the local machine
// and uploads hourly totals to the account it was enrolled with.
//
// The parsing lives in libs/go/tokenusage, which clients in other languages
// match through tests/tokenusage. What is here is the part only a CLI has:
// flags, settings on disk, and talking to the server.
package main

import (
	"errors"
	"fmt"
	"os"
)

// version is set at build time from the git tag, the same version every app
// in the repository shows. A plain go build says dev.
var version = "dev"

// defaultURL is the service login uses when told no other. Set at build time
// for a build meant for another deployment; --url overrides it either way.
var defaultURL = "https://coder.pokegosu.com"

const usageText = `pokecoder collects coding agent token usage.

usage:
  pokecoder login [flags]   save settings and register this machine
  pokecoder scan [flags]    parse local logs and print hourly rollups
  pokecoder sync [flags]    upload what has changed since the last run
  pokecoder version         print this build's version

run "pokecoder <command> -h" for the flags.
`

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "pokecoder: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
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
	case "version", "--version":
		fmt.Println(version)
		return nil
	case "-h", "--help", "help":
		fmt.Print(usageText)
		return nil
	default:
		fmt.Fprint(os.Stderr, usageText)
		return fmt.Errorf("unknown command %q", cmd)
	}
}
