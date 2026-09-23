package account

import (
	"context"
	"fmt"
	"time"
)

// Enrollment is what the server hands back when a machine asks to be let in.
type Enrollment struct {
	// ClaimToken is how this machine proves it is the one that asked, when
	// it comes back for the key. The server made it; nothing else has it.
	ClaimToken string

	// ExpiresAt is when the request stops being approvable.
	ExpiresAt time.Time
}

// StartEnrollment asks to be let in under a code this machine drew.
//
// It is one of the two calls made without a key, because they are where the
// key comes from. Nothing here is worth anything until a person approves it.
func (c *Client) StartEnrollment(ctx context.Context, code, deviceID, deviceName string) (Enrollment, error) {
	body := map[string]string{
		"code":        code,
		"device_id":   deviceID,
		"device_name": deviceName,
	}

	var started struct {
		ClaimToken string `json:"claim_token"`
		ExpiresAt  string `json:"expires_at"`
	}
	if err := c.transport.Post(ctx, "start-enrollment", body, &started); err != nil {
		return Enrollment{}, err
	}

	expires, err := time.Parse(time.RFC3339, started.ExpiresAt)
	// Something else at that address can answer 201 with anything. A reply
	// with no token, or no deadline, did not start an enrolment.
	if started.ClaimToken == "" || err != nil {
		return Enrollment{}, fmt.Errorf(
			"the server at %s did not answer like pokegosu; check --url", c.transport.BaseURL)
	}
	return Enrollment{ClaimToken: started.ClaimToken, ExpiresAt: expires}, nil
}

// Claim is the answer to asking whether the machine has been let in yet.
type Claim struct {
	// Waiting is true while nobody has approved the request. The caller is
	// meant to ask again.
	Waiting bool

	// APIKey is this machine's own credential, handed over once.
	APIKey string

	// DeviceName is what the account will call this machine, which is what
	// the person approved.
	DeviceName string

	// EnrolledAt is when this machine was first let in, by the server's
	// clock. Enrolling again does not move it.
	EnrolledAt time.Time
}

// ClaimEnrollment collects the key, if a person has approved the request.
//
// The key is minted for this call, so the answer is the only copy that will
// ever exist outside the digest the server keeps.
func (c *Client) ClaimEnrollment(ctx context.Context, claimToken string) (Claim, error) {
	var claimed struct {
		Status     string `json:"status"`
		APIKey     string `json:"api_key"`
		DeviceName string `json:"device_name"`
		EnrolledAt string `json:"enrolled_at"`
	}
	if err := c.transport.Post(ctx, "claim-enrollment", map[string]string{"claim_token": claimToken}, &claimed); err != nil {
		return Claim{}, err
	}

	if claimed.APIKey == "" {
		// 202 and a status, or something that is not an answer at all; both
		// mean "not yet", and the caller asks again until the deadline.
		return Claim{Waiting: true}, nil
	}
	// A server that hands over a key without saying when this machine was
	// enrolled leaves the zero time, which reads as "no floor" rather than
	// as "everything is too old to send".
	enrolled, _ := time.Parse(time.RFC3339, claimed.EnrolledAt)
	return Claim{APIKey: claimed.APIKey, DeviceName: claimed.DeviceName, EnrolledAt: enrolled}, nil
}
