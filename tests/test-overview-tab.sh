#!/usr/bin/env bash
# Tests for the Overview tab (#40).
#
# The Overview is a tab built by the same machinery as a Source's, so these
# tests pin the three seams that make that true: the non-Source tab entry the
# registry declares (ADR 0003), the rule that decides which tab is showing, and
# the Section that draws the rows it is handed.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping Overview tab tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Extracting the Overview tab contract ==="

node - "$SCRIPT_DIR" >/tmp/overview-tab-report.txt 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const root = process.argv[2];

const load = (file, suffix) => {
    const source = fs.readFileSync(path.join(root, file), "utf8").replace(/^\.pragma library\s*/, "");
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source + suffix, sandbox, { filename: file });
    return sandbox;
};

const reg = load("sources.js", "; this.api = { SOURCES, byId, ids, overviewRow, overviewRows, OVERVIEW_TAB };").api;
const tr = load("translations.js", "; this.strings = strings;").strings;

const widget = fs.readFileSync(path.join(root, "AiUsageWidget.qml"), "utf8");
const tab = fs.readFileSync(path.join(root, "ui/SourceTab.qml"), "utf8");
const section = fs.readFileSync(path.join(root, "ui/OverviewSection.qml"), "utf8");
// Comments name the registry on purpose; only real code decides whether the
// Section reaches for it.
const sectionCode = section.split("\n").filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line)).join("\n");

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// --- The non-Source tab entry ---
// The Overview has no provider, nothing to fetch and no credentials, so it is
// not a Source; it is still a tab entry, so the strip and the Section list are
// generated from the registry rather than from a second, hand-written path.
const entry = reg.OVERVIEW_TAB;
check(!!entry, "sources.js declares the Overview's tab entry");
check(!!entry && entry.id === "overview", "the Overview's tab id is \"overview\"");
check(!!entry && reg.byId(entry.id) === null && reg.ids().indexOf(entry.id) < 0,
      "the Overview is not a Source in the registry");
check(!!entry && tr[entry.labelKey] !== undefined, "the Overview's tab label is translated");
check(!!entry && Array.isArray(entry.sections) && entry.sections.length > 0,
      "the Overview's tab entry declares Sections");
check(!!entry && !entry.script && !entry.windows && !entry.accounts,
      "the Overview's tab entry claims no provider, no fetch and no credentials");

// A Section type no renderer implements would come up blank, which is what the
// Source descriptors are checked for too.
const implemented = new Set();
for (const m of tab.matchAll(/case "([a-z]+)":/g))
    implemented.add(m[1]);
for (const s of (entry && entry.sections) || [])
    check(implemented.has(s.type), `the Overview's "${s.type}" Section is implemented by SourceTab`);
check(/OverviewSection\s*\{\}/.test(tab), "SourceTab's \"overview\" case renders OverviewSection");

// --- The rule that decides which tab is showing ---
// Extracted from the widget itself rather than copied here, so the rule cannot
// drift from the code that runs.
function extract(name) {
    const m = widget.match(new RegExp("function " + name + "\\([^\\n]*\\)[\\s\\S]*?\\n    \\}"));
    if (!m)
        throw new Error("could not extract " + name);
    return m[0];
}
const tabs = [{ id: "claude" }, { id: "chatgpt" }];
const sandbox = { Sources: reg, console };
vm.createContext(sandbox);
vm.runInContext(extract("resolveTabId") + "\n" + extract("popoutTabsFor"), sandbox, { filename: "popout-tabs" });

check(sandbox.resolveTabId("", [entry.id, "claude"]) === entry.id,
      "the popout opens on the Overview when the user has picked nothing");
check(sandbox.resolveTabId("claude", [entry.id, "claude"]) === "claude",
      "a tab the user picked stays selected");
check(sandbox.resolveTabId(entry.id, ["claude"]) === "claude",
      "with the Overview absent the selection falls back to the first visible Source");
check(sandbox.resolveTabId("ghost", [entry.id, "claude"]) === entry.id,
      "an id no longer on the strip falls back to the first tab");
check(sandbox.resolveTabId("", []) === "", "no tabs at all selects nothing");
check(sandbox.popoutTabsFor(true, tabs).map((t) => t.id).join(",") === "overview,claude,chatgpt",
      "the Overview leads the strip");
check(sandbox.popoutTabsFor(true, tabs)[0] === reg.OVERVIEW_TAB,
      "the leading tab is the registry's Overview entry");
check(sandbox.popoutTabsFor(false, tabs).map((t) => t.id).join(",") === "claude,chatgpt",
      "with the Overview absent the strip is the visible Sources alone");

// The floor: an Overview's toggle alone is not enough, it also needs rows to
// rank, which is what makes it absent below two visible Sources.
const shownBinding = widget.match(/property bool overviewShown:\s*([^\n]+)/);
check(!!shownBinding, "the widget declares overviewShown");
if (shownBinding) {
    const resolve = new Function("root", "return (" + shownBinding[1].trim() + ");");
    check(resolve({ overviewEnabled: true, overviewRows: [{}, {}] }) === true,
          "the Overview is on when its toggle is on and there are rows to rank");
    check(resolve({ overviewEnabled: false, overviewRows: [{}, {}] }) === false,
          "the Overview's own toggle hides it");
    check(resolve({ overviewEnabled: true, overviewRows: [] }) === false,
          "the Overview is absent when there is nothing to rank");
}
check(/overviewStates: root\.visibleDescriptors\.map/.test(widget),
      "the Overview ranks the visible Sources in settings order");
check(/overviewRows: Sources\.overviewRows\(root\.overviewStates\)/.test(widget),
      "the rows come from the registry's ranking, which holds the two-Source floor");

// --- The widget renders the strip and the body from that one list ---
check(widget.indexOf('"overview"') < 0,
      "the widget hardcodes no Overview id; it comes from the registry");
check(/model: root\.popoutTabs/.test(widget), "the tab strip is generated from the popout's tab list");
check(/color: root\.activeTabId === modelData\.id/.test(widget), "the strip marks the selected tab");
check(/onClicked: root\.popoutTabId = modelData\.id/.test(widget), "a press on a strip entry selects it");
check(/tab: root\.activeTab/.test(widget), "the body renders the selected tab entry, Overview included");
check(/ctx: root\.activeTab \? root\.contextFor\(root\.activeTab\.id\) : null/.test(widget),
      "the body builds the selected tab's context");
const overviewContext = widget.match(/if \(id === Sources\.OVERVIEW_TAB\.id\) \{([\s\S]*?)\n        \}/);
check(!!overviewContext && /rows: root\.overviewRows/.test(overviewContext[1]),
      "the Overview's context is the ranking rather than a Source's state");
// CONTEXT.md keeps Descriptor meaning "a Source's entry in the registry", so the
// Overview must not travel under that name.
check(!!overviewContext && overviewContext[1].indexOf("descriptor") < 0,
      "the Overview's context is not handed over as a Descriptor");
check(/property var tab: null/.test(tab) && tab.indexOf("property var descriptor") < 0,
      "the tab renderer takes a tab entry, not a Descriptor");
check(/popoutWidth: 380/.test(widget) && /popoutHeight: 740/.test(widget),
      "the popout stays 380 x 740");
check(widget.indexOf("popoutSourceTab") < 0, "no stale Source-only tab property is left behind");

// --- The row data the Overview draws ---
// A row carries everything the tab needs, so the degradations the Source tab
// renders differently can be drawn by a repeater that knows no descriptors.
const fixture = (id, over) => Object.assign({
    id,
    credsStatus: "ok",
    hasData: true,
    primary: { util: 10, resetMs: 1000, windowSeconds: 18000 },
    secondary: { util: 5, resetMs: 2000, windowSeconds: 604800 }
}, over || {});

const cliRow = reg.overviewRow(fixture("claude"));
check(cliRow.loginKind === "cli" && cliRow.loginBodyKey === null,
      "a CLI Source's row carries the login card's button");
const textRow = reg.overviewRow(fixture("zai"));
check(textRow.loginKind === "text", "a key-based Source's row declares a text login");
check(textRow.loginBodyKey && tr[textRow.loginBodyKey] !== undefined,
      "a key-based row's login copy is translated");
check(reg.overviewRow(fixture("zai", { credsStatus: "missing" })).missing === true &&
      reg.overviewRow(fixture("zai", { credsStatus: "missing" })).ranked === false,
      "a Missing row is unranked, so it draws the sign-in affordance instead of a bar");
check(reg.overviewRow(fixture("opencode", { credsStatus: "unavailable" })).stale === true,
      "an Unavailable row keeps a reading to draw dimmed and marked stale");

// --- The Section that draws them ---
check(/model: root\.rows/.test(section), "the Overview is a repeater over the rows it is handed");
check(/ctx\.rows/.test(section), "the Overview's rows come from its context");
check(sectionCode.indexOf("Sources.") < 0, "the Overview Section reads no registry: it draws, it does not rank");
check(/modelData\.loginKind === "cli"/.test(section) && /api\.startLogin\(/.test(section),
      "a Missing CLI row offers the login card's button");
check(/modelData\.loginBodyKey/.test(section),
      "a Missing key-based row offers the login card's pointer instead");
check(/api\.tr\("stale"\)/.test(section), "an Unavailable row is marked stale");
check(/visible: !row\.missing/.test(section),
      "a Missing row draws no bar: its sign-in takes the bar's place");
check(/modelData\.stale \? 0\.5 : 1/.test(section), "an Unavailable row's bar is dimmed");
check(/api\.selectTab\(row\.sourceId\)/.test(section), "a press on a row switches to that Source's tab");
check(/api\.tr\("Resets in"\)/.test(section) && /windowLabelForLength/.test(section),
      "a row names its Tightest Window and when it resets");
check(/api\.progressColor\(modelData\.util\)/.test(section),
      "the row's bar and percentage use the Ring's colour rule");
check(/Math\.round\(modelData\.util\) \+ "%"/.test(section), "a row shows its Utilisation as a percentage");
check(/showsReading: modelData\.ranked/.test(section) && /visible: row\.showsReading/.test(section),
      "an unranked row shows no percentage, no reset line and no bar value");
check(/Theme\.surfaceVariant/.test(section), "the bar draws a track behind the fill");

// The marker is read from a Section, which the translation test does not scan,
// so its three locales are pinned here.
check(tr["stale"] !== undefined && tr["stale"].fr && tr["stale"].es,
      "the stale marker is translated");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then
        pass "$label"
    else
        fail "$label"
    fi
done < /tmp/overview-tab-report.txt

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "Overview tab report produced no results (node failed?) see /tmp/overview-tab-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
