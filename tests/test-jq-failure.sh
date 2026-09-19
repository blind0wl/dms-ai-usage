#!/usr/bin/env bash
# Tests for a jq that is present but fails in get-claude-usage (#59, ADR 0005).
#
# A failing jq must not abort the usage fetch. The response body separates the
# two causes: a body that is not valid JSON is the endpoint answering with
# something unexpected, which is Unavailable, and a jq that fails on a valid body
# is the tool's own failure, which is Blocked with jq named. Either way the
# Script writes a complete result file, exits 0, and never emits an empty
# CREDS_STATUS. The read-back's defaults are reachable, so a result file with a
# line missing yields that line's documented default instead of an empty value.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/get-claude-usage"
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

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available"
    exit 0
fi
REAL_JQ=$(command -v jq)

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# A PATH directory holding the mocks a Script run needs: a `claude` that only has
# to exist, a `curl` whose answer follows MOCK_USAGE_BODY, and a `jq` that either
# works or fails on the usage extraction the way a broken jq would.
make_bin() {
    local dir="$1" fail_pattern="${2:-}"
    mkdir -p "$dir"
    cat > "$dir/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        *api/oauth/usage*) printf '%s' "$MOCK_USAGE_BODY"; exit 0 ;;
    esac
done
echo '{}'
EOF
    chmod +x "$dir/claude" "$dir/curl"
    if [ -n "$fail_pattern" ]; then
        # Answers the validity probe (`jq -e .`, which carries no field path) and
        # then dies on the extraction, which is what a jq good enough to be
        # running but unable to read the body does.
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

setup_home() {
    local dir="$TMPDIR_ROOT/$1"
    mkdir -p "$dir/.claude/projects/test-project"
    printf '{"claudeAiOauth":{"subscriptionType":"pro","rateLimitTier":"t1_pro","accessToken":"fake-token"}}\n' \
        > "$dir/.claude/.credentials.json"
    echo "$dir"
}

BIN_FAIL="$TMPDIR_ROOT/bin-fail"
BIN_FAIL_LATE="$TMPDIR_ROOT/bin-fail-late"
BIN_OK="$TMPDIR_ROOT/bin-ok"
make_bin "$BIN_FAIL" "five_hour.utilization"
make_bin "$BIN_FAIL_LATE" "seven_day.utilization"
make_bin "$BIN_OK" ""

OUT=""
RC=0
run_script() {
    local bin="$1" home="$2" body="$3"
    shift 3
    if OUT=$(HOME="$home" PATH="$bin:$PATH" MOCK_USAGE_BODY="$body" \
            bash "$SCRIPT" "$@" 2>/dev/null); then
        RC=0
    else
        RC=$?
    fi
}

val() { echo "$1" | grep "^$2=" | cut -d= -f2-; }

# ============================================================
echo "=== jq fails the extraction on a valid body ==="
# ============================================================
HOME_FAIL=$(setup_home "fail")
run_script "$BIN_FAIL" "$HOME_FAIL" '{}'
assert_eq "$RC" "0" "the Script exits 0 rather than aborting the subshell"
assert_eq "$(val "$OUT" CREDS_STATUS)" "blocked" "CREDS_STATUS=blocked, a defined state rather than an empty one"
assert_eq "$(val "$OUT" BLOCKING_REQUIREMENT)" "jq" "BLOCKING_REQUIREMENT names the failing command"
assert_eq "$(echo "$OUT" | grep -c '^CREDS_STATUS=')" "1" "exactly one CREDS_STATUS line is emitted"
assert_eq "$(val "$OUT" PROFILE_CREDS_STATUS)" "default:blocked" "the Profile's own report is blocked too"
# Lines the failure report deliberately omits must fall back to their defaults,
# which is only possible because the read-back defaults are reachable.
assert_eq "$(val "$OUT" FIVE_HOUR_UTIL)" "0" "an omitted reading line falls back to its default"
assert_eq "$(val "$OUT" SEVEN_DAY_UTIL)" "0" "a second omitted reading line falls back to its default"
assert_eq "$(val "$OUT" SUBSCRIPTION_TYPE)" "unknown" "an omitted plan line falls back to its default"

# ============================================================
echo "=== a later extraction failing is routed the same way ==="
# ============================================================
# Each of the five extractions carries its own guard, so a failure in any of
# them reports the same Blocked state rather than aborting the subshell.
HOME_LATE=$(setup_home "fail-late")
run_script "$BIN_FAIL_LATE" "$HOME_LATE" '{}'
assert_eq "$RC" "0" "the Script still exits 0"
assert_eq "$(val "$OUT" CREDS_STATUS)" "blocked" "a later extraction's failure is Blocked too"
assert_eq "$(val "$OUT" BLOCKING_REQUIREMENT)" "jq" "the command list still names jq"

# ============================================================
echo "=== jq present, the body is not valid JSON ==="
# ============================================================
HOME_NONJSON=$(setup_home "nonjson")
run_script "$BIN_OK" "$HOME_NONJSON" '<html>not json</html>'
assert_eq "$RC" "0" "the Script still exits 0"
assert_eq "$(val "$OUT" CREDS_STATUS)" "unavailable" "an unexpected body is Unavailable, not Blocked"
assert_no_key "$OUT" BLOCKING_REQUIREMENT "no command is blamed for an endpoint failure"

# ============================================================
echo "=== jq present and working emits no command list ==="
# ============================================================
HOME_WORKING=$(setup_home "working")
run_script "$BIN_OK" "$HOME_WORKING" '{}'
assert_eq "$(val "$OUT" CREDS_STATUS)" "expired" "a live fetch with no reading is expired"
assert_no_key "$OUT" BLOCKING_REQUIREMENT "an expired report names no command"

HOME_NOCREDS="$TMPDIR_ROOT/no-creds"
mkdir -p "$HOME_NOCREDS/.claude/projects/test-project"
run_script "$BIN_OK" "$HOME_NOCREDS" '{}'
assert_eq "$(val "$OUT" CREDS_STATUS)" "missing" "no credentials reports missing"
assert_no_key "$OUT" BLOCKING_REQUIREMENT "a missing report names no command"

# ============================================================
echo "=== jq absent: the preflight still blocks before any request ==="
# ============================================================
NO_JQ_PATH="$TMPDIR_ROOT/no-jq"
mkdir -p "$NO_JQ_PATH"
for cmd in dirname sed tr bash; do
    ln -sf "$(command -v "$cmd")" "$NO_JQ_PATH/$cmd"
done
CURL_LOG="$TMPDIR_ROOT/curl.log"
: > "$CURL_LOG"
cat > "$TMPDIR_ROOT/logging-curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
echo '{}'
EOF
chmod +x "$TMPDIR_ROOT/logging-curl"
ln -sf "$TMPDIR_ROOT/logging-curl" "$NO_JQ_PATH/curl"

HOME_NOJQ=$(setup_home "nojq")
if OUT_NOJQ=$(HOME="$HOME_NOJQ" PATH="$NO_JQ_PATH" CURL_LOG="$CURL_LOG" bash "$SCRIPT" 2>/dev/null); then
    RC_NOJQ=0
else
    RC_NOJQ=$?
fi
assert_eq "$RC_NOJQ" "0" "the preflight exits 0"
assert_eq "$(val "$OUT_NOJQ" CREDS_STATUS)" "blocked" "the preflight reports blocked"
assert_eq "$(val "$OUT_NOJQ" BLOCKING_REQUIREMENT)" "jq" "the preflight names jq"
if [ -s "$CURL_LOG" ]; then
    fail "no request may be made while jq is absent"
else
    pass "no request is made while jq is absent"
fi

# ============================================================
echo "=== the read-back defaults are reachable ==="
# ============================================================
# The helper is extracted so a result file with a line missing can be fed to the
# exact code the Script runs, not only to a file a fetch happened to produce.
eval "$(sed -n '/^result_value() {/,/^}/p' "$SCRIPT")"

printf 'FIVE_HOUR_UTIL=42\n' > "$TMPDIR_ROOT/partial-result"
assert_eq "$(result_value "$TMPDIR_ROOT/partial-result" FIVE_HOUR_UTIL 0)" "42" "a line that is present is read"
assert_eq "$(result_value "$TMPDIR_ROOT/partial-result" SUBSCRIPTION_TYPE unknown)" "unknown" "a missing line yields its default"
assert_eq "$(result_value "$TMPDIR_ROOT/partial-result" CREDS_STATUS missing)" "missing" "a missing status yields the missing default"
printf 'FIVE_HOUR_UTIL=\n' > "$TMPDIR_ROOT/empty-result"
assert_eq "$(result_value "$TMPDIR_ROOT/empty-result" FIVE_HOUR_UTIL 0)" "0" "an empty value yields its default"
assert_eq "$(result_value "$TMPDIR_ROOT/does-not-exist" CREDS_STATUS missing)" "missing" "an absent file yields its default"

# The shape this replaced could not default at all: `||` took cut's exit status,
# which is 0 even when grep matched nothing, so the fallback never fired.
old_default=$(grep "^SUBSCRIPTION_TYPE=" "$TMPDIR_ROOT/partial-result" 2>/dev/null | cut -d= -f2- || echo "unknown")
assert_eq "$old_default" "" "the old pipeline shape left its default unreachable"

# ============================================================
echo "=== the result write is all-or-nothing ==="
# ============================================================
eval "$(sed -n '/^write_usage_result() {/,/^}/p' "$SCRIPT")"

DEST="$TMPDIR_ROOT/result"
write_usage_result "$DEST" "CREDS_STATUS=blocked" "BLOCKING_REQUIREMENT=jq"
assert_eq "$(cat "$DEST")" "$(printf 'CREDS_STATUS=blocked\nBLOCKING_REQUIREMENT=jq')" \
    "the finished file carries every line it was given"
if [ -e "$DEST.tmp.$$" ]; then
    fail "the temporary file is removed after a successful write"
else
    pass "the temporary file is removed after a successful write"
fi

# A destination that cannot be written leaves nothing behind, not a half-file.
write_usage_result "$TMPDIR_ROOT/missing-dir/result" "CREDS_STATUS=blocked"
if [ -e "$TMPDIR_ROOT/missing-dir" ]; then
    fail "a failed write leaves no destination behind"
else
    pass "a failed write leaves no destination behind"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
