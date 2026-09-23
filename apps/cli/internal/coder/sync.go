package coder

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder/state"
	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/scan"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
	"github.com/pokegosu-com/pokegosu/libs/go/pokegosu"
)

const syncUsage = `usage: pokegosu coder sync [flags]

Reads the local agent logs and uploads the hourly rollups that have changed
since the last run. One pass, then it exits: run it from cron, a systemd
timer or launchd rather than leaving it resident.

flags:
  --all            upload every bucket, not only the changed ones. Use after
                   the server has lost data, or to check a disagreement
  --quiet          print nothing unless something went wrong, which is what a
                   scheduled run wants
  --path DIR       read DIR instead of the default log location. Repeatable
  --provider ID    read only this provider's logs. Repeatable, and needed
                   alongside --path once there is more than one provider

A sync reports nothing from before this machine was enrolled: what the logs
hold from before then is nobody's business but this machine's. The server
ignores those hours whoever sends them; skipping them here only saves the
request. The hour the enrolment fell in is reported whole.

Run login first: sync needs the settings it writes.
`

// A first run can carry months of logs, and the server takes ten thousand
// rollups per request. Rollups are absolute values, so splitting them across
// requests lands on the same numbers.
const maxPerRequest = 5000

func runSync(args []string) error {
	fs := flag.NewFlagSet("sync", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	var (
		all       = fs.Bool("all", false, "upload every bucket")
		quiet     = fs.Bool("quiet", false, "print nothing unless something went wrong")
		paths     pathList
		providers pathList
	)
	fs.Var(&paths, "path", "log directory to read instead of the default")
	fs.Var(&providers, "provider", "read only this provider's logs")

	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			fmt.Print(syncUsage)
			return nil
		}
		fmt.Fprint(os.Stderr, syncUsage)
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(os.Stderr, syncUsage)
		return fmt.Errorf("unexpected argument %q", fs.Arg(0))
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if cfg == nil || cfg.APIKey == "" || cfg.APIURL == "" || cfg.DeviceID == "" {
		return fmt.Errorf("not logged in: run pokegosu auth login first")
	}

	selected, err := selectProviders(providers)
	if err != nil {
		return err
	}

	// The server ignores anything older anyway; this keeps a first run from
	// carrying months of logs across the network to be dropped.
	result, err := scan.Run(scan.Options{Roots: paths, Providers: selected, Since: cfg.EnrolledAt})
	if err != nil {
		return err
	}
	report(*quiet, result)

	settingsPath, err := config.Path()
	if err != nil {
		return err
	}
	cachePath := state.Path(settingsPath)
	cache := state.Load(cachePath, cfg.APIURL, cfg.DeviceID)

	pending := result.Rollups
	if *all {
		// Restating the whole ledger starts from nothing known. Otherwise a
		// run that fails half way records the batches that landed against a
		// cache that already claimed them, and the rest is never sent again.
		cache.Forget()
	} else {
		pending = cache.Changed(result.Rollups, time.Now())
	}
	if len(pending) == 0 {
		if !*quiet {
			fmt.Println("nothing to send")
		}
		return nil
	}

	client := &pokegosu.Client{BaseURL: cfg.APIURL, APIKey: cfg.APIKey}
	sent, sendErr := send(client, pending)

	// Whatever the server took, it holds — even if a later batch failed.
	// Recording it keeps the next run from sending those rows again.
	cache.Record(sent)
	if err := state.Save(cachePath, cache); err != nil {
		fmt.Fprintf(os.Stderr, "pokegosu: %v: %v\n", state.ErrNotSaved, err)
	}

	if sendErr != nil {
		return explainSync(sendErr)
	}
	if !*quiet {
		fmt.Printf("sent %s to %s\n", count(len(sent), "bucket", "buckets"), cfg.URL)
	}
	return nil
}

// send uploads in batches and returns everything the server accepted, which
// on failure is the batches that landed before it.
func send(client *pokegosu.Client, rollups []usage.Rollup) ([]usage.Rollup, error) {
	var sent []usage.Rollup

	for start := 0; start < len(rollups); start += maxPerRequest {
		end := min(start+maxPerRequest, len(rollups))
		batch := rollups[start:end]

		if _, _, err := client.Ingest(context.Background(), batch); err != nil {
			return sent, err
		}
		sent = append(sent, batch...)
	}
	return sent, nil
}

// report says what was read before anything is uploaded, so that a wrong
// number can be told apart from a failed upload without a second run.
//
// What could not be read goes to stderr even under --quiet: a scheduled run
// that says nothing should mean nothing went wrong, and a log this client
// cannot parse is the one thing that would make its numbers quietly small.
func report(quiet bool, result scan.Result) {
	if !quiet {
		fmt.Printf("read %s from %s in %s\n",
			count(result.Messages, "message", "messages"),
			count(result.Stats.Files, "file", "files"),
			count(len(result.Roots), "directory", "directories"))
	}

	if s := result.Stats; s.BadLines > 0 || s.BadRecords > 0 || s.Unreadable > 0 {
		fmt.Fprintf(os.Stderr,
			"pokegosu: skipped %s that could not be decoded, %s without a usable id, %s that could not be opened\n",
			count(s.BadLines, "line", "lines"),
			count(s.BadRecords, "line", "lines"),
			count(s.Unreadable, "file", "files"))
	}

	if len(result.Roots) == 0 {
		fmt.Fprintln(os.Stderr,
			"pokegosu: no agent logs were found, so there is nothing to send")
	}
}

// explainSync turns a server refusal into the thing to do about it.
func explainSync(err error) error {
	var serverErr *pokegosu.Error
	if !errors.As(err, &serverErr) {
		return err
	}
	switch {
	case serverErr.KeyRefused():
		// A key the server does not know and a machine somebody retired read
		// the same from here, and the way out of both is the same: a machine
		// is enrolled once, so this one starts again as a new machine.
		return fmt.Errorf("the server refused this machine's key: %s; "+
			"it may have been retired in the web. Delete this machine's settings "+
			"and run pokegosu auth login to enrol it as a new machine",
			serverErr.Message)
	case serverErr.Status == 401:
		return fmt.Errorf("the server rejected the request before it reached coder (%s); "+
			"check the settings login wrote", serverErr.Error())
	default:
		return err
	}
}
