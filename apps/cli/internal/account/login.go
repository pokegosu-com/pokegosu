// Package account is the part of the command line that is not any one
// service's: enrolling this machine with a pokegosu account, and the settings
// that enrolment leaves behind. Every service speaks with the key it gets
// here.
package account

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/api"
	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
)

const loginUsage = `usage: pokegosu login [flags]

Enrols this machine. Open the web, ask it to add a machine, and type in the
code it shows you. The machine gets its own key that way — nothing secret is
ever typed or pasted.

flags:
  --url URL           the service you sign in at, for a deployment other
                      than the default. The web's "add a machine" page shows
                      the command with it filled in
  --code CODE         the enrollment code, for a script that cannot be asked.
                      Left out, login asks for it.
  --device-name NAME  what this machine is called in the web UI.
                      Defaults to the hostname

Settings are written to ~/.config/coder/config.json, readable only by you.

A machine that is already enrolled is enrolled again with the new code: it
keeps its id, and so its history, and gets a new key. That is how a machine
retired in the web comes back.
`

// defaultURL is the service login uses when told no other. Set at build time
// for a build meant for another deployment; --url overrides it either way.
var defaultURL = "https://account.pokegosu.com"

// Login enrols this machine with an account.
func Login(args []string) error {
	fs := flag.NewFlagSet("login", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	var (
		url        = fs.String("url", "", "the service URL")
		code       = fs.String("code", "", "the enrollment code")
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
	if enrolled(stored) {
		fmt.Printf("%q is enrolled with %s; a new code enrols it again with a new key\n",
			stored.DeviceName, stored.URL)
	}

	cfg, err := settings(stored, *url, *deviceName)
	if err != nil {
		return err
	}

	typed, err := readCode(*code, os.Stdin, os.Stdout)
	if err != nil {
		return err
	}

	// Asked every time rather than kept from last time: the service decides
	// where its API is, and may have moved it.
	cfg.APIURL, err = api.Discover(context.Background(), nil, cfg.URL)
	if err != nil {
		return err
	}

	client := &api.Client{BaseURL: cfg.APIURL}
	key, err := client.Enrol(context.Background(), typed, cfg.DeviceID, cfg.DeviceName)
	if err != nil {
		return explain(err)
	}
	cfg.APIKey = key

	// Saved only after the server accepted them: settings on disk should mean
	// settings that work.
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

// readCode resolves where the enrollment code comes from.
//
// Asking is the normal way: a code on the command line is readable by anyone
// who can run ps and is kept in shell history. That matters less than it did
// for a long-lived key — this one dies in minutes and works once — but the
// flag is still there for a script that has nobody to ask.
func readCode(flagValue string, in io.Reader, prompt io.Writer) (string, error) {
	if flagValue != "" {
		return strings.TrimSpace(flagValue), nil
	}

	fmt.Fprint(prompt, "enrollment code: ")
	line, err := bufio.NewReader(in).ReadString('\n')
	typed := strings.TrimSpace(line)
	if err != nil && !errors.Is(err, io.EOF) {
		return "", fmt.Errorf("reading the enrollment code: %w", err)
	}
	if typed == "" {
		return "", fmt.Errorf("no enrollment code given; the web shows one under \"add a machine\"")
	}
	return typed, nil
}

// explain turns a server refusal into the thing to do about it.
func explain(err error) error {
	var serverErr *api.Error
	if !errors.As(err, &serverErr) {
		return err
	}
	switch {
	case serverErr.CodeRefused():
		return fmt.Errorf("%s", serverErr.Message)
	case serverErr.DeviceTaken():
		// The server's wording covers the what; this adds the how. The id is
		// in the settings file, so a new file is a new machine.
		return fmt.Errorf("this machine is enrolled with another account; " +
			"delete this machine's settings file to enrol it as a new machine")
	case serverErr.Status == 401:
		// Nothing of ours refused the code, so the request did not reach us.
		return fmt.Errorf("the server rejected the request before it reached coder "+
			"(%s); check that --url is the coder service", serverErr.Error())
	default:
		return err
	}
}
