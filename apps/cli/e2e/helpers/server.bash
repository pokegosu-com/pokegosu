#!/usr/bin/env bash
# Talking to a local stack the way the web does: making an account, holding
# its session, asking for an enrollment code, and reading back what the
# account can see of its machines.
#
# The sign-in takes a shortcut: a person gets a code by mail and types it
# back, which is the web's business. What matters here is holding a session,
# not how it was come by.

API_URL=${API_URL:-http://127.0.0.1:54321}

# The keys a local "supabase start" always prints. Not secret: they are fixed
# in the CLI, so every local stack has the same ones. The secret key is used
# only to make and remove test accounts.
PUBLISHABLE_KEY=${PUBLISHABLE_KEY:-sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH}
SECRET_KEY=${SECRET_KEY:-sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz}

# json <command> <args...> — see json.mjs.
json() { node "$BATS_TEST_DIRNAME/helpers/json.mjs" "$@"; }

# require_tools aborts with a readable message instead of a confusing failure
# halfway through a test.
require_tools() {
    local tool
    for tool in curl node; do
        command -v "$tool" > /dev/null || {
            echo "$tool is required" >&2
            return 1
        }
    done
}

random_hex() { od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; }

# admin <method> <path> [body] — account management, with the secret key.
admin() {
    local method=$1 path=$2 body=${3:-}
    curl -s --max-time 30 -X "$method" "$API_URL$path" \
        -H "apikey: $SECRET_KEY" \
        -H "Authorization: Bearer $SECRET_KEY" \
        -H 'Content-Type: application/json' \
        ${body:+-d "$body"}
}

# as_person <session> <method> <path> [body] — a request the web would make.
as_person() {
    local session=$1 method=$2 path=$3 body=${4:-}
    curl -s --max-time 30 -X "$method" "$API_URL$path" \
        -H "apikey: $PUBLISHABLE_KEY" \
        -H "Authorization: Bearer $session" \
        -H 'Content-Type: application/json' \
        ${body:+-d "$body"}
}

# new_account — sets ACCOUNT_USER_ID and ACCOUNT_SESSION for the caller to use
# and delete.
new_account() {
    local email password
    email="$(random_hex)@e2e.test"
    password=$(random_hex)

    ACCOUNT_USER_ID=$(admin POST /auth/v1/admin/users \
        "{\"email\": \"$email\", \"password\": \"$password\", \"email_confirm\": true}" | json get id)
    [[ -n $ACCOUNT_USER_ID ]] || {
        echo "could not create a user; is the stack running at $API_URL?" >&2
        return 1
    }

    ACCOUNT_SESSION=$(curl -s --max-time 30 -X POST "$API_URL/auth/v1/token?grant_type=password" \
        -H "apikey: $PUBLISHABLE_KEY" \
        -H 'Content-Type: application/json' \
        -d "{\"email\": \"$email\", \"password\": \"$password\"}" | json get access_token)
    [[ -n $ACCOUNT_SESSION ]] || { echo "could not sign in as $email" >&2; return 1; }
}

# delete_account <user id> — what it owns goes with it, rollups first.
delete_account() {
    [[ -n ${1:-} ]] || return 0
    admin DELETE "/auth/v1/admin/users/$1" > /dev/null
}

# random_code — a code of the shape a machine draws, for tests that need to
# know it in advance.
random_code() {
    od -An -N8 -tu1 /dev/urandom | tr -s ' ' '\n' | awk '
        BEGIN { split("0123456789ABCDEFGHJKMNPQRSTVWXYZ", a, "") }
        NF { printf "%s", a[($1 % 32) + 1] }'
}

# approve <session> <code> — what a person does in the web, once they have
# read the code off the machine asking.
#
# Retried: the machine may not have asked yet when a test gets here, and the
# request appears the moment it does.
approve() {
    local session=$1 code=$2 outcome i
    for i in $(seq 1 100); do
        outcome=$(as_person "$session" POST /rest/v1/rpc/approve_enrollment \
            "{\"code\": \"$code\"}" | json get outcome)
        [[ $outcome == approved ]] && return 0
        sleep 0.1
    done
    echo "could not approve $code; the machine never asked" >&2
    return 1
}

# known_as <session> <device id> — the name the account sees for a machine,
# or nothing if it cannot see one.
known_as() {
    as_person "$1" GET "/rest/v1/devices?select=name&id=eq.$2" | json get 0.name
}

# retire <session> <device id> — what the web does to take a machine away.
retire() {
    as_person "$1" PATCH "/rest/v1/devices?id=eq.$2" "{\"revoked_at\": \"$(date -u +%FT%TZ)\"}" > /dev/null
}

# device_rollups <session> <device id> — what the account can see for a
# machine, shaped like the body a client sends, so it can be compared with a
# fixture.
#
# PostgREST renders a timestamptz as "+00:00" where a client writes "Z". The
# column is UTC on the hour by constraint, so the offset can only be zero.
device_rollups() {
    as_person "$1" GET "/rest/v1/usage_rollups?select=provider,hour_bucket,tokens&device_id=eq.$2&order=hour_bucket.asc,provider.asc" \
        | node -e '
            const rows = JSON.parse(require("fs").readFileSync(0, "utf8"));
            console.log(JSON.stringify({ rollups: rows.map((r) => ({
              provider: r.provider,
              hour_bucket: r.hour_bucket.replace(/(\+00:00|Z)$/, "Z"),
              tokens: Number(r.tokens),
            })) }));'
}

# start_service — serves the discovery document the CLI reads at login, and
# sets SERVICE_URL, the address a person would type. Once per file, from
# setup_file; stop_service in teardown_file.
start_service() {
    # fd 3 is closed so bats does not wait on the server to finish.
    node "$BATS_TEST_DIRNAME/helpers/service.mjs" "$API_URL" > "$BATS_FILE_TMPDIR/service.port" 3>&- &
    echo $! > "$BATS_FILE_TMPDIR/service.pid"

    local i
    for i in $(seq 1 50); do
        [[ -s $BATS_FILE_TMPDIR/service.port ]] && break
        sleep 0.1
    done
    [[ -s $BATS_FILE_TMPDIR/service.port ]] || { echo "the discovery service did not start" >&2; return 1; }
    export SERVICE_URL="http://127.0.0.1:$(cat "$BATS_FILE_TMPDIR/service.port")"
}

stop_service() {
    [[ -f $BATS_FILE_TMPDIR/service.pid ]] && kill "$(cat "$BATS_FILE_TMPDIR/service.pid")" 2> /dev/null
    return 0
}
