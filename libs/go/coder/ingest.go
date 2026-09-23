// The coder service's client: what a machine sends once it has read its
// agents' logs into hourly totals.
//
// The reading is the packages beside this one — scan, usage, provider — and
// clients in other languages match them through tests/coder. This is the
// other half: handing those totals to the server.
package coder

import (
	"context"
	"fmt"
	"net/http"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
	"github.com/pokegosu-com/pokegosu/libs/go/internal/transport"
)

// Client reaches one deployment's Edge Functions, as one machine.
type Client struct {
	transport transport.Client
}

// New is a client for the API a deployment named, speaking as the machine
// that holds this key.
func New(apiURL, apiKey string) *Client {
	return &Client{transport: transport.Client{BaseURL: apiURL, APIKey: apiKey}}
}

// KeyRefused reports whether our own function turned down the machine's key,
// which a machine somebody retired reads the same as one that never existed.
//
// A 401 from the gateway is a different problem and must not be reported as
// this one: the key may be perfectly good and the request never reached us.
func KeyRefused(err error) bool {
	return transport.CodeIs(err, "unauthorized")
}

// GatewayRefused reports whether something in front of the functions turned
// the request away, which says nothing about the key it carried.
func GatewayRefused(err error) bool {
	return transport.StatusIs(err, http.StatusUnauthorized) && !KeyRefused(err)
}

// Ingest records this machine's rollups, and says how many the server took
// and how many it ignored as older than this machine's enrolment.
//
// Which machine they belong to comes from the key, so there is nothing to
// say about it here.
//
// The rollups are absolute values, so a batch that is sent twice, or split
// differently, lands on the same numbers.
func (c *Client) Ingest(ctx context.Context, rollups []usage.Rollup) (accepted, ignored int, err error) {
	body := struct {
		Rollups []usage.Rollup `json:"rollups"`
	}{Rollups: rollups}

	var took struct {
		Accepted int `json:"accepted"`
		Ignored  int `json:"ignored"`
	}
	if err := c.transport.Post(ctx, "ingest", body, &took); err != nil {
		return 0, 0, err
	}
	// Ignored rows are the server keeping its own rule, not a failure. Rows
	// that are neither taken nor ignored went missing, which is one.
	if took.Accepted+took.Ignored != len(rollups) {
		return took.Accepted, took.Ignored, fmt.Errorf(
			"the server took %d and ignored %d of %d rollups",
			took.Accepted, took.Ignored, len(rollups))
	}
	return took.Accepted, took.Ignored, nil
}
