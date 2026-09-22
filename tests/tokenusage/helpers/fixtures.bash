#!/usr/bin/env bash
# The shared fixtures: where they are, what they expect, and whether an
# implementation's output agrees.

FIXTURES=${FIXTURES:-$BATS_TEST_DIRNAME/fixtures}

require_fixture_tools() {
    command -v node > /dev/null || {
        echo "node is required" >&2
        return 1
    }
}

# fixture_cases <provider> — the case names that exist for a provider.
fixture_cases() {
    local dir
    for dir in "$FIXTURES/$1"/*/; do
        [[ -d $dir ]] || continue
        basename "$dir"
    done
}

# fixture_logs <provider> <case> — the directory an implementation scans.
fixture_logs() {
    local logs=$FIXTURES/$1/$2/logs
    [[ -d $logs ]] || { echo "no logs in $FIXTURES/$1/$2" >&2; return 1; }
    printf '%s' "$logs"
}

# fixture_expected <provider> <case> — the file holding what the case
# expects, as the JSON body the ingest endpoint takes.
fixture_expected() {
    local expected=$FIXTURES/$1/$2/expected-rollups.json
    [[ -f $expected ]] || { echo "no expected-rollups.json in $FIXTURES/$1/$2" >&2; return 1; }
    printf '%s' "$expected"
}

# assert_same_json <expected file> <actual json>
assert_same_json() {
    printf '%s' "$2" | node "$BATS_TEST_DIRNAME/helpers/same-json.mjs" "$1"
}

# assert_fixtures_all_covered <provider>
#
# A fixture nobody names is a fixture nobody runs, and adding one is exactly
# when it is easy to forget the case that runs it. Any mention of the name in
# this test file counts, so it holds however a suite chooses to call them.
assert_fixtures_all_covered() {
    local provider=$1 missing=() case
    while read -r case; do
        [[ -n $case ]] || continue
        grep -q -- "$case" "$BATS_TEST_FILENAME" || missing+=("$case")
    done < <(fixture_cases "$provider")

    [[ ${#missing[@]} -eq 0 ]] || {
        echo "no case in $(basename "$BATS_TEST_FILENAME") mentions: ${missing[*]}" >&2
        return 1
    }
}
