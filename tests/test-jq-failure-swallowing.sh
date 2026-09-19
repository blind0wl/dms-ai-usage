#!/usr/bin/env bash
# Tests for a jq that is present but fails inside the three Scripts that used to
# swallow its failure (#64, ADR 0005).
#
# Every jq call in get-chatgpt-usage, get-zai-usage and get-opencode-go-usage
# used to carry a guard of the form `2>/dev/null || echo ""`, which cannot tell
# "the file has no such key" from "jq could not read the file at all". A jq that
# ran and failed therefore read as an absent credential: ChatGPT offered a
# sign-in for credentials that were present, and Z.ai and opencode Go reported
# Not installed with an empty Account list.
#
# These tests run each Script against a jq that exits non-zero and pin the same
# rule the Claude Script follows: a failed read is Blocked with the command
# named, a body that is not valid JSON is Unavailable, and a file that genuinely
# lacks the key keeps its credential verdict.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}
assert_no_key() {
    if echo "$1" | grep -q "^$2="; then fail "$3 (unexpected key '$2')"; else pass "$3"; fi
}
# CREDS_STATUS must always be one the widget can render: never empty, never a
# value outside the vocabulary (AiUsageWidget.qml's applyCredsStatus and the
# registry's status handling).
assert_renderable() {
    local out="$1" label="$2" status
    status=$(val "$out" CREDS_STATUS)
    if [ -z "$status" ]; then
        fail "$label: CREDS_STATUS is empty"
    elif echo "$status" | grep -qE '^(ok|missing|expired|not_installed|unavailable|blocked)$'; then
        pass "$label: CREDS_STATUS=$status is renderable"
    else
        fail "$label: CREDS_STATUS='$status' is outside the vocabulary"
    fi
    assert_eq "$(echo "$out" | grep -c "^CREDS_STATUS=")" "1" "$label: exactly one CREDS_STATUS line"
}

val() { echo "$1" | grep "^$2=" | cut -d= -f2-; }

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available"
    exit 0
fi
REAL_JQ=$(command -v jq)

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# The captured-response fixtures the Scripts parse on a healthy run.
CHATGPT_OK='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":42,"reset_at":"2099-01-01T00:00:00Z","limit_window_seconds":18000},"secondary_window":{"used_percent":15,"reset_at":"2099-01-07T00:00:00Z","limit_window_seconds":604800}},"credits":{"balance":5,"has_credits":true}}'
ZAI_QUOTA='{"code":200,"msg":"ok","data":{"limits":[{"type":"CREDIT_LIMIT","unit":3,"percentage":34,"nextResetTime":1789279094313},{"type":"CREDIT_LIMIT","unit":6,"percentage":6,"nextResetTime":1789865116984}],"level":"lite"},"success":true}'
ZAI_MODEL='{"code":200,"success":true,"data":{"granularity":"hourly","totalUsage":{"totalModelCallCount":0,"totalTokensUsage":0},"modelSummaryList":[],"x_time":[],"tokensUsage":[]}}'
OPENCODE_OK='{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-09-16T15:31:05.155Z"},"weekly":{"status":"ok","percent":6,"resetsAt":"2026-09-21T00:00:00.155Z"}}}'

# A PATH holding the mocks a Script run needs plus a jq that either works or
# fails on the argument the given pattern matches, the way a broken jq does.
# Everything it is not told to fail on is answered by the real jq.
CURL_LOG=""
make_bin() {
    local dir="$1" fail_pattern="${2:-}"
    mkdir -p "$dir"
    cat > "$dir/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
url=""
want_status=0
for arg in "$@"; do
    case "$arg" in
        https://*) url="$arg" ;;
        *'%{http_code}'*) want_status=1 ;;
    esac
done
printf '%s\n' "$url" >> "${CURL_LOG:-/dev/null}"
body='{}'
case "$url" in
    *chatgpt.com*)  body="$MOCK_CHATGPT_BODY" ;;
    *api.z.ai*quota/limit*) body="$MOCK_ZAI_QUOTA" ;;
    *api.z.ai*)     body="$MOCK_ZAI_MODEL" ;;
    *opencode.ai*)  body="$MOCK_OPENCODE_BODY" ;;
esac
printf '%s' "$body"
# Only the z.ai and opencode Go Scripts ask for the status line; the ChatGPT one
# does not, so appending it there would corrupt the body.
[ "$want_status" = 1 ] && printf '\n%s' "${MOCK_HTTP_STATUS:-200}"
exit 0
EOF
    chmod +x "$dir/codex" "$dir/curl"
    if [ -n "$fail_pattern" ]; then
        cat > "$dir/jq" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    case "\$arg" in *$fail_pattern*) exit 3 ;; esac
done
exec "$REAL_JQ" "\$@"
EOF
        chmod +x "$dir/jq"
    else
        ln -sf "$REAL_JQ" "$dir/jq"
    fi
}

# A PATH whose jq cannot validate even a known-good object: it fails every
# `jq -e .` call, which is the probe that separates a bad body from a broken
# tool.
make_probe_bin() {
    local dir="$1"
    make_bin "$dir"
    rm -f "$dir/jq"
    cat > "$dir/jq" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-e" ] && [ "\$2" = "." ]; then exit 3; fi
exec "$REAL_JQ" "\$@"
EOF
    chmod +x "$dir/jq"
}

# --- Per-Script credential fixtures, one per outcome the Script must tell apart ---
# mode: valid (a complete credential), read-fail (a complete credential under a
# jq that fails on it), no-key (a valid file that genuinely lacks the key).
setup_home() {
    local script="$1" dir="$2" mode="$3"
    case "$script" in
        get-chatgpt-usage)
            mkdir -p "$dir/.codex"
            case "$mode" in
                no-key) printf '{"tokens":{},"last_refresh":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dir/.codex/auth.json" ;;
                *)
                    local exp payload
                    exp=$(( $(date +%s) + 86400 ))
                    payload=$(printf '{"exp":%d}' "$exp" | base64 -w0 | tr '+/' '-_' | tr -d '=')
                    printf '{"tokens":{"access_token":"h.%s.s","account_id":"acct"},"last_refresh":"%s"}\n' \
                        "$payload" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dir/.codex/auth.json"
                    ;;
            esac
            ;;
        get-zai-usage)
            mkdir -p "$dir/.pi/agent"
            case "$mode" in
                no-key) printf '{"providers":{"zai":{}}}\n' > "$dir/.pi/agent/models.json" ;;
                *) printf '{"providers":{"zai":{"apiKey":"k1"}}}\n' > "$dir/.pi/agent/models.json" ;;
            esac
            ;;
        get-opencode-go-usage)
            mkdir -p "$dir/.pi/agent"
            case "$mode" in
                no-key) printf '{"opencode-go":{}}\n' > "$dir/.pi/agent/auth.json" ;;
                *) printf '{"opencode-go":{"type":"api_key","key":"k1"}}\n' > "$dir/.pi/agent/auth.json" ;;
            esac
            ;;
    esac
}

run_script() {
    local script="$1" bin="$2" home="$3"
    shift 3
    HOME="$home" CODEX_HOME="$home/.codex" PATH="$bin:$TMPDIR_ROOT:$PATH" \
    CURL_LOG="$CURL_LOG" \
    MOCK_CHATGPT_BODY="$CHATGPT_OK" MOCK_ZAI_QUOTA="$ZAI_QUOTA" \
    MOCK_ZAI_MODEL="$ZAI_MODEL" MOCK_OPENCODE_BODY="$OPENCODE_OK" \
    ZAI_API_KEY="" OPENCODE_GO_KEY="" OPENCODE_API_KEY="" \
        bash "$SCRIPT_DIR/$script" "$@" 2>/dev/null
}

BIN_OK="$TMPDIR_ROOT/bin-ok"
make_bin "$BIN_OK"

# script | credential-read fail pattern | response-extraction fail pattern |
# status a valid file that lacks the key yields | 1 when discovery reads the file
# (so a listing is Blocked too)
SPECS=(
    "get-chatgpt-usage|.tokens.|.rate_limit.primary_window.used_percent|missing|0"
    "get-zai-usage|providers.zai.apiKey|data.level|not_installed|1"
    "get-opencode-go-usage|opencode-go|usage.rolling.percent|not_installed|1"
)

new_home() { local dir="$TMPDIR_ROOT/$1"; mkdir -p "$dir"; echo "$dir"; }

for spec in "${SPECS[@]}"; do
    IFS='|' read -r script cred_fail resp_fail no_key_status list_fail <<< "$spec"
    BIN_CREDS="$TMPDIR_ROOT/bin-creds-$script"
    BIN_RESP="$TMPDIR_ROOT/bin-resp-$script"
    make_bin "$BIN_CREDS" "$cred_fail"
    make_bin "$BIN_RESP" "$resp_fail"

    # ============================================================
    echo "=== $script: jq fails reading the credential file ==="
    # ============================================================
    CURL_LOG="$TMPDIR_ROOT/curl-creds.log"; : > "$CURL_LOG"
    HOME_CREDS=$(new_home "$script-creds")
    setup_home "$script" "$HOME_CREDS" valid
    OUT_CREDS=$(run_script "$script" "$BIN_CREDS" "$HOME_CREDS")

    assert_eq "$(val "$OUT_CREDS" CREDS_STATUS)" "blocked" "a failed credential read is Blocked, not a credential verdict"
    assert_eq "$(val "$OUT_CREDS" BLOCKING_REQUIREMENT)" "jq" "the Blocked report names jq"
    if [ "$list_fail" = 1 ]; then
        # The read happens during discovery, so nothing was found to list.
        assert_eq "$(val "$OUT_CREDS" ACCOUNTS)" "" "no Account is reported when the discovery read failed"
    else
        # The Account is discovered from the file's presence; only its
        # credential could not be read, so it stays listed for the Blocked card.
        if [ -n "$(val "$OUT_CREDS" ACCOUNTS)" ]; then
            pass "the discovered Account stays listed when only its read failed"
        else
            fail "the discovered Account should stay listed when only its read failed"
        fi
    fi
    assert_renderable "$OUT_CREDS" "$script credential read"
    for wrong in ok missing expired not_installed; do
        if [ "$(val "$OUT_CREDS" CREDS_STATUS)" = "$wrong" ]; then
            fail "a failed credential read must not report $wrong"
        else
            pass "a failed credential read is not $wrong"
        fi
    done
    assert_no_key "$OUT_CREDS" "PRIMARY_UTIL" "a Blocked report carries no Window reading"
    if [ -s "$CURL_LOG" ]; then
        fail "no request may be made once the credential read has failed"
    else
        pass "no request is made once the credential read has failed"
    fi

    if [ "$list_fail" = 1 ]; then
        CURL_LOG="$TMPDIR_ROOT/curl-creds-list.log"; : > "$CURL_LOG"
        LIST_CREDS=$(run_script "$script" "$BIN_CREDS" "$HOME_CREDS" --list-accounts)
        assert_eq "$(val "$LIST_CREDS" CREDS_STATUS)" "blocked" "the listing is Blocked too, so the editor knows why it is empty"
        assert_eq "$(val "$LIST_CREDS" BLOCKING_REQUIREMENT)" "jq" "the listing names the failed command"
        assert_eq "$(val "$LIST_CREDS" ACCOUNTS)" "" "the listing answers with an empty Account list"
        if [ -s "$CURL_LOG" ]; then
            fail "opening the settings page may not spend a request"
        else
            pass "opening the settings page spends no request"
        fi
    fi

    # ============================================================
    echo "=== $script: jq fails extracting a valid response body ==="
    # ============================================================
    HOME_RESP=$(new_home "$script-resp")
    setup_home "$script" "$HOME_RESP" valid
    OUT_RESP=$(run_script "$script" "$BIN_RESP" "$HOME_RESP")

    assert_eq "$(val "$OUT_RESP" CREDS_STATUS)" "blocked" "an extraction failure on a valid body is Blocked"
    assert_eq "$(val "$OUT_RESP" BLOCKING_REQUIREMENT)" "jq" "the extraction failure names jq"
    assert_renderable "$OUT_RESP" "$script response extraction"

    # ============================================================
    echo "=== $script: jq fails the validity probe ==="
    # ============================================================
    # A jq that cannot parse even a known-good object is the tool failing, not
    # the endpoint answering with an unexpected body, so it must be Blocked.
    BIN_PROBE="$TMPDIR_ROOT/bin-probe-$script"
    make_probe_bin "$BIN_PROBE"
    HOME_PROBE=$(new_home "$script-probe")
    setup_home "$script" "$HOME_PROBE" valid
    OUT_PROBE=$(run_script "$script" "$BIN_PROBE" "$HOME_PROBE")

    assert_eq "$(val "$OUT_PROBE" CREDS_STATUS)" "blocked" "a jq that cannot parse a known-good object is Blocked, not Unavailable"
    assert_eq "$(val "$OUT_PROBE" BLOCKING_REQUIREMENT)" "jq" "the probe failure names jq"
    assert_renderable "$OUT_PROBE" "$script probe failure"

    # ============================================================
    echo "=== $script: the body is not valid JSON ==="
    # ============================================================
    HOME_UNJ=$(new_home "$script-nonjson")
    setup_home "$script" "$HOME_UNJ" valid
    # The fixtures are environment variables, so a non-JSON body is set inline.
    OUT_UNJ=$(HOME="$HOME_UNJ" CODEX_HOME="$HOME_UNJ/.codex" PATH="$BIN_OK:$TMPDIR_ROOT:$PATH" \
        MOCK_CHATGPT_BODY='<html>not json</html>' MOCK_ZAI_QUOTA='<html>not json</html>' \
        MOCK_ZAI_MODEL='<html>not json</html>' MOCK_OPENCODE_BODY='<html>not json</html>' \
        ZAI_API_KEY="" OPENCODE_GO_KEY="" OPENCODE_API_KEY="" \
        bash "$SCRIPT_DIR/$script" 2>/dev/null)

    assert_eq "$(val "$OUT_UNJ" CREDS_STATUS)" "unavailable" "a body that is not valid JSON is Unavailable, not Blocked"
    assert_no_key "$OUT_UNJ" "BLOCKING_REQUIREMENT" "no command is blamed for an endpoint's unexpected body"
    assert_renderable "$OUT_UNJ" "$script non-JSON body"

    # ============================================================
    echo "=== $script: a valid file that genuinely lacks the key ==="
    # ============================================================
    HOME_NOKEY=$(new_home "$script-nokey")
    setup_home "$script" "$HOME_NOKEY" no-key
    OUT_NOKEY=$(run_script "$script" "$BIN_OK" "$HOME_NOKEY")

    assert_eq "$(val "$OUT_NOKEY" CREDS_STATUS)" "$no_key_status" "a file that lacks the key keeps its credential verdict"
    assert_no_key "$OUT_NOKEY" "BLOCKING_REQUIREMENT" "a genuine absence names no command"
    assert_renderable "$OUT_NOKEY" "$script absent key"
done

# The token's own jq read is guarded too: a payload that cannot be parsed is the
# tool failing, not a token with no expiry.
echo "=== get-chatgpt-usage: jq fails reading the token's exp claim ==="
BIN_JWT="$TMPDIR_ROOT/bin-jwt"
make_bin "$BIN_JWT" ".exp"
HOME_JWT=$(new_home "chatgpt-jwt")
setup_home "get-chatgpt-usage" "$HOME_JWT" valid
OUT_JWT=$(run_script "get-chatgpt-usage" "$BIN_JWT" "$HOME_JWT")
assert_eq "$(val "$OUT_JWT" CREDS_STATUS)" "blocked" "a failed exp read is Blocked, not a token with no expiry"
assert_eq "$(val "$OUT_JWT" BLOCKING_REQUIREMENT)" "jq" "the exp read failure names jq"

# The z.ai endpoint is documented, so a valid body that is not the quota shape is
# an unexpected body rather than a rejected key: Unavailable, never Missing.
HOME_ZAI_SHAPE=$(new_home "zai-shape")
setup_home "get-zai-usage" "$HOME_ZAI_SHAPE" valid
OUT_ZAI_SHAPE=$(HOME="$HOME_ZAI_SHAPE" CODEX_HOME="$HOME_ZAI_SHAPE/.codex" PATH="$BIN_OK:$TMPDIR_ROOT:$PATH" \
    MOCK_CHATGPT_BODY="$CHATGPT_OK" MOCK_ZAI_QUOTA='{"code":200,"success":true}' \
    MOCK_ZAI_MODEL="$ZAI_MODEL" MOCK_OPENCODE_BODY="$OPENCODE_OK" \
    ZAI_API_KEY="" OPENCODE_GO_KEY="" OPENCODE_API_KEY="" \
    bash "$SCRIPT_DIR/get-zai-usage" 2>/dev/null)

echo "=== get-zai-usage: a valid body outside the quota shape ==="
assert_eq "$(val "$OUT_ZAI_SHAPE" CREDS_STATUS)" "unavailable" "a valid body without data.limits is Unavailable, not a rejected key"
assert_no_key "$OUT_ZAI_SHAPE" "BLOCKING_REQUIREMENT" "an unexpected body names no command"

# An HTTP rejection is authoritative whatever the body carries, so reading the
# body's validity first must not turn a rejected key into Unavailable.
for script in get-zai-usage get-opencode-go-usage; do
    echo "=== $script: an HTTP 401 with a body that is not JSON ==="
    HOME_401=$(new_home "$script-401")
    setup_home "$script" "$HOME_401" valid
    OUT_401=$(HOME="$HOME_401" CODEX_HOME="$HOME_401/.codex" PATH="$BIN_OK:$TMPDIR_ROOT:$PATH" \
        MOCK_CHATGPT_BODY='<html>not json</html>' MOCK_ZAI_QUOTA='<html>not json</html>' \
        MOCK_ZAI_MODEL='<html>not json</html>' MOCK_OPENCODE_BODY='<html>not json</html>' \
        MOCK_HTTP_STATUS=401 \
        ZAI_API_KEY="" OPENCODE_GO_KEY="" OPENCODE_API_KEY="" \
        bash "$SCRIPT_DIR/$script" 2>/dev/null)

    assert_eq "$(val "$OUT_401" CREDS_STATUS)" "missing" "an HTTP rejection stays Missing whatever the body says"
    assert_no_key "$OUT_401" "BLOCKING_REQUIREMENT" "an HTTP rejection blames no command"
done

# ============================================================
echo "=== the result write is all-or-nothing ==="
# ============================================================
# Each Script publishes a result file with a temp-then-rename, so a reader never
# sees a half-written file. The writer is the library's, so it is sourced and run
# directly rather than only exercised through a fetch that happened to complete.
# shellcheck source-path=SCRIPTDIR source=../lib/source-script.sh
. "$SCRIPT_DIR/lib/source-script.sh"
for script in get-chatgpt-usage get-zai-usage get-opencode-go-usage; do
    DEST="$TMPDIR_ROOT/result-$script"
    write_usage_result "$DEST" "CREDS_STATUS=blocked" "BLOCKING_REQUIREMENT=jq"
    assert_eq "$(cat "$DEST")" "$(printf 'CREDS_STATUS=blocked\nBLOCKING_REQUIREMENT=jq')" \
        "$script: the finished file carries every line it was given"
    if [ -e "$DEST.tmp.$$" ]; then
        fail "$script: the temporary file is removed after a successful write"
    else
        pass "$script: the temporary file is removed after a successful write"
    fi
    write_usage_result "$TMPDIR_ROOT/missing-dir-$script/result" "CREDS_STATUS=blocked"
    if [ -e "$TMPDIR_ROOT/missing-dir-$script" ]; then
        fail "$script: a failed write leaves no destination behind"
    else
        pass "$script: a failed write leaves no destination behind"
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
