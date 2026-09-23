package main

import (
	"github.com/spf13/cobra"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/coder"
)

func newCoderCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "coder",
		Short: "Collect coding agent token usage",
		Long: `Collect coding agent token usage from this machine, and upload hourly totals
to the account it was enrolled with.`,
	}
	cmd.AddCommand(newScanCmd(), newSyncCmd())
	return cmd
}

func newScanCmd() *cobra.Command {
	var opts coder.ScanOptions

	cmd := &cobra.Command{
		Use:   "scan",
		Short: "Parse local logs and print hourly rollups",
		Long: `Parses the local agent logs and prints hourly token rollups. Nothing is sent
anywhere. Run it first when a number looks wrong.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return coder.Scan(opts)
		},
	}

	f := cmd.Flags()
	f.StringVar(&opts.Since, "since", "",
		"only print hours at or after `DATE`: YYYY-MM-DD (UTC) or RFC3339, rounded down to the hour")
	f.StringVar(&opts.Format, "format", "text",
		"`text` or json; json is the body the ingest endpoint takes")
	f.StringArrayVar(&opts.Paths, "path", nil,
		"read `DIR` instead of the default log location (repeatable)")
	f.StringArrayVar(&opts.Providers, "provider", nil,
		"read only the logs of provider `ID` (repeatable); needed with --path once there is more than one")
	return cmd
}

func newSyncCmd() *cobra.Command {
	var opts coder.SyncOptions

	cmd := &cobra.Command{
		Use:   "sync",
		Short: "Upload what has changed since the last run",
		Long: `Reads the local agent logs and uploads the hourly rollups that have changed
since the last run. One pass, then it exits: run it from cron, a systemd
timer or launchd rather than leaving it resident.

A sync reports nothing from before this machine was enrolled: what the logs
hold from before then is nobody's business but this machine's. The server
ignores those hours whoever sends them; skipping them here only saves the
request. The hour the enrolment fell in is reported whole.

Run "pokegosu auth login" first: sync needs the settings it writes.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return coder.Sync(opts)
		},
	}

	f := cmd.Flags()
	f.BoolVar(&opts.All, "all", false,
		"upload every bucket, not only the changed ones: after the server lost data, or to check a disagreement")
	f.BoolVarP(&opts.Quiet, "quiet", "q", false,
		"print nothing unless something went wrong, which is what a scheduled run wants")
	f.StringArrayVar(&opts.Paths, "path", nil,
		"read `DIR` instead of the default log location (repeatable)")
	f.StringArrayVar(&opts.Providers, "provider", nil,
		"read only the logs of provider `ID` (repeatable); needed with --path once there is more than one")
	return cmd
}
