#!/usr/bin/env bash
# Tests for get-opencode-go-usage script
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/get-opencode-go-usage"
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

MOCK_DIR="$TMPDIR_ROOT/mocks"
mkdir -p "$MOCK_DIR"

# Mock curl: picks a fixture by the API key in the Authorization header, then
# appends the HTTP status line the script requests with -w. The endpoint takes
# the key as "Bearer <key>".
cat > "$TMPDIR_ROOT/curl" << 'CURLEOF'
#!/usr/bin/env bash
auth=""
for a in "$@"; do
    case "$a" in
        Authorization:*) auth="${a#Authorization: }" ;;
    esac
done
key="${auth#Bearer }"

f="$OPENCODE_MOCK_DIR/${key}.json"
if [ -f "$f" ]; then cat "$f"; else echo '{}'; fi
printf '\n%s' "$(cat "$OPENCODE_MOCK_DIR/${key}.code" 2>/dev/null || echo 200)"
CURLEOF
chmod +x "$TMPDIR_ROOT/curl"

# Sets up an isolated HOME (so the two credential files are under test control)
# and runs the script against the mock curl.
run_script() {
    local home_dir="$1"
    shift
    HOME="$home_dir" \
    OPENCODE_MOCK_DIR="$MOCK_DIR" \
    PATH="$TMPDIR_ROOT:$PATH" \
    OPENCODE_GO_KEY="${OPENCODE_GO_KEY_OVERRIDE:-}" \
    OPENCODE_API_KEY="${OPENCODE_API_KEY_OVERRIDE:-}" \
        bash "$SCRIPT" "$@" 2>/dev/null
}

new_home() {
    local dir="$TMPDIR_ROOT/$1"
    mkdir -p "$dir"
    echo "$dir"
}

# pi's auth store: the opencode-go entry's key field.
write_pi_key() {
    mkdir -p "$1/.pi/agent"
    jq -n --arg k "$2" '{ "opencode-go": { type: "api_key", key: $k } }' > "$1/.pi/agent/auth.json"
}

# opencode's own credentials file, which its connect flow writes.
write_opencode_key() {
    mkdir -p "$1/.local/share/opencode"
    jq -n --arg k "$2" '{ "opencode-go": { type: "api", key: $k } }' > "$1/.local/share/opencode/auth.json"
}

val() { echo "$1" | grep "^$2=" | cut -d= -f2-; }

# --- Fixtures (captured from the endpoint; inline so the suite needs nothing
# outside the repo) ---
cat > "$MOCK_DIR/k1.json" << 'EOF'
{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-09-16T15:31:05.155Z"},"weekly":{"status":"ok","percent":6,"resetsAt":"2026-09-21T00:00:00.155Z"},"monthly":{"status":"ok","percent":3,"resetsAt":"2026-10-16T05:20:21.155Z"}}}
EOF
echo 200 > "$MOCK_DIR/k1.code"

echo '{"type":"error","error":{"type":"AuthError","message":"Invalid API key."}}' > "$MOCK_DIR/k2.json"
echo 401 > "$MOCK_DIR/k2.code"

cat > "$MOCK_DIR/k3.json" << 'EOF'
{"usage":{"rolling":{"status":"ok","percent":80,"resetsAt":"2026-09-17T00:00:00.000Z"},"weekly":{"status":"ok","percent":2,"resetsAt":"2026-09-22T00:00:00.000Z"},"monthly":{"status":"ok","percent":9,"resetsAt":"2026-10-17T00:00:00.000Z"}}}
EOF
echo 200 > "$MOCK_DIR/k3.code"

# ============================================================
echo "=== Test 1: The captured response drives the two modelled Windows ==="
# ============================================================
H1=$(new_home home1)
write_pi_key "$H1" k1
OUT1=$(run_script "$H1")

for key in PLAN_TYPE PRIMARY_UTIL PRIMARY_RESET SECONDARY_UTIL SECONDARY_RESET CREDS_STATUS ACCOUNTS; do
    if echo "$OUT1" | grep -q "^${key}="; then pass "key $key present"; else fail "key $key missing"; fi
done

assert_eq "$(val "$OUT1" CREDS_STATUS)" "ok" "CREDS_STATUS=ok on a successful usage call"
assert_eq "$(val "$OUT1" PRIMARY_UTIL)" "1" "PRIMARY_UTIL from rolling.percent"
assert_eq "$(val "$OUT1" SECONDARY_UTIL)" "6" "SECONDARY_UTIL from weekly.percent"
assert_eq "$(val "$OUT1" PRIMARY_RESET)" "2026-09-16T15:31:05.155Z" "PRIMARY_RESET is rolling.resetsAt, ISO-8601 unconverted"
assert_eq "$(val "$OUT1" SECONDARY_RESET)" "2026-09-21T00:00:00.155Z" "SECONDARY_RESET is weekly.resetsAt"
assert_eq "$(val "$OUT1" ACCOUNTS)" "default" "ACCOUNTS lists the discovered key as default"
assert_eq "$(val "$OUT1" PLAN_TYPE)" "unknown" "PLAN_TYPE=unknown: the response carries no plan name"

# `monthly` is returned but not modelled, so it must not surface as a third
# Window or overwrite the weekly one.
assert_no_key "$OUT1" "MONTHLY_UTIL" "the response's monthly Window stays unreported (no MONTHLY_UTIL)"
assert_eq "$(val "$OUT1" SECONDARY_UTIL)" "6" "monthly.percent does not overwrite the weekly Window"

# ============================================================
echo "=== Test 2: Rejected key — HTTP 401 ==="
# ============================================================
H2=$(new_home home2)
write_pi_key "$H2" k2
OUT2=$(run_script "$H2")

assert_eq "$(val "$OUT2" CREDS_STATUS)" "missing" "CREDS_STATUS=missing when the endpoint rejects the key"
assert_eq "$(val "$OUT2" PRIMARY_UTIL)" "0" "PRIMARY_UTIL=0 for a rejected key"
assert_eq "$(val "$OUT2" SECONDARY_UTIL)" "0" "SECONDARY_UTIL=0 for a rejected key"

# A rejected key is a missing-credentials state, not a confirmed zero reading:
# a working key must still be able to report a real 0.
assert_eq "$(val "$OUT1" CREDS_STATUS)" "ok" "a working key reports ok, distinct from a rejected key"

# The same verdict when the body, not the status line, carries the AuthError.
cp "$MOCK_DIR/k2.json" "$MOCK_DIR/k2b.json"
echo 200 > "$MOCK_DIR/k2b.code"
H2B=$(new_home home2b)
write_pi_key "$H2B" k2b
assert_eq "$(val "$(run_script "$H2B")" CREDS_STATUS)" "missing" "CREDS_STATUS=missing when the body carries an AuthError"

# ============================================================
echo "=== Test 3: No key anywhere — not_installed ==="
# ============================================================
H3=$(new_home home3)
OUT3=$(run_script "$H3")
assert_eq "$(val "$OUT3" CREDS_STATUS)" "not_installed" "CREDS_STATUS=not_installed with no key from any source"
assert_eq "$(val "$OUT3" ACCOUNTS)" "" "ACCOUNTS empty when not installed"
assert_eq "$(val "$OUT3" PRIMARY_UTIL)" "0" "PRIMARY_UTIL=0 when not installed, but hidden by the status"

# An empty key field is not a credential.
H3B=$(new_home home3b)
write_pi_key "$H3B" ""
assert_eq "$(val "$(run_script "$H3B")" CREDS_STATUS)" "not_installed" "empty pi key ignored"

# ============================================================
echo "=== Test 4: Credential discovery order, first hit wins ==="
# ============================================================
# pi's auth store beats opencode's credentials file
H4=$(new_home home4)
write_pi_key "$H4" k1
write_opencode_key "$H4" k2
assert_eq "$(val "$(run_script "$H4")" CREDS_STATUS)" "ok" "pi auth store wins over opencode's credentials file"

# opencode's credentials file is used when pi has nothing
H4B=$(new_home home4b)
write_opencode_key "$H4B" k1
OUT4B=$(run_script "$H4B")
assert_eq "$(val "$OUT4B" CREDS_STATUS)" "ok" "opencode credentials file used when pi auth store is empty"
assert_eq "$(val "$OUT4B" ACCOUNTS)" "default" "opencode credentials file registers as default"

# a local credential file beats the environment
H4C=$(new_home home4c)
write_opencode_key "$H4C" k1
OUT4C=$(OPENCODE_GO_KEY_OVERRIDE=k2 run_script "$H4C")
assert_eq "$(val "$OUT4C" CREDS_STATUS)" "ok" "credential file wins over OPENCODE_GO_KEY"

# the environment is used when no local file has a key
H4D=$(new_home home4d)
OUT4D=$(OPENCODE_GO_KEY_OVERRIDE=k1 run_script "$H4D")
assert_eq "$(val "$OUT4D" CREDS_STATUS)" "ok" "OPENCODE_GO_KEY used when no local file has a key"

# OPENCODE_API_KEY is the second environment fallback
H4E=$(new_home home4e)
OUT4E=$(OPENCODE_API_KEY_OVERRIDE=k1 run_script "$H4E")
assert_eq "$(val "$OUT4E" CREDS_STATUS)" "ok" "OPENCODE_API_KEY used as the second environment fallback"

# OPENCODE_GO_KEY beats OPENCODE_API_KEY
H4F=$(new_home home4f)
OUT4F=$(OPENCODE_GO_KEY_OVERRIDE=k1 OPENCODE_API_KEY_OVERRIDE=k2 run_script "$H4F")
assert_eq "$(val "$OUT4F" CREDS_STATUS)" "ok" "OPENCODE_GO_KEY wins over OPENCODE_API_KEY"

# the environment beats a key added under Custom opencode Accounts
H4G=$(new_home home4g)
OUT4G=$(OPENCODE_GO_KEY_OVERRIDE=k1 run_script "$H4G" "default=k2")
assert_eq "$(val "$OUT4G" CREDS_STATUS)" "ok" "environment wins over a Custom opencode Accounts key"

# a Custom opencode Accounts key is used when nothing else has one
H4H=$(new_home home4h)
OUT4H=$(run_script "$H4H" "work=k1")
assert_eq "$(val "$OUT4H" CREDS_STATUS)" "ok" "Custom opencode Accounts key used when nothing else has one"
assert_eq "$(val "$OUT4H" ACCOUNTS)" "work" "Custom opencode Accounts key registered under its name"

# ============================================================
echo "=== Test 5: Worse utilisation across two Accounts binds ==="
# ============================================================
H5=$(new_home home5)
write_pi_key "$H5" k1
OUT5=$(run_script "$H5" "work=k3")
assert_eq "$(val "$OUT5" ACCOUNTS)" "default,work" "ACCOUNTS lists both keys, discovery order first"
assert_eq "$(val "$OUT5" PRIMARY_UTIL)" "80" "PRIMARY_UTIL is the max across Accounts"
assert_eq "$(val "$OUT5" PRIMARY_RESET)" "2026-09-17T00:00:00.000Z" "PRIMARY_RESET comes from the Account holding the max"
assert_eq "$(val "$OUT5" SECONDARY_UTIL)" "6" "SECONDARY_UTIL is the max across Accounts"
assert_eq "$(val "$OUT5" SECONDARY_RESET)" "2026-09-21T00:00:00.155Z" "SECONDARY_RESET comes from the Account holding the max"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
