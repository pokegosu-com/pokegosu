package auth

import (
	"strings"
	"testing"
)

func TestNewCodeIsDrawnFromTheUnambiguousAlphabet(t *testing.T) {
	seen := map[string]bool{}

	for range 200 {
		code, err := newCode()
		if err != nil {
			t.Fatal(err)
		}
		if len(code) != codeLength {
			t.Fatalf("code %q is %d characters, want %d", code, len(code), codeLength)
		}
		for _, c := range code {
			if !strings.ContainsRune(alphabet, c) {
				t.Fatalf("code %q holds %q, which is not in the alphabet", code, c)
			}
		}
		seen[code] = true
	}

	// Not a test of randomness, only that the source is one at all: a
	// constant would show up here immediately.
	if len(seen) < 190 {
		t.Errorf("200 draws gave %d different codes", len(seen))
	}
}

func TestFormatSplitsTheCodeInHalf(t *testing.T) {
	if got := format("XPTQ4F2K"); got != "XPTQ-4F2K" {
		t.Errorf("format() = %q, want %q", got, "XPTQ-4F2K")
	}
	// Whatever a --code flag carried is shown as it is rather than mangled.
	if got := format("xptq-4f2k"); got != "xptq-4f2k" {
		t.Errorf("format() = %q, want it left alone", got)
	}
}
