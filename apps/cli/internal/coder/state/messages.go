package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

// Messages is every message this machine's logs have held, with the files
// each was read from.
//
// The server overwrites each hour with the total sent last, so a log the
// agent deletes would lower hours already counted: Claude Code deletes
// sessions after thirty days. Keeping what each message cost lets a scan
// still count a message after its log is gone. Unlike the sent-rollups
// cache, this is a record: losing it loses nothing while the logs are there,
// but nothing brings back a message whose log went first.
//
// Only Claude Code is kept. Codex's logs name no message, so its records
// would need another key.
//
// It describes this machine's logs, not any server, so it is not thrown
// away when the machine is enrolled again.
type Messages struct {
	Records []usage.Record
}

// KeptProviders are the providers whose messages are kept.
var KeptProviders = map[string]bool{"claude_code": true}

// MessagesPath returns the record, beside the settings.
func MessagesPath(settingsPath string) string {
	return filepath.Join(filepath.Dir(settingsPath), "coder.messages.json")
}

// messagesFile is the record on disk. Paths are listed once and messages
// point at them, since a session's file is shared by all its messages.
type messagesFile struct {
	Version  int           `json:"version"`
	Files    []string      `json:"files"`
	Messages []messageLine `json:"messages"`
}

type messageLine struct {
	Provider  string `json:"provider"`
	ID        string `json:"id"`
	Request   string `json:"request,omitempty"`
	Sidechain bool   `json:"sidechain,omitempty"`

	// At keeps nanoseconds: without a request id, the time is part of what
	// says two lines are the same message.
	At     string `json:"at"`
	Tokens int64  `json:"tokens"`
	Files  []int  `json:"files"`
}

const messagesVersion = 1

// LoadMessages reads the record. A missing file is an empty record, which is
// what a machine has before its first sync. One that cannot be read is also
// empty, with the reason, so the caller can say the protection is gone
// rather than fail the sync.
func LoadMessages(path string) (Messages, error) {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return Messages{}, nil
	}
	if err != nil {
		return Messages{}, err
	}

	var f messagesFile
	if err := json.Unmarshal(data, &f); err != nil {
		return Messages{}, fmt.Errorf("reading %s: %w", path, err)
	}
	if f.Version != messagesVersion {
		return Messages{}, fmt.Errorf("%s is version %d; this pokegosu reads %d", path, f.Version, messagesVersion)
	}

	m := Messages{Records: make([]usage.Record, 0, len(f.Messages))}
	for _, line := range f.Messages {
		at, err := time.Parse(time.RFC3339Nano, line.At)
		if err != nil {
			return Messages{}, fmt.Errorf("reading %s: message %s: %w", path, line.ID, err)
		}
		r := usage.Record{
			Provider:    line.Provider,
			MessageID:   line.ID,
			RequestID:   line.Request,
			IsSidechain: line.Sidechain,
			At:          at,
			Tokens:      line.Tokens,
		}
		for _, i := range line.Files {
			if i < 0 || i >= len(f.Files) {
				return Messages{}, fmt.Errorf("reading %s: message %s names file %d of %d", path, line.ID, i, len(f.Files))
			}
			r.Sources = append(r.Sources, f.Files[i])
		}
		m.Records = append(m.Records, r)
	}
	return m, nil
}

// Keep is the record a scan's messages make: the kept providers' messages
// from since on. Older ones are left out, since a sync never sends a bucket
// from before the machine was enrolled.
func Keep(records []usage.Record, since time.Time) Messages {
	cutoff := since.UTC().Truncate(time.Hour)

	var m Messages
	for _, r := range records {
		if !KeptProviders[r.Provider] || r.At.Before(cutoff) {
			continue
		}
		m.Records = append(m.Records, r)
	}
	return m
}

// SaveMessages writes the record, replacing it atomically so that an
// interrupted sync leaves the previous one rather than a truncated one.
func SaveMessages(path string, m Messages) error {
	f := messagesFile{Version: messagesVersion, Files: []string{}, Messages: make([]messageLine, 0, len(m.Records))}
	index := make(map[string]int)
	for _, r := range m.Records {
		line := messageLine{
			Provider:  r.Provider,
			ID:        r.MessageID,
			Request:   r.RequestID,
			Sidechain: r.IsSidechain,
			At:        r.At.UTC().Format(time.RFC3339Nano),
			Tokens:    r.Tokens,
			Files:     []int{},
		}
		for _, source := range r.Sources {
			i, ok := index[source]
			if !ok {
				i = len(f.Files)
				index[source] = i
				f.Files = append(f.Files, source)
			}
			line.Files = append(line.Files, i)
		}
		f.Messages = append(f.Messages, line)
	}

	data, err := json.Marshal(f)
	if err != nil {
		return fmt.Errorf("encoding the messages: %w", err)
	}
	return writeAtomically(path, ".messages-*.json", data)
}

// writeAtomically replaces path with data through a temporary file in the
// same directory.
func writeAtomically(path, pattern string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("creating %s: %w", dir, err)
	}

	temp, err := os.CreateTemp(dir, pattern)
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
