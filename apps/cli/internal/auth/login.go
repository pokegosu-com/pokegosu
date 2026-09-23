// Package auth is the part of the command line that is not any one service's:
// enrolling this machine with a pokegosu account, and the settings that
// enrolment leaves behind. Every service speaks with the key it gets here.
package auth

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
	authapi "github.com/pokegosu-com/pokegosu/libs/go/auth"
)

const loginUsage = `usage: pokegosu auth login [flags]

Enrols this machine. It shows a short code and an address; open that address,
signed in, and approve the code you see here. Nothing secret is typed or
pasted, and the machine's key is handed to this machine alone.

flags:
  --url URL           the deployment, for one other than the default
  --device-name NAME  what this machine is called in the web.
                      Defaults to the hostname
  --code CODE         ask under this code instead of drawing one, for a
                      script that has to know it in advance

Settings are written to ~/.config/pokegosu/config.json, readable only by you.

A machine is enrolled once. Its id lives in those settings, so a machine that
needs a new key — one that was retired, or that lost its settings — enrols as
a new machine, and the old one keeps the history it earned.
`

// pollInterval is how often the machine asks whether it has been let in.
// Short enough that approving feels immediate, long enough that ten minutes
// of waiting is a few hundred requests.
var pollInterval = 2 * time.Second

// attempts is how many times a drawn code may collide with one already being
// waited on before login gives up. One collision is a one in a trillion
// event; three is not worth a retry loop that never ends.
const attempts = 3

// defaultURL is the service login uses when told no other. Set at build time
// for a build meant for another deployment; --url overrides it either way.
var defaultURL = "https://pokegosu.com"

func runLogin(args []string) error {
	fs := flag.NewFlagSet("login", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	var (
		url        = fs.String("url", "", "the service URL")
		givenCode  = fs.String("code", "", "ask under this code instead of drawing one")
		deviceName = fs.String("device-name", "", "what this machine is called")
	)

	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			fmt.Print(loginUsage)
			return nil
		}
		fmt.Fprint(os.Stderr, loginUsage)
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(os.Stderr, loginUsage)
		return fmt.Errorf("unexpected argument %q", fs.Arg(0))
	}

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

	cfg, err := settings(stored, *url, *deviceName)
	if err != nil {
		return err
	}

	ctx := context.Background()

	// Asked every time rather than kept from last time: the deployment
	// decides where its parts are, and may have moved them.
	service, err := authapi.Discover(ctx, nil, cfg.URL)
	if err != nil {
		return err
	}
	cfg.APIURL = service.APIURL

	client := authapi.New(cfg.APIURL)
	code, started, err := ask(ctx, client, cfg, *givenCode)
	if err != nil {
		return err
	}

	fmt.Printf("\nopen %s/devices/add/%s\n", service.AccountURL, format(code))
	fmt.Printf("and approve this machine. The code is %s.\n\n", format(code))

	claim, err := wait(ctx, client, started, os.Stdout)
	if err != nil {
		return explain(err)
	}
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

// ask starts an enrolment, drawing a code unless one was given.
//
// A code already being waited on is not a failure: the machine draws another.
// A code from --code is the caller's, so a collision there is reported rather
// than worked around.
func ask(ctx context.Context, client *authapi.Client, cfg *config.Config, given string) (string, authapi.Enrollment, error) {
	if given != "" {
		code := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(given), "-", ""))
		started, err := client.StartEnrollment(ctx, code, cfg.DeviceID, cfg.DeviceName)
		return code, started, err
	}

	for range attempts {
		code, err := newCode()
		if err != nil {
			return "", authapi.Enrollment{}, err
		}

		started, err := client.StartEnrollment(ctx, code, cfg.DeviceID, cfg.DeviceName)
		if err == nil {
			return code, started, nil
		}

		if !authapi.CodeTaken(err) {
			return "", authapi.Enrollment{}, err
		}
	}
	return "", authapi.Enrollment{}, fmt.Errorf("could not find a free enrollment code; try again")
}

// wait asks until a person approves, or the request runs out.
func wait(ctx context.Context, client *authapi.Client, started authapi.Enrollment, progress io.Writer) (authapi.Claim, error) {
	fmt.Fprint(progress, "waiting for approval… ")

	for {
		claim, err := client.ClaimEnrollment(ctx, started.ClaimToken)
		if err != nil {
			fmt.Fprintln(progress)
			return authapi.Claim{}, err
		}
		if !claim.Waiting {
			fmt.Fprintln(progress, "approved")
			return claim, nil
		}

		if time.Now().After(started.ExpiresAt) {
			fmt.Fprintln(progress)
			return authapi.Claim{}, fmt.Errorf(
				"nobody approved this machine in time; run pokegosu auth login again")
		}

		select {
		case <-ctx.Done():
			fmt.Fprintln(progress)
			return authapi.Claim{}, ctx.Err()
		case <-time.After(pollInterval):
		}
	}
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
		return err
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
