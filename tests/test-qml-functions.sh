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

var widgetSources = (function () {
    var fs = require("fs");
    var vm = require("vm");
    var sandbox = { console: console };
    vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync("__ROOT__/sources.js", "utf8").replace(/^\.pragma library\s*/, "") + "; this.SOURCES = SOURCES;", sandbox);
    return sandbox.SOURCES;
})();

function brandColor(id) {
    for (var i = 0; i < widgetSources.length; i++)
        if (widgetSources[i].id === id)
            return widgetSources[i].brandColor
    return "primary"
}

function utilisationColor(id, pct) {
    if (pct > 80) return "error"
    if (pct > 50) return "warning"
    return brandColor(id)
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
    return ""
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

JS_HARNESS="${JS_HARNESS//__ROOT__/$SCRIPT_DIR}"

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
echo "=== Test 3b: Brand Colour ==="
# ============================================================

test_brand_color() {
    local input="$1" expected="$2" label="$3"
    local result
    result=$(run_js "${JS_HARNESS} console.log(brandColor('$input'))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_brand_color claude "#D97757" "brandColor(claude) = the clay"
test_brand_color chatgpt "#10A37F" "brandColor(chatgpt) = the green"
test_brand_color zai "#4F7CFF" "brandColor(zai) = the blue"
test_brand_color opencode "#A78BFA" "brandColor(opencode) = the violet"
test_brand_color overview "primary" "brandColor falls back to the theme primary for a non-Source tab"

test_utilisation_color() {
    local input="$1" id="$2" expected="$3" label="$4"
    local result
    result=$(run_js "${JS_HARNESS} console.log(utilisationColor('$id', $input))")
    if [ "$result" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$result')"
    fi
}

test_utilisation_color 0 "claude" "#D97757" "utilisationColor keeps the Brand Colour at 0%"
test_utilisation_color 50 "chatgpt" "#10A37F" "utilisationColor keeps the Brand Colour at 50%"
test_utilisation_color 51 "zai" "warning" "utilisationColor takes the warning colour past 50%"
test_utilisation_color 80 "zai" "warning" "utilisationColor holds the warning colour at 80%"
test_utilisation_color 81 "opencode" "error" "utilisationColor takes the error colour past 80%"
test_utilisation_color 100 "opencode" "error" "utilisationColor holds the error colour at 100%"

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
test_format_tier "custom_plan" "en" "" "formatTier hides unrecognised tiers"
test_format_tier "default_claude_ai" "en" "" "formatTier hides Claude Pro's default tier"

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
    "windowSeconds", "selectAccount", "accountNames",
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

// --- The Account setting key is resolved from the descriptor ---
sandbox.pluginData = { customOpencodeAccounts: [{ name: "work", key: "sk-1" }] };
widget.accountSettings = { customOpencodeAccounts: sandbox.pluginData.customOpencodeAccounts };
check(widget.settingList("customOpencodeAccounts").length === 1, "settingList resolves a descriptor's settingKey");
check(widget.settingList("notAKey").length === 0, "settingList returns an empty list for an unknown key");

// Reading a report into a State is state.js's, and tests/test-source-state.sh
// runs it there. What is left here is the widget's own half: the settings it
// resolves, the login commands it builds, and the refetching it schedules.

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

# ============================================================
echo "=== Test 14: the fetch set is every enabled Source ==="
# ============================================================

# ADR 0004: visibility is a display filter, so a hidden Source is still fetched
# and a Source whose credentials come back recovers without a restart. These
# checks pin the separation: every fetch entry point reads the enabled list, and
# only the display layer reads the shared hidden value.
FETCH_REPORT=/tmp/fetch-set-report.txt
node - "$SCRIPT_DIR" > "$FETCH_REPORT" 2>&1 <<'NODE'
const fs = require("fs");
const path = require("path");
const root = process.argv[2];
const widget = fs.readFileSync(path.join(root, "AiUsageWidget.qml"), "utf8");
const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

const fetchEnabled = widget.match(/function fetchEnabled\(\) \{[\s\S]*?\n    \}/);
check(!!fetchEnabled, "the widget has one fetch-everything entry point");
check(!!fetchEnabled && /root\.sourceOrder/.test(fetchEnabled[0]),
      "fetchEnabled iterates every enabled Source, not the visible ones");
check((widget.match(/function fetchVisible\s*\(/g) || []).length === 0,
      "no display-derived fetch function is left behind");

// The refresh timer and the countdown tick's wake-from-sleep branch both call it.
check(/if \(elapsed > 120000\) \{\s*root\.fetchEnabled\(\)/.test(widget),
      "waking from sleep refetches every enabled Source");
check(/onTriggered: root\.fetchEnabled\(\)/.test(widget),
      "the refresh timer fetches every enabled Source");
const countdown = widget.match(/interval: 60000[\s\S]*?\n    \}/);
check(!!countdown && /root\.sourceOrder/.test(countdown[0]),
      "the countdown tick's reset-expiry refetch iterates every enabled Source");

// The display layer filters on the shared hidden value rather than a raw status.
const visible = widget.match(/readonly property var visibleDescriptors: \{[\s\S]*?\n    \}/);
check(!!visible && /st\.hidden !== true/.test(visible[0]) &&
      !/credsStatus\s*!==\s*"not_installed"/.test(visible[0]),
      "the Pill and Popout filter on the shared hidden value");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$FETCH_REPORT"

if ! grep -q "^PASS\|^FAIL" "$FETCH_REPORT"; then
    fail "fetch-set report produced no results (node failed?) see $FETCH_REPORT"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
