// Package codex parses Codex session logs.
//
// Logs live at ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, and at
// archived_sessions/ beside it once Codex archives a session. One JSON object
// per line, and only event_msg lines whose payload is a token_count count.
// Four details decide whether the numbers come out right:
//
//   - A token_count carries two usages: last_token_usage, what the turn just
//     spent, and total_token_usage, the session's running sum. The turn's own
//     usage is counted; when a line has only the running sum, the previous
//     sum is subtracted from it.
//   - The same token_count is written again with an unchanged running sum,
//     for instance when only the rate limits moved. A sum that has not moved
//     is not a new turn, whatever last_token_usage says.
//   - Tokens are total_tokens, which is input plus output. Cached input is
//     already inside input, and reasoning inside output, so neither is added
//     again. A zero total means the field is missing, not that the turn was
//     free, so it is worked out from input and output instead.
//   - A forked session, and a sub-agent's, starts by replaying its parent's
//     history into its own log. Those turns were spent once, by the parent,
//     and are skipped — see replayed.
//
// Codex writes no message id, so a turn is known by when it happened and what
// it spent: a copy of the same log, archived or resumed, lands on the same
// turns and deduplicates away.
//
// These rules follow ccusage's Codex adapter (rust/adapters/codex), checked
// on 2026-09-27.
package codex

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/provider"
	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// ID is the providers.id value for Codex.
const ID = "codex"

// Parser reads Codex logs.
type Parser struct{}

// New returns a Parser.
func New() Parser { return Parser{} }

// ID implements provider.Provider.
func (Parser) ID() string { return ID }

// Roots implements provider.Provider.
//
// CODEX_HOME moves Codex's whole directory, logs included. Archived sessions
// are read too: archiving a session does not take back what it spent.
func (Parser) Roots() ([]string, error) {
	home := strings.TrimSpace(os.Getenv("CODEX_HOME"))
	if home == "" {
		dir, err := os.UserHomeDir()
		if err != nil {
			return nil, err
		}
		home = filepath.Join(dir, ".codex")
	}
	return []string{
		filepath.Join(home, "sessions"),
		filepath.Join(home, "archived_sessions"),
	}, nil
}

// logLine is the subset of a log line we read. Everything else in the line,
// including fields added by future versions, is ignored by the decoder.
type logLine struct {
	Timestamp string `json:"timestamp"`
	Type      string `json:"type"`
	Payload   *struct {
		Type  string `json:"type"`
		Model string `json:"model"`

		// session_meta
		ID           string          `json:"id"`
		ForkedFromID string          `json:"forked_from_id"`
		Source       json.RawMessage `json:"source"`

		// token_count
		Info *struct {
			Model string      `json:"model"`
			Last  *tokenUsage `json:"last_token_usage"`
			Total *tokenUsage `json:"total_token_usage"`
		} `json:"info"`
	} `json:"payload"`
}

// tokenUsage is one usage block. Cached input is part of input, and
// reasoning part of output; both are kept only so that two turns are told
// apart by everything they recorded.
type tokenUsage struct {
	Input     int64 `json:"input_tokens"`
	Cached    int64 `json:"cached_input_tokens"`
	Output    int64 `json:"output_tokens"`
	Reasoning int64 `json:"reasoning_output_tokens"`
	Total     int64 `json:"total_tokens"`
}

func (u tokenUsage) negative() bool {
	return u.Input < 0 || u.Cached < 0 || u.Output < 0 || u.Reasoning < 0 || u.Total < 0
}

func (u tokenUsage) zero() bool {
	return u == tokenUsage{}
}

// tokens is what the turn consumed, cache included.
func (u tokenUsage) tokens() int64 {
	if u.Total > 0 {
		return u.Total
	}
	return u.Input + u.Output
}

// minus is what u adds to prev. A running sum is not supposed to shrink; a
// field that does counts as nothing rather than as a refund.
func (u tokenUsage) minus(prev *tokenUsage) tokenUsage {
	if prev == nil {
		return u
	}
	sub := func(a, b int64) int64 { return max(a-b, 0) }
	return tokenUsage{
		Input:     sub(u.Input, prev.Input),
		Cached:    sub(u.Cached, prev.Cached),
		Output:    sub(u.Output, prev.Output),
		Reasoning: sub(u.Reasoning, prev.Reasoning),
		Total:     sub(u.tokens(), prev.tokens()),
	}
}

// turn is one usage record read from a file, before replays are skipped.
type turn struct {
	at    time.Time
	model string
	usage tokenUsage
}

// session is what one log file holds.
type session struct {
	// id and parentID come from the session_meta line that opens the file.
	// A parent means the log starts by replaying the parent's history.
	id       string
	parentID string
	started  time.Time

	turns []turn

	// burst is when the first two usage lines were written, used to spot a
	// replay when the parent's log is not there to compare against.
	burst []time.Time
}

// Parse implements provider.Provider. Files are visited in lexical order.
//
// Every file is read before any turn is emitted, because whether a turn in
// one file counts can depend on another file: the parent it was forked from.
// Only a parent under the same root is found; one elsewhere falls back to
// how the replay was written.
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
	sort.Strings(files)

	var sessions []*session
	byID := make(map[string][]*session)
	for _, path := range files {
		s, fileStats, err := parseFile(path)
		stats.Add(fileStats)
		if err != nil {
			return stats, err
		}
		if s == nil {
			continue
		}
		sessions = append(sessions, s)
		if s.id != "" {
			byID[s.id] = append(byID[s.id], s)
		}
	}

	for _, s := range sessions {
		for _, t := range s.turns[replayed(s, parentOf(s, byID)):] {
			stats.Entries++
			emit(entryOf(t))
		}
	}
	return stats, nil
}

// parentOf finds the log a session was forked from, if it was and the log is
// here.
func parentOf(s *session, byID map[string][]*session) *session {
	if s.parentID == "" {
		return nil
	}
	for _, candidate := range byID[s.parentID] {
		if candidate != s {
			return candidate
		}
	}
	return nil
}

// burstPause is the longest pause inside a replay that Codex wrote in one go.
//
// ccusage measured replays that took 10 to 40ms to write, followed by 5.8 to
// 15.3 seconds before the session's own first turn, so a second sits well
// clear of both.
const burstPause = time.Second

// replayed says how many of a forked session's leading turns are its
// parent's history, written again.
//
// With the parent's log at hand, that is how many turns match the parent's,
// in order, up to the moment of the fork. Without it, or when Codex rewrote
// the copied history so that nothing matches, it is the burst the log opens
// with: history is written all at once, while a turn of one's own follows a
// pause.
func replayed(s *session, parent *session) int {
	if s.parentID == "" {
		return 0
	}

	if parent != nil {
		n := 0
		for _, t := range parent.turns {
			// What the parent did after the fork was never replayed.
			if !s.started.IsZero() && t.at.After(s.started) {
				break
			}
			if n >= len(s.turns) || s.turns[n].usage != t.usage {
				break
			}
			n++
		}
		if n > 0 {
			return n
		}
	}

	if len(s.burst) < 2 || !within(s.burst[0], s.burst[1]) {
		return 0
	}
	last := s.burst[0]
	n := 0
	for _, t := range s.turns {
		if !within(last, t.at) {
			break
		}
		last = t.at
		n++
	}
	return n
}

// within reports whether b was written no more than burstPause after a.
func within(a, b time.Time) bool {
	d := b.Sub(a)
	return d >= 0 && d <= burstPause
}

// entryOf turns a turn into the entry the aggregator deduplicates.
//
// Codex has no message id, so what the turn recorded stands in for one, and
// with no request id the aggregator matches the timestamp as well. There is
// no session either: a resumed or archived copy of a log is the same turns,
// in whichever file they turn up.
func entryOf(t turn) usage.Entry {
	u := t.usage
	return usage.Entry{
		Provider: ID,
		MessageID: fmt.Sprintf("%s/%d/%d/%d/%d/%d",
			t.model, u.Input, u.Cached, u.Output, u.Reasoning, u.Total),
		At:     t.at,
		Tokens: u.tokens(),
	}
}

// Lines that can matter carry one of these. Codex logs every message and tool
// result in full, and decoding each of those only to throw it away is most of
// the cost of a scan.
var (
	markTokenCount  = []byte(`"token_count"`)
	markTurnContext = []byte(`"turn_context"`)
	markSessionMeta = []byte(`"session_meta"`)
)

func parseFile(path string) (*session, provider.Stats, error) {
	var stats provider.Stats

	f, err := os.Open(path)
	if err != nil {
		stats.Unreadable++
		return nil, stats, nil
	}
	defer f.Close()
	stats.Files++

	s := &session{}
	var prev *tokenUsage
	var model string

	// ReadBytes rather than bufio.Scanner: a line holding a large tool result
	// can exceed any fixed buffer, and Scanner would abandon the rest of the
	// file. It also hands back a final line with no newline, which is exactly
	// what a log being written to right now looks like.
	r := bufio.NewReaderSize(f, 64*1024)
	for {
		line, readErr := r.ReadBytes('\n')

		if trimmed := bytes.TrimSpace(line); len(trimmed) > 0 {
			stats.Lines++
			if bytes.Contains(trimmed, markTokenCount) ||
				bytes.Contains(trimmed, markTurnContext) ||
				bytes.Contains(trimmed, markSessionMeta) {
				switch parseLine(trimmed, s, &prev, &model) {
				case statusEntry:
					// Counted in Parse, once replays are skipped.
				case statusBadRecord:
					stats.BadRecords++
				case statusBadLine:
					stats.BadLines++
				}
			}
		}

		if readErr != nil {
			if errors.Is(readErr, io.EOF) {
				return s, stats, nil
			}
			return s, stats, readErr
		}
	}
}

// lineStatus is what one log line turned out to be.
type lineStatus int

const (
	statusSkip      lineStatus = iota // not a usage line, or one that adds nothing
	statusEntry                       // a turn's usage
	statusBadLine                     // could not be decoded, usually a truncated write
	statusBadRecord                   // carries usage, but nothing we can trust
)

// parseLine reads one log line into s. prev is the session's running sum so
// far, and model the model the session last said it was using.
func parseLine(line []byte, s *session, prev **tokenUsage, model *string) lineStatus {
	var l logLine
	if err := json.Unmarshal(line, &l); err != nil {
		return statusBadLine
	}
	if l.Payload == nil {
		return statusSkip
	}

	switch l.Type {
	case "session_meta":
		if s.id == "" {
			s.id = l.Payload.ID
			s.parentID = l.Payload.ForkedFromID
			if s.parentID == "" {
				s.parentID = spawnedBy(l.Payload.Source)
			}
			s.started, _ = time.Parse(time.RFC3339, l.Timestamp)
		}
		return statusSkip
	case "turn_context":
		if l.Payload.Model != "" {
			*model = l.Payload.Model
		}
		return statusSkip
	case "event_msg":
		if l.Payload.Type != "token_count" || l.Payload.Info == nil {
			return statusSkip
		}
	default:
		return statusSkip
	}

	info := l.Payload.Info
	if info.Last == nil && info.Total == nil {
		return statusSkip
	}
	if (info.Last != nil && info.Last.negative()) || (info.Total != nil && info.Total.negative()) {
		return statusBadRecord
	}
	at, err := time.Parse(time.RFC3339, l.Timestamp)
	if err != nil {
		return statusBadRecord
	}
	if len(s.burst) < 2 {
		s.burst = append(s.burst, at)
	}

	// A running sum that has not moved is the same turn written again.
	advanced := info.Total == nil || *prev == nil || *info.Total != **prev
	var spent tokenUsage
	switch {
	case info.Last != nil && advanced:
		spent = *info.Last
	case info.Total != nil:
		spent = info.Total.minus(*prev)
	}
	if info.Total != nil {
		*prev = info.Total
	}
	if spent.zero() {
		return statusSkip
	}

	m := *model
	if l.Payload.Model != "" {
		m = l.Payload.Model
	} else if info.Model != "" {
		m = info.Model
	}
	s.turns = append(s.turns, turn{at: at, model: m, usage: spent})
	return statusEntry
}

// spawnedBy reads the parent thread out of a sub-agent's source. For a
// session a person started, source is a plain string such as "cli".
func spawnedBy(source json.RawMessage) string {
	var src struct {
		Subagent struct {
			ThreadSpawn struct {
				ParentThreadID string `json:"parent_thread_id"`
			} `json:"thread_spawn"`
		} `json:"subagent"`
	}
	if json.Unmarshal(source, &src) != nil {
		return ""
	}
	return src.Subagent.ThreadSpawn.ParentThreadID
}
