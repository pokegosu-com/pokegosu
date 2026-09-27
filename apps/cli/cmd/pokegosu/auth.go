package main

import (
	"github.com/spf13/cobra"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/auth"
)

func newAuthCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "auth",
		Short: "Enrol this machine with your account",
		Long: `Enrol this machine with your account.

A machine is enrolled once, whatever services it goes on to use.`,
	}
	cmd.AddCommand(newLoginCmd())
	return cmd
}

func newLoginCmd() *cobra.Command {
	var opts auth.LoginOptions

	cmd := &cobra.Command{
		Use:   "login",
		Short: "Enrol this machine, approved by you in the web",
		Long: `Enrols this machine. It shows a short code and an address; open that address,
signed in, and approve the code you see here. Nothing secret is typed or
pasted, and the machine's key is handed to this machine alone.

Settings are written to ~/.config/pokegosu/config.json, readable only by you.

A machine is enrolled once. Its id lives in those settings, so a machine that
needs a new key — one that was deleted, or that lost its settings — enrols as
a new machine, and the old one keeps the history it earned.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return auth.Login(cmd.Context(), opts)
		},
	}

	cmd.Flags().StringVar(&opts.URL, "url", "",
		"the deployment at `URL`, for one other than the default")
	cmd.Flags().StringVar(&opts.DeviceName, "device-name", "",
		"call this machine `NAME` in the web (default: the hostname)")
	return cmd
}
