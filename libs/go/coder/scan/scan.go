// Package scan turns local agent logs into hourly rollups.
//
// This is the read half of sync, kept separate so it can be exercised without
// a server: `coder scan` prints what it found, `sync` uploads the same
// result. No network, and no stored state of its own: what an earlier scan
// kept comes in through Options.Kept.
package scan

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider/claudecode"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider/codex"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// Providers returns every provider the client knows how to read.
func Providers() []provider.Provider {
	return []provider.Provider{claudecode.New(), codex.New()}
}

// Options configures a scan.
type Options struct {
	// Providers to read. Empty means Providers().
	Providers []provider.Provider

	// Roots overrides the directories to scan and applies to every provider.
	// Empty means each provider's own default locations. A named root that
	// does not exist is an error; a default one that does not exist is not.
	Roots []string

	// Since drops buckets that start before it, rounded down to the hour so
	// that every bucket returned covers a full hour. Zero keeps everything.
	Since time.Time

	// Kept is what an earlier scan read, from Result.Records. A message in it
	// counts again only when every file it was read from is gone and no log
	// read now holds it: agents delete their own logs (Claude Code after
	// thirty days, Codex by compressing them), and the usage still happened.
	// A message whose file is still there is as that file says, so a count a
	// newer parser corrects can fall.
	Kept []usage.Record
}

// Result is what a scan found.
type Result struct {
	// Rollups are the hourly totals, ordered by hour then provider.
	Rollups []usage.Rollup

	// Messages is how many distinct messages the rollups were built from,
	// after deduplication.
	Messages int

	// Stats is the parse tally across every provider and root.
	Stats provider.Stats

	// Roots lists the directories actually read, in the order read.
	Roots []string

	// Records is every message to keep for the next scan: what was read
	// now, what of Kept still counts, and Kept's messages from providers not
	// read this time, untouched.
	Records []usage.Record

	// Restored is how many messages of Kept counted because their logs are
	// gone.
	Restored int
}

// Run parses the logs and returns the rollups.
//
// Every provider feeds one aggregator, because deduplication has to span the
// whole scan: a resumed session repeats its earlier messages in a new file,
// sometimes under a different root.
func Run(opts Options) (Result, error) {
	providers := opts.Providers
	if len(providers) == 0 {
		providers = Providers()
	}

	agg := usage.NewAggregator()
	result := Result{}

	for _, p := range providers {
		roots := opts.Roots
		if len(roots) == 0 {
			defaults, err := p.Roots()
			if err != nil {
				return result, fmt.Errorf("locating %s logs: %w", p.ID(), err)
			}
			roots = existing(defaults)
		} else {
			for _, root := range roots {
				if _, err := os.Stat(root); err != nil {
					return result, fmt.Errorf("reading %s: %w", root, err)
				}
			}
		}

		for _, root := range roots {
			stats, err := p.Parse(root, agg.Add)
			result.Stats.Add(stats)
			if err != nil {
				return result, fmt.Errorf("parsing %s logs in %s: %w", p.ID(), root, err)
			}
			result.Roots = append(result.Roots, root)
		}
	}

	read := make(map[string]bool, len(providers))
	for _, p := range providers {
		read[p.ID()] = true
	}
	var untouched []usage.Record
	for _, r := range opts.Kept {
		switch {
		case !read[r.Provider]:
			untouched = append(untouched, r)
		case gone(r.Sources) && agg.Restore(r):
			result.Restored++
		}
	}

	result.Rollups = agg.Rollups(opts.Since)
	result.Messages = agg.Messages()
	result.Records = append(agg.Records(), untouched...)
	return result, nil
}

// gone reports whether none of the files are there any more. A message with
// no file named is not one a deletion can explain, so it is not gone.
func gone(files []string) bool {
	if len(files) == 0 {
		return false
	}
	for _, f := range files {
		if _, err := os.Lstat(f); err == nil || !errors.Is(err, fs.ErrNotExist) {
			return false
		}
	}
	return true
}

// existing keeps the directories that are actually there. A provider's
// default location is absent whenever that agent is not installed, which is
// the normal case, not a failure.
func existing(dirs []string) []string {
	var found []string
	for _, dir := range dirs {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			found = append(found, dir)
		}
	}
	return found
}

// Total sums the rollups.
func (r Result) Total() int64 {
	var total int64
	for _, rollup := range r.Rollups {
		total += rollup.Tokens
	}
	return total
}
