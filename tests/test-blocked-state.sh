#!/usr/bin/env bash
# Tests for the Blocked Source state (#58, ADR 0005).
#
# A Source whose Script could not read past a missing or failing Requirement is
# Blocked. It stays in the Pill with a hollow ring, its Overview row draws `--`
# and names the commands, its tab carries a card naming them with no login
# affordance and no settings pointer, and the settings Accounts editor shows the
# notice instead of an empty Account list. These tests pin the registry's Blocked
# row shape and the four surfaces that draw it.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping Blocked state tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Extracting the Blocked state contract ==="

node - "$SCRIPT_DIR" >/tmp/blocked-state-report.txt 2>&1 <<'NODE' || true
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

const reg = load("sources.js", "; this.api = { SOURCES, byId, overviewRow, overviewRows, hasReading, nextNotInstalledCount, isHidden, STATUS_KEY, NOT_INSTALLED, BLOCKING_REQUIREMENT, BLOCKED };").api;

const widget = fs.readFileSync(path.join(root, "AiUsageWidget.qml"), "utf8");
const status = fs.readFileSync(path.join(root, "ui/StatusSection.qml"), "utf8");
const overview = fs.readFileSync(path.join(root, "ui/OverviewSection.qml"), "utf8");
const editor = fs.readFileSync(path.join(root, "ui/AccountsEditor.qml"), "utf8");

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// --- The registry's wire contract ---
check(reg.STATUS_KEY === "CREDS_STATUS", "the credential status key is still CREDS_STATUS");
check(typeof reg.BLOCKING_REQUIREMENT === "string" && reg.BLOCKING_REQUIREMENT.length > 0 &&
      reg.BLOCKING_REQUIREMENT !== reg.STATUS_KEY,
      "the Requirement key is a Source-level key beside CREDS_STATUS");
check(reg.BLOCKED === "blocked", "the Blocked state's value is \"blocked\"");

// A Blocked report resets the consecutive Not installed count, which is what
// keeps a Source from being hidden by the state that replaced its Not installed
// reports (ADR 0004, ADR 0005).
check(reg.nextNotInstalledCount(5, reg.BLOCKED) === 0,
      "a Blocked report resets the consecutive Not installed count");

// The shared reading rule: a Blocked Source with no last-good reading has
// nothing to draw, and the Window card drops rather than fabricating a zero.
check(reg.hasReading({ credsStatus: reg.BLOCKED, hasData: false }) === false,
      "a Blocked Source with no reading has nothing to draw");
check(reg.hasReading({ credsStatus: reg.BLOCKED, hasData: true }) === true,
      "a Blocked Source keeps a last-good reading for the Window card, as Unavailable does");

// --- The Overview row shape ---
const fixture = (id, over) => Object.assign({
    id,
    credsStatus: "ok",
    hasData: true,
    primary: { util: 10, resetMs: 1000, windowSeconds: 18000 },
    secondary: { util: 5, resetMs: 2000, windowSeconds: 604800 }
}, over || {});

const blockedRow = reg.overviewRow(fixture("claude", { credsStatus: reg.BLOCKED, blockingRequirement: "jq,curl" }));
check(!!blockedRow && blockedRow.blocked === true, "a Blocked row carries the blocked flag");
check(!!blockedRow && blockedRow.ranked === false,
      "a Blocked row is unranked, so the Overview draws `--` rather than a Utilisation");
check(!!blockedRow && blockedRow.missing === false && blockedRow.unavailable === false,
      "Blocked is its own state, not Missing and not Unavailable");
check(!!blockedRow && blockedRow.degraded === true, "a Blocked row is one of the degraded rows");
check(!!blockedRow && blockedRow.requirements.join(",") === "jq,curl",
      "a Blocked row names every command the Script reported, in the report's order");
check(reg.overviewRow(fixture("zai")).requirements.length === 0,
      "no row other than a Blocked one carries a command list");
check(reg.overviewRow(fixture("claude", { credsStatus: reg.BLOCKED, blockingRequirement: "jq", hidden: true })) === null,
      "a hidden Blocked Source yields no row");

const ranked = reg.overviewRows([
    fixture("claude", { credsStatus: reg.BLOCKED, blockingRequirement: "jq" }),
    fixture("zai")
]);
check(ranked.length === 2 && ranked[0].id === "zai" && ranked[1].id === "claude",
      "a Blocked Source follows a Source that holds a reading, so it cannot outrank one");

// --- The widget: routing the report into state ---
check(/case "BLOCKING_REQUIREMENT":/.test(widget) && /st\.blockingRequirement = val;/.test(widget),
      "the widget routes BLOCKING_REQUIREMENT to a state field the way it routes CREDS_STATUS");
check(/blockingRequirement: ""/.test(widget), "the empty state starts with no command list");
check(/if \(val !== Sources\.BLOCKED\)\s*\n\s*st\.blockingRequirement = "";/.test(widget),
      "any report other than Blocked clears the command list a previous one left");

// The Pill's own reading predicate, run rather than pattern-matched. The rule is
// narrower than the registry's: it asks whether the reading is current, so a
// Blocked Source draws a hollow ring even when the tab keeps a last-good value.
function extract(name) {
    const m = widget.match(new RegExp("function " + name + "\\([^\\n]*\\)[\\s\\S]*?\\n    \\}"));
    if (!m)
        throw new Error("could not extract " + name);
    return m[0];
}

const pill = { Sources: reg, console, root: { sourceData: {} } };
vm.createContext(pill);
vm.runInContext(extract("pillHasReading"), pill, { filename: "pillHasReading" });
const ringFor = (statusValue, hasData) => {
    pill.root.sourceData = { s: { credsStatus: statusValue, hasData: hasData === true } };
    return pill.pillHasReading("s");
};
check(ringFor(reg.BLOCKED) === false, "a Blocked Source draws a hollow ring");
check(ringFor(reg.BLOCKED, true) === false, "a Blocked Source draws a hollow ring even with a last-good reading kept");
check(ringFor("ok") === true, "a Source with a good reading still draws its ring");

// applyCredsStatus, run for real: a Blocked report lands as the status, and a
// restored Source comes back with no stale command list.
const creds = { Sources: reg, console };
vm.createContext(creds);
vm.runInContext(extract("applyCredsStatus"), creds, { filename: "applyCredsStatus" });
const blockedState = { credsStatus: "ok", blockingRequirement: "" };
creds.applyCredsStatus(blockedState, reg.BLOCKED);
check(blockedState.credsStatus === reg.BLOCKED, "a Blocked report lands as the Source's status");
check(blockedState.notInstalledCount === 0, "a Blocked report resets the consecutive Not installed count");
blockedState.blockingRequirement = "jq";
creds.applyCredsStatus(blockedState, "ok");
check(blockedState.credsStatus === "ok" && blockedState.blockingRequirement === "" && blockedState.hasData === true,
      "a restored Source returns with no stale command list and its reading back");

// --- The status card ---
check(/readonly property bool blocked: source && source\.credsStatus === "blocked"/.test(status),
      "the status card knows the Blocked state");
check(/readonly property bool shown: blocked \|\| unavailable/.test(status),
      "one status component shows for Blocked or Unavailable");
check(/api\.tr\("Blocked by a requirement"\)/.test(status), "the Blocked card titles itself without naming settings");
check(/Sources\.splitList\(source\.blockingRequirement\)/.test(status),
      "the Blocked card names the commands from the Script's report");
check(!/SetupGuideLink/.test(status), "the Blocked card offers no Setup guide link");
check(!/startLogin|LoginButton/.test(status), "the Blocked card offers no login affordance");

// The card says which state it is in, and never sends a Blocked Source to
// settings: no plugin setting supplies a Requirement.
check(/if \(!status\)\s*\n\s*return "";/.test(status), "the Unavailable copy still comes from the descriptor");
check(/if \(blocked\)\s*\n\s*return api\.tr\("Blocked by a requirement"\);/.test(status),
      "the Blocked title is chosen before the descriptor's Unavailable copy");

// --- The Overview row ---
check(/function blockedLine\(row\)/.test(overview) && /row\.requirements\.join/.test(overview),
      "the Overview draws a line naming a Blocked row's commands");
check(/visible: row\.blocked/.test(overview), "that line shows on a Blocked row");
check(/visible: !row\.missing && !row\.blocked/.test(overview),
      "a Blocked row draws no bar, because no credential was read");
check(/showsReading: modelData\.ranked/.test(overview),
      "a Blocked row keeps the unranked row's `--` percentage");

// --- The settings Accounts editor ---
check(/pair\.value === Sources\.BLOCKED/.test(editor), "the editor reads the Blocked status from the listing");
check(/pair\.key === Sources\.BLOCKING_REQUIREMENT/.test(editor), "the editor reads the Requirement list from the listing");
check(/readonly property string blockedCommands: Sources\.splitList\(root\.blockingRequirement\)\.join/.test(editor),
      "the editor turns the report's list into the commands it names");
check(/visible: root\.blocked/.test(editor) && /root\.blockedCommands/.test(editor),
      "the editor shows a notice naming the commands when the Script is Blocked");
check(/visible: !root\.blocked/.test(editor), "the editor hides its rows when the Script is Blocked");

// --- Every Source can be Blocked, so every tab declares the card ---
for (const d of reg.SOURCES) {
    const hasStatusSection = d.sections.some((s) => s.type === "status");
    check(hasStatusSection, `descriptor "${d.id}" declares a status Section so a Blocked Source shows its card`);
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
done < /tmp/blocked-state-report.txt

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "blocked-state report produced no results (node failed?) see /tmp/blocked-state-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
