#!/usr/bin/env bash
# The cases: where they are, what they expect, and whether an implementation's
# output agrees.
#
# One suite, one provider — this one reads Codex's logs — so a case is
# named by what it catches rather than by which agent wrote the log.

CASES=${CASES:-$BATS_TEST_DIRNAME/cases}

require_case_tools() {
    command -v node > /dev/null || {
        echo "node is required" >&2
        return 1
    }
}

# case_names — every case in this suite.
case_names() {
    local dir
    for dir in "$CASES"/*/; do
        [[ -d $dir ]] || continue
        basename "$dir"
    done
}

# case_logs <case> — the directory an implementation scans.
case_logs() {
    local logs=$CASES/$1/logs
    [[ -d $logs ]] || { echo "no logs in $CASES/$1" >&2; return 1; }
    printf '%s' "$logs"
}

# case_expected <case> — the file holding what the case expects, as the JSON
# body the ingest endpoint takes.
case_expected() {
    local expected=$CASES/$1/expected-rollups.json
    [[ -f $expected ]] || { echo "no expected-rollups.json in $CASES/$1" >&2; return 1; }
    printf '%s' "$expected"
}

# assert_same_json <expected file> <actual json>
assert_same_json() {
    printf '%s' "$2" | node "$BATS_TEST_DIRNAME/helpers/same-json.mjs" "$1"
}

# assert_every_case_is_named
#
# A case nobody names is a case nobody runs, and adding one is exactly when it
# is easy to forget the test that runs it. Any mention of the name in this
# test file counts, so it holds however a suite chooses to write them.
assert_every_case_is_named() {
    local missing=() case
    while read -r case; do
        [[ -n $case ]] || continue
        grep -q -- "$case" "$BATS_TEST_FILENAME" || missing+=("$case")
    done < <(case_names)

    [[ ${#missing[@]} -eq 0 ]] || {
        echo "no test in $(basename "$BATS_TEST_FILENAME") mentions: ${missing[*]}" >&2
        return 1
    }
}
