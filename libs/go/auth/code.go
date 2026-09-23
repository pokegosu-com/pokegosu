package auth

import (
	"crypto/rand"
	"fmt"
)

// The alphabet drops the four characters people confuse — I, L, O and U —
// which also keeps a code from spelling anything. The server folds them back
// to the digits they were mistaken for, so reading a 1 as an I is not a
// wrong code.
const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

const codeLength = 8

// newCode draws the code this machine will ask to be approved under.
//
// The machine draws it rather than the server so that what a person reads off
// this terminal cannot have come from anywhere else: approving is approving
// the code in front of them.
//
// The alphabet is 32 characters and a byte holds 256 values, so taking each
// byte modulo 32 is uniform — 32 divides 256 exactly, and the modulo bias
// that usually haunts this has nowhere to come from.
//
// Eight characters over 32 is about a trillion codes. That is only half the
// argument: a code lives ten minutes, works once, and takes a signed-in
// person to be worth anything.
func newCode() (string, error) {
	bytes := make([]byte, codeLength)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("drawing an enrollment code: %w", err)
	}

	code := make([]byte, codeLength)
	for i, b := range bytes {
		code[i] = alphabet[int(b)%len(alphabet)]
	}
	return string(code), nil
}

// Format is how a code is shown: split in half, because eight characters in a
// row are hard to keep your place in. The server reads either.
func Format(code string) string {
	if len(code) != codeLength {
		return code
	}
	return code[:4] + "-" + code[4:]
}
