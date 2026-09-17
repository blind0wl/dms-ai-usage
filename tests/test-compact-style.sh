#!/usr/bin/env bash
# Tests for the Sections' compact spacing and type scale (#43).
#
# The Popout keeps its 380 x 740 panel, so the room the Overview tab needs comes
# from tightening every Section rather than from growing the panel. The scale is
# two sizes: Theme.spacingS for an inset and for the gap between two Sections,
# Theme.spacingXS (and Theme.spacingXXS between a label and its value) inside one.
# Type stops at Theme.fontSizeSmall apart from the Window card's own hero number.
# DMS's file-browser sidebar is the precedent: Theme.spacingS insets,
# Theme.spacingXS between its rows, and a fontSizeSmall header at Font.Medium.
#
# Every value is read from the components themselves, so a component that drifts
# back to the roomier scale fails here instead of quietly eating the panel's room
# again.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping compact-style tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Compact style report ==="

STYLE_REPORT=/tmp/compact-style-report.txt
node - "$SCRIPT_DIR" > "$STYLE_REPORT" 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");

const root = process.argv[2];
const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// Every component in ui/, so a Section cannot be left on the old scale.
const names = fs.readdirSync(path.join(root, "ui")).filter((name) => name.endsWith(".qml")).sort();
const sources = {};
for (const name of names)
    sources[name] = fs.readFileSync(path.join(root, "ui", name), "utf8");

// --- The scale itself ---
// One step down from the roomier scale: an inset or a gap is S, XS or XXS, and
// nothing in a Section is spaced with the steps above them.
const ROOMY = ["Theme.spacingM", "Theme.spacingL", "Theme.spacingXL"];
for (const name of names) {
    const found = ROOMY.filter((token) => sources[name].includes(token));
    check(found.length === 0,
          `ui/${name} spaces nothing with the roomier scale${found.length ? ` (${found.join(", ")})` : ""}`);
}

// Type is a token, never a raw pixel size, and the only size above the compact
// header is the Window card's own Utilisation number.
for (const name of names) {
    const raw = sources[name].match(/font\.pixelSize:\s*[0-9]/g) || [];
    check(raw.length === 0, `ui/${name} sizes no type with a raw pixel number`);
    check(!sources[name].includes("Theme.fontSizeXLarge"), `ui/${name} keeps no type above fontSizeLarge`);
}
const large = names.filter((name) => sources[name].includes("Theme.fontSizeLarge"));
check(large.length === 1 && large[0] === "WindowsSection.qml",
      "fontSizeLarge is the Window card's Utilisation number and nothing else");

// A card is inset by S, or by XS around a ring that brings its own room.
for (const name of names) {
    const margins = sources[name].match(/anchors\.margins:\s*Theme\.spacing\w+/g) || [];
    const off = margins.filter((line) => !/Theme\.spacing(S|XS)$/.test(line));
    check(off.length === 0, `ui/${name} insets its content by the compact scale only`);
}

// --- The two things that make a card tall carry a compact size ---
const windows = sources["WindowsSection.qml"];
const chart = sources["ChartSection.qml"];
check(/width:\s*root\.compact \? 56 : 84/.test(windows),
      "the Window card's Ring is the compact 56/84 rather than 72/100");
check(/height:\s*56/.test(chart), "the activity chart's plot area is the compact 56 rather than 70");

// --- The rhythm of a tab ---
const tab = sources["SourceTab.qml"];
check(/spacing:\s*Theme\.spacingS/.test(tab), "Sections are spaced by Theme.spacingS, not Theme.spacingL");
check(/model: root\.tab \? root\.tab\.sections : \[\]/.test(tab),
      "the Section list is still what SourceTab renders");
const overview = sources["OverviewSection.qml"];
check(/spacing:\s*Theme\.spacingXS/.test(overview), "Overview rows are spaced by Theme.spacingXS");

// --- The Popout body adds the host's own inset, not a second wider one ---
const widget = fs.readFileSync(path.join(root, "AiUsageWidget.qml"), "utf8");
const body = widget.match(/popoutContent: Component \{[\s\S]*?\n    \}/);
check(!!body, "the widget still declares popoutContent");
if (body) {
    check(/width:\s*parent\.width - Theme\.spacingS \* 2/.test(body[0]),
          "the popout body insets its content by Theme.spacingS");
    check(/spacing:\s*Theme\.spacingS/.test(body[0]), "the popout body's own rhythm is Theme.spacingS");
    check(!body[0].includes("Theme.spacingM"), "the popout body adds no wider inset on top of the host's");
}

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then
        pass "$label"
    else
        fail "$label"
    fi
done < "$STYLE_REPORT"

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "compact-style report produced no results (node failed?) see $STYLE_REPORT"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
