#!/usr/bin/env bash
# Tests for the widget's pure formatters: the figures, clocks, pacing labels
# and plan names every surface renders the same way.
#
# format.js is a .pragma library like sources.js and state.js, so these run
# the production code rather than a copy of it: the harness forks that used to
# mirror these functions inside test-qml-functions.sh drifted (its paceInfo
# took an ISO timestamp where the widget's took milliseconds), which is why
# they are gone.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping format tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== The widget's pure formatters ==="

node - "$SCRIPT_DIR" >/tmp/format-report.txt 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const root = process.argv[2];

// QML's own library directives have no meaning under Node: .pragma marks the
// file as a shared library, and .import is how format.js reaches the
// translation table. Both are stripped, and the imported libraries are handed
// to the sandbox instead, exactly as tests/test-source-state.sh does.
const read = (file) => fs.readFileSync(path.join(root, file), "utf8")
    .replace(/^\.pragma library\s*/, "")
    .replace(/^\.import\s+"[^"]+"\s+as\s+\w+\s*$/gm, "");

const load = (file, suffix, extra) => {
    const sandbox = Object.assign({ console }, extra || {});
    vm.createContext(sandbox);
    vm.runInContext(read(file) + suffix, sandbox, { filename: file });
    return sandbox;
};

const Tr = load("translations.js", "; this.api = { tr };").api;

// resetClockLabel formats through Qt.formatDateTime, which exists only under
// QML. This shim models the engine for the three patterns format.js uses; it
// is sandbox plumbing, not a copy of anything under test.
const Qt = {
    formatDateTime: function (date, fmt) {
        const pad = (n) => (n < 10 ? "0" : "") + n;
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        if (fmt === "ddd HH:mm")
            return days[date.getDay()] + " " + pad(date.getHours()) + ":" + pad(date.getMinutes());
        if (fmt === "yyyy-MM-dd")
            return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
        return pad(date.getHours()) + ":" + pad(date.getMinutes());
    }
};

const Format = load("format.js",
    "; this.api = { formatTokens, formatCost, paceInfo, formatCountdown, resetClockLabel, formatWindowLabel, formatTier, formatSubscription, paceLabel, shortModelName, todayIndex };",
    { Tr: Tr, Qt: Qt }).api;

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);
const eq = (got, want, label) => check(got === want,
    label + (got === want ? "" : ` (expected '${want}', got '${got}')`));
const eqj = (got, want, label) => eq(JSON.stringify(got), JSON.stringify(want), label);

// --- formatTokens: K/M/B compaction ---
eq(Format.formatTokens(0), "0", "formatTokens(0) = 0");
eq(Format.formatTokens(999), "999", "formatTokens(999) stays raw");
eq(Format.formatTokens(1000), "1.0K", "formatTokens(1000) = 1.0K");
eq(Format.formatTokens(1500), "1.5K", "formatTokens(1500) = 1.5K");
eq(Format.formatTokens(999999), "1000.0K", "formatTokens(999999) = 1000.0K");
eq(Format.formatTokens(1000000), "1.0M", "formatTokens(1000000) = 1.0M");
eq(Format.formatTokens(2500000000), "2.5B", "formatTokens(2500000000) = 2.5B");

// --- formatCost: USD by default, EUR only for French with a rate ---
eq(Format.formatCost(0, "en", 0), "$0.00", "formatCost(0) USD = $0.00");
eq(Format.formatCost(5.5, "en", 0), "$5.50", "formatCost(5.5) USD = $5.50");
eq(Format.formatCost(15.3, "en", 0), "$15.3", "formatCost(15.3) USD = $15.3");
eq(Format.formatCost(150, "en", 0), "$150", "formatCost(150) USD = $150");
eq(Format.formatCost(1500, "en", 0), "$1.5K", "formatCost(1500) USD = $1.5K");
eq(Format.formatCost(10, "fr", 0.92), "9.20 €", "formatCost(10) EUR = 9.20 €");
eq(Format.formatCost(100, "fr", 0.92), "92.0 €", "formatCost(100) EUR = 92.0 € (92 < 100, so toFixed(1))");
eq(Format.formatCost(1500, "fr", 0.92), "1.4K €", "formatCost(1500) EUR = 1.4K €");
eq(Format.formatCost(5, "fr", 0), "$5.00", "a French locale with no rate falls back to USD");

// --- paceInfo: burn against the linear rate for the elapsed Window ---
const NOW = 1757000000000;
const FIVE_H = 5 * 3600000;
const midReset = NOW + FIVE_H / 2; // half the Window has elapsed
eqj(Format.paceInfo(50, midReset, FIVE_H, NOW),
    { timeFrac: 0.5, delta: 0, status: "on" }, "half the Window and half the allowance is on pace");
eqj(Format.paceInfo(60, midReset, FIVE_H, NOW),
    { timeFrac: 0.5, delta: 10, status: "over" }, "ten points past the linear rate is over pace");
eqj(Format.paceInfo(40, midReset, FIVE_H, NOW),
    { timeFrac: 0.5, delta: -10, status: "under" }, "ten points behind the linear rate is under pace");
eqj(Format.paceInfo(55, midReset, FIVE_H, NOW),
    { timeFrac: 0.5, delta: 5, status: "over" }, "a delta of exactly 5 is already over");
eqj(Format.paceInfo(45, midReset, FIVE_H, NOW),
    { timeFrac: 0.5, delta: -5, status: "under" }, "a delta of exactly -5 is still under");
eqj(Format.paceInfo(100, midReset, FIVE_H, NOW),
    { timeFrac: 0.5, delta: 50, status: "over_quota" }, "a full Window is over quota whatever the clock says");
eqj(Format.paceInfo(0, 0, 0, NOW),
    { timeFrac: 0, delta: 0, status: "unknown" }, "no Window data is unknown");
eqj(Format.paceInfo(100, 0, 0, NOW),
    { timeFrac: 1, delta: 100, status: "over_quota" }, "over quota without Window data still says so");
eqj(Format.paceInfo(50, NOW - 60000, FIVE_H, NOW),
    { timeFrac: 1, delta: -50, status: "under" }, "a reset already past clamps the elapsed fraction at 1");
eqj(Format.paceInfo(10, NOW + FIVE_H + 60000, FIVE_H, NOW),
    { timeFrac: 0, delta: 10, status: "over" }, "an unstarted Window clamps the elapsed fraction at 0");

// --- formatCountdown and resetClockLabel ---
eq(Format.formatCountdown(0, "en", NOW), "", "a zero reset is empty");
eq(Format.formatCountdown(NOW - 1000, "en", NOW), "Resetting...", "a past reset is Resetting...");
eq(Format.formatCountdown(NOW - 1000, "fr", NOW), "Réinitialisation...", "a past reset translates");

// The appended clock is the reset instant in local time; the expected label
// goes through the same engine shim, so the assertion is timezone-proof. The
// same-calendar-day check runs against the real wall clock, as production's
// countdowns do.
const subReset = NOW + 139 * 60000;
const subSameDay = Qt.formatDateTime(new Date(subReset), "yyyy-MM-dd")
    === Qt.formatDateTime(new Date(), "yyyy-MM-dd");
eq(Format.formatCountdown(subReset, "en", NOW),
    "2h 19m (" + Qt.formatDateTime(new Date(subReset), subSameDay ? "HH:mm" : "ddd HH:mm") + ")",
    "a sub-24h reset appends the reset instant's local clock");
const multiReset = NOW + 5 * 86400000 + 3 * 3600000;
eq(Format.formatCountdown(multiReset, "en", NOW),
    "5d 3h 00m (" + Qt.formatDateTime(new Date(multiReset), "ddd HH:mm") + ")",
    "a multi-day reset appends the weekday and the clock");

// Anchored to the real clock so the branch taken is the same whatever time or
// timezone the suite runs in: 23:59 today is the same calendar day, +48h is not.
const tonight = new Date();
tonight.setHours(23, 59, 0, 0);
check(/^\([0-9]{2}:[0-9]{2}\)$/.test(Format.resetClockLabel(tonight.getTime()).trim()),
    "a same-calendar-day reset shows the time only");
check(/^\([A-Za-z]{3} [0-9]{2}:[0-9]{2}\)$/.test(Format.resetClockLabel(Date.now() + 48 * 3600000).trim()),
    "another calendar day's reset includes the weekday");

// --- formatWindowLabel ---
eq(Format.formatWindowLabel(0, "Primary Window", "en"), "Primary Window",
    "no length yet falls back to the slot's generic name");
eq(Format.formatWindowLabel(604800, "", "en"), "Weekly Window", "a 7d window is the Weekly Window");
eq(Format.formatWindowLabel(18000, "", "en"), "5h Window", "a 5h window is the 5h Window");
eq(Format.formatWindowLabel(18000, "", "fr"), "Fenêtre de 5 h", "the 5h Window label translates");
eq(Format.formatWindowLabel(604800, "", "fr"), "Fenêtre hebdomadaire", "the Weekly Window label translates");
eq(Format.formatWindowLabel(259200, "", "en"), "3d Window", "259200s reads as a 3d Window");
eq(Format.formatWindowLabel(7200, "", "en"), "2h Window", "7200s reads as a 2h Window");
eq(Format.formatWindowLabel(5400, "", "en"), "2h Window", "hours round to the nearest whole hour");

// --- formatTier ---
eq(Format.formatTier("t3_max_20x_something", "en"), "Max 20x", "formatTier reads max_20x");
eq(Format.formatTier("t2_max_5x_something", "en"), "Max 5x", "formatTier reads max_5x");
eq(Format.formatTier("t1_pro_something", "en"), "Pro", "formatTier reads pro");
eq(Format.formatTier("free_tier", "fr"), "Gratuit", "formatTier free translates to French");
eq(Format.formatTier("team_tier", "es"), "Equipo", "formatTier team translates to Spanish");
eq(Format.formatTier("enterprise_tier", "fr"), "Entreprise", "formatTier enterprise translates to French");
eq(Format.formatTier("unknown", "en"), "", "formatTier hides unknown");
eq(Format.formatTier("custom_plan", "en"), "", "formatTier hides unrecognised tiers");
eq(Format.formatTier("default_claude_ai", "en"), "",
    "formatTier hides Claude Pro's default tier, which names no plan the user bought");

// --- formatSubscription ---
eq(Format.formatSubscription("claude_pro", "unknown", "en"), "Pro", "a known subscription stands alone");
eq(Format.formatSubscription("unknown", "max_5x_x", "en"), "Max 5x", "an unknown subscription falls back to the tier");
eq(Format.formatSubscription("claude_max", "max_20x_y", "en"), "Max · Max 20x", "subscription and tier read together");
eq(Format.formatSubscription("claude_pro", "pro_x", "en"), "Pro", "an identical subscription and tier reads once");
eq(Format.formatSubscription("team", "enterprise_y", "en"), "Team · Enterprise", "a bare subType keeps its own name");
eq(Format.formatSubscription("claude_pro", "free_tier", "fr"), "Pro · Gratuit", "the pairing translates");

// --- paceLabel ---
eq(Format.paceLabel(null, "en"), "", "no pacing reads as empty");
eq(Format.paceLabel({ status: "over_quota" }, "en"), "Over quota", "over quota labels");
eq(Format.paceLabel({ status: "over_quota" }, "fr"), "Quota dépassé", "over quota labels translate");
eq(Format.paceLabel({ status: "over", delta: 10.4 }, "en"), "10% over pace", "over pace rounds its delta");
eq(Format.paceLabel({ status: "over", delta: 10.4 }, "fr"), "10% au-dessus du rythme", "over pace labels translate");
eq(Format.paceLabel({ status: "under", delta: -7.6 }, "en"), "8% under pace", "under pace rounds its delta");
eq(Format.paceLabel({ status: "on" }, "en"), "On pace", "on pace labels");
eq(Format.paceLabel({ status: "unknown" }, "en"), "", "an unknown pace reads as empty");

// --- shortModelName ---
eq(Format.shortModelName("opus"), "Opus", "shortModelName capitalises");
eq(Format.shortModelName("sonnet"), "Sonnet", "shortModelName capitalises sonnet");
eq(Format.shortModelName(""), "", "shortModelName passes the empty string through");
eq(Format.shortModelName(null), null, "shortModelName passes null through");

// --- todayIndex: Monday=0 .. Sunday=6, from an explicit instant ---
eq(Format.todayIndex(Date.UTC(2026, 8, 14)), 0, "Monday 14 Sep 2026 is index 0");
eq(Format.todayIndex(Date.UTC(2026, 8, 15)), 1, "Tuesday 15 Sep 2026 is index 1");
eq(Format.todayIndex(Date.UTC(2026, 8, 18)), 4, "Friday 18 Sep 2026 is index 4");
eq(Format.todayIndex(Date.UTC(2026, 8, 19)), 5, "Saturday 19 Sep 2026 is index 5");
eq(Format.todayIndex(Date.UTC(2026, 8, 13)), 6, "Sunday 13 Sep 2026 is index 6");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < /tmp/format-report.txt

if ! grep -q "^PASS\|^FAIL" /tmp/format-report.txt; then
    fail "format report produced no results (node failed?) see /tmp/format-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
