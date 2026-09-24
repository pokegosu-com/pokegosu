package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/auth"
	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder/hooks"
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
needs a new key — one that was retired, or that lost its settings — enrols as
a new machine, and the old one keeps the history it earned.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := auth.Login(cmd.Context(), opts); err != nil {
				return err
			}
			return offerHooks(cmd.InOrStdin())
		},
	}

	cmd.Flags().StringVar(&opts.URL, "url", "",
		"the deployment at `URL`, for one other than the default")
	cmd.Flags().StringVar(&opts.DeviceName, "device-name", "",
		"call this machine `NAME` in the web (default: the hostname)")
	return cmd
}

// offerHooks asks, once a machine is enrolled, whether its coding agents
// should run sync, since without that nothing is ever sent.
// Asked rather than done: it writes to another program's settings. With no
// one at the terminal to ask, it says how instead.
func offerHooks(stdin io.Reader) error {
	var ids, names []string
	for _, a := range hooks.Agents {
		if !a.Present() {
			continue
		}
		if installed, err := a.Installed(); err == nil && !installed {
			ids = append(ids, a.ID())
			names = append(names, a.Name())
		}
	}
	if len(ids) == 0 {
		return nil
	}
	command := "pokegosu coder hook install " + strings.Join(ids, " ")

	if !interactive() {
		fmt.Printf("\nto have %s run sync for you: %s\n", strings.Join(names, " and "), command)
		return nil
	}

	fmt.Printf("\nHave %s run sync for you, when a session ends and every so often\nwhile one is open? This adds a hook to its settings. [Y/n] ", strings.Join(names, " and "))
	answer, err := bufio.NewReader(stdin).ReadString('\n')
	if err != nil {
		// Input ended without a line, as from /dev/null, which is also a
		// character device: nobody answered, so nothing is written.
		fmt.Println()
		fmt.Printf("left as it is; %s does it later\n", command)
		return nil
	}
	switch strings.ToLower(strings.TrimSpace(answer)) {
	case "", "y", "yes":
		return installHooks(ids)
	default:
		fmt.Printf("left as it is; %s does it later\n", command)
		return nil
	}
}

// interactive says whether someone is at the terminal to answer.
func interactive() bool {
	info, err := os.Stdin.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}
