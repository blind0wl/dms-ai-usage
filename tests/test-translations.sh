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

let failed = false;
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

console.log(`PASS: ${keys.size} UI keys have complete French and Spanish translations`);
console.log("PASS: Spanish weekday labels are present");
NODE
