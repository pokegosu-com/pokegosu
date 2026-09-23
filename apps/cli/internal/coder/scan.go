package coder

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/scan"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// ScanOptions is what a person can tell scan.
type ScanOptions struct {
	// Since, when set, is YYYY-MM-DD (UTC) or a full RFC3339 timestamp.
	// Rounded down to the hour, so the hour containing it is printed whole.
	Since string

	// Format is "text" or "json". The json form is the body the ingest
	// endpoint takes.
	Format string

	// Paths read these directories instead of the default log locations.
	Paths []string

	// Providers read only these agents' logs, by id. Needed alongside Paths
	// once there is more than one provider, since a log directory belongs to
	// one agent.
	Providers []string
}

// Scan parses the local agent logs and prints hourly token rollups. Nothing
// is sent anywhere.
func Scan(opts ScanOptions) error {
	if opts.Format == "" {
		opts.Format = "text"
	}
	if opts.Format != "text" && opts.Format != "json" {
		return fmt.Errorf("unknown format %q: want text or json", opts.Format)
	}

	selected, err := selectProviders(opts.Providers)
	if err != nil {
		return err
	}

	scanOpts := scan.Options{Roots: opts.Paths, Providers: selected}
	if opts.Since != "" {
		at, err := parseSince(opts.Since)
		if err != nil {
			return err
		}
		scanOpts.Since = at
	}

	result, err := scan.Run(scanOpts)
	if err != nil {
		return err
	}

	warn(result, opts.Paths)

	if opts.Format == "json" {
		return printJSON(result.Rollups)
	}
	printText(result)
	return nil
}

// selectProviders resolves --provider values to parsers. No values means
// every provider, which is what a plain scan does.
//
// --path applies to whichever providers are selected, so naming one matters
// as soon as there is more than a single provider: a log directory belongs to
// one agent, and handing it to another agent's parser is meaningless at best.
func selectProviders(ids []string) ([]provider.Provider, error) {
	if len(ids) == 0 {
		return nil, nil
	}

	known := make(map[string]provider.Provider, len(scan.Providers()))
	var names []string
	for _, p := range scan.Providers() {
		known[p.ID()] = p
		names = append(names, p.ID())
	}

	var selected []provider.Provider
	for _, id := range ids {
		p, ok := known[id]
		if !ok {
			return nil, fmt.Errorf("unknown provider %q: want one of %s", id, strings.Join(names, ", "))
		}
		selected = append(selected, p)
	}
	return selected, nil
}

// parseSince accepts a plain UTC date or a full RFC3339 timestamp.
func parseSince(s string) (time.Time, error) {
	if at, err := time.Parse("2006-01-02", s); err == nil {
		return at.UTC(), nil
	}
	if at, err := time.Parse(time.RFC3339, s); err == nil {
		return at.UTC(), nil
	}
	return time.Time{}, fmt.Errorf("cannot read --since %q: want YYYY-MM-DD or RFC3339", s)
}

// warn reports what the scan could not read. These go to stderr so that
// redirecting stdout into a fixture stays clean, and they are counts rather
// than failures: a log being appended to right now has a half-written last
// line, and an agent that is not installed has no directory at all.
func warn(result scan.Result, paths []string) {
	if len(result.Roots) == 0 && len(paths) == 0 {
		var looked []string
		for _, p := range scan.Providers() {
			roots, err := p.Roots()
			if err != nil {
				continue
			}
			looked = append(looked, roots...)
		}
		fmt.Fprintf(os.Stderr, "pokegosu: no logs found; looked in %s\n", strings.Join(looked, ", "))
	}

	s := result.Stats
	if s.BadLines > 0 {
		fmt.Fprintf(os.Stderr, "pokegosu: skipped %s that could not be decoded (truncated write?)\n",
			count(s.BadLines, "line", "lines"))
	}
	if s.BadRecords > 0 {
		fmt.Fprintf(os.Stderr, "pokegosu: skipped %s with usage but no usable message id or timestamp\n",
			count(s.BadRecords, "line", "lines"))
	}
	if s.Unreadable > 0 {
		fmt.Fprintf(os.Stderr, "pokegosu: skipped %s that could not be opened\n",
			count(s.Unreadable, "file", "files"))
	}
}

// printJSON writes the ingest request body, so `scan --format json` can be
// piped straight at the endpoint or saved as a fixture.
func printJSON(rollups []usage.Rollup) error {
	if rollups == nil {
		rollups = []usage.Rollup{} // an empty scan is [], not null
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(usage.Payload{Rollups: rollups})
}

func printText(result scan.Result) {
	if len(result.Rollups) == 0 {
		fmt.Println("no usage found")
		return
	}

	providerWidth := len("provider")
	tokenWidth := len("tokens")
	for _, r := range result.Rollups {
		providerWidth = max(providerWidth, len(r.Provider))
		tokenWidth = max(tokenWidth, len(thousands(r.Tokens)))
	}

	fmt.Printf("%-20s  %-*s  %*s\n", "hour (UTC)", providerWidth, "provider", tokenWidth, "tokens")
	for _, r := range result.Rollups {
		fmt.Printf("%-20s  %-*s  %*s\n",
			r.HourBucket.UTC().Format(time.RFC3339),
			providerWidth, r.Provider,
			tokenWidth, thousands(r.Tokens))
	}

	fmt.Printf("\n%s, %s tokens (%s, %s)\n",
		count(len(result.Rollups), "bucket", "buckets"),
		thousands(result.Total()),
		count(result.Messages, "message", "messages"),
		count(result.Stats.Files, "file", "files"))
}

// thousands groups digits so that a nine-digit token count stays readable.
func thousands(n int64) string {
	s := strconv.FormatInt(n, 10)
	var b strings.Builder
	for i := range len(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func count(n int, singular, plural string) string {
	if n == 1 {
		return "1 " + singular
	}
	return thousands(int64(n)) + " " + plural
}
