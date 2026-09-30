package auth

import (
	"context"

	"github.com/pokegosu-com/pokegosu/libs/go/internal/transport"
)

// KeyRefused reports whether our own function turned down the machine's key:
// one never known, or one already retired, which read the same.
func KeyRefused(err error) bool {
	return transport.CodeIs(err, "unauthorized")
}

// Retire retires the machine that holds this key, the same retirement the web
// does. It is final: the key stops working, the machine keeps the history it
// earned, and the next enrolment is a new machine with an id of its own.
//
// It answers with the name the account knew the machine by.
func (c *Client) Retire(ctx context.Context, apiKey string) (string, error) {
	keyed := c.transport
	keyed.APIKey = apiKey

	var retired struct {
		DeviceName string `json:"device_name"`
	}
	if err := keyed.Post(ctx, "retire-device", struct{}{}, &retired); err != nil {
		return "", err
	}
	return retired.DeviceName, nil
}
