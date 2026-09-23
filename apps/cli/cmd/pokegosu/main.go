// Command pokegosu is the command line to pokegosu's services. Each service
// is a word of its own: `pokegosu coder sync` is coder's.
//
// This package is only the shape of the command line — which words there
// are, which flags they take, and what their help says. What each command
// does lives in internal/, one package per service, as plain functions that
// know nothing of cobra, so they are tested as functions.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"

	"github.com/spf13/cobra"
)

// version is set at build time from the git tag, the same version every app
// in the repository shows. A plain go build says dev.
var version = "dev"

func main() {
	// Ctrl-C cancels whatever is waiting, such as a login waiting for a
	// person to approve it, rather than leaving it to be killed mid-write.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	if err := newRoot().ExecuteContext(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "pokegosu: %v\n", err)
		os.Exit(1)
	}
}

func newRoot() *cobra.Command {
	root := &cobra.Command{
		Use:   "pokegosu",
		Short: "The command line to pokegosu",
		Long: `The command line to pokegosu.

A machine is enrolled once, with the account, and every service speaks with
the key that enrolment leaves behind.`,
		Version: version,

		// Errors are printed once, by main, in one shape; a mistake in the
		// flags already says what was wrong without the whole usage after it.
		SilenceErrors: true,
		SilenceUsage:  true,
	}
	root.SetVersionTemplate("{{.Version}}\n")

	root.AddCommand(newAuthCmd(), newCoderCmd(), newVersionCmd())
	return root
}

func newVersionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print this build's version",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprintln(cmd.OutOrStdout(), version)
		},
	}
}
