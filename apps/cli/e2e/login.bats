#!/usr/bin/env bats
#
# What "pokegosu coder login" claims, and whether the server agrees.
#
#   moon run supabase:start
#   moon run cli:e2e
#
# Enrolling is where a machine's credential comes into being, so most of these
# are about what must not work: a code twice, a code for someone else's
# machine, a code that was never issued.
#
# Every test gets its own account and its own settings file, so they can be
# run in any order, one at a time.

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
    delete_account "${USER_ID:-}"
    delete_account "${STRANGER_USER_ID:-}"
}

@test "login enrols this machine under the name it was given" {
    run pokegosu coder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" --device-name laptop
    [ "$status" -eq 0 ]

    device=$(setting device_id)
    [[ $device =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
    [ "$(known_as "$SESSION" "$device")" = laptop ]
}

# The key is the one thing the machine did not have and could not have made:
# it comes back from the server and is what every later sync is checked by.
@test "login saves a key it was never given" {
    run pokegosu coder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" --device-name laptop
    [ "$status" -eq 0 ]

    [[ "$(setting api_key)" == pgt_* ]]
    [ "$(setting url)" = "$SERVICE_URL" ]
    [ "$(setting device_name)" = laptop ]
}

# A person types the service's address; where its API lives is the service's
# to say, and login asks rather than being told.
@test "login finds the API through the service it was pointed at" {
    run pokegosu coder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" --device-name laptop
    [ "$status" -eq 0 ]

    [ "$(setting api_url)" = "$API_URL" ]
    [ "$(setting device_name)" = laptop ]
}

@test "the settings file holds a secret and is readable only by its owner" {
    pokegosu coder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" --device-name laptop

    [ "$(stat -c %a "$SETTINGS")" = 600 ]
}

@test "logging in again keeps the machine and replaces its key" {
    pokegosu coder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" --device-name laptop
    device=$(setting device_id)
    before=$(setting api_key)

    run pokegosu coder login --code "$(enrollment_code "$SESSION")"
    [ "$status" -eq 0 ]
    [[ $output == *"enrols it again"* ]]

    # Same machine, so the same history; a new key, and the old one dead
    # rather than left working beside it.
    [ "$(setting device_id)" = "$device" ]
    [ "$(setting api_key)" != "$before" ]
    [ "$(known_as "$SESSION" "$device")" = laptop ]
}

@test "a code works once" {
    code=$(enrollment_code "$SESSION")
    pokegosu coder login --url "$SERVICE_URL" --code "$code" --device-name first

    use_config_home "$BATS_TEST_TMPDIR/second"
    run pokegosu coder login --url "$SERVICE_URL" --code "$code" --device-name second
    [ "$status" -ne 0 ]

    [ ! -e "$SETTINGS" ]
}

@test "a code nobody issued leaves no settings behind" {
    run pokegosu coder login --url "$SERVICE_URL" --code XPTQ-4F2K --device-name laptop
    [ "$status" -ne 0 ]
    [[ $output == *"not valid"* ]]

    [ ! -e "$SETTINGS" ]
}

# The code is read off one screen and typed into another. Someone who types it
# in lower case, or leaves the dash out, has not got it wrong.
@test "a code survives being typed by a person" {
    code=$(enrollment_code "$SESSION")
    mangled=$(printf '%s' "$code" | tr 'A-Z' 'a-z' | tr -d -)

    run pokegosu coder login --url "$SERVICE_URL" --code "$mangled" --device-name laptop
    [ "$status" -eq 0 ]
}

@test "the code can be typed in instead of passed as a flag" {
    code=$(enrollment_code "$SESSION")

    run sh -c "printf '%s\n' '$code' | '$POKEGOSU_BIN' coder login --url '$SERVICE_URL' --device-name typed"
    [ "$status" -eq 0 ]

    [ "$(known_as "$SESSION" "$(setting device_id)")" = typed ]
}

@test "another account cannot claim this machine" {
    pokegosu coder login --url "$SERVICE_URL" --code "$(enrollment_code "$SESSION")" --device-name laptop
    device=$(setting device_id)

    new_account
    STRANGER_USER_ID=$ACCOUNT_USER_ID

    # The stranger arrives already holding the id, the way a copied settings
    # file would leave them, but with a code from their own account.
    use_config_home "$BATS_TEST_TMPDIR/stranger"
    printf '{"url": "%s", "device_id": "%s", "device_name": "stolen"}' "$SERVICE_URL" "$device" > "$SETTINGS"

    run pokegosu coder login --code "$(enrollment_code "$ACCOUNT_SESSION")"
    [ "$status" -ne 0 ]
    [[ $output == *"another account"* ]]

    [ "$(known_as "$SESSION" "$device")" = laptop ]
    [ -z "$(known_as "$ACCOUNT_SESSION" "$device")" ]
}

# The API's own address is not a service: it has no discovery document. A
# person who pasted it gets told so before any code is spent.
@test "an address that is not a coder service is refused, and nothing is saved" {
    run pokegosu coder login --url "$API_URL" --code "$(enrollment_code "$SESSION")" --device-name laptop
    [ "$status" -ne 0 ]
    [[ $output == *"does not look like a coder service"* ]]

    [ ! -e "$SETTINGS" ]
}
