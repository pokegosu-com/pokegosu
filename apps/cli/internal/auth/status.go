package auth

import (
	"fmt"
	"io"
	"time"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
)

// Status says whether this machine is enrolled, and with what, from the
// settings alone. It asks no server: there is nothing to ask that would not
// cost a sync, and the settings are what every service goes by.
//
// A machine that is not enrolled is an error, so a script can tell from the
// exit status alone.
func Status(w io.Writer) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if !enrolled(cfg) {
		return fmt.Errorf("this machine is not enrolled; run pokegosu auth login")
	}

	// The key is never printed: it is the one thing here worth stealing, and
	// a status is the sort of output people paste into an issue.
	fmt.Fprintf(w, "%q is enrolled with %s\n", cfg.DeviceName, cfg.URL)
	if !cfg.EnrolledAt.IsZero() {
		fmt.Fprintf(w, "enrolled at  %s\n", cfg.EnrolledAt.Local().Format(time.DateTime+" MST"))
	}
	fmt.Fprintf(w, "machine id   %s\n", cfg.DeviceID)
	fmt.Fprintf(w, "API          %s\n", cfg.APIURL)
	fmt.Fprintf(w, "settings     %s\n", settingsPathOrDefault())
	return nil
}
