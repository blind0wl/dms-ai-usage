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
TODAY=$(date +%Y-%m-%d)

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
    *"startTime=${ZAI_MOCK_TODAY}+00:00:00&endTime=${ZAI_MOCK_TODAY}+"*)
        # The today call shares its URL with the month one on the month's
        # first day, so there the month fixture answers both and today's cost
        # reads as the month's - the same figures the real API returns.
        [ "$ZAI_MOCK_TODAY" = "$ZAI_MOCK_MONTH_START" ] || kind=today ;;
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
    # The pricing cache the Script reads lives under XDG_CACHE_HOME, so that
    # is pinned inside the test environment: a developer's real cache must
    # not price a fixture, and a fixture must not write into it.
    HOME="$home_dir" XDG_CACHE_HOME="$home_dir/.cache" \
    ZAI_MOCK_DIR="$MOCK_DIR" ZAI_MOCK_WEEK_START="$WEEK_START" ZAI_MOCK_MONTH_START="$MONTH_START" \
    ZAI_MOCK_TODAY="$TODAY" \
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

# Writes the shared pricing cache the way the library's refresh would.
# Usage: write_pricing_cache <home_dir> <models-json> [usd_eur_rate]
write_pricing_cache() {
    local home_dir="$1" models="$2" rate="${3:-0}"
    mkdir -p "$home_dir/.cache/dms-ai-usage"
    printf '{"updated": "%s", "models": %s, "usd_eur_rate": %s}' \
        "$TODAY" "$models" "$rate" > "$home_dir/.cache/dms-ai-usage/pricing.json"
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
assert_eq "$(val "$OUT8" ACCOUNT_PRIMARY_UTIL)" "work:80,default:34" "ACCOUNT_PRIMARY_UTIL carries each Account's own primary Utilisation"
assert_eq "$(val "$OUT8" ACCOUNT_PRIMARY_RESET)" "work:1700000000,default:1789279094" "ACCOUNT_PRIMARY_RESET carries each Account's own reset, ms converted to seconds"
assert_eq "$(val "$OUT8" ACCOUNT_SECONDARY_UTIL)" "work:2,default:6" "ACCOUNT_SECONDARY_UTIL carries each Account's own secondary Utilisation"
assert_eq "$(val "$OUT8" ACCOUNT_SECONDARY_RESET)" "work:1700000001,default:1789865116" "ACCOUNT_SECONDARY_RESET carries each Account's own reset"
assert_eq "$(val "$OUT8" ACCOUNT_CREDS_STATUS)" "work:ok,default:ok" "ACCOUNT_CREDS_STATUS carries each Account's own status"

# ============================================================
echo "=== Test 10: A rejected secondary key is reported, not masked ==="
# ============================================================
H9=$(new_home home9)
write_pi_key "$H9" k1
OUT9=$(run_script "$H9" "work=k4")

assert_eq "$(val "$OUT9" ACCOUNT_CREDS_STATUS)" "work:missing,default:ok" "a rejected key is reported as missing while the healthy Account still reads ok"
# The Account whose key was rejected reports its own zero rather than the
# healthy Account's reading, matching what the Source-level keys do for a lone
# Account whose key was rejected.
assert_eq "$(val "$OUT9" ACCOUNT_PRIMARY_UTIL)" "work:0,default:34" "the Account whose key was rejected reports its own zero, not the healthy Account's reading"

# ============================================================
echo "=== Test 11: Listing mode reports every Account and where it came from ==="
# ============================================================
# The settings page asks the same Script the Popout asks, so the Accounts it
# lists can never disagree with the selector. --list-accounts returns the list
# and its origins without fetching anything, so opening the settings page
# costs no request.
H10=$(new_home home10)
write_pi_key "$H10" k1
LIST10=$(run_script "$H10" --list-accounts)
assert_eq "$(val "$LIST10" ACCOUNTS)" "default" "listing mode lists the detected Account"
assert_eq "$(val "$LIST10" ACCOUNT_ORIGINS)" "default:~/.pi/agent/models.json" "listing mode names the pi config key as the origin"
assert_eq "$(echo "$LIST10" | wc -l)" "3" "listing mode returns the Account, origin and refused lists and nothing else"

# A Custom Account is reported as coming from the Custom Account list. It keeps
# its name even where that name shadows a detected Account, because the Script's
# own name de-duplication decides which of the two the selector shows.
H11=$(new_home home11)
write_pi_key "$H11" k4
LIST11=$(run_script "$H11" --list-accounts "default=k1")
assert_eq "$(val "$LIST11" ACCOUNTS)" "default" "a Custom Account name wins against a detected one"
assert_eq "$(val "$LIST11" ACCOUNT_ORIGINS)" "default:custom" "an Account the Custom Account list provided reports it as its origin"

H12=$(new_home home12)
write_pi_key "$H12" k4
LIST12=$(run_script "$H12" --list-accounts "work=k1")
assert_eq "$(val "$LIST12" ACCOUNT_ORIGINS)" "work:custom,default:~/.pi/agent/models.json" "listing mode reports Custom and detected origins side by side"

H13=$(new_home home13)
LIST13=$(ZAI_API_KEY_OVERRIDE=k1 run_script "$H13" --list-accounts)
assert_eq "$(val "$LIST13" ACCOUNT_ORIGINS)" "default:ZAI_API_KEY" "the environment variable is named as the origin"

# A Custom Account can take a detected one's place, and the listing says so: the
# refused registration arrives with the origin it came from, which is how the
# settings page shows the detected key as overridden rather than leaving the user
# to meet it as a rejected key.
H15=$(new_home home15)
write_pi_key "$H15" k1
LIST15=$(run_script "$H15" --list-accounts "default=k2")
assert_eq "$(val "$LIST15" ACCOUNTS)" "default" "the Custom Account is the one registered"
assert_eq "$(val "$LIST15" ACCOUNT_ORIGINS)" "default:custom" "the Custom Account is reported as coming from the Custom list"
assert_eq "$(val "$LIST15" ACCOUNT_SHADOWED)" "default|default:~/.pi/agent/models.json" "the detected key the Custom Account took the name of is reported as refused, naming the row that took it"

# The clash can be the value rather than the name: the Script keeps one key once.
LIST16=$(run_script "$H15" --list-accounts "work=k1")
assert_eq "$(val "$LIST16" ACCOUNTS)" "work" "a Custom Account whose key is the detected one's is registered"
assert_eq "$(val "$LIST16" ACCOUNT_SHADOWED)" "work|default:~/.pi/agent/models.json" "the detected key it took the value of is reported as refused, naming the row that took it"

# No clash, no report.
assert_eq "$(val "$LIST12" ACCOUNT_SHADOWED)" "" "a Custom Account beside the detected key refuses nothing"

H14=$(new_home home14)
LIST14=$(run_script "$H14" --list-accounts)
assert_eq "$(val "$LIST14" ACCOUNTS)" "" "listing mode lists nothing when no key is found anywhere"
assert_eq "$(echo "$LIST14" | grep -c "^ACCOUNTS=")" "1" "listing mode answers with the Account key even with nothing to list"
assert_eq "$(val "$LIST14" ACCOUNT_ORIGINS)" "" "listing mode reports no origin when no key is found anywhere"
assert_eq "$(echo "$LIST14" | grep -c "^ACCOUNT_ORIGINS=")" "1" "listing mode answers with the origins key even with nothing to list"
assert_eq "$(echo "$LIST14" | grep "^CREDS_STATUS=" | cut -d= -f2)" "not_installed" "an empty listing says the Source is not installed, rather than leaving the page to blame the rows"

# ============================================================
echo "=== Test 12: Cost — the three model-usage bodies priced ==="
# ============================================================
# A fresh key with small figures so the arithmetic is exact: today 40 tokens,
# the week 100, the month 300, all on GLM-5.3. The cache prices zai's own
# rate row for glm-5.3 at 0.001 per token, so today reads 0.04, the week
# 0.10 and the month 0.30.
cat > "$MOCK_DIR/k9.quota.json" << 'EOF'
{"code":200,"msg":"ok","data":{"limits":[
  {"type":"CREDIT_LIMIT","unit":3,"percentage":10,"nextResetTime":1789279094313},
  {"type":"CREDIT_LIMIT","unit":6,"percentage":20,"nextResetTime":1789865116984}
],"level":"lite"},"success":true}
EOF
jq -n '{code: 200, success: true,
  data: {granularity: "hourly",
    totalUsage: {totalTokensUsage: 100, totalModelCallCount: 1},
    modelSummaryList: [{modelName: "GLM-5.3", totalTokens: 100, sortOrder: 1}],
    x_time: [], tokensUsage: []}}' > "$MOCK_DIR/k9.week.json"
jq -n '{code: 200, success: true,
  data: {granularity: "hourly",
    totalUsage: {totalTokensUsage: 300, totalModelCallCount: 3},
    modelSummaryList: [{modelName: "GLM-5.3", totalTokens: 300, sortOrder: 1}],
    x_time: [], tokensUsage: []}}' > "$MOCK_DIR/k9.month.json"
jq -n '{code: 200, success: true,
  data: {granularity: "hourly",
    totalUsage: {totalTokensUsage: 40, totalModelCallCount: 1},
    modelSummaryList: [{modelName: "GLM-5.3", totalTokens: 40, sortOrder: 1}],
    x_time: [], tokensUsage: []}}' > "$MOCK_DIR/k9.today.json"

H16=$(new_home home16)
write_pi_key "$H16" k9
write_pricing_cache "$H16" '{"zai/glm-5.3": {"input": 0.001, "output": 0.002, "cache_read": 0.001, "cache_write": 0}}' 0.9

OUT16=$(run_script "$H16")

assert_eq "$(val "$OUT16" TODAY_COST)" "0.04" "TODAY_COST prices the today call's model tokens"
assert_eq "$(val "$OUT16" WEEK_COST)" "0.10" "WEEK_COST prices the week call's model tokens"
assert_eq "$(val "$OUT16" MONTH_COST)" "0.30" "MONTH_COST prices the month call's model tokens"
assert_eq "$(val "$OUT16" USD_EUR_RATE)" "0.9" "USD_EUR_RATE rides the same cache"
assert_eq "$(val "$OUT16" WEEK_TOKENS)" "100" "costing leaves the token counts alone"
assert_eq "$(val "$OUT16" ACCOUNT_TODAY_COST)" "default:0.04" "ACCOUNT_TODAY_COST carries the per-Account figure"
assert_eq "$(val "$OUT16" ACCOUNT_WEEK_COST)" "default:0.10" "ACCOUNT_WEEK_COST carries the per-Account figure"
assert_eq "$(val "$OUT16" ACCOUNT_MONTH_COST)" "default:0.30" "ACCOUNT_MONTH_COST carries the per-Account figure"
assert_eq "$(val "$OUT16" CREDS_STATUS)" "ok" "pricing leaves the credential verdict alone"

# ============================================================
echo "=== Test 13: Model names price case-insensitively under Z.ai's own rates ==="
# ============================================================
# The API reports GLM- prefixed names; LiteLLM rows Z.ai's rates under
# zai/-prefixed lowercase keys. A model neither names contributes zero.
jq '.data.modelSummaryList = [{modelName: "GLM-4.6", totalTokens: 100, sortOrder: 1},
                              {modelName: "GLM-9.9-Unknown", totalTokens: 500, sortOrder: 2}]' \
    "$MOCK_DIR/k9.week.json" > "$MOCK_DIR/k10.week.json"
cp "$MOCK_DIR/k9.quota.json" "$MOCK_DIR/k10.quota.json"
cp "$MOCK_DIR/k9.today.json" "$MOCK_DIR/k10.today.json"
jq '.data.modelSummaryList = [.data.modelSummaryList[0]]' "$MOCK_DIR/k9.month.json" > "$MOCK_DIR/k10.month.json"

H17=$(new_home home17)
write_pi_key "$H17" k10
write_pricing_cache "$H17" '{"zai/glm-4.6": {"input": 0.0001, "output": 0.0002, "cache_read": 0.0001, "cache_write": 0}, "zai/glm-5.3": {"input": 0.001, "output": 0.002, "cache_read": 0.001, "cache_write": 0}}'

OUT17=$(run_script "$H17")

assert_eq "$(val "$OUT17" WEEK_COST)" "0.01" "WEEK_COST finds the model under Z.ai's own rate row, and only that one"
assert_match "$OUT17" '^WEEK_MODELS=.*GLM-9.9-Unknown=500' "the unpriced model still counts its tokens"

# ============================================================
echo "=== Test 14: No pricing cache — costs read zero, tokens still count ==="
# ============================================================
H18=$(new_home home18)
write_pi_key "$H18" k9
OUT18=$(run_script "$H18")

assert_eq "$(val "$OUT18" TODAY_COST)" "0.00" "TODAY_COST=0.00 with no cache and no table"
assert_eq "$(val "$OUT18" WEEK_COST)" "0.00" "WEEK_COST=0.00 with no cache and no table"
assert_eq "$(val "$OUT18" MONTH_COST)" "0.00" "MONTH_COST=0.00 with no cache and no table"
assert_eq "$(val "$OUT18" WEEK_TOKENS)" "100" "WEEK_TOKENS still counts"
assert_eq "$(val "$OUT18" USD_EUR_RATE)" "0" "USD_EUR_RATE stays 0 with nothing to read it from"

# ============================================================
echo "=== Test 15: Costs aggregate across accounts ==="
# ============================================================
# k7 (default) has 600 GLM-5.3 tokens on the week, k8 (work) 400 plus 600 on
# GLM-5.3-Air, which the cache does not name and so prices at zero. At the
# same 0.001 rate the week reads work:0.40,default:0.60 and sums to 1.00.
H19=$(new_home home19)
write_pi_key "$H19" k7
write_pricing_cache "$H19" '{"zai/glm-5.3": {"input": 0.001, "output": 0.002, "cache_read": 0.001, "cache_write": 0}}'

OUT19=$(run_script "$H19" "work=k8")

assert_eq "$(val "$OUT19" WEEK_COST)" "1.00" "WEEK_COST sums across accounts"
assert_eq "$(val "$OUT19" ACCOUNT_WEEK_COST)" "work:0.40,default:0.60" "ACCOUNT_WEEK_COST carries each Account's own cost"

# ============================================================
echo "=== Test 16: Not installed — cost keys present at zero ==="
# ============================================================
# Test 5's output carries the not-installed heredoc; the cost keys must be
# part of it, so a Source that is not present reports zeros rather than
# teaching the reader to miss the keys.
assert_eq "$(val "$OUT5" TODAY_COST)" "0.00" "the not-installed answer carries TODAY_COST=0.00"
assert_eq "$(val "$OUT5" WEEK_COST)" "0.00" "the not-installed answer carries WEEK_COST=0.00"
assert_eq "$(val "$OUT5" MONTH_COST)" "0.00" "the not-installed answer carries MONTH_COST=0.00"
assert_eq "$(echo "$OUT5" | grep -c '^ACCOUNT_TODAY_COST=')" "1" "the not-installed answer carries the per-Account cost keys"

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
