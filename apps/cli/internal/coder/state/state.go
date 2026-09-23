// Package state remembers what this machine has already sent.
//
// Rollups are absolute values, so re-sending one is harmless — but a routine
// sync would otherwise carry every hour the machine has ever worked, and that
// grows without bound. Keeping the last value sent for each bucket turns a
// sync into the one or two rows that actually moved.
//
// This is a cache, not a record: losing it costs one large upload, and the
// server lands on the same numbers either way.
package state

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// State is what was last accepted by one server for one device.
type State struct {
	// Server and DeviceID say whose numbers these are. Pointed at another
	// deployment, or re-registered as a new machine, the file describes
	// somebody else's ledger and has to be thrown away.
	Server   string `json:"server"`
	DeviceID string `json:"device_id"`

	// Sent is the value the server holds for each bucket, as far as this
	// machine knows.
	Sent []usage.Rollup `json:"sent"`
}

// Path returns the cache file, which sits beside the settings enrolment
// wrote, in the same config directory.
//
// Named for coder rather than for the settings: the settings belong to the
// account and every service reads them, while this is one service's memory of
// what it has already sent.
func Path(settingsPath string) string {
	return filepath.Join(filepath.Dir(settingsPath), "coder.sent-rollups.json")
}

// Load reads what was sent to this server for this device.
//
// Anything unreadable, or written for a different server or device, comes
// back empty: the next sync then sends everything, which is correct and
// costs one upload.
func Load(path, server, deviceID string) *State {
	empty := &State{Server: server, DeviceID: deviceID}

	data, err := os.ReadFile(path)
	if err != nil {
		return empty
	}

	var loaded State
	if err := json.Unmarshal(data, &loaded); err != nil {
		return empty
	}
	if loaded.Server != server || loaded.DeviceID != deviceID {
		return empty
	}
	return &loaded
}

// Save writes the cache, replacing it atomically so that an interrupted sync
// leaves the previous cache rather than a truncated one.
func Save(path string, s *State) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("creating %s: %w", dir, err)
	}

	data, err := json.Marshal(s)
	if err != nil {
		return fmt.Errorf("encoding the cache: %w", err)
	}

	temp, err := os.CreateTemp(dir, ".sent-*.json")
	if err != nil {
		return fmt.Errorf("creating a temporary file in %s: %w", dir, err)
	}
	name := temp.Name()
	defer os.Remove(name)

	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return fmt.Errorf("writing %s: %w", name, err)
	}
	if err := temp.Close(); err != nil {
		return fmt.Errorf("writing %s: %w", name, err)
	}
	if err := os.Rename(name, path); err != nil {
		return fmt.Errorf("saving %s: %w", path, err)
	}
	return nil
}

// RecentWindow is how far back a sync restates buckets it believes the
// server already holds.
//
// What this cache holds is what one process asked the server for, not what
// the server ended up with. Two syncs overlapping — a scheduled run and
// someone impatient — can send different values for the same hour and arrive
// in the other order, leaving the server holding one and the cache claiming
// the other. An hour whose log has stopped growing never differs from the
// cache again, so without this the difference would last forever; §9 calls a
// reordered arrival harmless only because a later sync restates the value.
//
// Two hours, not the forty-eight §6 recomputes. Recomputing is about parsing
// and costs nothing; restating is rows on the wire, and §6 wants a routine
// sync to carry one or two. Two hours is what it takes: a bucket can only be
// raced while its value is still moving, which is the hour being written and
// the one just behind it.
const RecentWindow = 2 * time.Hour

// Changed returns the rollups the server may not already hold, in the order
// they were given: anything whose value has moved, plus the last few hours
// whether or not it has (see RecentWindow).
//
// A bucket the server has but the scan no longer reports is left alone. Logs
// are read, not written: a bucket disappearing means the log did, and the
// usage still happened (§9).
func (s *State) Changed(current []usage.Rollup, now time.Time) []usage.Rollup {
	known := make(map[key]int64, len(s.Sent))
	for _, r := range s.Sent {
		known[keyOf(r)] = r.Tokens
	}
	recent := now.Add(-RecentWindow)

	var changed []usage.Rollup
	for _, r := range current {
		tokens, held := known[keyOf(r)]
		if !held || tokens != r.Tokens || !r.HourBucket.Before(recent) {
			changed = append(changed, r)
		}
	}
	return changed
}

// Forget drops everything the cache claims the server holds.
//
// A run that means to restate the whole ledger starts from here, so that
// failing or being interrupted part-way leaves the rest outstanding rather
// than recorded as delivered.
func (s *State) Forget() {
	s.Sent = nil
}

// Record folds accepted rollups into what the server is known to hold.
func (s *State) Record(accepted []usage.Rollup) {
	held := make(map[key]usage.Rollup, len(s.Sent)+len(accepted))
	for _, r := range s.Sent {
		held[keyOf(r)] = r
	}
	for _, r := range accepted {
		held[keyOf(r)] = r
	}

	s.Sent = make([]usage.Rollup, 0, len(held))
	for _, r := range held {
		s.Sent = append(s.Sent, r)
	}
	usage.SortRollups(s.Sent)
}

type key struct {
	provider string
	hour     int64
}

func keyOf(r usage.Rollup) key {
	return key{provider: r.Provider, hour: r.HourBucket.UTC().Unix()}
}

// ErrNotSaved is returned when the cache could not be written. The sync
// itself succeeded, so a caller reports it without failing.
var ErrNotSaved = errors.New("the sent-rollups cache could not be written")
