// Package scan turns local agent logs into hourly rollups.
//
// This is the read half of sync, kept separate so it can be exercised without
// a server: `coder scan` prints what it found, `sync` uploads the same
// result. No network, no stored state.
package scan

import (
	"fmt"
	"os"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider/claudecode"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// Providers returns every provider the client knows how to read.
func Providers() []provider.Provider {
	return []provider.Provider{claudecode.New()}
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

	result.Rollups = agg.Rollups(opts.Since)
	result.Messages = agg.Messages()
	return result, nil
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
