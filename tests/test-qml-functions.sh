#!/usr/bin/env bash
# Tests for the widget's own orchestration, extracted from AiUsageWidget.qml
# and run against the real registry: the Account adapter, the login commands,
# the refetch scheduling, the Overview toggle and the fetch set. The pure
# formatters are format.js's and have their own file: tests/test-format.sh.
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

# ============================================================
echo "=== Test 1: descriptor-declared Accounts, login and Account keys ==="
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
echo "=== Test 2: the Overview toggle is its own setting ==="
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
echo "=== Test 3: the fetch set is every enabled Source ==="
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
