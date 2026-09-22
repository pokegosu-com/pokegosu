// Package provider defines what a log parser has to offer the scanner.
//
// Providers are the coding agents whose logs we read: claude_code today,
// Codex and Gemini CLI later. Each one owns its log location and its own
// quirks; everything downstream of Parse is shared.
package provider

import "github.com/pokegosu-com/pokegosu/libs/go/tokenusage/usage"

// Provider reads one agent's logs.
type Provider interface {
	// ID is the providers.id value rows are stored under.
	ID() string

	// Roots returns the directories to scan when the user names none, most
	// specific first. Directories that do not exist are allowed: the agent
	// may simply not be installed.
	Roots() ([]string, error)

	// Parse walks root and calls emit for every usage record it finds.
	// Lines it cannot read are counted in Stats rather than failing the
	// scan — a log being appended to right now has a half-written last
	// line, and that is not an error.
	Parse(root string, emit func(usage.Entry)) (Stats, error)
}

// Stats reports what a parse pass saw. The counters exist so that a bad line
// shows up as a warning instead of a quietly smaller number.
type Stats struct {
	Files      int // log files read
	Lines      int // non-empty lines read
	Entries    int // usage records emitted, before deduplication
	BadLines   int // lines that could not be decoded, usually a truncated write
	BadRecords int // usage lines missing an id, a timestamp, or with a negative count
	Unreadable int // files or directories that could not be opened
}

// Add sums another pass into s.
func (s *Stats) Add(o Stats) {
	s.Files += o.Files
	s.Lines += o.Lines
	s.Entries += o.Entries
	s.BadLines += o.BadLines
	s.BadRecords += o.BadRecords
	s.Unreadable += o.Unreadable
}
