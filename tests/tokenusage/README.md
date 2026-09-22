# tokenusage conformance

Every pokecoder client reads the same agent logs into the same hourly totals, whatever language it is written in. The cases here are how that is checked: one harness, one set of fixtures, and a small driver per language.

The rules the fixtures encode came from [ccusage](https://github.com/ccusage/ccusage), not from first principles.

## Running

```sh
moon run tests-tokenusage:conformance-go
```

That builds the Go driver and runs `scan.bats` against it. Any other driver runs the same way:

```sh
TOKENUSAGE_DRIVER=path/to/driver bats tests/tokenusage/scan.bats
```

## The driver protocol

A driver is the smallest program that puts a language's library behind this protocol. It holds no logic of its own: it calls the entry points a client in that language calls, and only turns arguments into options and results into JSON. The Go one is `drivers/go`.

```
driver scan <provider> <logs directory>
```

- **On success** it exits 0 and prints the rollups, as the body the ingest endpoint takes: `{"rollups": [{"provider", "hour_bucket", "tokens"}]}`. `hour_bucket` is RFC3339 in UTC with a `Z` and no fractional seconds. An empty scan is `{"rollups": []}`.
- **On failure** it exits non-zero and prints `{"error": {"kind": "..."}}`. Failures are compared by kind, never by message, so implementations can word theirs as they like. The kinds so far: `unknown_provider`.

Output is compared as JSON values, so key order and whitespace do not matter. Anything written to stderr is ignored.

## Fixtures

`fixtures/<provider>/<case>/` holds `logs/`, the directory handed to the driver, and `expected-rollups.json`. Every case must be named in `scan.bats`; a test fails if one is not, so a new fixture cannot be added without the case that runs it.
