package auth

import (
	"context"
	"fmt"
)

// Identity is which machine a key belongs to, and whose.
type Identity struct {
	DeviceID   string
	DeviceName string

	// DisplayName is what the account is called now. Empty for an account
	// that has not picked a handle yet.
	DisplayName string
}

// Whoami asks which machine holds apiKey, and whose it is.
//
// It is the one call here made with a key: the others are how a machine gets
// one. The client stays keyless, so the key is passed for this call alone.
func (c *Client) Whoami(ctx context.Context, apiKey string) (Identity, error) {
	keyed := c.transport
	keyed.APIKey = apiKey

	var found struct {
		DeviceID    string  `json:"device_id"`
		DeviceName  string  `json:"device_name"`
		DisplayName *string `json:"display_name"`
	}
	if err := keyed.Post(ctx, "whoami", struct{}{}, &found); err != nil {
		return Identity{}, err
	}
	// Something else at that address can answer 200 with anything. A reply
	// that names no machine did not come from us.
	if found.DeviceID == "" {
		return Identity{}, fmt.Errorf(
			"the server at %s did not answer like pokegosu", c.transport.BaseURL)
	}

	id := Identity{DeviceID: found.DeviceID, DeviceName: found.DeviceName}
	if found.DisplayName != nil {
		id.DisplayName = *found.DisplayName
	}
	return id, nil
}
