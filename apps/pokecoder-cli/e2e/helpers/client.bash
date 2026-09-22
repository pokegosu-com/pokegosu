#!/usr/bin/env bash
# Running the client under test.
#
# POKECODER_BIN names the binary under test; moon sets it to the one
# pokecoder-cli:build just made.

# require_client aborts with a readable message rather than "command not
# found" from inside a test.
require_client() {
    [[ -n ${POKECODER_BIN:-} ]] || {
        echo "POKECODER_BIN is not set; build the client and point it here" >&2
        return 1
    }
    [[ -x $POKECODER_BIN ]] || {
        echo "POKECODER_BIN is not an executable: $POKECODER_BIN" >&2
        return 1
    }
}

# use_settings <path> — every later run of the client reads and writes this
# file.
#
# Exported rather than passed, so that a test invoking the binary directly —
# through env, or a pipeline — is isolated too. Forgetting would otherwise
# write a test account's API key into the developer's own settings.
use_settings() {
    SETTINGS=$1
    export POKECODER_CONFIG=$SETTINGS
}

# pokecoder <args...> — the client under test.
#
# stdout and stderr are left apart. A caller reading output meant for a
# machine gets only that, while bats's own "run" still collects both for a
# test that asserts on a message. Merging here once cost an afternoon: a
# warning about a truncated log turned the JSON it accompanied into garbage.
pokecoder() {
    "$POKECODER_BIN" "$@"
}

# setting <field> — one field of what the client wrote, or nothing if it wrote
# no settings at all.
setting() {
    [[ -f $SETTINGS ]] || return 0
    json get "$1" < "$SETTINGS"
}
