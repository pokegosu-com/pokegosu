#!/usr/bin/env bash
# The fixtures the conformance suite uses, reused here as logs to sync.

FIXTURES=${FIXTURES:-$BATS_TEST_DIRNAME/../../../tests/coder/fixtures}

# fixture_logs <provider> <case> — the directory a client scans.
fixture_logs() {
    local logs=$FIXTURES/$1/$2/logs
    [[ -d $logs ]] || { echo "no logs in $FIXTURES/$1/$2" >&2; return 1; }
    printf '%s' "$logs"
}

# assert_synced <provider> <case> <actual json> — what the server holds is
# what the case expects.
assert_synced() {
    printf '%s' "$3" | json same "$FIXTURES/$1/$2/expected-rollups.json"
}
