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
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source + suffix, sandbox, { filename: file });
    return sandbox;
};

const reg = load("sources.js", "; this.api = { SOURCES, byId, ids, reconcileList, resolveList, ACCOUNT_FIELDS, tightestWindow, overviewRows, accountArgs, detectedAccounts, unregisteredRows, scriptPath, scriptCommand, wirePair, splitList, nameValueMap, displacedOrigin, shadowingAccount, CUSTOM_ORIGIN, LIST_ACCOUNTS_FLAG };").api;
const tr = load("translations.js", "; this.strings = strings;").strings;

const widget = fs.readFileSync(path.join(root, "AiUsageWidget.qml"), "utf8");
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
// Every key a descriptor lists in accounts.fields has to have an ACCOUNT_FIELDS
// row, because pickFields() copies the row rather than a name: a missing row
// would otherwise drop the key from the wire with no error anywhere. The table
// is keyed by the unprefixed concept, so the two wire prefixes share one row.
const accountFields = reg.ACCOUNT_FIELDS || {};
check(Object.keys(accountFields).every((k) => !/^(PROFILE|ACCOUNT)_/.test(k)),
      "ACCOUNT_FIELDS is keyed by concept, not once per prefix");
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
        // The settings editor asks the Script's own listing mode which Accounts
        // it would report and where each came from, so it can show what it does
        // not own without re-deriving detection. The key that list arrives under
        // is descriptor data, like the Account list itself.
        check(typeof d.accounts.originsKey === "string" && d.accounts.originsKey.length > 0,
              `${tag} account declares the output key its Account origins arrive under`);
        // The settings editor's read-only list heads itself with the Source's own
        // word for an Account, because CONTEXT.md keeps Profile for Claude-facing
        // copy and Account for everything else.
        check(typeof d.accounts.detectedTitleKey === "string" && tr[d.accounts.detectedTitleKey] !== undefined,
              `${tag} account declares a translated heading for the detected list`);
        // The editor marks a detected Account a Custom one replaced from the
        // listing's own report, so the key it arrives under and the copy that
        // describes it are descriptor data too.
        check(typeof d.accounts.shadowedKey === "string" && d.accounts.shadowedKey.length > 0,
              `${tag} account declares the output key its refused registrations arrive under`);
        check(typeof d.accounts.overriddenKey === "string" && tr[d.accounts.overriddenKey] !== undefined,
              `${tag} account declares translated copy for a detected Account a Custom one replaced`);
        const script = fs.readFileSync(path.join(root, d.script), "utf8");
        for (const key of [d.accounts.listKey, d.accounts.originsKey, d.accounts.shadowedKey])
            check(script.includes(`${key}=`), `${tag} script ${d.script} reports ${key}`);
        // The editor drops an Account the Custom Account list provided by its
        // exact origin tag, so a Script that spelled it differently would look
        // like it had detected the user's own Accounts. Both strings have to be
        // tagged where the Account is registered, not merely mentioned.
        const lines = script.split("\n");
        const tagAtCallSite = new RegExp(`add_(account|profile) .*"${reg.CUSTOM_ORIGIN}"\\s*;;`);
        check(lines.some((line) => tagAtCallSite.test(line)),
              `${tag} script ${d.script} tags a Custom Account where it registers it`);
        check(lines.some((line) => line.includes(`"${reg.LIST_ACCOUNTS_FLAG}"`) && line.includes("LIST_ACCOUNTS=1")),
              `${tag} script ${d.script} answers the listing mode in its argument loop`);
        check(d.accounts.fields !== undefined && Object.keys(d.accounts.fields).length > 0, `${tag} account declares its output fields`);
        // The prefix a Source's per-Account keys wear is descriptor data, so
        // nothing here has to ask which Source it is. Claude declares PROFILE_
        // because get-claude-usage is upstream's file; the rest declare
        // ACCOUNT_, which CONTEXT.md's Account term implies.
        check(typeof d.accounts.keyPrefix === "string" && /^[A-Z]+_$/.test(d.accounts.keyPrefix),
              `${tag} account declares the prefix its output keys wear`);
        const keyPrefix = typeof d.accounts.keyPrefix === "string" ? d.accounts.keyPrefix : "";
        const declaredFields = new Set();
        for (const [key, spec] of Object.entries(d.accounts.fields || {})) {
            check(keyPrefix.length > 0 && key.indexOf(keyPrefix) === 0,
                  `${tag} account field "${key}" wears the prefix the descriptor declares`);
            const suffix = keyPrefix.length > 0 ? key.slice(keyPrefix.length) : key;
            check(accountFields[suffix] !== undefined,
                  `${tag} account field "${key}" has an ACCOUNT_FIELDS row for suffix "${suffix}"`);
            if (!spec) {
                check(false, `${tag} account field "${key}" resolves in ACCOUNT_FIELDS`);
                continue;
            }
            check(typeof spec.field === "string" && spec.field.length > 0, `${tag} account field "${key}" names an overlay field`);
            check(["text", "number", "boolean", "series", "models"].indexOf(spec.type) >= 0, `${tag} account field "${key}" has a known reader`);
            declaredFields.add(spec.field);
        }
        // Selecting an Account moves both Window cards, so the overlay slots the
        // cards read have to be covered by the fields the descriptor lists.
        for (const slot of ["primaryUtil", "primaryReset", "secondaryUtil", "secondaryReset"])
            check(declaredFields.has(slot), `${tag} account fields cover the ${slot} overlay slot`);
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

// --- Detected Accounts ---
// The settings editor shows the Accounts a Source's Script detects outside the
// plugin settings: those are the ones the Popout's selector offers and the
// editor cannot edit. The Script's own listing mode says which they are, so the
// two surfaces cannot disagree about detection.
//
// The same listing reports the registrations the Script refused, because the
// Script keeps the first registration of a name or of a value. A refused detected
// registration is the serious half: the Source is now authenticating with a
// Custom Account instead of the key on this machine, and the editor has to say so
// rather than let the user meet it as a rejected key.
const listed = (...args) => JSON.stringify(reg.detectedAccounts(...args));
const live = (name, origin) => ({ name: name, origin: origin, overridden: false, winner: "" });
const lost = (name, origin, winner) => ({ name: name, origin: origin, overridden: true, winner: winner });
check(listed("work,default", "work:custom,default:~/.pi/agent/models.json") === JSON.stringify([live("default", "~/.pi/agent/models.json")]),
      "detectedAccounts drops the Accounts the settings list provided");
check(listed("work,default", "work:custom,default:ZAI_API_KEY") === JSON.stringify([live("default", "ZAI_API_KEY")]),
      "detectedAccounts carries the origin the Script named");
check(listed("a,b", "a:~/.claude,b:~/.ccs/instances") === JSON.stringify([live("a", "~/.claude"), live("b", "~/.ccs/instances")]),
      "detectedAccounts keeps the Script's own Account order");
check(listed("default", "default:") === JSON.stringify([live("default", "")]),
      "detectedAccounts reports an Account with no origin rather than hiding it");
check(listed("default", "") === JSON.stringify([live("default", "")]),
      "detectedAccounts reports an Account whose Script named no origin at all");
check(listed("", "") === "[]", "detectedAccounts reports nothing for an empty Account list");
check(listed("work", "work:custom") === "[]", "detectedAccounts reports nothing when every Account came from the settings list");
// An origin is a path or a variable name and may itself carry a colon; the name
// is what the pair is split on, and a name never carries one.
check(listed("work", "work:~/.ccs/instances:one") === JSON.stringify([live("work", "~/.ccs/instances:one")]),
      "detectedAccounts splits a name:origin pair at the first colon");
// A Script that reports an origin for a name it does not list adds nothing.
check(listed("", "ghost:~/.claude") === "[]", "detectedAccounts only reports Accounts the Script listed");
check(listed(null, null) === "[]", "detectedAccounts reports nothing for a missing listing");

// A detected Account the Script refused because a Custom Account took its name
// or its value: still reported, marked, and in the Script's own order after the
// Accounts that are live.
check(listed("default", "default:custom", "default|default:~/.pi/agent/models.json") === JSON.stringify([lost("default", "~/.pi/agent/models.json", "default")]),
      "detectedAccounts reports a detected registration a Custom Account took the name of");
check(listed("work", "work:custom", "work|default:~/.pi/agent/models.json") === JSON.stringify([lost("default", "~/.pi/agent/models.json", "work")]),
      "detectedAccounts reports a detected registration a Custom Account took the value of, naming the row that took it");
check(listed("a", "a:~/.claude", "b|b:~/.ccs/instances") === JSON.stringify([live("a", "~/.claude"), lost("b", "~/.ccs/instances", "b")]),
      "detectedAccounts marks only the refused registration as overridden");
check(listed("a", "a:~/.claude", "a|a:~/.claude") === JSON.stringify([live("a", "~/.claude")]),
      "detectedAccounts does not call a detected Account overridden when it is the one in use");
// The reverse direction is the Custom row's business, not this list's: a refused
// Custom registration is reported by unregisteredRows and marked there.
check(listed("default", "default:~/.codex", "default|default:custom") === JSON.stringify([live("default", "~/.codex")]),
      "detectedAccounts ignores a refused Custom registration");
check(listed("work", "work:custom", "default|ghost:custom") === "[]",
      "detectedAccounts reports nothing when the only refused registration was a Custom one");
// A pair without the winner is still read, so a Script that has not been updated
// leaves the row marked and its origin shown rather than dropping it.
check(listed("default", "default:custom", "default:~/.pi/agent/models.json") === JSON.stringify([lost("default", "~/.pi/agent/models.json", "")]),
      "detectedAccounts reads a refused registration that names no winner");

// Which Custom row is the one authenticating instead of a detected Account: the
// editor marks that row, and only the Script can say which it was.
const displaced = (detected, name) => reg.displacedOrigin(detected, name);
const sample = JSON.parse(listed("work", "work:custom", "work|default:~/.pi/agent/models.json"));
check(displaced(sample, "work") === "~/.pi/agent/models.json",
      "displacedOrigin names the origin the Custom row took the place of");
check(displaced(sample, "other") === "", "displacedOrigin reports nothing for a row that displaced nothing");
check(displaced(JSON.parse(listed("work", "work:custom", "")), "work") === "",
      "displacedOrigin reports nothing when no registration was refused");
check(displaced(null, "work") === "" && displaced([], "work") === "",
      "displacedOrigin reports nothing for a missing listing");

// The other half of the same question: which detected Account kept what a Custom
// row asked for. The Script names it, and on a clash of values the two names
// differ, so without this the user cannot tell which detected Account is in the
// refused row's place.
const keptBy = (origins, shadowed, name) => JSON.stringify(reg.shadowingAccount(origins, shadowed, name));
check(keptBy("default:CODEX_HOME", "default|mine:custom", "mine") === JSON.stringify({ name: "default", origin: "CODEX_HOME" }),
      "shadowingAccount names the detected Account that kept a Custom row's name or value");
check(keptBy("default:CODEX_HOME", "default|other:custom", "mine") === "null",
      "shadowingAccount reports nothing for a Custom row the Script refused for another reason");
check(keptBy("work:custom", "work|work:custom", "work") === "null",
      "shadowingAccount reports nothing when another Custom row kept the name");
check(keptBy("default:CODEX_HOME", "default|mine:custom", "default") === "null",
      "shadowingAccount reports nothing for a row the Script registered as detected");
check(keptBy("", "ghost|mine:custom", "mine") === "null",
      "shadowingAccount reports nothing when the winner has no origin to name");
check(keptBy("default:CODEX_HOME", "mine:custom", "mine") === "null",
      "shadowingAccount reports nothing for a refused registration that names no winner");
check(keptBy(null, null, "mine") === "null" && keptBy("default:CODEX_HOME", "default|mine:custom", "") === "null",
      "shadowingAccount reports nothing for a missing listing or a nameless row");

// The Custom Accounts the Script did not register. Its listing is the only
// source of that fact: the settings list cannot tell whether the Script kept a
// row, and the Popout's selector offers only what the Script kept.
const dropped = (names, origins, list) => JSON.stringify(reg.unregisteredRows(names, origins, list));
const rows = (...names) => names.map((name) => ({ name: name, key: "k-" + name }));
check(dropped("default", "default:CODEX_HOME", rows("default")) === JSON.stringify([0]),
      "unregisteredRows reports the row the Script registered under a detected origin");
check(dropped("work,default", "work:custom,default:~/.codex", rows("work")) === "[]",
      "unregisteredRows reports nothing for a row the Script kept");
check(dropped("work,default", "work:custom,default:~/.codex", rows("work", "default")) === JSON.stringify([1]),
      "unregisteredRows marks the shadowed row and leaves the kept one alone");
check(dropped("kept", "kept:custom", rows("kept", "ghost")) === JSON.stringify([1]),
      "unregisteredRows reports a row the Script did not list at all");
check(dropped("work", "work:custom", rows("other", "work")) === JSON.stringify([0]),
      "unregisteredRows reports the row that is not in use, whenever it sits in the list");
check(dropped("", "", rows("work")) === "[]",
      "unregisteredRows withholds a verdict when the Script reported no Account at all, as while a listing is in flight");
check(dropped("work", "work:custom", []) === "[]", "unregisteredRows reports nothing for an empty settings list");
check(dropped("work", "work:custom", null) === "[]", "unregisteredRows reports nothing for a missing settings list");
check(dropped("work", "work:custom", [{ key: "k1" }]) === "[]",
      "unregisteredRows ignores a settings row with no name");
// A Script registers one Account per name, so of two rows sharing a name only
// the first is the Account the selector offers.
check(dropped("work", "work:custom", rows("work", "work")) === JSON.stringify([1]),
      "unregisteredRows marks the second of two rows sharing a name");
check(dropped("work", "work:custom", rows("work", "work", "other")) === JSON.stringify([1, 2]),
      "unregisteredRows keeps the row order the editor renders");

// The wire-line split, shared by the widget's fetch parser and the settings
// editor's listing parser so the two read one wire the same way.
const pair = (line) => JSON.stringify(reg.wirePair(line));
check(pair("ACCOUNTS=work,default") === JSON.stringify({ key: "ACCOUNTS", value: "work,default" }),
      "wirePair splits a wire line into its key and value");
check(pair("ACCOUNT_PRIMARY_UTIL=work:80") === JSON.stringify({ key: "ACCOUNT_PRIMARY_UTIL", value: "work:80" }),
      "wirePair splits on the first = so a value may carry one");
check(pair("ACCOUNTS=") === JSON.stringify({ key: "ACCOUNTS", value: "" }),
      "wirePair keeps an empty value");
check(reg.wirePair("no delimiter") === null && reg.wirePair("") === null && reg.wirePair(null) === null,
      "wirePair reports nothing for a line that carries no key");

// One parser for the Scripts' "name:value" lists, which the per-Account values,
// the origins and the model breakdowns all wear. Only the separator differs, and
// the caller splits on its own.
const mapped = (entries, mapValue) => JSON.stringify(reg.nameValueMap(entries, mapValue));
check(mapped(["work:k1", "default:k2"]) === JSON.stringify({ work: "k1", default: "k2" }),
      "nameValueMap keys each entry by the name before its first colon");
check(mapped(["ACCOUNT_CREDITS:work:80"]) === JSON.stringify({ ACCOUNT_CREDITS: "work:80" }),
      "nameValueMap keeps a colon inside the value");
check(mapped(["work:k1", "nocolon", "empty:"]) === JSON.stringify({ work: "k1", empty: "" }),
      "nameValueMap skips an entry with no colon and keeps an empty value");
check(mapped(["work:1"]) === JSON.stringify({ work: "1" })
      && mapped(["work:1,2"], (v) => v.split(",")) === JSON.stringify({ work: ["1", "2"] }),
      "nameValueMap maps each value through the reader the caller gives it");
check(mapped([]) === "{}" && mapped(null) === "{}", "nameValueMap reports nothing for a missing entry list");

// The Script is started one way, watchdog included, so a fetch and a listing
// cannot diverge on how long they wait or which file they run.
check(JSON.stringify(reg.scriptCommand("/plugins", "aiUsage", reg.SOURCES[0], ["work=k1"])) ===
      JSON.stringify(["timeout", "120", "bash", `/plugins/aiUsage/${reg.SOURCES[0].script}`, "work=k1"]),
      "scriptCommand runs the Script under the watchdog with the caller's arguments");
check(JSON.stringify(reg.scriptCommand("/plugins", "aiUsage", reg.SOURCES[0])) ===
      JSON.stringify(["timeout", "120", "bash", `/plugins/aiUsage/${reg.SOURCES[0].script}`]),
      "scriptCommand runs a Script with no arguments when the caller passes none");
check(JSON.stringify(reg.scriptCommand("/plugins", "aiUsage", null)) === JSON.stringify(["timeout", "120", "bash", ""]),
      "scriptCommand still names the watchdog when it cannot name a file");
for (const name of ["AiUsageWidget.qml", "ui/AccountsEditor.qml"]) {
    const source = fs.readFileSync(path.join(root, name), "utf8");
    check(source.includes("Sources.scriptCommand("), `${name} starts a Script through scriptCommand`);
    check(!/\[\s*"timeout"/.test(source), `${name} does not restate the Script's launch prefix`);
}

// The arguments decide which of two Accounts sharing a name survives the
// Script's own de-duplication, so the widget's fetch and the settings editor's
// listing are built by one function rather than two.
const argsFor = (argField, list) => JSON.stringify(reg.accountArgs({ accounts: { argField: argField } }, list));
check(argsFor("key", [{ name: "work", key: "k1" }, { name: "default", key: "k2" }]) === JSON.stringify(["work=k1", "default=k2"]),
      "accountArgs builds one name=value argument per Account");
check(argsFor("path", [{ name: "work", path: "/tmp/work" }]) === JSON.stringify(["work=/tmp/work"]),
      "accountArgs reads the value from the field the descriptor names");
check(argsFor("key", [{ name: "work" }, { key: "k2" }, { name: "", key: "k3" }, { name: "x", key: "" }]) === "[]",
      "accountArgs skips an Account missing either half");
check(argsFor("key", []) === "[]", "accountArgs builds no argument for an empty settings list");
check(argsFor("key", null) === "[]", "accountArgs builds no argument for a missing settings list");
check(JSON.stringify(reg.accountArgs(null, [{ name: "work", key: "k1" }])) === "[]",
      "accountArgs builds no argument for a Source with no Accounts");

// The Script path is the same expression for the widget's fetch and the
// settings editor's listing, so neither can reach a different file.
check(reg.scriptPath("/plugins", "aiUsage", reg.SOURCES[0]) === `/plugins/aiUsage/${reg.SOURCES[0].script}`,
      "scriptPath joins the plugin directory, the plugin id and the descriptor's Script");
check(reg.scriptPath("/plugins", "aiUsage", null) === "" && reg.scriptPath("", "aiUsage", reg.SOURCES[0]) === "",
      "scriptPath returns nothing when it cannot name a file");
// Both the widget's fetch and the settings editor's listing reach the Script
// through one expression, so a change to where plugin files live cannot leave
// them pointing at different files.
for (const name of ["AiUsageWidget.qml", "ui/AccountsEditor.qml"]) {
    const source = fs.readFileSync(path.join(root, name), "utf8");
    check(source.includes("Sources.scriptCommand("), `${name} reaches a Script through scriptCommand`);
    check(!/pluginDirectory\s*\+/.test(source), `${name} does not build a Script path by hand`);
}

// The settings editor is per-Source code like the widget is, so it reads the
// Account wiring off the descriptor too: which keys the listing arrives under,
// and how the Script's arguments are built.
const editor = fs.readFileSync(path.join(root, "ui/AccountsEditor.qml"), "utf8");
for (const key of ["listKey", "originsKey"])
    check(editor.includes(`acct.${key}`), `the settings editor reads the Account ${key} off the descriptor`);
check(editor.includes("Sources.accountArgs("), "the settings editor builds the Script's Account arguments with the widget's own builder");
check(editor.includes("Sources.LIST_ACCOUNTS_FLAG"), "the settings editor asks for the listing mode by its declared flag");
check(editor.includes("Sources.detectedAccounts(") && editor.includes("Sources.unregisteredRows("),
      "the settings editor reads both Account lists from the registry rather than parsing them out");
check(editor.includes("acct.overriddenKey"), "the settings editor takes the override copy off the descriptor");
check(!/ACCOUNT_|PROFILE_/.test(editor), "the settings editor hardcodes no Account output key");

// The two ways this editor's own state went wrong in a user's hands, pinned
// because both failures are silent: an empty list, or a listing that answers for
// the list the user has just changed.
check(editor.includes("onPluginServiceChanged") && editor.includes("onPluginDataChanged"),
      "the settings editor re-reads the Account list when the store becomes readable and whenever it changes");
check(/listProcess\.command\s*=/.test(editor) && !/\blistCommand\b/.test(editor),
      "the settings editor builds the Script's command as it asks, rather than starting a cached one");
check(/modelData\.overridden/.test(editor) && /modelData\.winner/.test(editor),
      "the settings editor renders a detected Account a Custom one replaced, and names the row that did it");
check(editor.includes("Sources.displacedOrigin(") && editor.includes("Sources.shadowingAccount("),
      "the settings editor names what each Custom row took the place of, and what took its own");
check(/!root\.settingsRoot\.pluginService/.test(editor),
      "the settings editor does not ask the Script for a listing before the store it reads is available");

// One wire, one splitter: the widget's fetch parser and the settings editor's
// listing parser take their key and value from wirePair, and read a
// comma-separated list through splitList.
for (const name of ["AiUsageWidget.qml", "ui/AccountsEditor.qml"]) {
    const source = fs.readFileSync(path.join(root, name), "utf8");
    check(source.includes("Sources.wirePair("), `${name} splits a wire line with wirePair`);
}
check(widget.includes("Sources.splitList(") && !/val\.length > 0 \? val\.split\(","\)/.test(widget),
      "the widget reads a wire list with splitList rather than restating its shape");

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
check(!/command:\s*root\.loginCommandFor\(/.test(widget),
      "no login Process binds its command to the live Account selection");
for (const d of reg.SOURCES) {
    if (d.login && d.login.kind === "cli") {
        check(typeof d.login.program === "string" && d.login.program.length > 0, `descriptor "${d.id}" cli login names its program`);
        check(Array.isArray(d.login.args), `descriptor "${d.id}" cli login declares its args`);
        if (d.login.env) {
            check(typeof d.login.env.variable === "string" && d.login.env.variable.length > 0, `descriptor "${d.id}" login env names its variable`);
            check(d.login.env.settingKey === undefined, `descriptor "${d.id}" login env does not reuse the accounts settingKey name`);
            check(typeof d.login.env.accountField === "string" && d.login.env.accountField.length > 0, `descriptor "${d.id}" login env names the Account field it exports`);
        }
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

// --- Overview ranking ---
// The Overview ranks the visible Sources by Tightest Window (ADR 0003). The
// rules live here, not in a Descriptor: ranking is a property of the whole set.
//
// A state fixture shaped like the widget's emptyState()/stateFor() output, with
// settings order supplied by the caller's array order.
const overview = (id, over) => Object.assign({
    id,
    credsStatus: "ok",
    hasData: true,
    primary: { util: 0, resetMs: 0, windowSeconds: 18000 },
    secondary: { util: 0, resetMs: 0, windowSeconds: 604800 }
}, over || {});
const wins = (id, p, s, over) => overview(id, Object.assign({
    primary: { util: p, resetMs: 1000, windowSeconds: 18000 },
    secondary: { util: s, resetMs: 2000, windowSeconds: 604800 }
}, over || {}));
const rowIds = (rows) => rows.map((r) => r.id).join(",");

// tightestWindow names the Window with the highest Utilisation, and the tie goes
// to the primary slot so the answer is stable.
check(reg.tightestWindow(wins("claude", 10, 80)).window === "secondary",
      "tightestWindow names the secondary Window when it has the higher Utilisation");
check(reg.tightestWindow(wins("claude", 80, 10)).window === "primary",
      "tightestWindow names the primary Window when it has the higher Utilisation");
check(reg.tightestWindow(wins("claude", 40, 40)).window === "primary",
      "tightestWindow breaks a tie with the primary Window");
check(reg.tightestWindow(wins("claude", 10, 80)).util === 80,
      "tightestWindow reports the winning Utilisation");
check(reg.tightestWindow(wins("claude", 10, 80)).resetMs === 2000,
      "tightestWindow reports the winning Window's reset");
check(reg.tightestWindow(null) === null, "tightestWindow returns null for a missing state");

// A row carries everything the Overview renders, so #40 can be a dumb repeater.
const sampleRow = reg.overviewRows([wins("claude", 10, 80), wins("chatgpt", 5, 5)])[0];
for (const field of ["id", "labelKey", "window", "windowLabelKey", "windowSeconds", "util", "resetMs", "ranked", "stale", "missing", "unavailable", "degraded"])
    check(Object.prototype.hasOwnProperty.call(sampleRow, field), `an Overview row carries the "${field}" field`);
check(sampleRow.id === "claude" && sampleRow.labelKey === "Claude",
      "an Overview row names its Source by id and label key");
check(sampleRow.window === "secondary" && sampleRow.windowLabelKey === "7-Day Usage",
      "an Overview row's label follows the Tightest Window, not a fixed slot");
check(sampleRow.util === 80 && sampleRow.resetMs === 2000,
      "an Overview row carries the Tightest Window's Utilisation and reset");
check(sampleRow.ranked === true && sampleRow.stale === false && sampleRow.degraded === false,
      "a healthy Overview row is ranked, not stale and not degraded");
check(reg.overviewRows([wins("chatgpt", 10, 80), wins("claude", 5, 5)])[0].windowLabelKey === null,
      "an Overview row leaves windowLabelKey null when its descriptor names no label");

// Ranked before unranked, by Utilisation descending.
check(rowIds(reg.overviewRows([wins("claude", 40, 10), wins("chatgpt", 90, 20)])) === "chatgpt,claude",
      "overviewRows ranks rows by Utilisation descending");
check(rowIds(reg.overviewRows([
    wins("claude", 10, 10),
    overview("zai", { hasData: false, credsStatus: "unknown" })
])) === "claude,zai",
      "overviewRows ranks a Source with a reading above one with no reading yet");
check(rowIds(reg.overviewRows([
    wins("claude", 0, 0),
    overview("zai", { hasData: false, credsStatus: "unknown" })
])) === "claude,zai",
      "a genuine 0% reading is still a reading and outranks no reading at all");

// A tie keeps the settings order the caller passed in.
check(rowIds(reg.overviewRows([wins("claude", 50, 50), wins("chatgpt", 50, 50)])) === "claude,chatgpt",
      "overviewRows breaks a Utilisation tie with settings order");
check(rowIds(reg.overviewRows([
    overview("zai", { hasData: false, credsStatus: "unknown" }),
    overview("claude", { hasData: false, credsStatus: "unknown" })
])) === "zai,claude",
      "overviewRows keeps the unranked group in settings order");

// Unavailable keeps its last known reading and flags it stale.
const unavailableRows = reg.overviewRows([
    wins("opencode", 80, 10, { credsStatus: "unavailable" }),
    wins("claude", 30, 10)
]);
check(rowIds(unavailableRows) === "opencode,claude",
      "an Unavailable Source ranks on its last known value");
check(unavailableRows[0].stale === true && unavailableRows[0].ranked === true && unavailableRows[0].degraded === true,
      "an Unavailable Source's last known row is flagged stale and degraded");
check(unavailableRows[1].stale === false && unavailableRows[1].degraded === false,
      "a healthy row is not stale and not degraded");

// Unavailable with nothing to fall back on has no reading to rank.
const emptyUnavailable = reg.overviewRows([
    overview("opencode", { credsStatus: "unavailable", hasData: false }),
    wins("claude", 5, 1)
]);
check(emptyUnavailable[1].id === "opencode" && emptyUnavailable[1].window === null,
      "an Unavailable Source with no reading carries no Tightest Window");
check(emptyUnavailable[1].ranked === false && emptyUnavailable[1].stale === false && emptyUnavailable[1].degraded === true,
      "an Unavailable Source with no reading is unranked, not stale, and degraded");

// Missing sorts below every ranked row, even when it still has a last known value.
const missingRows = reg.overviewRows([
    wins("claude", 99, 10, { credsStatus: "missing" }),
    wins("chatgpt", 10, 5)
]);
check(rowIds(missingRows) === "chatgpt,claude",
      "a Missing Source sorts below every ranked row");
check(missingRows[1].missing === true && missingRows[1].ranked === false && missingRows[1].degraded === true,
      "a Missing Source's row is flagged missing and unranked");
check(reg.overviewRows([
    overview("zai", { credsStatus: "expired", hasData: false }),
    wins("claude", 10, 5)
])[1].missing === true,
      "an expired Source is Missing for ranking purposes");

// Not installed produces no row, matching the auto-hide rule.
check(rowIds(reg.overviewRows([
    wins("claude", 10, 5),
    overview("chatgpt", { credsStatus: "not_installed" }),
    wins("zai", 20, 5)
])) === "zai,claude",
      "a Not installed Source produces no Overview row");

// The floor: a comparison of one is noise.
check(reg.overviewRows([]).length === 0, "overviewRows returns nothing for no Sources");
check(reg.overviewRows([wins("claude", 10, 5)]).length === 0,
      "fewer than two visible Sources yields no Overview");
check(reg.overviewRows([
    wins("claude", 10, 5),
    overview("chatgpt", { credsStatus: "not_installed" })
]).length === 0,
      "one visible Source beside a Not installed one still yields no Overview");
check(reg.overviewRows(null).length === 0, "overviewRows returns nothing for a non-array input");

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
