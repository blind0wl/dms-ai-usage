#!/usr/bin/env bash
# cli-proxy (CLIProxyAPI) as a Source's source of truth (ADR 0009).
#
# When the widget hands a Script AI_USAGE_CLIPROXY_URL and AI_USAGE_CLIPROXY_KEY,
# the Script asks cli-proxy's management API for the auths it holds for that
# Source and reads each one's usage through cli-proxy's api-call route, which
# substitutes the auth's own live token for $TOKEN$. The upstream response is the
# one the local path already parses, so only the transport differs.
#
# Any failure to get an auth list - cli-proxy unset, unreachable, a rejected key,
# an unexpected body, or no auth for this Source - leaves the Script on its local
# path, which is the fallback.
#
# The key travels to curl on stdin as a config line rather than as an argument,
# so it never shows up in the process list.

CLIPROXY_ORIGIN="cli-proxy"
CLIPROXY_VALUE_PREFIX="cliproxy:"

# Set by cliproxy_read: whether this run reads from cli-proxy, and the auth lines
# it read. Set by cliproxy_take_registry: the local Accounts it replaced, whose
# directories still carry the token history, and the names cli-proxy holds
# disabled.
CLIPROXY_ACTIVE=0
CLIPROXY_LINES=""
LOCAL_ACCOUNT_VALUES=()
CLIPROXY_DISABLED=()

cliproxy_configured() {
    [ -n "${AI_USAGE_CLIPROXY_URL:-}" ] && [ -n "${AI_USAGE_CLIPROXY_KEY:-}" ]
}

# cliproxy_request <method> <path> [json-body] -> the body, a newline, and the
# HTTP status (000 when no response came back).
cliproxy_request() {
    local method="$1" path="$2" data="${3:-}" key
    local args=(-s --max-time 10 -X "$method" -w $'\n%{http_code}' -K -)
    [ -n "$data" ] && args+=(-H "Content-Type: application/json" --data-binary "$data")
    key="${AI_USAGE_CLIPROXY_KEY//\\/\\\\}"
    key="${key//\"/\\\"}"
    printf 'header = "Authorization: Bearer %s"\n' "$key" \
        | curl "${args[@]}" "${AI_USAGE_CLIPROXY_URL%/}${path}" 2>/dev/null \
        || printf '\n000'
}

# cliproxy_auths <provider> -> one tab-separated line per auth cli-proxy holds
# for the provider: name, auth_index, disabled (true|false), ChatGPT account id.
# A key auth has no email, and its label ends in the key's full hash, which is
# cut to its first eight characters so the name fits a tab.
# Returns non-zero when no list could be read, so the caller falls back.
cliproxy_auths() {
    local provider="$1" raw status body
    raw=$(cliproxy_request GET /v0/management/auth-files)
    status="${raw##*$'\n'}"
    body="${raw%$'\n'*}"
    [ "$status" = "200" ] || return 1
    printf '%s' "$body" | jq -r --arg p "$provider" '
        .files[]
        | select((.provider // .type // "" | ascii_downcase) == $p)
        | select((.auth_index // "") != "")
        | [(.email // (.label // .name | sub(" credential (?<h>[0-9a-f]{8})[0-9a-f]+$"; " \(.h)"))),
           .auth_index,
           ((.disabled == true) or (.status == "disabled") | tostring),
           (.id_token.chatgpt_account_id // "")]
        | @tsv' 2>/dev/null
}

# cliproxy_read <provider>
# Asks cli-proxy for its auths once, early, so a Script can tell before its own
# detection whether the Source is in use at all. Active only when the list holds
# at least one auth for the provider.
cliproxy_read() {
    cliproxy_configured || return 0
    CLIPROXY_LINES=$(cliproxy_auths "$1") || CLIPROXY_LINES=""
    [ -n "$CLIPROXY_LINES" ] && CLIPROXY_ACTIVE=1
    return 0
}

# cliproxy_take_registry
# Replaces the local registry with cli-proxy's auths, keeping the local values
# aside. The Account value is the auth_index behind CLIPROXY_VALUE_PREFIX, with
# the ChatGPT account id after a second colon when there is one.
cliproxy_take_registry() {
    local name index disabled account base len
    [ "$CLIPROXY_ACTIVE" -eq 1 ] || return 0
    # The registry arrays are source-script.sh's, and LOCAL_ACCOUNT_VALUES is
    # read by the Script that sourced both.
    # shellcheck disable=SC2034
    [ "${#ACCOUNT_VALUES[@]}" -eq 0 ] || LOCAL_ACCOUNT_VALUES=("${ACCOUNT_VALUES[@]}")
    ACCOUNT_NAMES=()
    ACCOUNT_VALUES=()
    # shellcheck disable=SC2034
    ACCOUNT_ORIGINS=()
    # shellcheck disable=SC2034
    ACCOUNT_SHADOWED=()
    while IFS=$'\t' read -r name index disabled account; do
        # Two auths can share an email, and each is its own Account, so a name
        # already taken gets the start of its auth_index, lengthened until the
        # name is free. The auth_index is unique, so the whole of it always is.
        name="${name//[,|:]/}"
        base="$name"
        len=4
        while cliproxy_taken "$name" && [ "$len" -le "${#index}" ]; do
            name="$base ${index:0:len}"
            len=$((len + 4))
        done
        add_account "$name" "${CLIPROXY_VALUE_PREFIX}${index}:${account}" "$CLIPROXY_ORIGIN"
        [ "$disabled" = "true" ] && CLIPROXY_DISABLED+=("$name")
    done <<< "$CLIPROXY_LINES"
    return 0
}

# cliproxy_taken <name> -> success when an Account already has the name.
cliproxy_taken() {
    local n
    for n in "${ACCOUNT_NAMES[@]:-}"; do
        [ "$n" = "$1" ] && return 0
    done
    return 1
}

# cliproxy_disabled <name> -> success when cli-proxy holds the Account disabled.
cliproxy_disabled() {
    local n
    for n in "${CLIPROXY_DISABLED[@]:-}"; do
        [ "$n" = "$1" ] && return 0
    done
    return 1
}

# The first Account cli-proxy holds enabled: the one whose reading stands for
# the Source in the Pill and the Overview, as "default" does on the local path.
# Empty when every Account is disabled.
cliproxy_first_enabled() {
    local n
    for n in "${ACCOUNT_NAMES[@]:-}"; do
        [ -n "$n" ] || continue
        cliproxy_disabled "$n" || { printf '%s' "$n"; return 0; }
    done
}

# cliproxy_call <account-value> <url> <header-json> [header-file]
# -> the upstream body, a newline, and the upstream status. A failure of the
# api-call route itself reports 000, which every caller reads as Unavailable.
# With a header file, the upstream response headers are written to it as
# "Name: value" lines, so a caller can read Retry-After as it would from curl.
cliproxy_call() {
    local value="${1#"$CLIPROXY_VALUE_PREFIX"}" url="$2" header="$3" header_file="${4:-}"
    local index="${value%%:*}" payload raw status body
    payload=$(jq -cn --arg i "$index" --arg u "$url" --argjson h "$header" \
        '{auth_index: $i, method: "GET", url: $u, header: $h}' 2>/dev/null) || { printf '\n000'; return 0; }
    raw=$(cliproxy_request POST /v0/management/api-call "$payload")
    status="${raw##*$'\n'}"
    body="${raw%$'\n'*}"
    if [ "$status" != "200" ]; then
        printf '\n000'
        return 0
    fi
    if [ -n "$header_file" ]; then
        printf '%s' "$body" | jq -r '.header // {} | to_entries[] | "\(.key): \(.value | if type == "array" then .[0] else . end)"' \
            > "$header_file" 2>/dev/null || true
    fi
    printf '%s' "$body" | jq -j '"\(.body // "")\n\(.status_code // 0)"' 2>/dev/null || printf '\n000'
}
