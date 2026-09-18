#!/usr/bin/env bash
# Tests for the Source tab's own layout and Brand Colour (#51).
#
# Before this the Source tab was upstream's card stack: a big ring card, a small
# ring card, Token Consumption, Daily Activity, Models This Week and an all-time
# footer. These tests pin the layout that replaces it and the Brand Colour that
# marks each Source, so a later change cannot quietly restore upstream's shape.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping Source tab layout tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== The Source tab's layout contract ==="

node - "$SCRIPT_DIR" >/tmp/source-tab-layout-report.txt 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const root = process.argv[2];

const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const ui = (name) => read(`ui/${name}.qml`);
const widget = read("AiUsageWidget.qml");
const tab = ui("SourceTab");
const sourcesSource = read("sources.js");

const sandbox = { console };
vm.createContext(sandbox);
vm.runInContext(sourcesSource.replace(/^\.pragma library\s*/, "") + "; this.api = { SOURCES, byId };", sandbox, { filename: "sources.js" });
const sources = sandbox.api.SOURCES;
const byId = (id) => sources.find((s) => s.id === id);

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// --- The header: Brand Colour dot, name, plan chip ---
const header = ui("HeaderSection");
check(/color:\s*root\.brandColor/.test(header), "the header draws the Brand Colour dot");
check(/border\.color:\s*root\.brandColor/.test(header), "the plan chip is outlined in the Brand Colour");
check(/ctx\.descriptor\.planStyle/.test(header), "the header still reads the plan style from the descriptor");
check(!/api\.tr\("Plan"\)/.test(header) && !/api\.tr\("Subscription"\)/.test(header),
      "the plan chip shows the plan itself, not a Plan:/Subscription: prefix");

// --- The Windows card: both Windows as bar rows, no Ring ---
const windows = ui("WindowsSection");
check(/model:\s*\["primary",\s*"secondary"\]/.test(windows),
      "one card holds both Windows");
check(!/\bRing\s*\{/.test(windows), "the Windows card draws bars, not rings");
check(/api\.utilisationColor\(/.test(windows), "the Windows bars and percentages wear the Brand Colour");
check(/timeFrac/.test(windows), "each Window bar carries a pace tick at the linear-burn position");
check(/section\.counts === true/.test(windows) && /modelData !== "secondary"/.test(windows),
      "the week's counts ride on the secondary row only");
check(/root\.api\.tr\("Resets in"\)/.test(windows), "each Window row names its reset countdown");

// --- The Token Consumption card: figures plus the all-time line ---
const stats = ui("StatsSection");
check(/api\.tr\("Token Consumption"\)/.test(stats), "the Token Consumption card keeps its title");
check(/font\.pixelSize:\s*modelData\.text \? Theme\.fontSizeMedium : Theme\.fontSizeLarge/.test(stats),
      "the period figures read as a large value over a small label");
check(/Since/.test(stats) && /sessions/.test(stats) && /msgs/.test(stats),
      "the all-time line rides at the foot of the Token Consumption card");

// The card is gone: no component, no Section type, no descriptor entry.
check(!fs.existsSync(path.join(root, "ui/AlltimeSection.qml")), "AlltimeSection is gone");
check(!/case "alltime"/.test(tab), "SourceTab implements no alltime Section");
check(!/type:\s*"alltime"/.test(sourcesSource), "no descriptor lists an alltime Section");

// --- The chart and the model bars wear the Brand Colour, muted titles ---
for (const name of ["ChartSection", "ModelsSection"]) {
    const section = ui(name);
    check(/readonly property color brandColor: ctx && ctx\.brandColor/.test(section),
          `${name} takes the Source's Brand Colour`);
    check(/color:\s*Theme\.surfaceVariantText/.test(section),
          `${name} titles itself in the muted style the cards share`);
}
check(/color:\s*root\.brandColor/.test(ui("ChartSection")), "the activity bars are drawn in the Brand Colour");
check(/color:\s*root\.brandColor/.test(ui("ModelsSection")), "the model bars are drawn in the Brand Colour");

// --- The Brand Colour is descriptor data, not per-Source code (ADR 0001) ---
const brands = { claude: "#D97757", chatgpt: "#10A37F", zai: "#4F7CFF", opencode: "#A78BFA" };
for (const [id, hex] of Object.entries(brands)) {
    const d = byId(id);
    check(!!d && d.brandColor === hex, `descriptor "${id}" declares its Brand Colour ${hex}`);
}
check(sources.every((d) => typeof d.brandColor === "string" && /^#[0-9A-F]{6}$/.test(d.brandColor)),
      "every descriptor declares a fixed hex Brand Colour");
check(/function brandColor\(id\)[\s\S]*?Sources\.byId\(id\)/.test(widget),
      "the widget reads the Brand Colour from the descriptor");
check(/hasBrandColor\(modelData\.id\)/.test(widget) && /brandColor\(modelData\.id\)/.test(widget),
      "the active tab chip wears the Source's Brand Colour");
check(/utilisationColor\(modelData\.id, modelData\.util\)/.test(ui("OverviewSection")),
      "the Overview bar reads the Brand Colour through utilisationColor");

// --- The Pill is untouched: its colour rule stays the theme's ---
check(/function progressColor\(pct\)/.test(widget) && /return root\.progressColor\(pct\)/.test(widget),
      "the widget keeps progressColor for the Pill");
check(!/brandColor/.test(ui("Ring")), "the Ring draws the theme's colours, not the Brand Colour");

// --- opencode Go is Windows-only, so its tab is header plus the Windows card ---
const opencode = byId("opencode");
const types = opencode.sections.map((s) => s.type);
check(types.indexOf("stats") < 0 && types.indexOf("chart") < 0 && types.indexOf("models") < 0,
      "opencode Go's tab carries no stats, chart or models Section");
check(types.indexOf("windows") >= 0 && types.indexOf("header") >= 0,
      "opencode Go's tab is the header and the Windows card");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then
        pass "$label"
    else
        fail "$label"
    fi
done < /tmp/source-tab-layout-report.txt

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "source-tab-layout report produced no results (node failed?) see /tmp/source-tab-layout-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
