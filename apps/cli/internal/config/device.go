package config

import (
	"crypto/rand"
	"fmt"
)

// NewDeviceID returns a random identifier for this machine.
//
// The client generates it rather than the server so that a machine keeps one
// identity: the first call already has an id to report, and a retried
// registration cannot create a second device.
func NewDeviceID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("generating a device id: %w", err)
	}

	// Version 4, variant 1, per RFC 4122.
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80

	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}
