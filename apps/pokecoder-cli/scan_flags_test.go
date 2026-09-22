package main

import "testing"

func TestSelectProviders(t *testing.T) {
	t.Run("none means all", func(t *testing.T) {
		got, err := selectProviders(nil)
		if err != nil {
			t.Fatalf("selectProviders: %v", err)
		}
		if got != nil {
			t.Errorf("got %v, want nil so that scan uses every provider", got)
		}
	})

	t.Run("by id", func(t *testing.T) {
		got, err := selectProviders([]string{"claude_code"})
		if err != nil {
			t.Fatalf("selectProviders: %v", err)
		}
		if len(got) != 1 || got[0].ID() != "claude_code" {
			t.Errorf("got %v, want the claude_code provider", got)
		}
	})

	// An unknown id has to fail rather than quietly scan nothing: --path
	// hands a directory to whichever providers are selected, and a typo
	// would report zero tokens for logs that are right there.
	t.Run("unknown id", func(t *testing.T) {
		_, err := selectProviders([]string{"codex"})
		if err == nil {
			t.Fatal("selectProviders succeeded, want an error naming the known providers")
		}
		if want := "claude_code"; !contains(err.Error(), want) {
			t.Errorf("error = %q, want it to list %q", err, want)
		}
	})
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
