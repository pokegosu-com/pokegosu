#!/usr/bin/env bats
#
# What every implementation has to make of Claude Code's logs.
#
#   moon run coder-scan-claude-code:go
#
# or, with any driver built:
#
#   CODER_SCAN_DRIVER=path/to/driver bats tests/coder-scan-claude-code/scan.bats
#
# Each case is written out rather than discovered from the directory: a case
# can then be skipped or annotated on its own, and its name can say what it
# catches instead of what folder it lives in.
#
# Each token field carries its own decimal place — input 1, cache_creation 10,
# cache_read 100, output 1000 — so one message is 1111 and a wrong total says
# which field was dropped. What each case expects lives with it; what is
# written here is why it exists.

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

@test "a plain session counts all four token fields" {
    assert_case normal-session
}

@test "every session file in a project is read" {
    assert_case multiple-sessions
}

@test "every project directory is read" {
    assert_case multiple-projects
}

# --- what counts as one message ---------------------------------------------

@test "a message logged two or three times is one message" {
    assert_case duplicate-messages
}

@test "a resumed session does not count its replays again" {
    assert_case session-resume
}

@test "a message copied into a forked session counts once" {
    assert_case forked-session
}

@test "without a request id the timestamp separates records" {
    assert_case missing-request-id
}

@test "a sidechain replay is the message it replays" {
    assert_case sidechain-replay
}

@test "a record written before the response finished loses to the complete one" {
    assert_case partial-then-complete
}

# --- which hour a message belongs to ----------------------------------------

@test "copies straddling an hour belong to the earliest" {
    assert_case hour-boundary
}

@test "a session crossing midnight lands in two hours on two dates" {
    # Also the only case that separates ordering by instant from ordering by
    # hour of day: hour-boundary runs 14:00 to 15:00, where the two agree.
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

@test "unknown fields are ignored and iterations are not added" {
    assert_case unknown-fields
}

@test "the cache_creation breakdown wins over the flat field" {
    assert_case cache-creation-breakdown
}

@test "totals past a 32-bit integer survive" {
    assert_case large-totals
}

# --- the cases and the tests agreeing --------------------------------------

@test "every case above is named by a test" {
    assert_every_case_is_named
}
