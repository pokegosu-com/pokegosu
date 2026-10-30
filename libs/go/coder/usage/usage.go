// Package usage models token usage read from coding agent logs and folds it
// into the hourly rollups the server stores.
//
// The unit the server keeps is an absolute value: "the 14:00 UTC bucket is
// 3,200,000 tokens", not "3,200,000 more tokens". Re-sending the same bucket
// therefore has to produce the same number every time, which is why
// deduplication and bucketing live here, once, instead of in each parser.
//
// The deduplication rules follow ccusage, the reference implementation for
// this kind of parsing (rust/adapters/claude/src/daily.rs). They are not
// obvious and were not arrived at from first principles — see Aggregator.Add.
package usage

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"
)

// Entry is one usage record read from a log: what a single message cost, when
// it was recorded, and the identifiers that say whether two records are the
// same message.
type Entry struct {
	// Provider is the providers.id value this entry belongs to.
	Provider string

	// MessageID identifies the API response. Agents write the same response
	// to the log two or three times, and a resumed or forked session copies
	// its earlier responses into a new session under the same id.
	MessageID string

	// RequestID identifies the API call. Empty when the log does not carry
	// one, which changes how duplicates are matched.
	RequestID string

	// SessionID is the session the record was written in. It separates
	// records only where the ids above cannot: see Aggregator.Add.
	SessionID string

	// IsSidechain marks a record written by a sub-agent transcript, which
	// replays its parent's messages under new request ids.
	IsSidechain bool

	// At is when the message was recorded, in any location.
	At time.Time

	// Tokens is everything the message consumed, cache included. Never
	// negative.
	Tokens int64

	// Source is the log file the record was read from. Empty when it came
	// from nowhere on disk, as in a test.
	Source string
}

// Rollup is the absolute token total for one provider in one UTC hour. This
// is the unit the client uploads and the server stores.
type Rollup struct {
	Provider   string
	HourBucket time.Time
	Tokens     int64
}

// Payload is the ingest request body: the rollups a client uploads in one
// call. It is also the shape of the golden fixtures, so a scan result can be
// posted, printed, and compared without a second representation of it.
type Payload struct {
	Rollups []Rollup `json:"rollups"`
}

// rollupWire is how a Rollup crosses the wire. hour_bucket is RFC3339 in UTC
// on the dot, which is what the hour_bucket_is_truncated check in the schema
// expects.
type rollupWire struct {
	Provider   string `json:"provider"`
	HourBucket string `json:"hour_bucket"`
	Tokens     int64  `json:"tokens"`
}

// MarshalJSON implements json.Marshaler.
func (r Rollup) MarshalJSON() ([]byte, error) {
	return json.Marshal(rollupWire{
		Provider:   r.Provider,
		HourBucket: r.HourBucket.UTC().Format(time.RFC3339),
		Tokens:     r.Tokens,
	})
}

// UnmarshalJSON implements json.Unmarshaler.
func (r *Rollup) UnmarshalJSON(data []byte) error {
	var w rollupWire
	if err := json.Unmarshal(data, &w); err != nil {
		return err
	}
	at, err := time.Parse(time.RFC3339, w.HourBucket)
	if err != nil {
		return fmt.Errorf("hour_bucket %q: %w", w.HourBucket, err)
	}
	*r = Rollup{Provider: w.Provider, HourBucket: at.UTC(), Tokens: w.Tokens}
	return nil
}

// Aggregator collects entries and folds them into hourly rollups.
//
// Deduplication belongs here rather than in the parsers because the set has
// to span every file read in one scan: a resumed session writes its earlier
// messages again into a new file.
type Aggregator struct {
	records []record

	// exact indexes records by the identifiers that make two records the
	// same message.
	exact map[exactKey]int

	// byMessage indexes records by (provider, message, session) for the
	// sidechain fallback, where request ids differ but the message is one. A
	// record copied across sessions is indexed under each of them.
	byMessage map[messageKey][]int
}

type exactKey struct {
	provider  string
	messageID string
	requestID string

	// session and at distinguish records only when there is no request id.
	// With one, the request id already says whether two records are the same
	// call.
	session string
	at      int64
}

type messageKey struct {
	provider  string
	messageID string
	session   string
}

type record struct {
	provider    string
	messageID   string
	requestID   string
	sessionID   string
	at          time.Time
	tokens      int64
	isSidechain bool

	// sources are the files the message was read from, so that a client can
	// tell later whether its logs are still there.
	sources []string
}

// NewAggregator returns an empty Aggregator.
func NewAggregator() *Aggregator {
	return &Aggregator{
		exact:     make(map[exactKey]int),
		byMessage: make(map[messageKey][]int),
	}
}

// Add records an entry, merging it into an earlier one if they are the same
// message.
//
// Two records are the same message when provider, message id and request id
// all match. Session is not part of that: resuming or forking a session copies
// its earlier messages into the new session, ids and all, and counting them
// there again inflated real totals by a tenth.
//
// Without a request id, the records also have to share a session, since a
// gateway can reuse one message id for every response. A real Anthropic id
// (msg_ or resp_) is unique per response, and Claude Code writes one line per
// content block under it at different times, so those match across times;
// any other id has to match the timestamp too.
//
// A record with no message id at all matches nothing and counts as it is.
//
// The exception is a sidechain replay. A sub-agent transcript repeats its
// parent's messages under fresh request ids, so when either side is marked as
// a sidechain, matching provider, message id and session is enough. A message
// copied into another session can be replayed from either.
//
// When two records merge, the larger token count wins and a real message is
// preferred over its sidechain copy — a record can be written before the
// response finished, so the bigger number is the complete one. The bucket
// keeps the earliest timestamp, which makes the result independent of the
// order files are read in; ccusage has no rule here because it aggregates by
// day, where the choice cannot change the answer.
//
// These rules follow ccusage's Claude Code adapter. Changing one without
// checking there is how the four clients drift apart.
func (a *Aggregator) Add(e Entry) {
	idx, found := a.lookup(e)
	if !found {
		idx = len(a.records)
		a.records = append(a.records, record{
			provider:    e.Provider,
			messageID:   e.MessageID,
			requestID:   e.RequestID,
			sessionID:   e.SessionID,
			at:          e.At,
			tokens:      e.Tokens,
			isSidechain: e.IsSidechain,
			sources:     appendSource(nil, e.Source),
		})
		if e.MessageID != "" {
			a.index(e, idx)
		}
		return
	}

	r := &a.records[idx]
	if e.At.Before(r.at) {
		r.at = e.At
	}
	if replaces(e, *r) {
		r.tokens = e.Tokens
		r.isSidechain = e.IsSidechain
	}
	r.sources = appendSource(r.sources, e.Source)
	// Index this spelling of the message too, so the next copy matches
	// directly instead of falling through to the sidechain scan, and a
	// sidechain in this session finds it.
	a.index(e, idx)
}

func (a *Aggregator) index(e Entry, idx int) {
	a.exact[a.exactKeyOf(e)] = idx
	mk := messageKey{e.Provider, e.MessageID, e.SessionID}
	for _, held := range a.byMessage[mk] {
		if held == idx {
			return
		}
	}
	a.byMessage[mk] = append(a.byMessage[mk], idx)
}

func (a *Aggregator) lookup(e Entry) (int, bool) {
	if e.MessageID == "" {
		return 0, false
	}
	if idx, ok := a.exact[a.exactKeyOf(e)]; ok {
		return idx, true
	}
	for _, idx := range a.byMessage[messageKey{e.Provider, e.MessageID, e.SessionID}] {
		if e.IsSidechain || a.records[idx].isSidechain {
			return idx, true
		}
	}
	return 0, false
}

func (a *Aggregator) exactKeyOf(e Entry) exactKey {
	k := exactKey{
		provider:  e.Provider,
		messageID: e.MessageID,
		requestID: e.RequestID,
	}
	if e.RequestID == "" {
		k.session = e.SessionID
		if !isAnthropicID(e.MessageID) {
			k.at = e.At.UTC().UnixNano()
		}
	}
	return k
}

// isAnthropicID reports whether a message id is one the API made, which is
// unique per response, rather than a placeholder a gateway reuses. A prefix is
// a heuristic, the same one ccusage uses.
func isAnthropicID(id string) bool {
	return strings.HasPrefix(id, "msg_") || strings.HasPrefix(id, "resp_")
}

// replaces reports whether the incoming record should supersede the stored
// one. A real message beats its sidechain copy; otherwise the larger total
// wins, because a record can be written before the response finished.
func replaces(e Entry, stored record) bool {
	if e.IsSidechain != stored.isSidechain {
		return stored.isSidechain
	}
	return e.Tokens > stored.tokens
}

func appendSource(sources []string, source string) []string {
	if source == "" {
		return sources
	}
	for _, s := range sources {
		if s == source {
			return sources
		}
	}
	return append(sources, source)
}

// Record is one message after deduplication, with the files it was read
// from. It is what a client keeps between scans, so that a message still
// counts after the agent has deleted its log.
type Record struct {
	Provider    string
	MessageID   string
	RequestID   string
	SessionID   string
	IsSidechain bool
	At          time.Time
	Tokens      int64
	Sources     []string
}

// Records returns every message recorded, in the order first seen. A message
// copied across sessions carries the first session it was seen in.
func (a *Aggregator) Records() []Record {
	out := make([]Record, len(a.records))
	for i, r := range a.records {
		out[i] = Record{
			Provider:    r.provider,
			MessageID:   r.messageID,
			RequestID:   r.requestID,
			SessionID:   r.sessionID,
			IsSidechain: r.isSidechain,
			At:          r.at,
			Tokens:      r.tokens,
			Sources:     append([]string(nil), r.sources...),
		}
	}
	return out
}

// Restore adds a message kept from an earlier scan whose logs are gone, and
// reports whether it counted.
//
// A message the logs still hold, in any spelling, is left as they say: what
// is read now is the truth, and a count corrected by a newer parser has to be
// able to fall.
func (a *Aggregator) Restore(r Record) bool {
	e := Entry{
		Provider:    r.Provider,
		MessageID:   r.MessageID,
		RequestID:   r.RequestID,
		SessionID:   r.SessionID,
		IsSidechain: r.IsSidechain,
		At:          r.At,
		Tokens:      r.Tokens,
	}
	if _, found := a.lookup(e); found {
		return false
	}
	a.Add(e)
	a.records[len(a.records)-1].sources = append([]string(nil), r.Sources...)
	return true
}

// Messages reports how many distinct messages have been recorded.
func (a *Aggregator) Messages() int { return len(a.records) }

// Rollups folds the recorded entries into hourly totals, ordered by hour and
// then provider.
//
// Buckets before since are dropped. A zero since keeps everything. Since is
// truncated down to the hour, so a returned bucket always covers a full hour:
// a bucket cut off halfway would upload as an absolute value that undercounts
// the hour it claims to describe.
func (a *Aggregator) Rollups(since time.Time) []Rollup {
	var cutoff int64
	if !since.IsZero() {
		cutoff = since.UTC().Truncate(time.Hour).Unix()
	}

	type bucketKey struct {
		provider string
		hour     int64
	}
	totals := make(map[bucketKey]int64)
	for _, r := range a.records {
		hour := r.at.UTC().Truncate(time.Hour).Unix()
		if hour < cutoff {
			continue
		}
		totals[bucketKey{r.provider, hour}] += r.tokens
	}

	rollups := make([]Rollup, 0, len(totals))
	for bk, tokens := range totals {
		rollups = append(rollups, Rollup{
			Provider:   bk.provider,
			HourBucket: time.Unix(bk.hour, 0).UTC(),
			Tokens:     tokens,
		})
	}
	SortRollups(rollups)
	return rollups
}

// SortRollups orders rollups by hour and then provider, the order every
// client reports and the fixtures expect.
func SortRollups(rollups []Rollup) {
	sort.Slice(rollups, func(i, j int) bool {
		if !rollups[i].HourBucket.Equal(rollups[j].HourBucket) {
			return rollups[i].HourBucket.Before(rollups[j].HourBucket)
		}
		return rollups[i].Provider < rollups[j].Provider
	})
}
