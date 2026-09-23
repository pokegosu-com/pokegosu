// Package api talks to the server's Edge Functions.
//
// One header carries a credential: x-api-key, this machine's key, which is
// what the functions check. It is never logged.
//
// Enrolment is the exception — it runs before there is a key, and the code it
// carries is the whole credential.
package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// Client reaches one deployment.
type Client struct {
	BaseURL string
	APIKey  string

	// HTTP is the transport. A zero value uses a client with a timeout,
	// because a sync is run by cron and must not hang forever.
	HTTP *http.Client
}

// Error is a failure the other end described.
type Error struct {
	Status  int
	Code    string
	Message string

	// FromServer marks an error our own functions produced, as opposed to
	// one from whatever sits in front of them. Only then does the code mean
	// what this package thinks it means.
	FromServer bool
}

func (e *Error) Error() string {
	if e.Message == "" {
		return fmt.Sprintf("server returned HTTP %d", e.Status)
	}
	return e.Message
}

// KeyRefused reports whether our own function rejected the API key. A 401
// from the gateway is a different problem and must not be reported as this
// one: the key may be perfectly good and the request never reached us.
func (e *Error) KeyRefused() bool {
	return e.FromServer && e.Status == http.StatusUnauthorized
}

// DeviceTaken reports whether the device id belongs to another account.
func (e *Error) DeviceTaken() bool {
	return e.FromServer && e.Code == "device_owned_by_another_account"
}

// CodeTaken reports whether another machine is already waiting on the code
// this one drew. Drawing again is the whole of the fix.
func (e *Error) CodeTaken() bool {
	return e.FromServer && e.Code == "enrollment_code_taken"
}

// RequestGone reports whether the enrolment this machine started is no longer
// waiting: expired, or already collected.
func (e *Error) RequestGone() bool {
	return e.FromServer && e.Code == "enrollment_not_found"
}

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
	if err := c.post(ctx, "start-enrollment", body, &started); err != nil {
		return Enrollment{}, err
	}

	expires, err := time.Parse(time.RFC3339, started.ExpiresAt)
	// Something else at that address can answer 201 with anything. A reply
	// with no token, or no deadline, did not start an enrolment.
	if started.ClaimToken == "" || err != nil {
		return Enrollment{}, fmt.Errorf(
			"the server at %s did not answer like pokegosu; check --url", c.BaseURL)
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
	}
	if err := c.post(ctx, "claim-enrollment", map[string]string{"claim_token": claimToken}, &claimed); err != nil {
		return Claim{}, err
	}

	if claimed.APIKey == "" {
		// 202 and a status, or something that is not an answer at all; both
		// mean "not yet", and the caller asks again until the deadline.
		return Claim{Waiting: true}, nil
	}
	return Claim{APIKey: claimed.APIKey, DeviceName: claimed.DeviceName}, nil
}

// Ingest records this machine's rollups and returns how many the server took.
//
// Which machine they belong to comes from the key, so there is nothing to
// say about it here.
//
// The rollups are absolute values, so a batch that is sent twice, or split
// differently, lands on the same numbers.
func (c *Client) Ingest(ctx context.Context, rollups []usage.Rollup) (int, error) {
	body := struct {
		Rollups []usage.Rollup `json:"rollups"`
	}{Rollups: rollups}

	var accepted struct {
		Accepted int `json:"accepted"`
	}
	if err := c.post(ctx, "ingest", body, &accepted); err != nil {
		return 0, err
	}
	if accepted.Accepted != len(rollups) {
		return accepted.Accepted, fmt.Errorf(
			"the server took %d of %d rollups", accepted.Accepted, len(rollups))
	}
	return accepted.Accepted, nil
}

func (c *Client) post(ctx context.Context, function string, body, out any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("encoding the request: %w", err)
	}

	url := fmt.Sprintf("%s/functions/v1/%s", c.BaseURL, function)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(encoded))
	if err != nil {
		return fmt.Errorf("building the request: %w", err)
	}
	req.Header.Set("content-type", "application/json")
	// Empty during enrolment, which is the one call made without a key.
	if c.APIKey != "" {
		req.Header.Set("x-api-key", c.APIKey)
	}

	resp, err := c.http().Do(req)
	if err != nil {
		return fmt.Errorf("calling %s: %w", url, err)
	}
	defer resp.Body.Close()

	// Enough to hold an error message, not enough for a bad address to feed
	// us a response until we run out of memory.
	payload, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("reading the response from %s: %w", url, err)
	}

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return serverError(resp.StatusCode, payload)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(payload, out); err != nil {
		return fmt.Errorf("reading the response from %s: %w", url, err)
	}
	return nil
}

// serverError reads whatever answered.
//
// Our functions use one error shape, but they are not the only thing that can
// reply: Supabase's gateway turns away a request before it reaches them and
// reports that its own way. Reading both matters because the two mean
// completely different things — a rejected credential against a request that
// never arrived — and a client told the wrong one goes looking in the wrong
// place.
func serverError(status int, payload []byte) error {
	var body struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`

		// The gateway's shape. Its "code" is left out on purpose: it is a
		// number in some replies and a string in others, and declaring
		// either type makes the whole document fail to decode, costing us
		// the message as well.
		Message string `json:"message"`
	}

	if err := json.Unmarshal(payload, &body); err == nil {
		if body.Error.Message != "" {
			return &Error{
				Status:     status,
				Code:       body.Error.Code,
				Message:    body.Error.Message,
				FromServer: true,
			}
		}
		if body.Message != "" {
			return &Error{Status: status, Message: body.Message}
		}
	}
	return &Error{Status: status}
}

func (c *Client) http() *http.Client {
	if c.HTTP == nil {
		return &http.Client{Timeout: 30 * time.Second, CheckRedirect: refuseRedirect}
	}
	if c.HTTP.CheckRedirect != nil {
		return c.HTTP
	}
	// Someone supplying a transport is thinking about proxies or timeouts,
	// not about the fact that Go will hand x-api-key to a redirect target.
	// They should not have to remember it.
	safe := *c.HTTP
	safe.CheckRedirect = refuseRedirect
	return &safe
}

// refuseRedirect stops the client from following a redirect.
//
// Go drops Authorization when a redirect crosses to another host, but it has
// no idea that x-api-key or apikey are credentials and forwards both. Our
// endpoints never redirect, so anything that does is either a misconfigured
// address or something trying to collect the key, and neither is worth
// following.
func refuseRedirect(req *http.Request, via []*http.Request) error {
	return fmt.Errorf("refusing to follow a redirect to %s: the API key would travel with it", req.URL.Host)
}
