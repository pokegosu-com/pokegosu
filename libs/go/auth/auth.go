// Package account is how a client in Go joins an account: finding the
// deployment it was pointed at, enrolling this machine with it, and asking
// afterwards which machine and whose it is.
//
// Enrolling belongs to the account rather than to any one service, because a
// machine is enrolled once and every service speaks with the key that leaves
// behind.
//
// Enrolling carries no key. It is what happens before there is one: the
// machine asks under a code it drew, a person approves it in the web, and the
// machine comes back for the key with the claim token the server gave it.
// Whoami is the one call made with the key that leaves behind.
package auth

import (
	"net/http"

	"github.com/pokegosu-com/pokegosu/libs/go/internal/transport"
)

// Client reaches one deployment's Edge Functions.
type Client struct {
	transport transport.Client
}

// New is a client for the API a deployment named, which Discover reports.
func New(apiURL string) *Client {
	return &Client{transport: transport.Client{BaseURL: apiURL}}
}

// DeviceTaken reports whether the machine id this client offered is already
// registered. The id is the machine's own, kept in its settings, so new
// settings are a new machine.
func DeviceTaken(err error) bool {
	return transport.CodeIs(err, "device_owned_by_another_account")
}

// CodeTaken reports whether another machine is already waiting on the code
// this one drew. Drawing again is the whole of the fix.
func CodeTaken(err error) bool {
	return transport.CodeIs(err, "enrollment_code_taken")
}

// RequestGone reports whether the enrolment this machine started is no longer
// waiting: expired, or already collected.
func RequestGone(err error) bool {
	return transport.CodeIs(err, "enrollment_not_found")
}

// GatewayRefused reports whether something in front of the functions turned
// the request away, which means it never reached us and says nothing about
// what it carried.
func GatewayRefused(err error) bool {
	return transport.StatusIs(err, http.StatusUnauthorized) && !KeyRefused(err)
}
