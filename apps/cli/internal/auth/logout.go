package auth

import (
	"context"
	"fmt"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
	authapi "github.com/pokegosu-com/pokegosu/libs/go/auth"
)

// Logout retires this machine in the account and deletes its settings.
//
// Retiring is final: the key stops working everywhere, and the machine keeps
// the history it earned. A login afterwards is a new machine, which is why
// the settings go too — the id in them is spent.
func Logout(ctx context.Context) error {
	stored, err := config.Load()
	if err != nil {
		return err
	}
	if stored == nil {
		fmt.Println("this machine is not enrolled")
		return nil
	}

	// Settings with no key have nothing to retire, but their id may be one
	// the server has already spent, so they go all the same.
	if stored.APIKey != "" && stored.APIURL != "" {
		if err := retire(ctx, stored); err != nil {
			return err
		}
	}

	path, err := config.Remove()
	if err != nil {
		return err
	}
	fmt.Printf("deleted %s\n", path)
	return nil
}

// retire asks the server to retire the machine, and says what became of it.
// Settings are kept on any failure but a refused key: while the key may
// still work, deleting it would leave a machine nobody can retire but the web.
func retire(ctx context.Context, cfg *config.Config) error {
	name, err := authapi.New(cfg.APIURL).Retire(ctx, cfg.APIKey)
	switch {
	case err == nil:
		fmt.Printf("retired %q from %s\n", name, cfg.URL)
		return nil
	case authapi.KeyRefused(err):
		// Retired in the web already, most likely. Either way the key works
		// for nothing, which is what logging out was for.
		fmt.Printf("%q was already retired from %s\n", cfg.DeviceName, cfg.URL)
		return nil
	case authapi.GatewayRefused(err):
		return fmt.Errorf("the server rejected the request before it reached pokegosu "+
			"(%s); the settings are kept, since the key may still work", err)
	default:
		return fmt.Errorf("%w; the settings are kept, since the key may still work — "+
			"try again, or retire this machine in the web", err)
	}
}
