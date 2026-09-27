// Command driver puts libs/go/coder behind this suite's protocol: given a
// directory of Codex logs, print the hourly rollups a Go client would
// send for them.
//
// It holds no logic of its own. It calls what a Go client calls, and only
// turns the result into JSON.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider/codex"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/scan"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: driver <logs directory>")
		os.Exit(2)
	}

	result, err := scan.Run(scan.Options{
		Providers: []provider.Provider{codex.New()},
		Roots:     []string{os.Args[1]},
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
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
