package auth

import (
	"context"
	"fmt"
	"io"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
	authapi "github.com/pokegosu-com/pokegosu/libs/go/auth"
)

// Status says which machine this is and whose, as the server has it: the
// account's name lives there and can change, and asking is also how to learn
// that the key still works.
//
// Anything short of an answer is an error, so a script can tell from the exit
// status alone whether this machine can sync.
func Status(ctx context.Context, w io.Writer) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if !enrolled(cfg) {
		return fmt.Errorf("this machine is not enrolled; run pokegosu auth login")
	}

	id, err := authapi.New(cfg.APIURL).Whoami(ctx, cfg.APIKey)
	switch {
	case authapi.KeyRefused(err):
		// Retired in the web, most likely. The id is spent with it, so the
		// way back is new settings, as login's own advice says.
		return fmt.Errorf("this machine's key no longer works; it may have been deleted in the web. "+
			"delete %s and run pokegosu auth login to enrol it as a new machine", settingsPathOrDefault())
	case authapi.GatewayRefused(err):
		return fmt.Errorf("the server rejected the request before it reached pokegosu (%s)", err)
	case err != nil:
		return err
	}

	name := id.DisplayName
	if name == "" {
		name = "(no name yet)"
	}
	fmt.Fprintf(w, "machine id  %s\n", id.DeviceID)
	fmt.Fprintf(w, "account     %s\n", name)
	return nil
}
