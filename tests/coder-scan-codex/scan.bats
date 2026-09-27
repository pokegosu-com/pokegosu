#!/usr/bin/env bats
#
# What every implementation has to make of Codex's logs.
#
#   moon run coder-scan-codex:go
#
# or, with any driver built:
#
#   CODER_SCAN_DRIVER=path/to/driver bats tests/coder-scan-codex/scan.bats
#
# Each case is written out rather than discovered from the directory: a case
# can then be skipped or annotated on its own, and its name can say what it
# catches instead of what folder it lives in.
#
# The two turns most cases share spend 110 and 220 tokens, 330 together. The
# cached input and the reasoning they record are already inside those
# totals, so a parser that adds them again lands on a number that is not a
# sum of 110s. What each case expects lives with it; what is written here is
# why it exists.

setup() {
    load helpers/driver
    load helpers/cases

    require_driver
    require_case_tools
}

# assert_case <case> — the driver's scan of that case is what it expects.
assert_case() {
    local logs expected actual
    logs=$(case_logs "$1") || return 1
    expected=$(case_expected "$1") || return 1
    actual=$(driver "$logs") || { echo "scan failed on $1: $actual" >&2; return 1; }

    assert_same_json "$expected" "$actual" || {
        echo "^ $1" >&2
        return 1
    }
}

# --- the shape of a scan ----------------------------------------------------

@test "a plain session counts each turn once, cache and reasoning inside" {
    assert_case normal-session
}

@test "a running sum alone is turned back into turns" {
    assert_case running-sum-only
}

@test "a zero total is worked out from input and output" {
    assert_case missing-total
}

# --- what counts as one turn ------------------------------------------------

@test "a token_count written again with the same running sum is one turn" {
    assert_case repeated-token-count
}

@test "a copy of a log, archived or resumed, is the same turns" {
    assert_case archived-copy
}

@test "a fork does not count the history it replays from its parent" {
    assert_case forked-session
}

@test "a sub-agent's replay is skipped even without the parent's log" {
    # Codex writes the replayed history in one burst, and the sub-agent's own
    # first turn follows a pause.
    assert_case subagent-replay
}

# --- which hour a turn belongs to -------------------------------------------

@test "turns either side of an hour belong to their own hours" {
    assert_case hour-boundary
}

@test "a session crossing midnight lands in two hours on two dates" {
    assert_case utc-day-boundary
}

@test "hours are cut in UTC wherever the machine is" {
    # A parser that truncates in local time and converts back lands on the
    # same instant in every whole-hour offset, so only a zone offset by part
    # of an hour can tell the two apart. India is +05:30.
    TZ=Asia/Kolkata
    export TZ
    assert_case normal-session
}

# --- input that is not a clean log ------------------------------------------

@test "a log still being written counts everything before the cut" {
    assert_case truncated-last-line
}

@test "empty and blank files are not an error" {
    assert_case empty-files
}

@test "other lines and unknown fields are ignored" {
    assert_case unknown-lines
}

@test "totals past a 32-bit integer survive" {
    assert_case large-totals
}

# --- the cases and the tests agreeing --------------------------------------

@test "every case above is named by a test" {
    assert_every_case_is_named
}
