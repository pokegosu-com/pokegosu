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
	cmd.AddCommand(newLoginCmd(), newLogoutCmd(), newStatusCmd())
	return cmd
}

func newLogoutCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "logout",
		Short: "Retire this machine and delete its settings",
		Long: `Retires this machine in your account, as deleting it in the web does, and
deletes its settings. Its key stops working, and the usage it sent stays in
the account.

Retiring is final. Running pokegosu auth login afterwards enrols this machine
as a new machine.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return auth.Logout(cmd.Context())
		},
	}
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

func newStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Say which machine this is, and whose",
		Long: `Asks the server which machine this is and which account it belongs to,
with the key this machine was enrolled with. The key is never printed.

It fails when this machine is not enrolled, or when its key no longer works,
so a script can tell from the exit status whether this machine can sync.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return auth.Status(cmd.Context(), cmd.OutOrStdout())
		},
	}
}
