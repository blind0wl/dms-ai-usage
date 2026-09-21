#!/usr/bin/env bash
# Checks that every plugin translation key has complete French and Spanish entries.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping translation tests"
    exit 0
fi

node - "$SCRIPT_DIR" <<'NODE'
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = process.argv[2];
const catalogPath = path.join(root, "translations.js");
const catalogSource = fs.readFileSync(catalogPath, "utf8").replace(/^\.pragma library\s*/, "");
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(catalogSource, sandbox, { filename: catalogPath });

const keys = new Set();
// Every file that renders copy: the widget, the settings page, and the Section
// components under ui/. A key only one Section uses is as untranslated as any
// other when that Section is the one on screen.
const rendered = ["AiUsageWidget.qml", "AiUsageSettings.qml"].concat(
    fs.readdirSync(path.join(root, "ui"))
        .filter((name) => name.endsWith(".qml"))
        .map((name) => path.join("ui", name))
);
for (const filename of rendered) {
    const source = fs.readFileSync(path.join(root, filename), "utf8");
    const pattern = /(?:root\.)?tr\("([^"]+)"\)/g;
    let match;
    while ((match = pattern.exec(source)) !== null)
        keys.add(match[1]);
}

// The descriptors render copy too, and a descriptor that names a key is asking
// for it to exist: a heading the editor reads off the descriptor never appears in
// a tr("...") call for this sweep to find.
const registrySource = fs.readFileSync(path.join(root, "sources.js"), "utf8").replace(/^\.pragma library\s*/, "");
const registry = {};
vm.createContext(registry);
vm.runInContext(registrySource + "; this.api = { SOURCES };", registry, { filename: "sources.js" });
const named = [];
const nameKey = (key) => {
    if (key !== undefined && key !== null)
        named.push(key);
};
for (const d of registry.api.SOURCES) {
    nameKey(d.labelKey);
    for (const which of ["primary", "secondary", "tertiary"]) {
        const w = d.windows ? d.windows[which] : null;
        if (w)
            nameKey(w.labelKey);
    }
    if (d.accounts)
        for (const key of ["labelKey", "titleKey", "descriptionKey", "fieldLabelKey", "detectedTitleKey"])
            nameKey(d.accounts[key]);
    if (d.login)
        nameKey(d.login.titleKey), nameKey(d.login.bodyKey);
    if (d.status)
        nameKey(d.status.titleKey), nameKey(d.status.bodyKey), nameKey(d.status.emptyBodyKey);
    for (const section of d.sections) {
        nameKey(section.captionKey);
        for (const column of section.columns || []) {
            nameKey(column.labelKey);
            for (const slot of ["value", "sub"])
                if (column[slot] && column[slot].kind === "count")
                    nameKey(column[slot].unitKey);
        }
    }
}
const descriptorProblems = [];
for (const key of named) {
    if (typeof key !== "string" || key.length === 0)
        descriptorProblems.push("a descriptor names an empty translation key");
    else if (sandbox.strings[key] === undefined)
        descriptorProblems.push(`descriptor key "${key}" has no translation entry`);
    else
        keys.add(key);
}

let failed = false;
for (const problem of descriptorProblems) {
    console.error(`FAIL: ${problem}`);
    failed = true;
}
for (const key of [...keys].sort()) {
    const entry = sandbox.strings[key];
    for (const language of ["fr", "es"]) {
        if (!entry || typeof entry[language] !== "string" || entry[language].trim() === "") {
            console.error(`FAIL: missing ${language} translation for "${key}"`);
            failed = true;
        }
    }
}

for (const [key, language, expected] of [
    ["Custom Profiles", "es", "Perfiles personalizados"],
    ["No items added yet", "es", "Todavía no se ha añadido ningún elemento"],
    ["Overview", "fr", "Vue d'ensemble"],
    ["Overview", "es", "Vista general"],
    ["msgs", "fr", "messages"]
]) {
    if (sandbox.tr(key, language) !== expected) {
        console.error(`FAIL: unexpected ${language} translation for "${key}"`);
        failed = true;
    }
}

const widget = fs.readFileSync(path.join(root, "AiUsageWidget.qml"), "utf8");
if (!/es:\s*\["Lu", "Ma", "Mi", "Ju", "Vi", "Sá", "Do"\]/.test(widget)) {
    console.error("FAIL: Spanish weekday labels are missing");
    failed = true;
}

if (failed)
    process.exit(1);

console.log(`PASS: ${keys.size} UI and descriptor keys have complete French and Spanish translations`);
console.log("PASS: Spanish weekday labels are present");
NODE
