#!/usr/bin/env bash
# Tests for the Source registry contract.
#
# Sources are data, so the descriptor shape is the interface between the
# registry and the widget. These tests pin that interface: every descriptor is
# complete, every Section type is one the renderer implements, every state key a
# Section reads exists, and the settings list rules hold.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping registry tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Extracting registry and renderer contracts ==="

node - "$SCRIPT_DIR" >/tmp/registry-report.txt 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const root = process.argv[2];

const load = (file, suffix) => {
    const source = fs.readFileSync(path.join(root, file), "utf8").replace(/^\.pragma library\s*/, "");
    const sandbox = {};
    vm.createContext(sandbox);
    vm.runInContext(source + suffix, sandbox, { filename: file });
    return sandbox;
};

const reg = load("sources.js", "; this.api = { SOURCES, byId, ids, reconcileList, resolveList };").api;
const tr = load("translations.js", "; this.strings = strings;").strings;

const widget = fs.readFileSync(path.join(root, "ClaudeCodeUsageWidget.qml"), "utf8");
const tab = fs.readFileSync(path.join(root, "ui/SourceTab.qml"), "utf8");

// State keys the widget produces: declared in emptyState(), or derived onto the
// state object in stateFor() and its helpers.
const stateKeys = new Set();
for (const m of widget.matchAll(/\bst\.([A-Za-z_][A-Za-z0-9_]*)\s*=/g))
    stateKeys.add(m[1]);
for (const m of widget.matchAll(/\bout\.([A-Za-z_][A-Za-z0-9_]*)\s*=/g))
    stateKeys.add(m[1]);
const stateBlock = widget.match(/function emptyState\(\)\s*\{\s*return \{([\s\S]*?)\n        \};/);
if (stateBlock) {
    for (const m of stateBlock[1].matchAll(/^\s*([A-Za-z_][A-Za-z0-9_]*):/gm))
        stateKeys.add(m[1]);
}
stateKeys.add("primary");
stateKeys.add("secondary");

// Section types SourceTab can render.
const implemented = new Set();
for (const m of tab.matchAll(/case "([a-z]+)":/g))
    implemented.add(m[1]);

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// --- Descriptor completeness ---
for (const d of reg.SOURCES) {
    const tag = `descriptor "${d.id}"`;
    check(typeof d.id === "string" && d.id.length > 0, `${tag} has an id`);
    check(typeof d.labelKey === "string" && d.labelKey.length > 0, `${tag} has a labelKey`);
    check(typeof d.script === "string" && d.script.length > 0, `${tag} has a script`);
    check(tr[d.labelKey] !== undefined, `${tag} labelKey "${d.labelKey}" is translated`);
    check(fs.existsSync(path.join(root, d.script)), `${tag} script ${d.script} exists`);

    check(d.windows !== undefined, `${tag} declares windows`);
    for (const which of ["primary", "secondary"]) {
        const w = d.windows && d.windows[which];
        check(w !== undefined, `${tag} declares a ${which} window`);
        if (!w) continue;
        check(typeof w.util === "string" && w.util.length > 0, `${tag} ${which} names a util key`);
        check(typeof w.reset === "string" && w.reset.length > 0, `${tag} ${which} names a reset key`);
        const hasLength = typeof w.windowSeconds === "number" || typeof w.windowSecondsKey === "string";
        check(hasLength, `${tag} ${which} declares a window length or the key for one`);
        // The Account-scoped form of the same slot. A Source's per-Account
        // Window keys are descriptor data, not shared with Claude's naming.
        check(w.account !== undefined && typeof w.account.util === "string" && typeof w.account.reset === "string", `${tag} ${which} names its per-Account util and reset keys`);
        if (w.labelKey)
            check(tr[w.labelKey] !== undefined, `${tag} ${which} label "${w.labelKey}" is translated`);
    }

    check(Array.isArray(d.sections) && d.sections.length > 0, `${tag} has sections`);

    let sawAccountsSection = false;
    for (const s of d.sections) {
        check(implemented.has(s.type), `${tag} section type "${s.type}" is implemented by SourceTab`);
        if (s.type === "accounts")
            sawAccountsSection = true;
        if (s.type === "windows") {
            check(s.which === "primary" || s.which === "secondary", `${tag} windows section names a real window`);
        }
        if (s.type === "stats") {
            check(Array.isArray(s.columns) && s.columns.length > 0, `${tag} stats declares columns`);
            for (const c of s.columns || []) {
                check(typeof c.labelKey === "string" && tr[c.labelKey] !== undefined, `${tag} stats column "${c.labelKey}" is translated`);
                for (const slot of ["value", "sub"]) {
                    const spec = c[slot];
                    if (!spec) continue;
                    check(["tokens", "cost", "count"].indexOf(spec.kind) >= 0, `${tag} stats ${slot} kind "${spec.kind}" is known`);
                    check(stateKeys.has(spec.key), `${tag} stats ${slot} reads state key "${spec.key}"`);
                    if (spec.kind === "count")
                        check(tr[spec.unitKey] !== undefined, `${tag} stats ${slot} unit "${spec.unitKey}" is translated`);
                }
            }
        }
    }

    // An accounts Section needs the descriptor to say how Accounts work, and
    // vice versa: a declared Account list the widget cannot read is dead config.
    if (sawAccountsSection)
        check(d.accounts !== undefined, `${tag} has an accounts section so declares account settings`);
    if (d.accounts) {
        check(sawAccountsSection, `${tag} declares account settings so renders an accounts section`);
        check(/^w*[Aa]ccounts?$|^custom\w+$/.test(d.accounts.settingKey), `${tag} account settingKey looks like a settings key`);
        check(widget.indexOf("pluginData[d.accounts.settingKey]") >= 0, `${tag} account settingKey is resolved generically by the widget`);
        check(["path", "key"].indexOf(d.accounts.argField) >= 0, `${tag} account argField is path or key`);
        check(typeof d.accounts.listKey === "string" && d.accounts.listKey.length > 0, `${tag} account declares the output key that lists its Accounts`);
        check(d.accounts.fields !== undefined && Object.keys(d.accounts.fields).length > 0, `${tag} account declares its non-Window output fields`);
        for (const [key, spec] of Object.entries(d.accounts.fields || {})) {
            check(/^PROFILE_/.test(key), `${tag} account field "${key}" is a per-Account key`);
            check(typeof spec.field === "string" && spec.field.length > 0, `${tag} account field "${key}" names an overlay field`);
            check(["text", "number", "boolean", "series", "models"].indexOf(spec.type) >= 0, `${tag} account field "${key}" has a known reader`);
        }
        check(tr[d.accounts.titleKey] !== undefined, `${tag} account title is translated`);
        check(tr[d.accounts.descriptionKey] !== undefined, `${tag} account description is translated`);
        check(tr[d.accounts.fieldLabelKey] !== undefined, `${tag} account field label is translated`);
    }

    // A status Section is a failed endpoint, not a credential problem. Its copy
    // must be complete and translated, and must never send the user to settings:
    // the whole point is that they cannot fix it there.
    let sawStatusSection = false;
    for (const s of d.sections)
        if (s.type === "status")
            sawStatusSection = true;
    if (sawStatusSection)
        check(d.status !== undefined, `${tag} has a status section so declares status copy`);
    if (d.status) {
        for (const key of [d.status.titleKey, d.status.bodyKey, d.status.emptyBodyKey]) {
            check(typeof key === "string" && key.length > 0, `${tag} status copy is a non-empty string`);
            check(tr[key] !== undefined, `${tag} status copy "${key}" is translated`);
        }
        const copies = [d.status.titleKey, d.status.bodyKey, d.status.emptyBodyKey];
        for (const key of copies) {
            for (const language of ["en", "fr", "es"]) {
                const text = language === "en" ? key : tr[key] && tr[key][language];
                check(typeof text === "string" && !/settings|paramètres|ajustes/i.test(text), `${tag} status copy "${key}" does not direct the user to settings (${language})`);
            }
        }
        check(d.status.bodyKey !== d.status.emptyBodyKey, `${tag} status copy distinguishes last known values from no data`);
    }
    if (d.status)
        check(sawStatusSection, `${tag} declares status copy so has a status section`);
}

// --- Identity ---
const ids = reg.ids();
check(new Set(ids).size === ids.length, "Source ids are unique");
check(reg.byId("nope") === null, "byId returns null for an unknown id");
check(reg.byId(ids[0]) === reg.SOURCES[0], "byId returns the matching descriptor");

// --- Renderer contract ---
// A Section hides itself when it does not apply, but a Loader does not inherit
// that and a Column lays out a Loader on its height alone. The renderer mirrors
// each Section's own `shown` rather than `visible`, because QML reports
// `visible` as false on every item while an ancestor is hidden and the popout
// primes its content hidden.
check(/visible:\s*item\s*\?\s*item\.shown\s*!==\s*false\s*:\s*true/.test(tab), "SourceTab's section Loader mirrors the Section's shown so hidden cards collapse");
for (const name of ["AccountsSection", "LoginSection", "StatusSection", "WindowsSection", "ModelsSection", "AlltimeSection"]) {
    const sectionSource = fs.readFileSync(path.join(root, `ui/${name}.qml`), "utf8");
    check(/property bool shown:/.test(sectionSource), `${name} declares shown so the renderer can collapse it`);
}

// --- The widget holds no per-Source branches ---
// ADR-0001: a Source is data. The Account setting key, the Account output keys
// and the login action all come from the descriptor, so a Source added to the
// registry needs no edit here and none of these strings should appear in the
// widget.
check(widget.indexOf("PROFILE_") < 0, "the widget names no Account output keys; they are descriptor data");
check(widget.indexOf("fiveHour") < 0 && widget.indexOf("sevenDay") < 0, "the widget holds no Claude-shaped Account fields");
for (const key of ["customProfiles", "customChatgptAccounts", "customZaiAccounts", "customOpencodeAccounts"])
    check(widget.indexOf(`"${key}"`) < 0, `the widget does not hardcode the setting key "${key}"`);
check(widget.indexOf("claudeLogin") < 0 && widget.indexOf("chatgptLogin") < 0, "the widget hardcodes no login action ids");
for (const d of reg.SOURCES) {
    if (d.login && d.login.kind === "cli") {
        check(typeof d.login.program === "string" && d.login.program.length > 0, `descriptor "${d.id}" cli login names its program`);
        check(Array.isArray(d.login.args), `descriptor "${d.id}" cli login declares its args`);
    }
}

// --- Settings list rules ---
check(JSON.stringify(reg.resolveList(undefined)) === JSON.stringify(ids), "absent list enables every Source in registry order");
check(reg.resolveList(null).length === ids.length, "null list enables every Source");
check(reg.resolveList([]).length === 0, "an explicitly empty list stays empty so the last Source can be switched off");
const partial = [ids[2], ids[0]];
const expectedPartial = partial.concat(ids.filter((id) => !partial.includes(id)));
check(JSON.stringify(reg.resolveList(partial)) === JSON.stringify(expectedPartial), "a partial list keeps its order and appends missing Sources");
check(reg.resolveList(["ghost"]).length === ids.length, "unknown ids are dropped");
check(reg.resolveList(["ghost", ids[1]])[0] === ids[1], "a dropped id does not displace a real one");
check(reg.resolveList([ids[0], ids[0]]).length === ids.length, "a duplicated id is not repeated");

// With a `known` set, an omitted id the user has seen stays off, and only an id
// they have never seen is appended. This is what makes switching one Source off
// stick while a Source added by an update still appears on its own.
const switchedOff = [ids[1], ids[2], ids[3]];
check(JSON.stringify(reg.resolveList(switchedOff, ids)) === JSON.stringify(switchedOff), "a Source in `known` but absent from the list stays switched off");
check(JSON.stringify(reg.resolveList([], ids)) === "[]", "an empty list stays empty even with a known set");
check(JSON.stringify(reg.resolveList([ids[0]], [ids[0]])) === JSON.stringify(ids), "a registry id absent from both the list and `known` is appended as newly added");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then
        pass "$label"
    else
        fail "$label"
    fi
done < /tmp/registry-report.txt

# A Node crash would leave the report empty, which would otherwise look like a
# clean run.
if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "registry report produced no results (node failed?) see /tmp/registry-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
