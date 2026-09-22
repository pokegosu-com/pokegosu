// Command driver is the Go implementation of the tokenusage conformance
// driver: the smallest program that puts libs/go/tokenusage behind the
// protocol in tests/tokenusage/README.md, so the shared harness can check it.
//
// It holds no logic of its own. It calls the same entry points a Go client
// calls, and only turns arguments into options and the result into JSON.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/scan"
	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/usage"
)

func main() {
	if len(os.Args) != 4 || os.Args[1] != "scan" {
		fmt.Fprintln(os.Stderr, "usage: driver scan <provider> <logs directory>")
		os.Exit(2)
	}

	p := find(os.Args[2])
	if p == nil {
		fail("unknown_provider")
	}

	result, err := scan.Run(scan.Options{
		Providers: []provider.Provider{p},
		Roots:     []string{os.Args[3]},
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		fail("scan_failed")
	}

	rollups := result.Rollups
	if rollups == nil {
		rollups = []usage.Rollup{} // an empty scan is [], not null
	}
	if err := json.NewEncoder(os.Stdout).Encode(usage.Payload{Rollups: rollups}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func find(id string) provider.Provider {
	for _, p := range scan.Providers() {
		if p.ID() == id {
			return p
		}
	}
	return nil
}

// fail reports a failure the way the protocol asks: a kind, not a message,
// so that implementations in different languages can agree on it.
func fail(kind string) {
	_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"error": map[string]string{"kind": kind}})
	os.Exit(1)
}
