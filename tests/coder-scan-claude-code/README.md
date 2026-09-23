# coder: reading Claude Code's logs

Every client reads the same agent logs into the same hourly totals, whatever language it is written in. The cases here are how that is checked, for one agent: one harness, one set of cases, and a small driver per language.

The rules they encode came from [ccusage](https://github.com/ccusage/ccusage), not from first principles.

Another agent gets a suite of its own — `coder-scan-<agent>` — because its logs, its cases and the rules for reading them are its own. What they share is the shape of the answer and the driver protocol below.

## Running

```sh
moon run coder-scan-claude-code:conformance-go
```

That builds the Go driver and runs `scan.bats` against it. Any other driver runs the same way:

```sh
CODER_SCAN_DRIVER=path/to/driver bats tests/coder-scan-claude-code/scan.bats
```

## The driver protocol

A driver is the smallest program that puts a language's library behind this protocol. It holds no logic of its own: it calls the entry points a client in that language calls, and only turns arguments into options and results into JSON. The Go one is `drivers/go`.

```
driver scan <provider> <logs directory>
```

- **On success** it exits 0 and prints the rollups, as the body the ingest endpoint takes: `{"rollups": [{"provider", "hour_bucket", "tokens"}]}`. `hour_bucket` is RFC3339 in UTC with a `Z` and no fractional seconds. An empty scan is `{"rollups": []}`.
- **On failure** it exits non-zero and prints `{"error": {"kind": "..."}}`. Failures are compared by kind, never by message, so implementations can word theirs as they like. The kinds so far: `unknown_provider`.

Output is compared as JSON values, so key order and whitespace do not matter. Anything written to stderr is ignored.

## Cases

`cases/<name>/` holds `logs/`, the directory handed to the driver, and `expected-rollups.json`. Every case must be named by a test in `scan.bats`; a test fails if one is not, so a new case cannot be added without the test that runs it.
