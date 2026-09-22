#!/usr/bin/env bash
# Running the implementation under test.
#
# TOKENUSAGE_DRIVER names a driver: a small program, one per language, that
# puts that language's library behind the protocol in README.md. The harness
# knows nothing else about it, which is what lets one set of cases check them
# all.

# require_driver aborts with a readable message rather than "command not
# found" from inside a test.
require_driver() {
    [[ -n ${TOKENUSAGE_DRIVER:-} ]] || {
        echo "TOKENUSAGE_DRIVER is not set; build a driver and point it here" >&2
        return 1
    }
    [[ -x $TOKENUSAGE_DRIVER ]] || {
        echo "TOKENUSAGE_DRIVER is not an executable: $TOKENUSAGE_DRIVER" >&2
        return 1
    }
}

# driver <args...> — the implementation under test.
driver() {
    "$TOKENUSAGE_DRIVER" "$@"
}
