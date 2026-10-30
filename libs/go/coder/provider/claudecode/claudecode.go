// Package claudecode parses Claude Code session logs.
//
// Logs live at ~/.claude/projects/**/*.jsonl, one JSON object per line, and
// only lines carrying .message.usage count. Three details decide whether the
// numbers come out right:
//
//   - Tokens are the sum of all four usage fields. Cache reads alone are
//     roughly 98% of the total, so leaving them out changes the result by two
//     orders of magnitude.
//   - Messages are deduplicated by .message.id. The same message is written
//     two or three times with identical usage; .uuid differs on every line and
//     using it inflates the total two- to threefold. The rest of the rule is
//     in usage.Aggregator.Add.
//   - The .iterations array repeats the top-level usage fields, so it is
//     ignored, except for an advisor's call, which the top level leaves out.
//
// Verified against Claude Code logs on 2026-09-12, and against ccusage's
// Claude adapter (rust/adapters/claude/src) on 2026-10-29.
package claudecode

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// ID is the providers.id value for Claude Code.
const ID = "claude_code"

// Parser reads Claude Code logs.
type Parser struct{}

// New returns a Parser.
func New() Parser { return Parser{} }

// ID implements provider.Provider.
func (Parser) ID() string { return ID }

// Roots implements provider.Provider.
//
// CLAUDE_CONFIG_DIR overrides the location and may list several directories
// separated by the platform's path separator. Otherwise both known config
// locations are scanned; deduplication by message id makes an overlap
// harmless.
func (Parser) Roots() ([]string, error) {
	if v := os.Getenv("CLAUDE_CONFIG_DIR"); v != "" {
		var roots []string
		for _, dir := range filepath.SplitList(v) {
			if dir = strings.TrimSpace(dir); dir != "" {
				roots = append(roots, filepath.Join(dir, "projects"))
			}
		}
		return roots, nil
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	return []string{
		filepath.Join(home, ".config", "claude", "projects"),
		filepath.Join(home, ".claude", "projects"),
	}, nil
}

// logLine is the subset of a log line we read. Everything else in the line,
// including fields added by future versions, is ignored by the decoder.
//
// requestId and isSidechain sit at the top level of the line, not inside
// message.
//
// The identifiers are pointers because a field that is absent and one that is
// an empty string mean different things: see parseLine.
type logLine struct {
	Timestamp   string  `json:"timestamp"`
	Version     *string `json:"version"`
	SessionID   *string `json:"sessionId"`
	RequestID   *string `json:"requestId"`
	IsSidechain bool    `json:"isSidechain"`
	Message     *struct {
		ID    *string      `json:"id"`
		Model *string      `json:"model"`
		Usage *usageFields `json:"usage"`
	} `json:"message"`
}

// usageFields is the token block of a log line.
type usageFields struct {
	tokenFields

	// Iterations repeat the top-level fields for the model's own turns, so
	// only an advisor's are read from them.
	Iterations []iteration `json:"iterations"`
}

type iteration struct {
	Type  string  `json:"type"`
	Model *string `json:"model"`
	tokenFields
}

// tokenFields are the four counts, wherever they appear.
type tokenFields struct {
	InputTokens              int64 `json:"input_tokens"`
	CacheCreationInputTokens int64 `json:"cache_creation_input_tokens"`
	CacheCreation            *struct {
		Ephemeral5m int64 `json:"ephemeral_5m_input_tokens"`
		Ephemeral1h int64 `json:"ephemeral_1h_input_tokens"`
	} `json:"cache_creation"`
	CacheReadInputTokens int64 `json:"cache_read_input_tokens"`
	OutputTokens         int64 `json:"output_tokens"`
}

// cacheCreationTokens prefers the per-lifetime breakdown over the flat field.
// The two agree in every line seen so far, but ccusage reads it this way and
// only the breakdown can distinguish the 1h cache, so the flat field is the
// fallback rather than the source.
func (u tokenFields) cacheCreationTokens() int64 {
	if u.CacheCreation != nil {
		return u.CacheCreation.Ephemeral5m + u.CacheCreation.Ephemeral1h
	}
	return u.CacheCreationInputTokens
}

// Parse implements provider.Provider. Files are visited in lexical order.
func (p Parser) Parse(root string, emit func(usage.Entry)) (provider.Stats, error) {
	var stats provider.Stats

	var files []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			// An unreadable subdirectory should not cost us the rest of the
			// tree; the count surfaces it to the user instead.
			stats.Unreadable++
			if d != nil && d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if !d.IsDir() && strings.HasSuffix(path, ".jsonl") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return stats, err
	}

	for _, path := range files {
		fileStats, err := p.parseFile(path, emit)
		stats.Add(fileStats)
		if err != nil {
			return stats, err
		}
	}
	return stats, nil
}

func (p Parser) parseFile(path string, emit func(usage.Entry)) (provider.Stats, error) {
	var stats provider.Stats

	f, err := os.Open(path)
	if err != nil {
		stats.Unreadable++
		return stats, nil
	}
	defer f.Close()
	stats.Files++

	// ReadBytes rather than bufio.Scanner: a line holding a large tool result
	// can exceed any fixed buffer, and Scanner would abandon the rest of the
	// file. It also hands back a final line with no newline, which is exactly
	// what a log being written to right now looks like.
	r := bufio.NewReaderSize(f, 64*1024)
	for {
		line, readErr := r.ReadBytes('\n')

		if trimmed := strings.TrimSpace(string(line)); trimmed != "" {
			stats.Lines++
			switch entries, status := parseLine(trimmed, sessionOf(path)); status {
			case statusEntry:
				for _, entry := range entries {
					stats.Entries++
					entry.Source = path
					emit(entry)
				}
			case statusBadRecord:
				stats.BadRecords++
			case statusBadLine:
				stats.BadLines++
			}
		}

		if readErr != nil {
			if errors.Is(readErr, io.EOF) {
				return stats, nil
			}
			return stats, readErr
		}
	}
}

// lineStatus is what one log line turned out to be.
type lineStatus int

const (
	statusSkip      lineStatus = iota // not a usage line
	statusEntry                       // a usage record
	statusBadLine                     // could not be decoded, usually a truncated write
	statusBadRecord                   // carries usage, but nothing we can trust
)

// sessionOf is the session a file holds when its lines do not say: Claude
// Code names each log after its session.
func sessionOf(path string) string {
	return strings.TrimSuffix(filepath.Base(path), ".jsonl")
}

// parseLine reads one log line into the message it records and any advisor
// calls made inside it. fallbackSession stands in for a line with no
// sessionId.
//
// A line is passed over, as ccusage passes it over, when its version is not a
// version or when it names a session, request, message or model as an empty
// string: absent and empty are different things there.
func parseLine(line, fallbackSession string) ([]usage.Entry, lineStatus) {
	var l logLine
	if err := json.Unmarshal([]byte(line), &l); err != nil {
		return nil, statusBadLine
	}
	if l.Message == nil || l.Message.Usage == nil {
		return nil, statusSkip
	}

	at, err := time.Parse(time.RFC3339, l.Timestamp)
	if err != nil {
		return nil, statusBadRecord
	}
	if (l.Version != nil && !isVersion(*l.Version)) ||
		isEmpty(l.SessionID) || isEmpty(l.RequestID) ||
		isEmpty(l.Message.ID) || isEmpty(l.Message.Model) {
		return nil, statusBadRecord
	}

	tokens, ok := l.Message.Usage.tokens()
	if !ok {
		return nil, statusBadRecord
	}

	base := usage.Entry{
		Provider:    ID,
		MessageID:   deref(l.Message.ID),
		RequestID:   deref(l.RequestID),
		SessionID:   deref(l.SessionID),
		IsSidechain: l.IsSidechain,
		At:          at,
		Tokens:      tokens,
	}
	if base.SessionID == "" {
		base.SessionID = fallbackSession
	}
	entries := []usage.Entry{base}

	// An advisor's call is billed apart from the message it sits in, and the
	// top-level usage does not include it. It is counted as a message of its
	// own, under an id ccusage gives it too, so its copies deduplicate like
	// any other.
	n := 0
	for _, it := range l.Message.Usage.Iterations {
		if it.Type != "advisor_message" || it.Model == nil || *it.Model == "" {
			continue
		}
		tokens, ok := it.tokens()
		if !ok {
			return nil, statusBadRecord
		}
		advisor := base
		if base.MessageID != "" {
			advisor.MessageID = fmt.Sprintf("%s:advisor:%d", base.MessageID, n)
		}
		advisor.Tokens = tokens
		entries = append(entries, advisor)
		n++
	}
	return entries, statusEntry
}

// tokens sums the four fields, and is not ok when any is negative.
func (u tokenFields) tokens() (int64, bool) {
	cacheCreation := u.cacheCreationTokens()
	if u.InputTokens < 0 || cacheCreation < 0 ||
		u.CacheReadInputTokens < 0 || u.OutputTokens < 0 {
		return 0, false
	}
	return u.InputTokens + cacheCreation + u.CacheReadInputTokens + u.OutputTokens, true
}

func isEmpty(s *string) bool { return s != nil && *s == "" }

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// isVersion reports whether s starts like a semantic version: digits, a dot,
// digits, a dot and a digit.
func isVersion(s string) bool {
	i := 0
	for part := 0; part < 2; part++ {
		start := i
		for i < len(s) && s[i] >= '0' && s[i] <= '9' {
			i++
		}
		if i == start || i >= len(s) || s[i] != '.' {
			return false
		}
		i++
	}
	return i < len(s) && s[i] >= '0' && s[i] <= '9'
}
