#!/usr/bin/env bash
# Tests for QML widget JavaScript functions
# Extracts pure JS functions from AiUsageWidget.qml and tests them via Node.js
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check for Node.js
if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping QML function tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

# Run a JS expression and capture stdout
run_js() {
    node -e "$1" 2>/dev/null
}

# Build JS test harness with functions extracted from the QML widget
JS_HARNESS='
// --- Functions extracted from AiUsageWidget.qml ---

function formatTokens(n) {
    if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(1) + "K"
    return Math.round(n).toString()
}

function shortModelName(name) {
    if (!name || name.length === 0) return name
    return name.charAt(0).toUpperCase() + name.slice(1)
}

function progressColor(pct) {
    if (pct > 80) return "error"
    if (pct > 50) return "warning"
    return "primary"
}

var testLang = "en"
var tierTranslations = {
    Free: { fr: "Gratuit", es: "Gratis" },
    Team: { fr: "Équipe", es: "Equipo" },
    Enterprise: { fr: "Entreprise", es: "Empresa" }
}

function tr(key) {
    return tierTranslations[key] && tierTranslations[key][testLang]
        ? tierTranslations[key][testLang]
        : key
}

function formatTier(tier) {
    if (!tier || tier === "unknown") return ""
    if (tier.indexOf("max_20x") >= 0) return tr("Max") + " 20x"
    if (tier.indexOf("max_5x") >= 0) return tr("Max") + " 5x"
    if (tier.indexOf("max") >= 0) return tr("Max")
    if (tier.indexOf("pro") >= 0) return tr("Pro")
    if (tier.indexOf("free") >= 0) return tr("Free")
    if (tier.indexOf("team") >= 0) return tr("Team")
    if (tier.indexOf("enterprise") >= 0) return tr("Enterprise")
    return tier.replace(/_/g, " ").replace(/\b\w/g, function (c) {
        return c.toUpperCase()
    })
}

function formatCost(usd, lang, usdEurRate) {
    var useEur = lang === "fr" && usdEurRate > 0
    var n = useEur ? usd * usdEurRate : usd
    var sym = useEur ? "" : "$"
    var suffix = useEur ? " €" : ""
    if (n >= 1000) return sym + (n / 1000).toFixed(1) + "K" + suffix
    if (n >= 100) return sym + Math.round(n) + suffix
    if (n >= 10) return sym + n.toFixed(1) + suffix
    return sym + n.toFixed(2) + suffix
}

function todayIndex() {
    var dow = new Date().getDay() // 0=Sunday, 6=Saturday
    return dow === 0 ? 6 : dow - 1
}

// parseLine: simulates the QML property-setting logic
function parseLine(line, state) {
    var idx = line.indexOf("=")
    if (idx < 0) return state
    var key = line.substring(0, idx)
    var val = line.substring(idx + 1)

    switch (key) {
    case "SUBSCRIPTION_TYPE": state.subscriptionType = val; break
    case "RATE_LIMIT_TIER": state.rateLimitTier = val; break
    case "FIVE_HOUR_UTIL": state.fiveHourUtil = parseFloat(val) || 0; break
    case "FIVE_HOUR_RESET": state.fiveHourReset = val; break
    case "SEVEN_DAY_UTIL": state.sevenDayUtil = parseFloat(val) || 0; break
    case "SEVEN_DAY_RESET": state.sevenDayReset = val; break
    case "EXTRA_USAGE_ENABLED": state.extraUsageEnabled = (val === "true"); break
    case "WEEK_MESSAGES": state.weekMessages = parseInt(val) || 0; break
    case "WEEK_SESSIONS": state.weekSessions = parseInt(val) || 0; break
    case "WEEK_TOKENS": state.weekTokens = parseFloat(val) || 0; break
    case "MONTH_TOKENS": state.monthTokens = parseFloat(val) || 0; break
    case "ALLTIME_SESSIONS": state.alltimeSessions = parseInt(val) || 0; break
    case "ALLTIME_MESSAGES": state.alltimeMessages = parseInt(val) || 0; break
    case "FIRST_SESSION": state.firstSession = val; break
    case "WEEK_MODELS":
        state.models = []
        if (val.length > 0) {
            var pairs = val.split(",")
            for (var i = 0; i < pairs.length; i++) {
                var kv = pairs[i].split(":")
                if (kv.length === 2)
                    state.models.push({ modelName: kv[0], modelTokens: parseInt(kv[1]) || 0 })
            }
        }
        break
    case "DAILY":
        var parts = val.split(",")
        var arr = []
        for (var j = 0; j < 7; j++)
            arr.push(j < parts.length ? (parseFloat(parts[j]) || 0) : 0)
        state.dailyTokens = arr
        break
    case "TODAY_COST": state.todayCost = parseFloat(val) || 0; break
    case "WEEK_COST": state.weekCost = parseFloat(val) || 0; break
    case "MONTH_COST": state.monthCost = parseFloat(val) || 0; break
    case "USD_EUR_RATE": state.usdEurRate = parseFloat(val) || 0; break
    case "DAILY_COSTS":
        var cparts = val.split(",")
        var carr = []
        for (var k = 0; k < 7; k++)
            carr.push(k < cparts.length ? (parseFloat(cparts[k]) || 0) : 0)
        state.dailyCosts = carr
        break
    }
    return state
}

function parseResetMs(val) {
    if (!val) return 0
    if (/^[0-9]+$/.test(val)) return parseFloat(val) * 1000
    var ms = new Date(val).getTime()
    return isNaN(ms) ? 0 : ms
}

// parseZaiLine: simulates the QML property-setting logic for the Z.ai Source
function parseZaiLine(line, state) {
    var idx = line.indexOf("=")
    if (idx < 0) return state
    var key = line.substring(0, idx)
    var val = line.substring(idx + 1)

    switch (key) {
    case "PLAN_TYPE": state.planType = val; break
    case "PRIMARY_UTIL": state.primaryUtil = parseFloat(val) || 0; break
    case "PRIMARY_RESET": state.primaryResetMs = parseResetMs(val); break
    case "PRIMARY_WINDOW_SECONDS": state.primaryWindowSeconds = parseFloat(val) || 0; break
    case "SECONDARY_UTIL": state.secondaryUtil = parseFloat(val) || 0; break
    case "SECONDARY_RESET": state.secondaryResetMs = parseResetMs(val); break
    case "SECONDARY_WINDOW_SECONDS": state.secondaryWindowSeconds = parseFloat(val) || 0; break
    case "CREDS_STATUS": state.credsStatus = val; break
    case "WEEK_TOKENS": state.weekTokens = parseFloat(val) || 0; break
    case "WEEK_CALLS": state.weekCalls = parseInt(val) || 0; break
    case "MONTH_TOKENS": state.monthTokens = parseFloat(val) || 0; break
    case "DAILY":
        var zparts = val.split(",")
        var zarr = []
        for (var zi = 0; zi < 7; zi++)
            zarr.push(zi < zparts.length ? (parseFloat(zparts[zi]) || 0) : 0)
        state.dailyTokens = zarr
        break
    case "WEEK_MODELS":
        state.models = []
        if (val.length > 0) {
            var zpairs = val.split(",")
            for (var zp = 0; zp < zpairs.length; zp++) {
                var zeq = zpairs[zp].indexOf("=")
                if (zeq >= 0)
                    state.models.push({ modelName: zpairs[zp].substring(0, zeq), modelTokens: parseInt(zpairs[zp].substring(zeq + 1)) || 0 })
            }
        }
        break
    case "ACCOUNTS": state.accounts = val.length > 0 ? val.split(",") : []; break
    }
    return state
}

var countdownNow = 0

function paceInfo(util, resetIso, windowMs) {
    util = util || 0
    if (!resetIso || !windowMs)
        return util >= 100 ? { timeFrac: 1, delta: util, status: "over_quota" }
            : { timeFrac: 0, delta: 0, status: "unknown" }
    var resetMs = new Date(resetIso).getTime()
    if (isNaN(resetMs))
        return { timeFrac: 0, delta: 0, status: "unknown" }
    var remaining = resetMs - countdownNow
    var timeFrac = (windowMs - remaining) / windowMs
    if (timeFrac < 0) timeFrac = 0
    else if (timeFrac > 1) timeFrac = 1
    var delta = util - timeFrac * 100
    var status
    if (util >= 100) status = "over_quota"
    else if (delta >= 5) status = "over"
    else if (delta <= -5) status = "under"
    else status = "on"
    return { timeFrac: timeFrac, delta: delta, status: status }
}

// Minimal Qt shim for the countdown clock label
var Qt = {
    formatDateTime: function (date, fmt) {
        var pad = function (n) { return (n < 10 ? "0" : "") + n }
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if (fmt === "ddd HH:mm")
            return days[date.getDay()] + " " + pad(date.getHours()) + ":" + pad(date.getMinutes())
        if (fmt === "yyyy-MM-dd")
            return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
        return pad(date.getHours()) + ":" + pad(date.getMinutes())
    }
}

// resetClockLabel: local wall clock appended to countdowns
function resetClockLabel(resetMs) {
    var resetDate = new Date(resetMs)
    var sameDay = Qt.formatDateTime(resetDate, "yyyy-MM-dd") === Qt.formatDateTime(new Date(), "yyyy-MM-dd")
    if (!sameDay)
        return " (" + Qt.formatDateTime(resetDate, "ddd HH:mm") + ")"
    return " (" + Qt.formatDateTime(resetDate, "HH:mm") + ")"
}

// formatCountdown: mirrors the QML body including the clock label
function formatCountdown(resetMs) {
    if (!resetMs)
        return "";
    var remaining = Math.max(0, resetMs - countdownNow);
    if (remaining <= 0)
        return tr("Resetting...");
    var days = Math.floor(remaining / 86400000);
    var hours = Math.floor((remaining % 86400000) / 3600000);
    var mins = Math.floor((remaining % 3600000) / 60000);
    if (days > 0)
        return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m" + resetClockLabel(resetMs);
    return hours + "h " + (mins < 10 ? "0" : "") + mins + "m" + resetClockLabel(resetMs);
}
'

# ============================================================
echo "=== Test 1: formatTokens ==="
# ============================================================

test_format_tokens() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(run_js "${JS_HARNESS} console.log(formatTokens($input))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_format_tokens 0 "0" "formatTokens(0) = 0"
test_format_tokens 1 "1" "formatTokens(1) = 1"
test_format_tokens 999 "999" "formatTokens(999) = 999"
test_format_tokens 1000 "1.0K" "formatTokens(1000) = 1.0K"
test_format_tokens 1500 "1.5K" "formatTokens(1500) = 1.5K"
test_format_tokens 999999 "1000.0K" "formatTokens(999999) = 1000.0K"
test_format_tokens 1000000 "1.0M" "formatTokens(1M) = 1.0M"
test_format_tokens 1500000 "1.5M" "formatTokens(1.5M) = 1.5M"
test_format_tokens 1000000000 "1.0B" "formatTokens(1B) = 1.0B"
test_format_tokens 2500000000 "2.5B" "formatTokens(2.5B) = 2.5B"

# ============================================================
echo "=== Test 2: shortModelName ==="
# ============================================================

test_short_model() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(run_js "${JS_HARNESS} console.log(shortModelName('$input'))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_short_model "opus" "Opus" "shortModelName(opus) = Opus"
test_short_model "sonnet" "Sonnet" "shortModelName(sonnet) = Sonnet"
test_short_model "haiku" "Haiku" "shortModelName(haiku) = Haiku"
test_short_model "a" "A" "shortModelName(a) = A"

# Empty/null cases
RESULT_EMPTY=$(run_js "${JS_HARNESS} console.log(shortModelName(''))")
if [ "$RESULT_EMPTY" = "" ]; then pass "shortModelName('') = empty"; else fail "shortModelName('') expected empty, got '$RESULT_EMPTY'"; fi

RESULT_NULL=$(run_js "${JS_HARNESS} console.log(shortModelName(null))")
if [ "$RESULT_NULL" = "null" ]; then pass "shortModelName(null) = null"; else fail "shortModelName(null) expected null, got '$RESULT_NULL'"; fi

# ============================================================
echo "=== Test 3: progressColor ==="
# ============================================================

test_progress_color() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(run_js "${JS_HARNESS} console.log(progressColor($input))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_progress_color 0 "primary" "progressColor(0) = primary"
test_progress_color 50 "primary" "progressColor(50) = primary"
test_progress_color 51 "warning" "progressColor(51) = warning"
test_progress_color 80 "warning" "progressColor(80) = warning"
test_progress_color 81 "error" "progressColor(81) = error"
test_progress_color 100 "error" "progressColor(100) = error"

# ============================================================
echo "=== Test 4: formatTier ==="
# ============================================================

test_format_tier() {
    local input="$1" lang="$2" expected="$3" label="$4"
    local result
    result=$(run_js "${JS_HARNESS} testLang='$lang'; console.log(formatTier('$input'))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_format_tier "t3_max_20x_something" "en" "Max 20x" "formatTier max_20x"
test_format_tier "t2_max_5x_something" "en" "Max 5x" "formatTier max_5x"
test_format_tier "t1_pro_something" "en" "Pro" "formatTier pro"
test_format_tier "free_tier" "fr" "Gratuit" "formatTier free in French"
test_format_tier "team_tier" "es" "Equipo" "formatTier team in Spanish"
test_format_tier "enterprise_tier" "fr" "Entreprise" "formatTier enterprise in French"
test_format_tier "unknown" "en" "" "formatTier hides unknown"
test_format_tier "custom_plan" "en" "Custom Plan" "formatTier formats unrecognised tiers"

# ============================================================
echo "=== Test 5: formatCost ==="
# ============================================================

test_format_cost() {
    local usd="$1" lang="$2" rate="$3" expected="$4" label="$5"
    local result
    result=$(run_js "${JS_HARNESS} console.log(formatCost($usd, '$lang', $rate))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

# USD mode (non-French locale)
test_format_cost 0 "en" 0 "\$0.00" "formatCost(0) USD = \$0.00"
test_format_cost 5.5 "en" 0 "\$5.50" "formatCost(5.5) USD = \$5.50"
test_format_cost 15.3 "en" 0 "\$15.3" "formatCost(15.3) USD = \$15.3"
test_format_cost 150 "en" 0 "\$150" "formatCost(150) USD = \$150"
test_format_cost 1500 "en" 0 "\$1.5K" "formatCost(1500) USD = \$1.5K"

# EUR mode (French locale with rate)
test_format_cost 10 "fr" 0.92 "9.20 €" "formatCost(10) EUR = 9.20 €"
test_format_cost 100 "fr" 0.92 "92.0 €" "formatCost(100) EUR = 92.0 € (92<100 → toFixed(1))"
test_format_cost 1500 "fr" 0.92 "1.4K €" "formatCost(1500) EUR = 1.4K €"

# French locale but rate=0 → falls back to USD
test_format_cost 5 "fr" 0 "\$5.00" "formatCost(5) FR no rate = USD fallback"

# ============================================================
echo "=== Test 6: todayIndex ==="
# ============================================================

# todayIndex should match: Monday=0, Tuesday=1, ..., Sunday=6
EXPECTED_INDEX=$(date +%u)  # 1=Monday, 7=Sunday
EXPECTED_INDEX=$((EXPECTED_INDEX - 1))  # 0=Monday, 6=Sunday
ACTUAL_INDEX=$(run_js "${JS_HARNESS} console.log(todayIndex())")

if [ "$ACTUAL_INDEX" = "$EXPECTED_INDEX" ]; then
    pass "todayIndex() = $EXPECTED_INDEX (matches today)"
else
    fail "todayIndex() expected $EXPECTED_INDEX, got $ACTUAL_INDEX"
fi

# Test specific days via mocking
test_today_index_mock() {
    local js_dow="$1" expected="$2" label="$3"
    local result
    result=$(run_js "
        var _getDay = Date.prototype.getDay;
        Date.prototype.getDay = function() { return $js_dow; };
        ${JS_HARNESS}
        console.log(todayIndex());
        Date.prototype.getDay = _getDay;
    ")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_today_index_mock 0 6 "todayIndex Sunday (getDay=0) → 6"
test_today_index_mock 1 0 "todayIndex Monday (getDay=1) → 0"
test_today_index_mock 2 1 "todayIndex Tuesday (getDay=2) → 1"
test_today_index_mock 3 2 "todayIndex Wednesday (getDay=3) → 2"
test_today_index_mock 4 3 "todayIndex Thursday (getDay=4) → 3"
test_today_index_mock 5 4 "todayIndex Friday (getDay=5) → 4"
test_today_index_mock 6 5 "todayIndex Saturday (getDay=6) → 5"

# ============================================================
echo "=== Test 7: parseLine ==="
# ============================================================

test_parse_line() {
    local input="$1" field="$2" expected="$3" label="$4"
    local result
    result=$(run_js "${JS_HARNESS}
        var s = {};
        parseLine('$input', s);
        console.log(typeof s.$field === 'undefined' ? 'UNDEFINED' : JSON.stringify(s.$field));
    ")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

# Basic key=value parsing
test_parse_line "SUBSCRIPTION_TYPE=pro" "subscriptionType" '"pro"' "parseLine SUBSCRIPTION_TYPE"
test_parse_line "FIVE_HOUR_UTIL=42.5" "fiveHourUtil" '42.5' "parseLine FIVE_HOUR_UTIL float"
test_parse_line "WEEK_MESSAGES=100" "weekMessages" '100' "parseLine WEEK_MESSAGES int"
test_parse_line "EXTRA_USAGE_ENABLED=true" "extraUsageEnabled" 'true' "parseLine EXTRA_USAGE bool true"
test_parse_line "EXTRA_USAGE_ENABLED=false" "extraUsageEnabled" 'false' "parseLine EXTRA_USAGE bool false"

# Empty values default to 0
test_parse_line "WEEK_TOKENS=" "weekTokens" '0' "parseLine empty value defaults to 0"
test_parse_line "FIVE_HOUR_UTIL=" "fiveHourUtil" '0' "parseLine empty float defaults to 0"

# No equals sign — ignored
RESULT_NOEQUALS=$(run_js "${JS_HARNESS}
    var s = { weekTokens: 99 };
    parseLine('GARBAGE', s);
    console.log(s.weekTokens);
")
if [ "$RESULT_NOEQUALS" = "99" ]; then
    pass "parseLine no equals sign is ignored"
else
    fail "parseLine no equals sign should be ignored (got weekTokens=$RESULT_NOEQUALS)"
fi

# DAILY with fewer than 7 values — padded with zeros
RESULT_SHORT=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('DAILY=100,200', s);
    console.log(JSON.stringify(s.dailyTokens));
")
if [ "$RESULT_SHORT" = "[100,200,0,0,0,0,0]" ]; then
    pass "parseLine DAILY short array padded to 7"
else
    fail "parseLine DAILY short array expected [100,200,0,0,0,0,0], got $RESULT_SHORT"
fi

# DAILY with 7 values
RESULT_FULL=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('DAILY=1,2,3,4,5,6,7', s);
    console.log(JSON.stringify(s.dailyTokens));
")
if [ "$RESULT_FULL" = "[1,2,3,4,5,6,7]" ]; then
    pass "parseLine DAILY full 7 values"
else
    fail "parseLine DAILY full expected [1,2,3,4,5,6,7], got $RESULT_FULL"
fi

# DAILY_COSTS with fewer than 7 values
RESULT_COSTS_SHORT=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('DAILY_COSTS=0.50,1.20', s);
    console.log(JSON.stringify(s.dailyCosts));
")
if [ "$RESULT_COSTS_SHORT" = "[0.5,1.2,0,0,0,0,0]" ]; then
    pass "parseLine DAILY_COSTS short array padded to 7"
else
    fail "parseLine DAILY_COSTS short expected [0.5,1.2,0,0,0,0,0], got $RESULT_COSTS_SHORT"
fi

# WEEK_MODELS with valid pairs
RESULT_MODELS=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('WEEK_MODELS=opus:5000,sonnet:3000', s);
    console.log(JSON.stringify(s.models));
")
if [ "$RESULT_MODELS" = '[{"modelName":"opus","modelTokens":5000},{"modelName":"sonnet","modelTokens":3000}]' ]; then
    pass "parseLine WEEK_MODELS valid pairs"
else
    fail "parseLine WEEK_MODELS expected [{opus,5000},{sonnet,3000}], got $RESULT_MODELS"
fi

# WEEK_MODELS empty value
RESULT_MODELS_EMPTY=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('WEEK_MODELS=', s);
    console.log(JSON.stringify(s.models));
")
if [ "$RESULT_MODELS_EMPTY" = "[]" ]; then
    pass "parseLine WEEK_MODELS empty = empty array"
else
    fail "parseLine WEEK_MODELS empty expected [], got $RESULT_MODELS_EMPTY"
fi

# WEEK_MODELS with malformed entry (no colon) — skipped
RESULT_MODELS_BAD=$(run_js "${JS_HARNESS}
    var s = {};
    parseLine('WEEK_MODELS=opus:5000,badentry,sonnet:3000', s);
    console.log(JSON.stringify(s.models));
")
if [ "$RESULT_MODELS_BAD" = '[{"modelName":"opus","modelTokens":5000},{"modelName":"sonnet","modelTokens":3000}]' ]; then
    pass "parseLine WEEK_MODELS malformed entry skipped"
else
    fail "parseLine WEEK_MODELS malformed expected opus+sonnet only, got $RESULT_MODELS_BAD"
fi

# paceInfo — shared by Claude (hardcoded window) and ChatGPT (real,
# API-reported window) callers alike.
RESULT_PACE_ON=$(run_js "${JS_HARNESS}
    // countdownNow=0, window=18000000 (5h), reset in 9000000ms => timeFrac=0.5, util=50 => on pace
    console.log(paceInfo(50, new Date(9000000).toISOString(), 18000000).status)
")
assert_eq "$RESULT_PACE_ON" "on" "paceInfo: on pace when util tracks elapsed time"

RESULT_PACE_OVER=$(run_js "${JS_HARNESS}
    console.log(paceInfo(80, new Date(9000000).toISOString(), 18000000).status)
")
assert_eq "$RESULT_PACE_OVER" "over" "paceInfo: over pace when util well ahead of elapsed time"

RESULT_PACE_UNDER=$(run_js "${JS_HARNESS}
    console.log(paceInfo(10, new Date(9000000).toISOString(), 18000000).status)
")
assert_eq "$RESULT_PACE_UNDER" "under" "paceInfo: under pace when util well behind elapsed time"

RESULT_PACE_QUOTA=$(run_js "${JS_HARNESS}
    console.log(paceInfo(100, new Date(9000000).toISOString(), 18000000).status)
")
assert_eq "$RESULT_PACE_QUOTA" "over_quota" "paceInfo: over_quota once util reaches 100 regardless of elapsed time"

RESULT_PACE_NORESET=$(run_js "${JS_HARNESS}
    console.log(paceInfo(50, '', 18000000).status)
")
assert_eq "$RESULT_PACE_NORESET" "unknown" "paceInfo: unknown with no reset timestamp and util<100"

RESULT_PACE_NORESET_FULL=$(run_js "${JS_HARNESS}
    console.log(paceInfo(100, '', 18000000).status)
")
assert_eq "$RESULT_PACE_NORESET_FULL" "over_quota" "paceInfo: over_quota with no reset timestamp but util=100"

# Regression: a zero/missing window length (e.g. before a Source's first
# fetch, or an API response missing limit_window_seconds) must not be
# treated as an elapsed-100%-of-window state — that previously produced a
# false "over pace" for any nonzero util (division by zero -> -Infinity ->
# clamped timeFrac 0, so delta == util for any positive util).
RESULT_PACE_ZEROWINDOW=$(run_js "${JS_HARNESS}
    console.log(paceInfo(50, new Date(9000000).toISOString(), 0).status)
")
assert_eq "$RESULT_PACE_ZEROWINDOW" "unknown" "paceInfo: zero window length falls back to unknown, not a false over-pace"

RESULT_PACE_ZEROWINDOW_FULL=$(run_js "${JS_HARNESS}
    console.log(paceInfo(100, new Date(9000000).toISOString(), 0).status)
")
assert_eq "$RESULT_PACE_ZEROWINDOW_FULL" "over_quota" "paceInfo: zero window length still reports over_quota at util=100"

# ============================================================
echo "=== Test 8: parseZaiLine ==="
# ============================================================

test_parse_zai() {
    local input="$1" field="$2" expected="$3" label="$4"
    local result
    result=$(run_js "${JS_HARNESS}
        var s = {};
        parseZaiLine('$input', s);
        console.log(typeof s.$field === 'undefined' ? 'UNDEFINED' : JSON.stringify(s.$field));
    ")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_parse_zai "PLAN_TYPE=lite" "planType" '"lite"' "parseZaiLine PLAN_TYPE"
test_parse_zai "PRIMARY_UTIL=34" "primaryUtil" '34' "parseZaiLine PRIMARY_UTIL"
test_parse_zai "PRIMARY_WINDOW_SECONDS=18000" "primaryWindowSeconds" '18000' "parseZaiLine PRIMARY_WINDOW_SECONDS"
test_parse_zai "SECONDARY_UTIL=6" "secondaryUtil" '6' "parseZaiLine SECONDARY_UTIL"
test_parse_zai "SECONDARY_WINDOW_SECONDS=604800" "secondaryWindowSeconds" '604800' "parseZaiLine SECONDARY_WINDOW_SECONDS"
test_parse_zai "CREDS_STATUS=ok" "credsStatus" '"ok"' "parseZaiLine CREDS_STATUS"
test_parse_zai "WEEK_TOKENS=1234567" "weekTokens" '1234567' "parseZaiLine WEEK_TOKENS"
test_parse_zai "WEEK_CALLS=482" "weekCalls" '482' "parseZaiLine WEEK_CALLS"
test_parse_zai "MONTH_TOKENS=98765432" "monthTokens" '98765432' "parseZaiLine MONTH_TOKENS"
test_parse_zai "ACCOUNTS=default,work" "accounts" '["default","work"]' "parseZaiLine ACCOUNTS"
test_parse_zai "ACCOUNTS=" "accounts" '[]' "parseZaiLine ACCOUNTS empty"

# The script emits resets as unix SECONDS; the widget stores milliseconds.
test_parse_zai "PRIMARY_RESET=1789279094" "primaryResetMs" '1789279094000' "parseZaiLine PRIMARY_RESET seconds to ms"
test_parse_zai "SECONDARY_RESET=1789865116" "secondaryResetMs" '1789865116000' "parseZaiLine SECONDARY_RESET seconds to ms"

# A window the API omits arrives with an empty RESET — no countdown, no pacing.
test_parse_zai "PRIMARY_RESET=" "primaryResetMs" '0' "parseZaiLine empty PRIMARY_RESET disables countdown"

RESULT_ZAI_DAILY=$(run_js "${JS_HARNESS}
    var s = {};
    parseZaiLine('DAILY=1,2,3', s);
    console.log(JSON.stringify(s.dailyTokens));
")
assert_eq "$RESULT_ZAI_DAILY" "[1,2,3,0,0,0,0]" "parseZaiLine DAILY short array padded to 7"

# Z.ai model names keep API casing and contain dots/dashes, so the pair
# separator must be the first "=" only.
RESULT_ZAI_MODELS=$(run_js "${JS_HARNESS}
    var s = {};
    parseZaiLine('WEEK_MODELS=GLM-4.6=5000,GLM-4.5-Air=3000', s);
    console.log(JSON.stringify(s.models));
")
assert_eq "$RESULT_ZAI_MODELS" '[{"modelName":"GLM-4.6","modelTokens":5000},{"modelName":"GLM-4.5-Air","modelTokens":3000}]' "parseZaiLine WEEK_MODELS keeps API model casing"

RESULT_ZAI_MODELS_EMPTY=$(run_js "${JS_HARNESS}
    var s = {};
    parseZaiLine('WEEK_MODELS=', s);
    console.log(JSON.stringify(s.models));
")
assert_eq "$RESULT_ZAI_MODELS_EMPTY" "[]" "parseZaiLine WEEK_MODELS empty = empty array"

# Claude/ChatGPT-only keys must not leak into Z.ai state.
RESULT_ZAI_IGNORED=$(run_js "${JS_HARNESS}
    var s = {};
    parseZaiLine('ALLTIME_SESSIONS=42', s);
    parseZaiLine('WEEK_MESSAGES=10', s);
    console.log(JSON.stringify(s));
")
assert_eq "$RESULT_ZAI_IGNORED" "{}" "parseZaiLine ignores keys Z.ai never emits"

# ============================================================
# ============================================================
echo "=== Test 9: countdown clock labels ==="
# ============================================================

# A sub-24h reset appends the local wall clock of the reset instant
RESULT_SUB=$(run_js "${JS_HARNESS} countdownNow = Date.UTC(2026, 8, 13, 3, 35, 0); console.log(formatCountdown(countdownNow + 139 * 60000))")
if echo "$RESULT_SUB" | grep -qE '^2h 19m \(([A-Za-z]{3} )?[0-9]{2}:[0-9]{2}\)$'; then pass "formatCountdown appends a clock label under 24h"; else fail "formatCountdown sub-24h label got '$RESULT_SUB'"; fi

# The appended clock is the reset instant rendered in local time
CLOCK=$(run_js "${JS_HARNESS} countdownNow = Date.UTC(2026, 8, 13, 3, 35, 0); var r = countdownNow + 139 * 60000; console.log(Qt.formatDateTime(new Date(r), 'HH:mm'))")
EXPECT=$(echo "$RESULT_SUB" | grep -oE '[0-9]{2}:[0-9]{2}' | tail -1)
if [ "$CLOCK" = "$EXPECT" ]; then pass "appended clock matches the reset instant"; else fail "clock mismatch: $CLOCK vs $EXPECT"; fi

# A multi-day reset includes the weekday
RESULT_MULTI=$(run_js "${JS_HARNESS} countdownNow = Date.UTC(2026, 8, 13, 3, 35, 0); console.log(formatCountdown(countdownNow + 5 * 86400000 + 3 * 3600000))")
if echo "$RESULT_MULTI" | grep -qE '^5d 3h 00m \(([A-Za-z]{3} )?[0-9]{2}:[0-9]{2}\)$'; then pass "formatCountdown appends a clock label past 24h"; else fail "formatCountdown multi-day label got '$RESULT_MULTI'"; fi

# A reset later today carries no date; a reset on another calendar day does.
# Anchored to the real clock (23:59 today, now + 48h) so the branch taken is
# the same whatever time or timezone the suite runs in.
RESULT_TODAY=$(run_js "${JS_HARNESS} var d = new Date(); d.setHours(23, 59, 0, 0); console.log(resetClockLabel(d.getTime()))")
RESULT_OTHERDAY=$(run_js "${JS_HARNESS} console.log(resetClockLabel(Date.now() + 48 * 3600000))")
if echo "$RESULT_TODAY" | grep -qE '^ \([0-9]{2}:[0-9]{2}\)$'; then pass "same-calendar-day reset shows time only"; else fail "same-day label got '$RESULT_TODAY'"; fi
if echo "$RESULT_OTHERDAY" | grep -qE '^ \([A-Za-z]{3} [0-9]{2}:[0-9]{2}\)$'; then pass "other-calendar-day reset includes the weekday"; else fail "other-day label got '$RESULT_OTHERDAY'"; fi

# Past and zero resets keep their previous shape
R_PAST=$(run_js "${JS_HARNESS} countdownNow = Date.UTC(2026, 8, 13, 3, 35, 0); console.log(formatCountdown(countdownNow - 1000))")
if [ "$R_PAST" = "Resetting..." ]; then pass "past reset still Resetting... without a label"; else fail "past reset got '$R_PAST'"; fi
R_ZERO=$(run_js "${JS_HARNESS} console.log(formatCountdown(0))")
if [ "$R_ZERO" = "" ]; then pass "zero reset still empty"; else fail "zero reset got '$R_ZERO'"; fi

# ============================================================
echo "=== Test 10: endpoint failures keep the last good reading ==="
# ============================================================

# applyCredsStatus is the one piece of the stale-value rule that is pure, so it
# is pulled out of the widget itself rather than copied into this harness, and
# exercised for real.
CREDS_REPORT=/tmp/creds-status-report.txt
node - "$SCRIPT_DIR/AiUsageWidget.qml" > "$CREDS_REPORT" 2>&1 <<'NODE'
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8");
const match = source.match(/function applyCredsStatus\(st, val\) \{[\s\S]*?\n    \}/);
if (!match) {
    console.log("FAIL\tapplyCredsStatus could not be extracted from the widget");
    process.exit(0);
}
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(match[0] + "; this.apply = applyCredsStatus;", sandbox, { filename: "applyCredsStatus" });
const apply = sandbox.apply;
const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// A good reading is the only thing that counts as data.
const good = { credsStatus: "unknown", hasData: false, primary: { util: 0 }, secondary: { util: 0 } };
apply(good, "ok");
check(good.hasData === true && good.credsStatus === "ok", "a good reading marks the Source as having data");

// An endpoint failure must not blank the last good reading: the script reports
// no Window values, so the widget keeps them and the status card marks them
// stale. hasData survives so the card knows there is something to fall back on.
const afterFailure = { credsStatus: "ok", hasData: true, primary: { util: 42 }, secondary: { util: 7 } };
apply(afterFailure, "unavailable");
check(afterFailure.hasData === true, "an endpoint failure keeps the last good reading marked as data");
check(afterFailure.credsStatus === "unavailable", "an endpoint failure is its own status");
check(afterFailure.primary.util === 42 && afterFailure.secondary.util === 7, "an endpoint failure does not overwrite the Window values with zeros");

// A first fetch that fails has nothing to fall back on, so the tab must say so
// rather than draw a fabricated zero.
const firstFailure = { credsStatus: "unknown", hasData: false, primary: { util: 0 }, secondary: { util: 0 } };
apply(firstFailure, "unavailable");
check(firstFailure.hasData === false, "a first endpoint failure reports no data to fall back on");

// A rejected key is a credential problem, not data: it must not mark the
// Source as having a current reading and must stay distinct from unavailable.
const rejected = { credsStatus: "unknown", hasData: false };
apply(rejected, "missing");
check(rejected.hasData === false && rejected.credsStatus === "missing", "a rejected key is not data and is not unavailable");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$CREDS_REPORT"

if ! grep -q "^PASS\|^FAIL" "$CREDS_REPORT"; then
    fail "creds-status report produced no results (node failed?) see $CREDS_REPORT"
fi

# ============================================================
echo "=== Test 11: the Pill's no-reading rule ==="
# ============================================================

# pillHasReading decides whether a Pill slot draws a reading or a hollow
# no-reading ring. Extracted from the widget so the rule cannot drift.
PILL_REPORT=/tmp/pill-reading-report.txt
node - "$SCRIPT_DIR/AiUsageWidget.qml" > "$PILL_REPORT" 2>&1 <<'NODE'
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8");
const match = source.match(/function pillHasReading\(id\) \{[\s\S]*?\n    \}/);
if (!match) {
    console.log("FAIL\tpillHasReading could not be extracted from the widget");
    process.exit(0);
}
const sandbox = { root: { sourceData: {} } };
vm.createContext(sandbox);
vm.runInContext(match[0] + "; this.pillHasReading = pillHasReading;", sandbox, { filename: "pillHasReading" });
const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);
const has = (status) => {
    sandbox.root.sourceData = status === undefined ? {} : { s: { credsStatus: status } };
    return sandbox.pillHasReading("s");
};
check(has(undefined) === true, "a Source before its first fetch keeps its ring");
check(has("unknown") === true, "an unknown status keeps its ring");
check(has("ok") === true, "a good reading draws the ring");
check(has("missing") === false, "missing credentials draw no reading");
check(has("expired") === false, "expired credentials draw no reading");
check(has("unavailable") === false, "an unavailable endpoint draws no reading");
console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$PILL_REPORT"

if ! grep -q "^PASS\|^FAIL" "$PILL_REPORT"; then
    fail "pill-reading report produced no results (node failed?) see $PILL_REPORT"
fi

# ============================================================
echo "=== Test 12: descriptor-declared Accounts, login and Account keys ==="
# ============================================================

# The widget's Account adapter is exercised against the real descriptors. The
# Account setting key, the Account output keys and the login command all come
# from sources.js, so this is where a Source-shaped branch creeping back into
# the widget would show up. Functions are extracted from the widget itself and
# wired to the real registry rather than copied into this harness.
ACCOUNT_REPORT=/tmp/account-overlay-report.txt
node - "$SCRIPT_DIR" > "$ACCOUNT_REPORT" 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const repo = process.argv[2];

const source = fs.readFileSync(path.join(repo, "AiUsageWidget.qml"), "utf8");

function extract(name) {
    const m = source.match(new RegExp("function " + name + "\\([\\s\\S]*?\\n    \\}"));
    if (!m) throw new Error("could not extract " + name);
    return m[0];
}

const registrySource = fs.readFileSync(path.join(repo, "sources.js"), "utf8").replace(/^\.pragma library\s*/, "");
const registry = {};
vm.createContext(registry);
vm.runInContext(registrySource + "; this.api = { SOURCES, byId, ids, wirePair, splitList, nameValueMap, scriptCommand, scriptPath };", registry, { filename: "sources.js" });
const Sources = registry.api;

const names = [
    "settingList", "accountFieldFor", "loginCommandFor", "shellQuote",
    "emptyState", "updateSource", "setWindow",
    "parseWindowKey", "parseAccountKey", "parseLine", "applyAccounts",
    "applyAccountField", "applyAccountNumber", "applyAccountBool",
    "applyAccountList", "applyAccountModels", "mutateAccounts",
    "parseAccountScalars", "parseAccountSeries", "parseAccountModels",
    "parseDaily", "parseModels", "parseResetMs", "applyCredsStatus",
    "stateFor", "windowSeconds", "selectAccount", "accountNames",
    "setLoginInProgress", "loginProcessFor", "startLogin",
    "refetchChangedAccounts"
];

const sandbox = {
    Sources: Sources,
    pluginData: {},
    console: console,
    root: {
        sourceData: {},
        accountData: {},
        selectedAccount: {},
        accountSettings: {},
        loginCommands: {},
        sourceOrder: [],
        lastAccountSettings: null,
        usdEurRate: 0,
        todayIndex: 0,
        cliSearchPathAdditions: "$HOME/.local/bin"
    }
};
vm.createContext(sandbox);
let code = "";
for (const n of names)
    code += extract(n) + "\n";
code += "for (var i = 0; i < " + JSON.stringify(names) + ".length; i++) { var n = " + JSON.stringify(names) + "[i]; root[n] = this[n]; }\n";
vm.runInContext(code, sandbox, { filename: "widget-functions" });

const widget = sandbox.root;
const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);
const parse = (id, line) => sandbox.parseLine(id, line);

// --- The Account setting key is resolved from the descriptor ---
sandbox.pluginData = { customOpencodeAccounts: [{ name: "work", key: "sk-1" }] };
widget.accountSettings = { customOpencodeAccounts: sandbox.pluginData.customOpencodeAccounts };
check(widget.settingList("customOpencodeAccounts").length === 1, "settingList resolves a descriptor's settingKey");
check(widget.settingList("notAKey").length === 0, "settingList returns an empty list for an unknown key");

// --- opencode Go: descriptor-declared Account keys fill the overlay ---
parse("opencode", "ACCOUNTS=default,work");
parse("opencode", "ACCOUNT_PRIMARY_UTIL=default:1,work:80");
parse("opencode", "ACCOUNT_PRIMARY_RESET=default:2026-09-16T15:31:05.155Z,work:2026-09-17T00:00:00.000Z");
parse("opencode", "ACCOUNT_SECONDARY_UTIL=default:6,work:2");
parse("opencode", "ACCOUNT_CREDS_STATUS=default:ok,work:ok");
check(widget.accountData.opencode.work.primaryUtil === 80, "opencode ACCOUNT_PRIMARY_UTIL lands on the generic primary slot");
check(widget.accountData.opencode.work.primaryReset === "2026-09-17T00:00:00.000Z", "opencode ACCOUNT_PRIMARY_RESET lands on the generic primary reset");
check(widget.accountData.opencode.work.secondaryUtil === 2, "opencode ACCOUNT_SECONDARY_UTIL lands on the generic secondary slot");

// --- Claude keeps its existing PROFILES + PROFILE_* contract ---
parse("claude", "PROFILES=default,work");
parse("claude", "PROFILE_FIVE_HOUR_UTIL=default:42,work:7");
parse("claude", "PROFILE_FIVE_HOUR_RESET=default:2099-01-01T00:00:00Z,work:2099-02-01T00:00:00Z");
check(widget.accountData.claude.work.primaryUtil === 7, "Claude's PROFILE_FIVE_HOUR_UTIL still fills the primary slot");
check(widget.accountData.claude.work.primaryReset === "2099-02-01T00:00:00Z", "Claude's PROFILE_FIVE_HOUR_RESET still fills the primary reset");

// --- ChatGPT's per-Account keys wear its own Window names ---
parse("chatgpt", "ACCOUNTS=default,work");
parse("chatgpt", "ACCOUNT_PRIMARY_UTIL=default:42,work:7");
parse("chatgpt", "ACCOUNT_SECONDARY_UTIL=default:15,work:3");
check(widget.accountData.chatgpt.work.primaryUtil === 7, "ChatGPT's ACCOUNT_PRIMARY_UTIL fills the primary slot");
check(widget.accountData.chatgpt.work.secondaryUtil === 3, "ChatGPT's ACCOUNT_SECONDARY_UTIL fills the secondary slot");

// --- stateFor overlays the selected Account, and falls back to the aggregate ---
widget.sourceData.opencode = Object.assign(widget.sourceData.opencode, {
    primary: { util: 1, resetMs: 0, windowSeconds: 18000 },
    secondary: { util: 6, resetMs: 0, windowSeconds: 604800 }
});
widget.selectedAccount.opencode = "work";
const stWork = widget.stateFor("opencode");
check(stWork.primary.util === 80, "stateFor overlays the selected Account's primary Window");
check(stWork.id === "opencode", "stateFor carries the Source id");
widget.selectedAccount.opencode = "all";
check(widget.stateFor("opencode").primary.util === 1, "stateFor with the aggregate selected keeps the aggregate");

parse("opencode", "ACCOUNTS=default,work,spare");
parse("opencode", "ACCOUNT_CREDS_STATUS=spare:missing");
widget.selectedAccount.opencode = "spare";
check(widget.stateFor("opencode").primary.util === 1, "an Account with no reading falls back to the aggregate");

// An endpoint failure omits an Account from the Window lists (ADR-0002), so its
// overlay must keep the last good reading rather than parse the silence as 0.
parse("opencode", "ACCOUNT_PRIMARY_UTIL=default:1");
widget.selectedAccount.opencode = "work";
check(widget.stateFor("opencode").primary.util === 80, "an Account omitted from an Unavailable run keeps its last good reading");

// --- The login command is built from the descriptor ---
widget.accountSettings = { customProfiles: [{ name: "work", path: "/home/u/.ccp/work" }] };
widget.selectedAccount = { claude: "work" };
const cmd = widget.loginCommandFor(Sources.byId("claude"), "claude");
check(cmd[0] === "bash" && cmd[1] === "-c", "a cli login runs through bash -c");
check(cmd[2].indexOf("CLAUDE_CONFIG_DIR='/home/u/.ccp/work'") === 0, "Claude's login exports the selected Account's config directory");
check(cmd[2].indexOf("exec claude 'auth' 'login' '--claudeai'") >= 0, "the login program and args come from the descriptor");
check(cmd[2].indexOf("exec claude auth login") < 0, "descriptor args are shell-quoted, not concatenated raw");
const cmdCg = widget.loginCommandFor(Sources.byId("chatgpt"), "chatgpt");
check(cmdCg[2].indexOf("CLAUDE_CONFIG_DIR=") < 0, "a login with no declared environment exports nothing");
check(cmdCg[2].indexOf("exec codex 'login'") >= 0, "ChatGPT's login program comes from its descriptor");
widget.selectedAccount = { claude: "all" };
check(widget.loginCommandFor(Sources.byId("claude"), "claude")[2].indexOf("CLAUDE_CONFIG_DIR=") < 0, "the aggregate selection leaves the CLI's own default in place");

// An arg with a space or a quote is the extension point this schema exists to
// create, so it must survive into the bash string intact.
const spacedCmd = widget.loginCommandFor({ login: { kind: "cli", program: "mycli", args: ["a b", "c'd"] } }, "synthetic");
check(spacedCmd[2].indexOf("exec mycli 'a b' 'c'\\''d'") >= 0, "a descriptor arg with a space or quote is shell-quoted");

// --- Two Sources can log in at the same time ---
// Each CLI descriptor gets its own Process, so a press on one Source must not
// be dropped because another Source's login is already running.
widget.loginInProgress = {};
widget.loginProcesses = { claude: { running: true }, chatgpt: { running: false }, opencode: { running: false } };
widget.startLogin("chatgpt");
check(widget.loginProcesses.chatgpt.running === true, "a second Source's login starts while the first is running");
check(widget.loginInProgress.chatgpt === true, "the second Source shows login progress");
check(widget.loginProcesses.claude.running === true, "the first Source's login keeps running");
widget.startLogin("chatgpt");
check(widget.loginInProgress.chatgpt === true, "re-pressing a running login leaves its progress shown");
widget.startLogin("opencode");
check(widget.loginProcesses.opencode.running === false, "a text-only login has no Process to start");

// The command a login runs with is fixed when the button is pressed. Changing
// the Account selection afterwards must not reach into a running Process.
widget.accountSettings = { customProfiles: [{ name: "work", path: "/home/u/.ccp/work" }, { name: "home", path: "/home/u/.claude" }] };
widget.selectedAccount = { claude: "work" };
widget.loginCommands = {};
widget.loginProcesses = { claude: { running: false } };
widget.startLogin("claude");
const snapshot = widget.loginCommands.claude;
check(!!snapshot && snapshot[2].indexOf("CLAUDE_CONFIG_DIR='/home/u/.ccp/work'") === 0,
      "pressing login snapshots the command for the Account selected at press time");
widget.selectedAccount = { claude: "home" };
check(widget.loginCommands.claude === snapshot,
      "changing the Account selection leaves a running login's command untouched");
widget.startLogin("claude");
check(widget.loginCommands.claude === snapshot,
      "re-pressing a running login does not rewrite its command");

// The first evaluation of the Account settings is the baseline, so it must not
// queue a refetch of every Source on top of the startup fetch.
const fetched = [];
widget.requestFetch = (id) => fetched.push(id);
widget.sourceOrder = ["claude", "chatgpt", "opencode", "zai"];
widget.lastAccountSettings = null;
widget.accountSettings = {
    customProfiles: [{ name: "work", path: "/p" }],
    customChatgptAccounts: [],
    customOpencodeAccounts: [],
    customZaiAccounts: []
};
widget.refetchChangedAccounts();
check(fetched.length === 0, "the first Account settings evaluation seeds the baseline and fetches nothing");
widget.accountSettings = Object.assign({}, widget.accountSettings, { customChatgptAccounts: [{ name: "work", path: "/c" }] });
widget.refetchChangedAccounts();
check(fetched.length === 1 && fetched[0] === "chatgpt", "a later change refetches only the Source whose Account list changed");
widget.refetchChangedAccounts();
check(fetched.length === 1, "an unchanged settings save refetches nothing");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$ACCOUNT_REPORT"

if ! grep -q "^PASS\|^FAIL" "$ACCOUNT_REPORT"; then
    fail "account overlay report produced no results (node failed?) see $ACCOUNT_REPORT"
fi

# ============================================================
echo "=== Test 13: the Overview toggle is its own setting ==="
# ============================================================

# The Overview is not a Source (ADR 0003): it is a standalone boolean, default
# on, that never enters the enabled-Sources array. Both halves are read from the
# files themselves, so the setting cannot drift.
OVERVIEW_REPORT=/tmp/overview-setting-report.txt
node - "$SCRIPT_DIR" > "$OVERVIEW_REPORT" 2>&1 <<'NODE'
const fs = require("fs");
const path = require("path");
const root = process.argv[2];
const widget = fs.readFileSync(path.join(root, "AiUsageWidget.qml"), "utf8");
const settings = fs.readFileSync(path.join(root, "AiUsageSettings.qml"), "utf8");
const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// A consumer reads the resolved boolean off the widget. The absence of the key
// must mean "on", matching every other boolean setting.
const binding = widget.match(/property bool overviewEnabled:\s*([^\n]+)/);
check(!!binding, "the widget declares overviewEnabled");
if (binding) {
    const resolve = new Function("pluginData", "return (" + binding[1].trim() + ");");
    check(resolve({}) === true, "overviewEnabled defaults to true when unset");
    check(resolve({ overviewEnabled: true }) === true, "overviewEnabled honours an explicit true");
    check(resolve({ overviewEnabled: false }) === false, "overviewEnabled honours an explicit false");
}

// The settings page persists it through the standard ToggleSetting, pinned
// above the draggable Source list and carrying no move buttons.
const toggle = settings.match(/ToggleSetting\s*\{[^}]*settingKey:\s*"overviewEnabled"[^}]*\}/);
check(!!toggle, "the settings page has an overviewEnabled toggle");
if (toggle) {
    check(/defaultValue:\s*true/.test(toggle[0]), "the settings toggle defaults to true");
    check(settings.indexOf(toggle[0]) < settings.indexOf("model: root.displayDescriptors"),
          "the toggle sits above the draggable Source list");
    check(!/move\(|keyboard_arrow/.test(toggle[0]), "the toggle has no move buttons");
}

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$OVERVIEW_REPORT"

if ! grep -q "^PASS\|^FAIL" "$OVERVIEW_REPORT"; then
    fail "overview-setting report produced no results (node failed?) see $OVERVIEW_REPORT"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
