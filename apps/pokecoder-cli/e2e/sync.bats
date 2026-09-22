#!/usr/bin/env bats
#
# What "pokecoder sync" claims: that the numbers the server ends up holding
# are the numbers the logs say, and that a routine run carries only what
# moved.
#
#   moon run supabase:start
#   moon run pokecoder-cli:e2e
#
# Each test gets its own account, machine and settings file, so they can be
# run in any order or one at a time.

setup_file() {
    load helpers/server
    start_service
}

teardown_file() {
    load helpers/server
    stop_service
}

setup() {
    load helpers/server
    load helpers/client
    load helpers/fixtures

    require_tools
    require_client

    export HOME=$BATS_TEST_TMPDIR/home
    mkdir -p "$HOME"
    use_settings "$BATS_TEST_TMPDIR/settings.json"

    new_account
    USER_ID=$ACCOUNT_USER_ID
    SESSION=$ACCOUNT_SESSION

    pokecoder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" \
        --device-name sync-test > /dev/null
    DEVICE=$(setting device_id)
}

teardown() {
    delete_account "${USER_ID:-}"
}

# sync_fixture <provider> <case> — sync reading one fixture instead of the
# machine's own logs.
sync_fixture() {
    pokecoder sync --provider "$1" --path "$(fixture_logs "$1" "$2")" "${@:3}"
}

@test "what the logs say is what the server ends up holding" {
    run sync_fixture claude_code normal-session
    [ "$status" -eq 0 ]

    assert_synced claude_code normal-session "$(device_rollups "$SESSION" "$DEVICE")"
}

@test "several hours and several projects arrive together" {
    run sync_fixture claude_code multiple-projects
    [ "$status" -eq 0 ]

    assert_synced claude_code multiple-projects "$(device_rollups "$SESSION" "$DEVICE")"
}

@test "a second run with nothing new sends nothing" {
    sync_fixture claude_code normal-session

    run sync_fixture claude_code normal-session
    [ "$status" -eq 0 ]
    [[ $output == *"nothing to send"* ]]
}

@test "--all sends everything again and lands on the same numbers" {
    sync_fixture claude_code normal-session

    run sync_fixture claude_code normal-session --all
    [ "$status" -eq 0 ]
    [[ $output == *"sent 1 bucket"* ]]

    assert_synced claude_code normal-session "$(device_rollups "$SESSION" "$DEVICE")"
}

@test "a bucket that grew is sent again and replaces the old value" {
    # The same hour from two fixtures: normal-session has three messages in
    # 14:00, truncated-last-line has two. Syncing one then the other is a
    # bucket changing value, which is what re-reading a growing log does.
    sync_fixture claude_code truncated-last-line
    [ "$(device_rollups "$SESSION" "$DEVICE" | json get rollups.0.tokens)" -eq 2222 ]

    run sync_fixture claude_code normal-session
    [ "$status" -eq 0 ]
    [[ $output == *"sent 1 bucket"* ]]

    # Absolute values: the later number wins rather than adding to the first.
    [ "$(device_rollups "$SESSION" "$DEVICE" | json get rollups.0.tokens)" -eq 3333 ]
}

@test "two machines on one account keep separate ledgers" {
    sync_fixture claude_code normal-session
    first=$DEVICE

    use_settings "$BATS_TEST_TMPDIR/second.json"
    pokecoder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" \
        --device-name second > /dev/null
    second=$(setting device_id)
    [ "$second" != "$first" ]

    run sync_fixture claude_code multiple-projects
    [ "$status" -eq 0 ]

    # Each machine reports its own logs, and neither overwrites the other.
    assert_synced claude_code normal-session "$(device_rollups "$SESSION" "$first")"
    assert_synced claude_code multiple-projects "$(device_rollups "$SESSION" "$second")"
}

@test "sync without login says to log in" {
    use_settings "$BATS_TEST_TMPDIR/absent.json"

    run pokecoder sync
    [ "$status" -ne 0 ]
    [[ $output == *login* ]]
}

# The key says which machine the rows are for, and the settings cannot argue:
# an id edited to name something else changes nothing about where usage lands.
@test "editing the settings cannot point the ledger at another machine" {
    json set "$SETTINGS" device_id 11111111-2222-4333-8444-555555555555

    run sync_fixture claude_code normal-session
    [ "$status" -eq 0 ]

    assert_synced claude_code normal-session "$(device_rollups "$SESSION" "$DEVICE")"
    [ "$(device_rollups "$SESSION" 11111111-2222-4333-8444-555555555555 | json get rollups.length)" = 0 ]
}

@test "a machine retired in the web is refused, and says how to come back" {
    retire "$SESSION" "$DEVICE"

    run sync_fixture claude_code normal-session
    [ "$status" -ne 0 ]
    [[ $output == *"login again"* ]]
}

@test "logging in again brings a retired machine back with its history" {
    sync_fixture claude_code truncated-last-line
    retire "$SESSION" "$DEVICE"

    pokecoder login --code "$(enrollment_code "$SESSION")" > /dev/null
    [ "$(setting device_id)" = "$DEVICE" ]

    run sync_fixture claude_code normal-session
    [ "$status" -eq 0 ]

    # One machine, one ledger: the hour it reported before retiring is the one
    # the new number replaces.
    assert_synced claude_code normal-session "$(device_rollups "$SESSION" "$DEVICE")"
}

@test "--quiet says nothing when there is nothing to say" {
    sync_fixture claude_code normal-session

    run sync_fixture claude_code normal-session --quiet
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
