#!/usr/bin/env bats
#
# What "pokegosu auth login" claims, and whether the server agrees.
#
#   moon run supabase:start
#   moon run cli:e2e
#
# The machine starts an enrolment and waits; a person approves it in the web.
# These tests are the person: they read the code out of what the machine
# printed, or pass one in with --code, and approve it the way the web does.
#
# Every test gets its own account and its own settings, so they can be run in
# any order, one at a time.

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

    require_tools
    require_client

    # A home of its own, so that a client looking for its default settings
    # path cannot find the developer's.
    export HOME=$BATS_TEST_TMPDIR/home
    mkdir -p "$HOME"
    use_config_home "$BATS_TEST_TMPDIR/settings"

    new_account
    SESSION=$ACCOUNT_SESSION
    USER_ID=$ACCOUNT_USER_ID
}

teardown() {
    kill "${LOGIN_PID:-}" 2> /dev/null
    delete_account "${USER_ID:-}"
    delete_account "${STRANGER_USER_ID:-}"
}

@test "the machine draws a code, and approving it enrols the machine" {
    login_in_background --url "$SERVICE_URL" --device-name laptop

    # The code a person reads off this terminal is the one the web is given.
    code=$(drawn_code)
    approve "$SESSION" "$code"
    login_finished

    device=$(setting device_id)
    [[ $device =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
    [ "$(known_as "$SESSION" "$device")" = laptop ]
}

@test "the machine says where to approve it, and says when it has been" {
    login_in_background --url "$SERVICE_URL" --device-name laptop
    code=$(drawn_code)
    approve "$SESSION" "$code"
    login_finished

    # Somebody has to be told where to go, and then that it worked.
    [[ $(cat "$LOGIN_OUTPUT") == *"$SERVICE_URL/devices/add/$code"* ]]
    [[ $(cat "$LOGIN_OUTPUT") == *approved* ]]
}

# The key is the one thing the machine did not have and could not have made:
# it comes back from the server and is what every later sync is checked by.
@test "login saves a key it was never given" {
    login_in_background --url "$SERVICE_URL" --device-name laptop
    approve "$SESSION" "$(drawn_code)"
    login_finished

    [[ "$(setting api_key)" == pgt_* ]]
    [ "$(setting url)" = "$SERVICE_URL" ]
    [ "$(setting device_name)" = laptop ]
}

# A person types the deployment's address; where its parts live is the
# deployment's to say, and login asks rather than being told.
@test "login finds the API through the service it was pointed at" {
    login_in_background --url "$SERVICE_URL" --device-name laptop
    approve "$SESSION" "$(drawn_code)"
    login_finished

    [ "$(setting api_url)" = "$API_URL" ]
}

@test "the settings file holds a secret and is readable only by its owner" {
    login_in_background --url "$SERVICE_URL" --device-name laptop
    approve "$SESSION" "$(drawn_code)"
    login_finished

    [ "$(stat -c %a "$SETTINGS")" = 600 ]
}

@test "nothing is saved until somebody approves" {
    login_in_background --url "$SERVICE_URL" --device-name laptop
    drawn_code

    # It is waiting, and has written nothing: an interrupted login leaves no
    # half-enrolled machine behind.
    [ ! -e "$SETTINGS" ]

    kill "$LOGIN_PID"
    login_failed
    [ ! -e "$SETTINGS" ]
}

@test "logging in again keeps the machine and replaces its key" {
    login_in_background --url "$SERVICE_URL" --device-name laptop
    approve "$SESSION" "$(drawn_code)"
    login_finished

    device=$(setting device_id)
    before=$(setting api_key)

    login_in_background
    approve "$SESSION" "$(drawn_code)"
    login_finished

    # Same machine, so the same history; a new key, and the old one dead
    # rather than left working beside it.
    [ "$(setting device_id)" = "$device" ]
    [ "$(setting api_key)" != "$before" ]
    [ "$(known_as "$SESSION" "$device")" = laptop ]
}

@test "a code works once" {
    code=$(random_code)
    login_in_background --url "$SERVICE_URL" --code "$code" --device-name first
    approve "$SESSION" "$code"
    login_finished

    # The request is spent, so approving it again finds nothing to approve.
    run approve "$SESSION" "$code"
    [ "$status" -ne 0 ]
}

@test "two machines cannot wait on one code" {
    code=$(random_code)
    login_in_background --url "$SERVICE_URL" --code "$code" --device-name first
    drawn_code

    use_config_home "$BATS_TEST_TMPDIR/second"
    run pokegosu auth login --url "$SERVICE_URL" --code "$code" --device-name second
    [ "$status" -ne 0 ]
    [[ $output == *"in use"* ]]
    [ ! -e "$SETTINGS" ]
}

@test "another account cannot take this machine" {
    login_in_background --url "$SERVICE_URL" --device-name laptop
    approve "$SESSION" "$(drawn_code)"
    login_finished
    device=$(setting device_id)

    new_account
    STRANGER_USER_ID=$ACCOUNT_USER_ID

    # The stranger arrives already holding the id, the way a copied settings
    # file would leave them, and approves their own request for it.
    use_config_home "$BATS_TEST_TMPDIR/stranger"
    printf '{"url": "%s", "device_id": "%s", "device_name": "stolen"}' "$SERVICE_URL" "$device" > "$SETTINGS"

    login_in_background
    approve "$ACCOUNT_SESSION" "$(drawn_code)"
    login_failed
    [[ $(cat "$LOGIN_OUTPUT") == *"another account"* ]]

    [ "$(known_as "$SESSION" "$device")" = laptop ]
    [ -z "$(known_as "$ACCOUNT_SESSION" "$device")" ]
}

# The API's own address is not a deployment: it has no discovery document. A
# person who pasted it gets told so before anything is started.
@test "an address that is not a pokegosu service is refused, and nothing is saved" {
    run pokegosu auth login --url "$API_URL" --device-name laptop
    [ "$status" -ne 0 ]
    [[ $output == *"does not look like a pokegosu service"* ]]

    [ ! -e "$SETTINGS" ]
}
