// Package transport is the HTTP these libraries share: one request shape, one
// error shape, and the rules about what not to follow.
//
// It is internal because what a client of pokegosu needs is the account and
// coder packages beside it; this is how they are built, not what they offer.
package transport

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
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

// CodeIs reports whether err is a failure one of our own functions described
// with this code. A gateway error carrying the same word is not one: nothing
// of ours answered, so the word does not mean what we mean by it.
func CodeIs(err error, code string) bool {
	var serverErr *Error
	return errors.As(err, &serverErr) && serverErr.FromServer && serverErr.Code == code
}

// StatusIs reports whether err came back with this status, whoever answered.
func StatusIs(err error, status int) bool {
	var serverErr *Error
	return errors.As(err, &serverErr) && serverErr.Status == status
}

func (c *Client) Post(ctx context.Context, function string, body, out any) error {
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
