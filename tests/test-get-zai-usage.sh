#!/usr/bin/env bash
# Tests for get-zai-usage script
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/get-zai-usage"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}
assert_match() {
    if echo "$1" | grep -qE "$2"; then pass "$3"; else fail "$3 (no match for '$2')"; fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

DOW=$(date +%u)
WEEK_START=$(date -d "$((DOW - 1)) days ago" +%Y-%m-%d)
MONTH_START=$(date +%Y-%m-01)

MOCK_DIR="$TMPDIR_ROOT/mocks"
mkdir -p "$MOCK_DIR"

# Mock curl: picks a fixture by the API key in the Authorization header and
# by which endpoint/date range the URL asks for, then appends the HTTP status
# line the script requests with -w.
cat > "$TMPDIR_ROOT/curl" << 'CURLEOF'
#!/usr/bin/env bash
url=""
key=""
for a in "$@"; do
    case "$a" in
        Authorization:*) key="${a#Authorization: }" ;;
        https://*) url="$a" ;;
    esac
done

kind=week
case "$url" in
    *quota/limit*) kind=quota ;;
    *"startTime=${ZAI_MOCK_MONTH_START}+"*) [ "$ZAI_MOCK_MONTH_START" = "$ZAI_MOCK_WEEK_START" ] || kind=month ;;
esac

f="$ZAI_MOCK_DIR/${key}.${kind}.json"
[ -f "$f" ] || f="$ZAI_MOCK_DIR/${key}.week.json"
if [ -f "$f" ]; then cat "$f"; else echo '{}'; fi
printf '\n%s' "$(cat "$ZAI_MOCK_DIR/${key}.code" 2>/dev/null || echo 200)"
CURLEOF
chmod +x "$TMPDIR_ROOT/curl"

# Sets up an isolated HOME (so the pi provider config is under test control)
# and runs the script against the mock curl.
run_script() {
    local home_dir="$1"
    shift
    HOME="$home_dir" \
    ZAI_MOCK_DIR="$MOCK_DIR" ZAI_MOCK_WEEK_START="$WEEK_START" ZAI_MOCK_MONTH_START="$MONTH_START" \
    PATH="$TMPDIR_ROOT:$PATH" ZAI_API_KEY="${ZAI_API_KEY_OVERRIDE:-}" \
        bash "$SCRIPT" "$@" 2>/dev/null
}

new_home() {
    local dir="$TMPDIR_ROOT/$1"
    mkdir -p "$dir/.pi/agent"
    echo "$dir"
}

write_pi_key() {
    printf '{"providers":{"zai":{"apiKey":"%s"}}}\n' "$2" > "$1/.pi/agent/models.json"
}

val() { echo "$1" | grep "^$2=" | cut -d= -f2-; }

# --- Fixtures (captured from api.z.ai; inline so the suite needs nothing outside the repo) ---
cat > "$MOCK_DIR/k1.quota.json" << 'EOF'
{"code":200,"msg":"Operation successful","data":{"limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":693,"remaining":1306,"percentage":34,"nextResetTime":1789279094313},{"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,"currentValue":693,"remaining":9306,"percentage":6,"nextResetTime":1789865116984}],"level":"lite"},"success":true}
EOF
cat > "$MOCK_DIR/k1.week.json" << 'EOF'
{"code":200,"msg":"Operation successful","success":true,"data":{"granularity":"hourly","totalUsage":{"totalModelCallCount":244,"totalTokensUsage":16797051},"modelSummaryList":[{"modelName":"GLM-5.3","totalTokens":68248,"sortOrder":1},{"modelName":"GLM-5.3-Flash","totalTokens":16728803,"sortOrder":2}],"x_time":["2026-09-07 01:00","2026-09-07 02:00"],"tokensUsage":[68248,16728803]}}
EOF
jq '.data.totalUsage.totalTokensUsage = 99000000' "$MOCK_DIR/k1.week.json" > "$MOCK_DIR/k1.month.json"

# ============================================================
echo "=== Test 1: Quota + model-usage fixtures drive every key ==="
# ============================================================
H1=$(new_home home1)
write_pi_key "$H1" k1
OUT1=$(run_script "$H1")

for key in PLAN_TYPE PRIMARY_UTIL PRIMARY_RESET PRIMARY_WINDOW_SECONDS SECONDARY_UTIL \
           SECONDARY_RESET SECONDARY_WINDOW_SECONDS CREDS_STATUS WEEK_TOKENS WEEK_CALLS \
           MONTH_TOKENS DAILY WEEK_MODELS ACCOUNTS; do
    if echo "$OUT1" | grep -q "^${key}="; then pass "key $key present"; else fail "key $key missing"; fi
done

assert_eq "$(val "$OUT1" PLAN_TYPE)" "lite" "PLAN_TYPE from data.level"
assert_eq "$(val "$OUT1" CREDS_STATUS)" "ok" "CREDS_STATUS=ok on a successful quota call"
assert_eq "$(val "$OUT1" PRIMARY_UTIL)" "34" "PRIMARY_UTIL from unit=3 percentage"
assert_eq "$(val "$OUT1" SECONDARY_UTIL)" "6" "SECONDARY_UTIL from unit=6 percentage"
assert_eq "$(val "$OUT1" PRIMARY_WINDOW_SECONDS)" "18000" "PRIMARY_WINDOW_SECONDS=18000"
assert_eq "$(val "$OUT1" SECONDARY_WINDOW_SECONDS)" "604800" "SECONDARY_WINDOW_SECONDS=604800"
assert_eq "$(val "$OUT1" PRIMARY_RESET)" "1789279094" "PRIMARY_RESET converted from epoch ms to seconds"
assert_eq "$(val "$OUT1" SECONDARY_RESET)" "1789865116" "SECONDARY_RESET converted from epoch ms to seconds"
assert_eq "$(val "$OUT1" WEEK_TOKENS)" "16797051" "WEEK_TOKENS from totalTokensUsage"
assert_eq "$(val "$OUT1" WEEK_CALLS)" "244" "WEEK_CALLS from totalModelCallCount"
assert_eq "$(val "$OUT1" WEEK_MODELS)" "GLM-5.3=68248,GLM-5.3-Flash=16728803" "WEEK_MODELS keeps API casing, ordered by sortOrder"
assert_eq "$(val "$OUT1" ACCOUNTS)" "default" "ACCOUNTS lists the pi provider account as default"

if [ "$WEEK_START" = "$MONTH_START" ]; then
    assert_eq "$(val "$OUT1" MONTH_TOKENS)" "16797051" "MONTH_TOKENS (week and month start coincide today)"
else
    assert_eq "$(val "$OUT1" MONTH_TOKENS)" "99000000" "MONTH_TOKENS comes from the month-to-date call"
fi

# ============================================================
echo "=== Test 2: unit drives the mapping, not array order or type ==="
# ============================================================
cat > "$MOCK_DIR/k2.quota.json" << 'EOF'
{"code":200,"msg":"ok","data":{"limits":[
  {"type":"TOKENS_LIMIT","unit":6,"percentage":71,"nextResetTime":1789865116984},
  {"type":"TOKENS_LIMIT","unit":3,"percentage":12,"nextResetTime":1789279094313},
  {"type":"TIME_LIMIT","unit":9,"percentage":99,"nextResetTime":1789279094313}
],"level":"pro"},"success":true}
EOF
echo '{"code":200,"data":{"totalUsage":{"totalTokensUsage":0,"totalModelCallCount":0},"modelSummaryList":[],"x_time":[],"tokensUsage":[]},"success":true}' > "$MOCK_DIR/k2.week.json"

H2=$(new_home home2)
write_pi_key "$H2" k2
OUT2=$(run_script "$H2")

assert_eq "$(val "$OUT2" PRIMARY_UTIL)" "12" "unit=3 maps to PRIMARY even when listed second"
assert_eq "$(val "$OUT2" SECONDARY_UTIL)" "71" "unit=6 maps to SECONDARY even when listed first"
assert_eq "$(val "$OUT2" PLAN_TYPE)" "pro" "PLAN_TYPE=pro"
assert_eq "$(val "$OUT2" CREDS_STATUS)" "ok" "TOKENS_LIMIT type accepted like CREDIT_LIMIT"
assert_eq "$(val "$OUT2" DAILY)" "0,0,0,0,0,0,0" "DAILY zeros on an empty model-usage response"
assert_eq "$(val "$OUT2" WEEK_MODELS)" "" "WEEK_MODELS empty on an empty model-usage response"

# ============================================================
echo "=== Test 3: A window the API omits — UTIL=0, empty RESET ==="
# ============================================================
cat > "$MOCK_DIR/k3.quota.json" << 'EOF'
{"code":200,"msg":"ok","data":{"limits":[
  {"type":"CREDIT_LIMIT","unit":3,"percentage":50,"nextResetTime":1789279094313}
],"level":"max"},"success":true}
EOF
cp "$MOCK_DIR/k2.week.json" "$MOCK_DIR/k3.week.json"

H3=$(new_home home3)
write_pi_key "$H3" k3
OUT3=$(run_script "$H3")

assert_eq "$(val "$OUT3" PRIMARY_UTIL)" "50" "present window still reported"
assert_eq "$(val "$OUT3" SECONDARY_UTIL)" "0" "missing window UTIL=0"
assert_eq "$(val "$OUT3" SECONDARY_RESET)" "" "missing window RESET empty"
assert_eq "$(val "$OUT3" SECONDARY_WINDOW_SECONDS)" "0" "missing window length 0 disables pacing"

# ============================================================
echo "=== Test 4: Rejected key — HTTP 200 body with code 401 ==="
# ============================================================
echo '{"code":401,"msg":"token expired or incorrect","success":false}' > "$MOCK_DIR/k4.quota.json"
H4=$(new_home home4)
write_pi_key "$H4" k4
OUT4=$(run_script "$H4")

assert_eq "$(val "$OUT4" CREDS_STATUS)" "missing" "CREDS_STATUS=missing when the body says success=false"
assert_eq "$(val "$OUT4" PRIMARY_UTIL)" "0" "PRIMARY_UTIL=0 for a rejected key"
assert_eq "$(val "$OUT4" PLAN_TYPE)" "unknown" "PLAN_TYPE=unknown for a rejected key"

# Same verdict when the transport itself returns 401
cp "$MOCK_DIR/k1.quota.json" "$MOCK_DIR/k4b.quota.json"
echo 401 > "$MOCK_DIR/k4b.code"
H4B=$(new_home home4b)
write_pi_key "$H4B" k4b
assert_eq "$(val "$(run_script "$H4B")" CREDS_STATUS)" "missing" "CREDS_STATUS=missing on HTTP 401"

# ============================================================
echo "=== Test 5: No credentials anywhere — not_installed ==="
# ============================================================
H5=$(new_home home5)
OUT5=$(run_script "$H5")
assert_eq "$(val "$OUT5" CREDS_STATUS)" "not_installed" "CREDS_STATUS=not_installed with no key from any source"
assert_eq "$(val "$OUT5" ACCOUNTS)" "" "ACCOUNTS empty when not installed"
assert_eq "$(val "$OUT5" DAILY)" "0,0,0,0,0,0,0" "DAILY zeros when not installed"

# An empty apiKey in models.json is not a credential
H5B=$(new_home home5b)
write_pi_key "$H5B" ""
assert_eq "$(val "$(run_script "$H5B")" CREDS_STATUS)" "not_installed" "empty apiKey ignored"

# ============================================================
echo "=== Test 6: Credential discovery priority ==="
# ============================================================
# argv beats the pi provider config for the same account name
H6=$(new_home home6)
write_pi_key "$H6" k4          # would be a rejected key
OUT6=$(run_script "$H6" "default=k1")
assert_eq "$(val "$OUT6" CREDS_STATUS)" "ok" "argv name=key wins over models.json"
assert_eq "$(val "$OUT6" ACCOUNTS)" "default" "argv account registered once"

# models.json beats ZAI_API_KEY
H6B=$(new_home home6b)
write_pi_key "$H6B" k1
OUT6B=$(ZAI_API_KEY_OVERRIDE=k4 run_script "$H6B")
assert_eq "$(val "$OUT6B" CREDS_STATUS)" "ok" "models.json wins over ZAI_API_KEY"

# ZAI_API_KEY used when models.json has nothing
H6C=$(new_home home6c)
OUT6C=$(ZAI_API_KEY_OVERRIDE=k1 run_script "$H6C")
assert_eq "$(val "$OUT6C" CREDS_STATUS)" "ok" "ZAI_API_KEY used as the default account"
assert_eq "$(val "$OUT6C" ACCOUNTS)" "default" "env key registered as default"

# ============================================================
echo "=== Test 7: DAILY bucketing from x_time hourly labels ==="
# ============================================================
D0="$WEEK_START"
D2=$(date -d "$WEEK_START + 2 days" +%Y-%m-%d)
cp "$MOCK_DIR/k1.quota.json" "$MOCK_DIR/k7.quota.json"
jq -n --arg d0 "$D0" --arg d2 "$D2" '{
  code: 200, success: true,
  data: {
    totalUsage: {totalTokensUsage: 600, totalModelCallCount: 4},
    modelSummaryList: [{modelName: "GLM-5.3", totalTokens: 600, sortOrder: 1}],
    x_time: ["\($d0) 01:00", "\($d0) 02:00", "\($d2) 05:00"],
    tokensUsage: [100, 200, 300],
    granularity: "hourly"
  }}' > "$MOCK_DIR/k7.week.json"

H7=$(new_home home7)
write_pi_key "$H7" k7
OUT7=$(run_script "$H7")
assert_eq "$(val "$OUT7" DAILY)" "300,0,300,0,0,0,0" "DAILY sums hourly buckets onto Mon..Sun"

# ============================================================
echo "=== Test 8: Aggregation across two accounts ==="
# ============================================================
cat > "$MOCK_DIR/k8.quota.json" << 'EOF'
{"code":200,"msg":"ok","data":{"limits":[
  {"type":"CREDIT_LIMIT","unit":3,"percentage":80,"nextResetTime":1700000000000},
  {"type":"CREDIT_LIMIT","unit":6,"percentage":2,"nextResetTime":1700000001000}
],"level":"max"},"success":true}
EOF
jq -n --arg d0 "$WEEK_START" '{
  code: 200, success: true,
  data: {
    totalUsage: {totalTokensUsage: 1000, totalModelCallCount: 10},
    modelSummaryList: [{modelName: "GLM-5.3", totalTokens: 400, sortOrder: 1},
                       {modelName: "GLM-5.3-Air", totalTokens: 600, sortOrder: 2}],
    x_time: ["\($d0) 01:00"],
    tokensUsage: [1000],
    granularity: "hourly"
  }}' > "$MOCK_DIR/k8.week.json"

H8=$(new_home home8)
write_pi_key "$H8" k7
OUT8=$(run_script "$H8" "work=k8")

assert_eq "$(val "$OUT8" ACCOUNTS)" "work,default" "ACCOUNTS lists both accounts"
assert_eq "$(val "$OUT8" PRIMARY_UTIL)" "80" "PRIMARY_UTIL is the max across accounts"
assert_eq "$(val "$OUT8" PRIMARY_RESET)" "1700000000" "PRIMARY_RESET comes from the account holding the max"
assert_eq "$(val "$OUT8" SECONDARY_UTIL)" "6" "SECONDARY_UTIL is the max across accounts"
assert_eq "$(val "$OUT8" SECONDARY_RESET)" "1789865116" "SECONDARY_RESET comes from the account holding the max"
assert_eq "$(val "$OUT8" WEEK_TOKENS)" "1600" "WEEK_TOKENS summed across accounts"
assert_eq "$(val "$OUT8" WEEK_CALLS)" "14" "WEEK_CALLS summed across accounts"
assert_eq "$(val "$OUT8" DAILY)" "1300,0,300,0,0,0,0" "DAILY summed across accounts"
assert_match "$(val "$OUT8" WEEK_MODELS)" "GLM-5\.3=1000" "WEEK_MODELS sums shared models across accounts"
assert_match "$(val "$OUT8" WEEK_MODELS)" "GLM-5\.3-Air=600" "WEEK_MODELS keeps per-account models"
assert_eq "$(val "$OUT8" PLAN_TYPE)" "lite" "PLAN_TYPE comes from the default account"

# ============================================================
echo "=== Test 9: Per-Account Window readings ==="
# ============================================================
# The aggregate is the max, which hides which Account is binding. Each Account's
# own reading is reported alongside it so two keys do not blur into one.
assert_eq "$(val "$OUT8" PROFILE_PRIMARY_UTIL)" "work:80,default:34" "PROFILE_PRIMARY_UTIL carries each Account's own primary Utilisation"
assert_eq "$(val "$OUT8" PROFILE_PRIMARY_RESET)" "work:1700000000,default:1789279094" "PROFILE_PRIMARY_RESET carries each Account's own reset, ms converted to seconds"
assert_eq "$(val "$OUT8" PROFILE_SECONDARY_UTIL)" "work:2,default:6" "PROFILE_SECONDARY_UTIL carries each Account's own secondary Utilisation"
assert_eq "$(val "$OUT8" PROFILE_SECONDARY_RESET)" "work:1700000001,default:1789865116" "PROFILE_SECONDARY_RESET carries each Account's own reset"
assert_eq "$(val "$OUT8" PROFILE_CREDS_STATUS)" "work:ok,default:ok" "PROFILE_CREDS_STATUS carries each Account's own status"

# ============================================================
echo "=== Test 10: A rejected secondary key is reported, not masked ==="
# ============================================================
H9=$(new_home home9)
write_pi_key "$H9" k1
OUT9=$(run_script "$H9" "work=k4")

assert_eq "$(val "$OUT9" PROFILE_CREDS_STATUS)" "work:missing,default:ok" "a rejected key is reported as missing while the healthy Account still reads ok"
# A rejected key reports its own zero rather than the healthy Account's reading,
# matching what the Source-level keys do for a lone rejected key.
assert_eq "$(val "$OUT9" PROFILE_PRIMARY_UTIL)" "work:0,default:34" "a rejected key reports its own zero, not the healthy Account's reading"

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
