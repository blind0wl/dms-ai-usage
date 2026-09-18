#!/usr/bin/env bash
# Tests for the Source picker in the settings Accounts area (#48).
#
# The page used to stack one AccountsEditor per Source, so four Sources meant
# four Custom blocks and four Detected blocks on one page. It now shows one
# Source at a time, chosen from a dropdown. These tests pin the three seams that
# make that true: the picker's model is the Sources that have Accounts, the
# editor is handed only the chosen descriptor, and the choice is a view of the
# page rather than a stored setting.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping Accounts picker tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Extracting the Accounts picker contract ==="

node - "$SCRIPT_DIR" >/tmp/accounts-picker-report.txt 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const root = process.argv[2];

const settings = fs.readFileSync(path.join(root, "AiUsageSettings.qml"), "utf8");

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// One editor, not one per Source: the whole point of the change is that the
// page stops growing with the number of Sources that have Accounts.
const editors = settings.match(/AccountsEditor\s*\{/g) || [];
check(editors.length === 1,
      "the accounts area instantiates one AccountsEditor rather than one per Source");

// The picker is a dropdown labelled Source, listing exactly the Sources that
// carry an accounts descriptor. Its menu reads the same list the page derived.
const picker = settings.slice(settings.indexOf("id: sourceDropdown"));
check(/text:\s*root\.tr\("Source"\)/.test(picker),
      "the picker is labelled Source");
check(/model:\s*root\.accountDescriptors/.test(picker),
      "the picker lists the Sources that have Accounts");
check(/root\.selectedSourceId = modelData\.id/.test(picker),
      "picking a row sets the chosen Source");
check(/id:\s*sourceDropdownPopup/.test(picker),
      "the picker's menu is a popup, so the page shows one selection at a time");

// The chosen Source is not persisted: an unset choice falls back to the first
// Source that has Accounts, and nothing writes the choice to the store.
check(/property string selectedSourceId:\s*""/.test(settings),
      "the chosen Source starts unset rather than stored");
check(!/saveValue\([^)]*selectedSourceId/.test(settings),
      "the chosen Source is not written to settings");
check(/selectedAccountDescriptor:\s*resolveAccountDescriptor\(selectedSourceId\)/.test(settings),
      "the editor's descriptor is resolved from the chosen Source");

// The fallback itself, run rather than pattern-matched: an unknown or unset id
// takes the first descriptor, and an empty registry yields nothing to show.
const fnMatch = settings.match(/function resolveAccountDescriptor\(id\)\s*\{[\s\S]*?\n    \}/);
check(!!fnMatch, "the page resolves a descriptor from an id");
if (fnMatch) {
    const make = (descs) => new Function("root", "return " + fnMatch[0])({ accountDescriptors: descs });
    const descs = [{ id: "claude" }, { id: "chatgpt" }, { id: "zai" }];
    check(make(descs)("zai") === descs[2], "a chosen id resolves to its own descriptor");
    check(make(descs)("") === descs[0], "an unset choice falls back to the first Source");
    check(make(descs)("nope") === descs[0], "an unknown id falls back to the first Source");
    check(make([])("anything") === null, "a page with no Accounts yields no descriptor");
}

// The editor is rebuilt when the choice changes, so a row or listing from the
// previous Source cannot linger in the next one.
check(/model:\s*root\.selectedAccountDescriptor\s*\?\s*\[root\.selectedAccountDescriptor\]\s*:\s*\[\]/.test(settings),
      "the editor is rebuilt for the chosen Source rather than reused across Sources");
check(/descriptor:\s*modelData/.test(settings),
      "the editor is handed the chosen descriptor");

// The heading the picker sits under, and the section break above it, are the
// only structure the page adds around the unchanged editor.
check(/text:\s*root\.tr\("Accounts"\)/.test(settings),
      "the accounts area is headed Accounts");
check(/id:\s*accountsSetting/.test(settings),
      "the accounts area is its own Column");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then
        pass "$label"
    else
        fail "$label"
    fi
done < /tmp/accounts-picker-report.txt

if ! grep -q "^PASS\|^FAIL" /tmp/accounts-picker-report.txt; then
    fail "accounts-picker report produced no results (node failed?) see /tmp/accounts-picker-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
