package coder

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder/state"
	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
	coderapi "github.com/pokegosu-com/pokegosu/libs/go/coder"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/scan"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// A first run can carry months of logs, and the server takes ten thousand
// rollups per request. Rollups are absolute values, so splitting them across
// requests lands on the same numbers.
const maxPerRequest = 5000

// SyncOptions is what a person can tell sync.
type SyncOptions struct {
	// All uploads every bucket, not only the changed ones: after the server
	// has lost data, or to check a disagreement.
	All bool

	// Quiet prints nothing unless something went wrong, which is what a
	// hook wants.
	Quiet bool

	// MinInterval skips the sync when the last one started less than this
	// long ago. An agent's hook that fires every turn asks for it, so that a
	// busy session does not send the same hour over and over.
	MinInterval time.Duration

	// Paths and Providers are as for scan.
	Paths     []string
	Providers []string
}

// now is the clock Sync reads, replaced in tests.
var now = time.Now

// Outcomes a sync can have.
const (
	Sent    = "sent"    // the server took Buckets rollups
	Nothing = "nothing" // nothing had changed
	Skipped = "skipped" // --min-interval held it back
	Failed  = "failed"  // Error says why
)

// Result is how a sync went: what --jsonl prints, one line per sync, and
// what a hook appends to its log.
type Result struct {
	At      time.Time `json:"at"`
	Outcome string    `json:"outcome"`
	Buckets int       `json:"buckets,omitempty"`
	Error   string    `json:"error,omitempty"`
}

// Sync reads the local agent logs and uploads the hourly rollups that have
// changed since the last run. One pass, then it returns, saying how it went.
func Sync(opts SyncOptions) (Result, error) {
	settingsPath, err := config.Path()
	if err != nil {
		return Result{At: now(), Outcome: Failed, Error: err.Error()}, err
	}
	runPath := state.RunPath(settingsPath)
	result := Result{At: now()}

	if opts.MinInterval > 0 {
		last := state.LoadRun(runPath)
		if ago := result.At.Sub(last.At); !last.At.IsZero() && ago < opts.MinInterval {
			if !opts.Quiet {
				fmt.Printf("the last sync was %s ago; skipped\n", ago.Round(time.Second))
			}
			result.Outcome = Skipped
			return result, nil
		}
	}

	// Recorded before the sync, so that another one starting meanwhile
	// counts its interval from this one.
	_ = state.SaveRun(runPath, state.Run{At: result.At})

	sent, err := sync(opts, settingsPath)
	switch {
	case err != nil:
		result.Outcome, result.Buckets, result.Error = Failed, sent, err.Error()
	case sent == 0:
		result.Outcome = Nothing
	default:
		result.Outcome, result.Buckets = Sent, sent
	}
	return result, err
}

// sync is one pass, and says how many rollups the server took.
func sync(opts SyncOptions, settingsPath string) (int, error) {
	cfg, err := config.Load()
	if err != nil {
		return 0, err
	}
	if cfg == nil || cfg.APIKey == "" || cfg.APIURL == "" || cfg.DeviceID == "" {
		return 0, fmt.Errorf("not logged in: run pokegosu auth login first")
	}

	selected, err := selectProviders(opts.Providers)
	if err != nil {
		return 0, err
	}

	// The server ignores anything older anyway; this keeps a first run from
	// carrying months of logs across the network to be dropped.
	result, err := scan.Run(scan.Options{Roots: opts.Paths, Providers: selected, Since: cfg.EnrolledAt})
	if err != nil {
		return 0, err
	}
	report(opts.Quiet, result)

	cachePath := state.Path(settingsPath)
	cache := state.Load(cachePath, cfg.APIURL, cfg.DeviceID)

	pending := result.Rollups
	if opts.All {
		// Restating the whole ledger starts from nothing known. Otherwise a
		// run that fails half way records the batches that landed against a
		// cache that already claimed them, and the rest is never sent again.
		cache.Forget()
	} else {
		pending = cache.Changed(result.Rollups, time.Now())
	}
	if len(pending) == 0 {
		if !opts.Quiet {
			fmt.Println("nothing to send")
		}
		return 0, nil
	}

	client := coderapi.New(cfg.APIURL, cfg.APIKey)
	sent, sendErr := send(client, pending)

	// Whatever the server took, it holds — even if a later batch failed.
	// Recording it keeps the next run from sending those rows again.
	cache.Record(sent)
	if err := state.Save(cachePath, cache); err != nil {
		fmt.Fprintf(os.Stderr, "pokegosu: %v: %v\n", state.ErrNotSaved, err)
	}

	if sendErr != nil {
		return len(sent), explainSync(sendErr)
	}
	if !opts.Quiet {
		fmt.Printf("sent %s to %s\n", count(len(sent), "bucket", "buckets"), cfg.URL)
	}
	return len(sent), nil
}

// send uploads in batches and returns everything the server accepted, which
// on failure is the batches that landed before it.
func send(client *coderapi.Client, rollups []usage.Rollup) ([]usage.Rollup, error) {
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
// What could not be read goes to stderr even under --quiet: a hook's run
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
	switch {
	case coderapi.KeyRefused(err):
		// A key the server does not know and a machine somebody retired read
		// the same from here, and the way out of both is the same: a machine
		// is enrolled once, so this one starts again as a new machine.
		return fmt.Errorf("the server refused this machine's key: %s; "+
			"it may have been retired in the web. Delete this machine's settings "+
			"and run pokegosu auth login to enrol it as a new machine",
			err)
	case coderapi.GatewayRefused(err):
		return fmt.Errorf("the server rejected the request before it reached coder (%s); "+
			"check the settings login wrote", err)
	default:
		return err
	}
}
