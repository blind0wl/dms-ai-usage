#!/usr/bin/env bash
# Tests for cli-proxy as the source of truth (ADR 0009): its auths replace the
# local Accounts, a disabled one is listed but never asked, and anything short of
# an auth list leaves the Script on its local path.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}
value_of() {
    printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2- || true
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

KEY='s3cret-"key'
URL="http://cliproxy.test:8317"

# A curl standing in for cli-proxy. It answers the two management routes from
# files in $STUB, records its arguments and its stdin config, and fails every
# other request as unreachable, so the local path's own calls go nowhere.
# Exported so the stub curl, a separate process, finds its files.
export STUB="$TMPDIR_ROOT/stub"
mkdir -p "$STUB/bin"
cat > "$STUB/bin/curl" << 'CURLEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB/argv.log"
url="" data="" prev="" config=""
for a in "$@"; do
    [ "$prev" = "--data-binary" ] && data="$a"
    [ "$prev" = "-K" ] && [ "$a" = "-" ] && config=$(cat)
    prev="$a"
    url="$a"
done
printf '%s\n' "$config" >> "$STUB/config.log"
case "$url" in
    */v0/management/auth-files)
        mode=$(cat "$STUB/mode" 2>/dev/null || echo up)
        case "$mode" in
            down) printf '\n000'; exit 7 ;;
            unauthorized) printf '{"error":"invalid management key"}\n401' ;;
            *) cat "$STUB/auth-files.json"; printf '\n200' ;;
        esac
        ;;
    */v0/management/api-call)
        printf '%s\n' "$data" >> "$STUB/api-calls.log"
        index=$(printf '%s' "$data" | jq -r '.auth_index')
        status=$(cat "$STUB/upstream-$index.status" 2>/dev/null || echo 200)
        jq -cn --rawfile b "$STUB/upstream-$index.json" --argjson s "$status" \
            '{status_code: $s, header: {}, body: $b}'
        printf '\n200'
        ;;
    *) printf '\n000'; exit 7 ;;
esac
CURLEOF
chmod +x "$STUB/bin/curl"

# Claude's usage cache would otherwise answer a run from the one before it.
reset_stub() {
    rm -f "$STUB"/*.log "$STUB"/*.status "$STUB/mode" "$HOME_DIR"/.claude/usage-cache*.json
}

auth_files() {
    printf '%s' "$1" > "$STUB/auth-files.json"
}

# A home with a local Claude Profile and a local Codex Account, so a fallback
# has something to fall back to.
HOME_DIR="$TMPDIR_ROOT/home"
mkdir -p "$HOME_DIR/.claude/projects/p" "$HOME_DIR/.codex/sessions"
printf '{"claudeAiOauth":{"accessToken":"local","subscriptionType":"pro"}}' > "$HOME_DIR/.claude/.credentials.json"
printf '{"tokens":{"access_token":"a.b.c","account_id":"local"}}' > "$HOME_DIR/.codex/auth.json"

run() {
    local script="$1"
    shift
    HOME="$HOME_DIR" PATH="$STUB/bin:$PATH" \
        AI_USAGE_CLIPROXY_URL="$URL" AI_USAGE_CLIPROXY_KEY="$KEY" \
        bash "$SCRIPT_DIR/$script" "$@" 2>/dev/null
}

THREE_AUTHS='{"files":[
 {"auth_index":"c1","provider":"claude","email":"a@x.com","disabled":false},
 {"auth_index":"c2","provider":"claude","email":"b@y.com","disabled":true},
 {"auth_index":"x1","provider":"codex","email":"c@z.com","disabled":false,"id_token":{"chatgpt_account_id":"acct-9"}},
 {"auth_index":"o1","provider":"opencode-go","label":"OpenCode Go credential c464ebc7b48be7969ae8b4fa","disabled":false}]}'
printf '{"five_hour":{"utilization":42,"resets_at":"2026-10-28T01:00:00Z"},"seven_day":{"utilization":7,"resets_at":"2026-11-01T00:00:00Z"}}' > "$STUB/upstream-c1.json"
printf '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":33,"reset_at":1793000000,"limit_window_seconds":18000},"secondary_window":{"used_percent":5,"reset_at":1793500000,"limit_window_seconds":604800}}}' > "$STUB/upstream-x1.json"
printf '{"usage":{"rolling":{"percent":12,"resetsAt":"2026-10-28T01:00:00Z"},"weekly":{"percent":3,"resetsAt":"2026-11-01T00:00:00Z"}}}' > "$STUB/upstream-o1.json"

echo "=== cli-proxy's Claude auths replace the local Profiles ==="
reset_stub
auth_files "$THREE_AUTHS"
OUT=$(run get-claude-usage)
assert_eq "$(value_of "$OUT" ACCOUNTS)" "a@x.com,b@y.com" "the Profiles are cli-proxy's Claude auths"
assert_eq "$(value_of "$OUT" CLIPROXY)" "true" "the report says cli-proxy answered"
assert_eq "$(value_of "$OUT" FIVE_HOUR_UTIL)" "42" "the Source reading is the first enabled auth's"
assert_eq "$(value_of "$OUT" CREDS_STATUS)" "ok" "the Source status is the first enabled auth's"
assert_eq "$(value_of "$OUT" ACCOUNT_CREDS_STATUS)" "a@x.com:ok,b@y.com:disabled" "a disabled auth is listed as disabled"
assert_eq "$(grep -c '"auth_index":"c2"' "$STUB/api-calls.log" || true)" "0" "a disabled auth is never asked for usage"
# shellcheck disable=SC2016
assert_eq "$(jq -r '.header.Authorization' < "$STUB/api-calls.log")" 'Bearer $TOKEN$' "cli-proxy puts the token in the request"
assert_eq "$(grep -c 's3cret' "$STUB/argv.log" || true)" "0" "the key never appears in curl's arguments"
assert_eq "$(grep -c 'Bearer s3cret-\\"key' "$STUB/config.log" || true)" "$(grep -c . "$STUB/config.log")" "the key reaches curl on stdin, quoted"

LIST=$(run get-claude-usage --list-accounts)
assert_eq "$(value_of "$LIST" ACCOUNT_ORIGINS)" "a@x.com:cli-proxy,b@y.com:cli-proxy" "the settings page lists them under cli-proxy"

echo "=== two auths sharing an email are two Accounts ==="
reset_stub
auth_files '{"files":[
 {"auth_index":"c1","provider":"claude","email":"a@x.com","disabled":false},
 {"auth_index":"c2aa0000","provider":"claude","email":"a@x.com","disabled":false},
 {"auth_index":"c2aa1111","provider":"claude","email":"a@x.com","disabled":true}]}'
cp "$STUB/upstream-c1.json" "$STUB/upstream-c2aa0000.json"
OUT=$(run get-claude-usage)
assert_eq "$(value_of "$OUT" ACCOUNT_CREDS_STATUS)" "a@x.com:ok,a@x.com c2aa:ok,a@x.com c2aa1111:disabled" "each keeps its own name and status"
auth_files "$THREE_AUTHS"

echo "=== an expired cli-proxy auth reports expired ==="
reset_stub
printf '401' > "$STUB/upstream-c1.status"
OUT=$(run get-claude-usage)
assert_eq "$(value_of "$OUT" CREDS_STATUS)" "expired" "an upstream 401 is expired, not a reading"
rm -f "$STUB/upstream-c1.status"

echo "=== every auth disabled: no fallback, no request ==="
reset_stub
auth_files '{"files":[{"auth_index":"c2","provider":"claude","email":"b@y.com","disabled":true}]}'
OUT=$(run get-claude-usage)
assert_eq "$(value_of "$OUT" ACCOUNTS)" "b@y.com" "the disabled auth stays listed"
assert_eq "$(value_of "$OUT" CREDS_STATUS)" "disabled" "the Source reports disabled"
assert_eq "$([ -f "$STUB/api-calls.log" ] && echo called || echo none)" "none" "nothing is asked of cli-proxy's api-call"

echo "=== falling back to the local path ==="
for mode in down unauthorized empty; do
    reset_stub
    if [ "$mode" = empty ]; then
        auth_files '{"files":[{"auth_index":"x1","provider":"codex","email":"c@z.com"}]}'
    else
        auth_files "$THREE_AUTHS"
        printf '%s' "$mode" > "$STUB/mode"
    fi
    OUT=$(run get-claude-usage)
    assert_eq "$(value_of "$OUT" ACCOUNTS)" "default" "$mode: the local Profile is used"
    assert_eq "$(value_of "$OUT" CLIPROXY)" "false" "$mode: the report says the local path answered"
done
reset_stub
auth_files "$THREE_AUTHS"
OUT=$(HOME="$HOME_DIR" PATH="$STUB/bin:$PATH" bash "$SCRIPT_DIR/get-claude-usage" 2>/dev/null)
assert_eq "$(value_of "$OUT" ACCOUNTS)" "default" "unset: the local Profile is used"
assert_eq "$(cat "$STUB/argv.log" 2>/dev/null | grep -c management || true)" "0" "unset: cli-proxy is never asked"

echo "=== ChatGPT and opencode Go read through cli-proxy too ==="
reset_stub
auth_files "$THREE_AUTHS"
OUT=$(run get-chatgpt-usage)
assert_eq "$(value_of "$OUT" ACCOUNTS)" "c@z.com" "ChatGPT's Accounts are cli-proxy's Codex auths"
assert_eq "$(value_of "$OUT" PRIMARY_UTIL)" "33" "ChatGPT's reading comes through api-call"
assert_eq "$(jq -r '.header["ChatGPT-Account-Id"]' < "$STUB/api-calls.log")" "acct-9" "the ChatGPT account id rides the request"

reset_stub
OUT=$(run get-opencode-go-usage)
assert_eq "$(value_of "$OUT" ACCOUNTS)" "OpenCode Go c464ebc7" "opencode Go's Accounts are cli-proxy's keys, by short hash"
assert_eq "$(value_of "$OUT" PRIMARY_UTIL)" "12" "opencode Go's reading comes through api-call"

# A second, busier key does not take the Source's reading from the first, and a
# broken local auth file does not stop cli-proxy being asked.
reset_stub
auth_files '{"files":[
 {"auth_index":"o1","provider":"opencode-go","label":"one","disabled":false},
 {"auth_index":"o2","provider":"opencode-go","label":"two","disabled":false}]}'
printf '{"usage":{"rolling":{"percent":90,"resetsAt":"2026-10-28T03:00:00Z"},"weekly":{"percent":3,"resetsAt":"2026-11-01T00:00:00Z"}}}' > "$STUB/upstream-o2.json"
mkdir -p "$HOME_DIR/.pi/agent"
printf '{broken' > "$HOME_DIR/.pi/agent/auth.json"
OUT=$(run get-opencode-go-usage)
assert_eq "$(value_of "$OUT" PRIMARY_UTIL)" "12" "the Source reading is the first enabled key's, not the highest"
assert_eq "$(value_of "$OUT" CREDS_STATUS)" "ok" "a broken local auth file does not block cli-proxy"
rm -rf "$HOME_DIR/.pi"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
