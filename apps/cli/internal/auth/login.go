// Package auth is the part of the command line that is not any one service's:
// enrolling this machine with a pokegosu account, and the settings that
// enrolment leaves behind. Every service speaks with the key it gets here.
package auth

import (
	"context"
	"fmt"
	"os"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
	authapi "github.com/pokegosu-com/pokegosu/libs/go/auth"
)

// defaultURL is the service login uses when told no other. Set at build time
// for a build meant for another deployment; --url overrides it either way.
var defaultURL = "https://pokegosu.com"

// LoginOptions is what a person can tell login. Empty means "the default":
// the service this machine was enrolled with, else the public one, and the
// hostname for a name.
type LoginOptions struct {
	URL        string
	DeviceName string
}

// Login enrols this machine: asks to be let in, tells the person where to
// approve it, and waits until they have.
func Login(ctx context.Context, opts LoginOptions) error {
	stored, err := config.Load()
	if err != nil {
		return err
	}
	// A machine id is enrolled once, and this machine has one. Saying so is
	// the whole of what login does here: there is nothing to ask for, and
	// the settings it already has are the ones that work.
	if enrolled(stored) {
		fmt.Printf("%q is already enrolled with %s\n", stored.DeviceName, stored.URL)
		fmt.Printf("to enrol this machine anew, delete %s first\n", settingsPathOrDefault())
		return nil
	}

	cfg, err := settings(stored, opts.URL, opts.DeviceName)
	if err != nil {
		return err
	}

	// Asked every time rather than kept from last time: the deployment
	// decides where its parts are, and may have moved them.
	service, err := authapi.Discover(ctx, nil, cfg.URL)
	if err != nil {
		return err
	}
	cfg.APIURL = service.APIURL

	client := authapi.New(cfg.APIURL)
	begun, err := client.Begin(ctx, service, cfg.DeviceID, cfg.DeviceName)
	if err != nil {
		return explain(err)
	}

	fmt.Printf("\nopen %s\n", begun.ApproveURL)
	fmt.Printf("and approve this machine. The code is %s.\n\n", begun.Code)
	fmt.Print("waiting for approval… ")

	claim, err := client.Wait(ctx, begun)
	if err != nil {
		fmt.Println()
		return explain(err)
	}
	fmt.Println("approved")

	cfg.APIKey = claim.APIKey
	if claim.DeviceName != "" {
		cfg.DeviceName = claim.DeviceName
	}
	cfg.EnrolledAt = claim.EnrolledAt

	// Saved only after the server handed over a key: settings on disk should
	// mean settings that work.
	path, err := config.Save(cfg)
	if err != nil {
		return err
	}

	fmt.Printf("enrolled %q with %s\n", cfg.DeviceName, cfg.URL)
	fmt.Printf("settings saved to %s\n", path)
	return nil
}

// enrolled reports whether this machine already has everything it needs.
//
// Enrolling it again is safe: the machine keeps its id, and the server
// replaces its key rather than adding one, so the old key stops working.
// login only says that it is happening.
func enrolled(cfg *config.Config) bool {
	return cfg != nil && cfg.URL != "" && cfg.APIURL != "" && cfg.APIKey != "" && cfg.DeviceID != ""
}

// settings fills in everything enrolment needs except the key, reporting what
// is missing as one message rather than making the user rediscover the flags
// one at a time.
func settings(stored *config.Config, url, deviceName string) (*config.Config, error) {
	cfg := config.Config{}
	if stored != nil {
		cfg = *stored
	}

	// --url wins, then the service this machine was enrolled with, then the
	// default.
	if url == "" {
		url = cfg.URL
	}
	if url == "" {
		url = defaultURL
	}
	normalized, err := config.NormalizeURL(url)
	if err != nil {
		return nil, err
	}
	cfg.URL = normalized

	if deviceName != "" {
		cfg.DeviceName = deviceName
	}

	// The id is the machine's own, made once and kept, so that a machine
	// whose settings are rebuilt is still the same machine.
	if cfg.DeviceID == "" {
		id, err := config.NewDeviceID()
		if err != nil {
			return nil, err
		}
		cfg.DeviceID = id
	}
	if cfg.DeviceName == "" {
		host, err := os.Hostname()
		if err != nil || host == "" {
			return nil, fmt.Errorf("could not read the hostname; pass --device-name")
		}
		cfg.DeviceName = host
	}
	return &cfg, nil
}

// explain turns a server refusal into the thing to do about it.
func explain(err error) error {
	switch {
	case authapi.RequestGone(err):
		return fmt.Errorf("%w; run pokegosu auth login again", err)
	case authapi.DeviceTaken(err):
		// The server's wording covers the what; this adds the how. The id is
		// in the settings file, so new settings are a new machine.
		return fmt.Errorf("this machine's id is already registered; " +
			"delete this machine's settings file to enrol it as a new machine")
	case authapi.GatewayRefused(err):
		// Nothing of ours refused anything, so the request did not reach us.
		return fmt.Errorf("the server rejected the request before it reached pokegosu "+
			"(%s); check that --url is the deployment's address", err)
	default:
		return err
	}
}

// settingsPathOrDefault names the file to delete, and falls back to the
// documented location rather than failing over a message.
func settingsPathOrDefault() string {
	path, err := config.Path()
	if err != nil {
		return "~/.config/pokegosu/config.json"
	}
	return path
}
