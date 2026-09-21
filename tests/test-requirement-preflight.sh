#!/usr/bin/env bash
# Tests for the Requirement preflight (#58).
#
# Every Script checks the Requirements plugin.json declares before it reads a
# credential or makes a request. With one absent it reports CREDS_STATUS=blocked
# and BLOCKING_REQUIREMENT naming the commands, rather than a credential verdict
# or a Not installed report that would send the user somewhere that cannot help
# (ADR 0005).
#
# The check is presence-only, so what these tests pin is the guard's own
# behaviour: the status, the command list, the listing answer the settings page
# needs, and that nothing downstream of the guard ran.
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

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

CURL_LOG="$TMPDIR_ROOT/curl.log"

# A curl that records every call and answers nothing: any request at all is a
# failure of the guard, whether or not its output would have parsed.
cat > "$TMPDIR_ROOT/curl" << 'CURLEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG:-/dev/null}"
echo '{}'
CURLEOF
chmod +x "$TMPDIR_ROOT/curl"

# A PATH holding only the commands a Script's guard needs, plus whichever of the
# Requirements the caller wants present. bash is on it because the temporary PATH
# is also what resolves the interpreter.
make_path() {
    local dir="$1"
    shift
    mkdir -p "$dir"
    local name
    for name in "$@"; do
        ln -sf "$(command -v "$name")" "$dir/$name"
    done
    printf '%s' "$dir"
}

NO_JQ_PATH=$(make_path "$TMPDIR_ROOT/no-jq" dirname sed tr bash)
NO_CURL_PATH=$(make_path "$TMPDIR_ROOT/no-curl" dirname sed tr bash jq)
NO_ANY_PATH=$(make_path "$TMPDIR_ROOT/no-any" dirname sed tr bash)
# curl is linked into the one path that is meant to have it. The other two are
# running with genuinely no curl, which is what makes the pair case meaningful.
ln -sf "$TMPDIR_ROOT/curl" "$NO_JQ_PATH/curl"

SCRIPTS="get-claude-usage get-chatgpt-usage get-zai-usage get-opencode-go-usage"

# The output key a Script names its Account list under. Claude's are Profiles.
list_key_for() {
    case "$1" in
        get-claude-usage) echo "PROFILES" ;;
        *) echo "ACCOUNTS" ;;
    esac
}

# Every Source gets real credentials, so a Script that fell through the guard
# would have something to read and report. The guard runs first, so these are
# never touched; they exist to make "credentials present" true rather than
# assumed.
setup_credentials() {
    local script="$1"
    local home="$2"
    case "$script" in
        get-claude-usage)
            mkdir -p "$home/.claude"
            printf '{"accessToken":"present"}\n' > "$home/.claude/.credentials.json" ;;
        get-chatgpt-usage)
            mkdir -p "$home/.codex"
            printf '{"tokens":{"access_token":"present"}}\n' > "$home/.codex/auth.json" ;;
    esac
}

# Runs one Script under a chosen PATH, with an isolated HOME. Z.ai's and opencode
# Go's detected credentials are environment variables, so they are set for every
# run; the other two Scripts ignore them.
run_script() {
    local script="$1"
    local path="$2"
    local home="$3"
    shift 3
    HOME="$home" \
    PATH="$path" \
    CURL_LOG="$CURL_LOG" \
    ZAI_API_KEY="present" \
    OPENCODE_GO_KEY="present" \
        bash "$SCRIPT_DIR/$script" "$@" 2>/dev/null
}

new_home() {
    local dir="$TMPDIR_ROOT/$1"
    mkdir -p "$dir"
    echo "$dir"
}

val() { echo "$1" | grep "^$2=" | cut -d= -f2-; }

for script in $SCRIPTS; do
    key=$(list_key_for "$script")

    # ============================================================
    echo "=== $script: jq absent, curl and credentials present ==="
    # ============================================================
    : > "$CURL_LOG"
    HOME_JQ=$(new_home "$script-jq")
    setup_credentials "$script" "$HOME_JQ"
    OUT=$(run_script "$script" "$NO_JQ_PATH" "$HOME_JQ")

    assert_eq "$(val "$OUT" CREDS_STATUS)" "blocked" "CREDS_STATUS=blocked names the state rather than a credential one"
    assert_eq "$(val "$OUT" BLOCKING_REQUIREMENT)" "jq" "BLOCKING_REQUIREMENT names jq and only jq"
    assert_eq "$(val "$OUT" "$key")" "" "the Account list is empty, so the editor parses a complete listing"
    # The false states this guard exists to prevent: a credential verdict from a
    # Source whose credentials are present, or a Not installed report that hides
    # the Source from the Pill.
    for wrong in ok missing expired not_installed; do
        if [ "$(val "$OUT" CREDS_STATUS)" = "$wrong" ]; then
            fail "CREDS_STATUS must not be $wrong when a Requirement is absent"
        else
            pass "CREDS_STATUS is not $wrong"
        fi
    done
    assert_no_key "$OUT" "PLAN_TYPE" "the guard returns before the Script reports a plan"
    assert_no_key "$OUT" "PRIMARY_UTIL" "the guard returns before any Window reading"
    assert_no_key "$OUT" "TERTIARY_UTIL" "the guard returns before the tertiary Window reading too"
    assert_no_key "$OUT" "TERTIARY_RESET" "the guard returns before the tertiary Window reset too"

    if [ -s "$CURL_LOG" ]; then
        fail "no request may be made while a Requirement is absent"
    else
        pass "no request is made while a Requirement is absent"
    fi

    # ============================================================
    echo "=== $script: the listing answer is complete when jq is absent ==="
    # ============================================================
    LIST=$(run_script "$script" "$NO_JQ_PATH" "$HOME_JQ" --list-accounts)
    assert_eq "$(val "$LIST" CREDS_STATUS)" "blocked" "the listing reports blocked, so the editor knows why it is empty"
    assert_eq "$(val "$LIST" BLOCKING_REQUIREMENT)" "jq" "the listing names jq"
    assert_eq "$(val "$LIST" "$key")" "" "the listing answers with an empty Account list"

    # ============================================================
    echo "=== $script: both Requirements absent ==="
    # ============================================================
    OUT_ANY=$(run_script "$script" "$NO_ANY_PATH" "$HOME_JQ")
    assert_eq "$(val "$OUT_ANY" BLOCKING_REQUIREMENT)" "jq,curl" "BLOCKING_REQUIREMENT lists both missing commands"

    # ============================================================
    echo "=== $script: only curl absent ==="
    # ============================================================
    # The list is the manifest's, not a jq-shaped special case: the other
    # Requirement is reported on its own when it is the one missing.
    OUT_NOCURL=$(run_script "$script" "$NO_CURL_PATH" "$HOME_JQ")
    assert_eq "$(val "$OUT_NOCURL" CREDS_STATUS)" "blocked" "CREDS_STATUS=blocked when only curl is absent"
    assert_eq "$(val "$OUT_NOCURL" BLOCKING_REQUIREMENT)" "curl" "BLOCKING_REQUIREMENT names curl when jq is present"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
