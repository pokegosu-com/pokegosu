package state

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// Run is when the last sync started, which is what --min-interval measures
// from. It is written before the sync, so that another one starting meanwhile
// counts from this one.
type Run struct {
	At time.Time `json:"at"`
}

// RunPath returns the record of the last sync, beside the settings.
func RunPath(settingsPath string) string {
	return filepath.Join(filepath.Dir(settingsPath), "coder.last-sync.json")
}

// LoadRun reads the last sync. Anything unreadable is no sync at all, which
// lets the next one go ahead.
func LoadRun(path string) Run {
	var r Run
	data, err := os.ReadFile(path)
	if err != nil || json.Unmarshal(data, &r) != nil {
		return Run{}
	}
	return r
}

// SaveRun replaces the record. Two syncs started together may both write it;
// either is a true account of a sync.
func SaveRun(path string, r Run) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(r)
	if err != nil {
		return err
	}
	temp, err := os.CreateTemp(dir, ".last-sync-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	return os.Rename(temp.Name(), path)
}
