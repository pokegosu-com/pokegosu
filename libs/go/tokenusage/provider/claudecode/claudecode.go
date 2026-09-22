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
//     using it inflates the total two- to threefold.
//   - The .iterations array repeats the top-level usage fields, so it is
//     ignored. Adding it in would double-count.
//
// Verified against Claude Code logs on 2026-09-12.
package claudecode

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/tokenusage/usage"
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
// requestId, sessionId and isSidechain sit at the top level of the line, not
// inside message.
type logLine struct {
	Timestamp   string `json:"timestamp"`
	RequestID   string `json:"requestId"`
	SessionID   string `json:"sessionId"`
	IsSidechain bool   `json:"isSidechain"`
	Message     *struct {
		ID    string       `json:"id"`
		Usage *usageFields `json:"usage"`
	} `json:"message"`
}

// usageFields is the token block of a log line.
type usageFields struct {
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
func (u usageFields) cacheCreationTokens() int64 {
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
			switch entry, status := parseLine(trimmed); status {
			case statusEntry:
				stats.Entries++
				emit(entry)
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

// parseLine reads one log line.
func parseLine(line string) (usage.Entry, lineStatus) {
	var l logLine
	if err := json.Unmarshal([]byte(line), &l); err != nil {
		return usage.Entry{}, statusBadLine
	}
	if l.Message == nil || l.Message.Usage == nil {
		return usage.Entry{}, statusSkip
	}

	if l.Message.ID == "" {
		// Without an id the message cannot be deduplicated, and counting it
		// would inflate the total by the two or three copies the log holds.
		return usage.Entry{}, statusBadRecord
	}
	at, err := time.Parse(time.RFC3339, l.Timestamp)
	if err != nil {
		return usage.Entry{}, statusBadRecord
	}

	u := l.Message.Usage
	cacheCreation := u.cacheCreationTokens()
	if u.InputTokens < 0 || cacheCreation < 0 ||
		u.CacheReadInputTokens < 0 || u.OutputTokens < 0 {
		return usage.Entry{}, statusBadRecord
	}

	return usage.Entry{
		Provider:    ID,
		SessionID:   l.SessionID,
		MessageID:   l.Message.ID,
		RequestID:   l.RequestID,
		IsSidechain: l.IsSidechain,
		At:          at,
		Tokens: u.InputTokens + cacheCreation +
			u.CacheReadInputTokens + u.OutputTokens,
	}, statusEntry
}
