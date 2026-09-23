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
	"time"
)

// Entry is one usage record read from a log: what a single message cost, when
// it was recorded, and the identifiers that say whether two records are the
// same message.
type Entry struct {
	// Provider is the providers.id value this entry belongs to.
	Provider string

	// SessionID scopes the message. Two records from different sessions are
	// different messages even when everything else matches.
	SessionID string

	// MessageID identifies the API response. Agents write the same response
	// to the log two or three times.
	MessageID string

	// RequestID identifies the API call. Empty when the log does not carry
	// one, which changes how duplicates are matched.
	RequestID string

	// IsSidechain marks a record written by a sub-agent transcript, which
	// replays its parent's messages under new request ids.
	IsSidechain bool

	// At is when the message was recorded, in any location.
	At time.Time

	// Tokens is everything the message consumed, cache included. Never
	// negative.
	Tokens int64
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

	// bySession indexes records by (provider, session, message) for the
	// sidechain fallback, where request ids differ but the message is one.
	bySession map[messageKey][]int
}

type exactKey struct {
	provider  string
	sessionID string
	messageID string
	requestID string

	// at distinguishes records only when there is no request id. With one,
	// the request id already says whether two records are the same call.
	at int64
}

type messageKey struct {
	provider  string
	sessionID string
	messageID string
}

type record struct {
	provider    string
	at          time.Time
	tokens      int64
	isSidechain bool
}

// NewAggregator returns an empty Aggregator.
func NewAggregator() *Aggregator {
	return &Aggregator{
		exact:     make(map[exactKey]int),
		bySession: make(map[messageKey][]int),
	}
}

// Add records an entry, merging it into an earlier one if they are the same
// message.
//
// Two records are the same message when provider, session, message id and
// request id all match. Without a request id the timestamp has to match too.
// Session is part of the key: the same message id under a different session
// is counted separately, because an id is only known to be unique within the
// session that produced it.
//
// The exception is a sidechain replay. A sub-agent transcript repeats its
// parent's messages under fresh request ids, so when either side is marked as
// a sidechain, matching provider, session and message id is enough.
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
			at:          e.At,
			tokens:      e.Tokens,
			isSidechain: e.IsSidechain,
		})
		mk := messageKey{e.Provider, e.SessionID, e.MessageID}
		a.bySession[mk] = append(a.bySession[mk], idx)
		a.exact[a.exactKeyOf(e)] = idx
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
	// Index this spelling of the message too, so the next copy matches
	// directly instead of falling through to the sidechain scan.
	a.exact[a.exactKeyOf(e)] = idx
}

func (a *Aggregator) lookup(e Entry) (int, bool) {
	if idx, ok := a.exact[a.exactKeyOf(e)]; ok {
		return idx, true
	}
	for _, idx := range a.bySession[messageKey{e.Provider, e.SessionID, e.MessageID}] {
		if e.IsSidechain || a.records[idx].isSidechain {
			return idx, true
		}
	}
	return 0, false
}

func (a *Aggregator) exactKeyOf(e Entry) exactKey {
	k := exactKey{
		provider:  e.Provider,
		sessionID: e.SessionID,
		messageID: e.MessageID,
		requestID: e.RequestID,
	}
	if e.RequestID == "" {
		k.at = e.At.UTC().UnixNano()
	}
	return k
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
