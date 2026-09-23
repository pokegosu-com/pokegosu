#!/usr/bin/env bash
# Running the client under test.
#
# POKEGOSU_BIN names the binary under test; moon sets it to the one
# cli:build just made.

# require_client aborts with a readable message rather than "command not
# found" from inside a test.
require_client() {
    [[ -n ${POKEGOSU_BIN:-} ]] || {
        echo "POKEGOSU_BIN is not set; build the client and point it here" >&2
        return 1
    }
    [[ -x $POKEGOSU_BIN ]] || {
        echo "POKEGOSU_BIN is not an executable: $POKEGOSU_BIN" >&2
        return 1
    }
}

# use_config_home <dir> — where every later run of the client keeps its
# settings.
#
# Exported rather than passed, so that a test invoking the binary directly —
# through env, or a pipeline — is isolated too. Forgetting would otherwise
# write a test account's API key into the developer's own settings.
use_config_home() {
    export POKEGOSU_CONFIG_HOME=$1
    SETTINGS=$1/config.json
    mkdir -p "$1"
}

# pokegosu <args...> — the client under test.
#
# stdout and stderr are left apart. A caller reading output meant for a
# machine gets only that, while bats's own "run" still collects both for a
# test that asserts on a message. Merging here once cost an afternoon: a
# warning about a truncated log turned the JSON it accompanied into garbage.
pokegosu() {
    "$POKEGOSU_BIN" "$@"
}

# login_in_background <flags...> — `pokegosu auth login`, which waits for
# somebody to approve it, so a test can go and be that somebody.
#
# Output goes to a file rather than the terminal: a test reads the code the
# machine drew out of it.
login_in_background() {
    LOGIN_OUTPUT=$BATS_TEST_TMPDIR/login.out
    : > "$LOGIN_OUTPUT"
    "$POKEGOSU_BIN" auth login "$@" > "$LOGIN_OUTPUT" 2>&1 3>&- &
    LOGIN_PID=$!
}

# login_finished — waits for the login started above, and fails if it did.
#
# Never through bats's `run`: that runs in a subshell, which cannot wait for
# a process this shell started and reports a status the login never returned.
login_finished() {
    wait "$LOGIN_PID"
}

# login_failed — waits for it and fails if it did NOT fail.
login_failed() {
    local status=0
    wait "$LOGIN_PID" || status=$?
    [[ $status -ne 0 ]] || {
        echo "login succeeded; expected it to fail:" >&2
        cat "$LOGIN_OUTPUT" >&2
        return 1
    }
}

# drawn_code — the code the machine printed, once it has printed one.
drawn_code() {
    local i code
    for i in $(seq 1 100); do
        code=$(grep -o '"*[0-9A-HJKMNP-TV-Z]\{4\}-[0-9A-HJKMNP-TV-Z]\{4\}' "$LOGIN_OUTPUT" \
            | tr -d '"' | head -1)
        [[ -n $code ]] && { printf '%s' "$code"; return 0; }
        sleep 0.1
    done
    echo "the machine printed no code:" >&2
    cat "$LOGIN_OUTPUT" >&2
    return 1
}

# enrol <session> [device name] — a whole enrolment, for a test that is about
# what comes after one.
enrol() {
    local session=$1 name=${2:-}
    if [[ -n $name ]]; then
        login_in_background --url "$SERVICE_URL" --device-name "$name"
    else
        login_in_background
    fi
    approve "$session" "$(drawn_code)"
    login_finished
}

# setting <field> — one field of what the client wrote, or nothing if it wrote
# no settings at all.
setting() {
    [[ -f $SETTINGS ]] || return 0
    json get "$1" < "$SETTINGS"
}
