#!/usr/bin/env bats
#
# What every implementation's scan has to produce for the shared fixtures.
#
#   moon run tests-coder:conformance-go
#
# or, with any driver built:
#
#   CODER_DRIVER=path/to/driver bats tests/coder/scan.bats
#
# Each case is written out rather than discovered from the directory: a case
# can then be skipped or annotated on its own, and its name can say what it
# catches instead of what folder it lives in.
#
# Each token field carries its own decimal place — input 1, cache_creation 10,
# cache_read 100, output 1000 — so one message is 1111 and a wrong total says
# which field was dropped. The expectations live with the fixtures; what is
# written here is why the case exists.

setup() {
    load helpers/driver
    load helpers/fixtures

    require_driver
    require_fixture_tools
}

# assert_scan_fixture <provider> <case> — the driver's scan of that case is
# what the case expects.
assert_scan_fixture() {
    local logs expected actual
    logs=$(fixture_logs "$1" "$2") || return 1
    expected=$(fixture_expected "$1" "$2") || return 1
    actual=$(driver scan "$1" "$logs") || { echo "scan failed on $2: $actual" >&2; return 1; }

    assert_same_json "$expected" "$actual" || {
        echo "^ $1/$2" >&2
        return 1
    }
}

# --- the protocol -----------------------------------------------------------

@test "an unknown provider is reported by kind, not by message" {
    run driver scan no-such-agent "$BATS_TEST_TMPDIR"
    [[ $status -ne 0 ]]

    printf '%s' '{"error": {"kind": "unknown_provider"}}' > "$BATS_TEST_TMPDIR/expected.json"
    assert_same_json "$BATS_TEST_TMPDIR/expected.json" "$output"
}

# --- the shape of a scan ----------------------------------------------------

@test "claude_code: a plain session counts all four token fields" {
    assert_scan_fixture claude_code normal-session
}

@test "claude_code: every session file in a project is read" {
    assert_scan_fixture claude_code multiple-sessions
}

@test "claude_code: every project directory is read" {
    assert_scan_fixture claude_code multiple-projects
}

# --- what counts as one message ---------------------------------------------

@test "claude_code: a message logged two or three times is one message" {
    assert_scan_fixture claude_code duplicate-messages
}

@test "claude_code: a resumed session does not count its replays again" {
    assert_scan_fixture claude_code session-resume
}

@test "claude_code: the same message id in another session is another message" {
    assert_scan_fixture claude_code different-sessions
}

@test "claude_code: without a request id the timestamp separates records" {
    assert_scan_fixture claude_code missing-request-id
}

@test "claude_code: a sidechain replay is the message it replays" {
    assert_scan_fixture claude_code sidechain-replay
}

@test "claude_code: a record written before the response finished loses to the complete one" {
    assert_scan_fixture claude_code partial-then-complete
}

# --- which hour a message belongs to ----------------------------------------

@test "claude_code: copies straddling an hour belong to the earliest" {
    assert_scan_fixture claude_code hour-boundary
}

@test "claude_code: a session crossing midnight lands in two hours on two dates" {
    # Also the only case that separates ordering by instant from ordering by
    # hour of day: hour-boundary runs 14:00 to 15:00, where the two agree.
    assert_scan_fixture claude_code utc-day-boundary
}

@test "claude_code: hours are cut in UTC wherever the machine is" {
    # A parser that truncates in local time and converts back lands on the
    # same instant in every whole-hour offset, so only a zone offset by part
    # of an hour can tell the two apart. India is +05:30.
    TZ=Asia/Kolkata
    export TZ
    assert_scan_fixture claude_code normal-session
}

# --- input that is not a clean log ------------------------------------------

@test "claude_code: a log still being written counts everything before the cut" {
    assert_scan_fixture claude_code truncated-last-line
}

@test "claude_code: empty and blank files are not an error" {
    assert_scan_fixture claude_code empty-files
}

@test "claude_code: unknown fields are ignored and iterations are not added" {
    assert_scan_fixture claude_code unknown-fields
}

@test "claude_code: the cache_creation breakdown wins over the flat field" {
    assert_scan_fixture claude_code cache-creation-breakdown
}

@test "claude_code: totals past a 32-bit integer survive" {
    assert_scan_fixture claude_code large-totals
}

# --- the cases and the fixtures agreeing ------------------------------------

@test "claude_code: every fixture has a case above" {
    assert_fixtures_all_covered claude_code
}
