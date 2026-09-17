#!/usr/bin/env bash
# Tests for the setup-guide link in the credentials card.
#
# A Source whose credentials are missing explains the fix in prose, so the card
# carries a "Setup guide" link into the README section for that Source. The link
# is composed from the descriptor's own id, which makes the anchor contract
# this: every Source id is the heading slug of a section in README.md. Both
# halves are read from the files themselves, so a Source added to the registry
# without its README section fails here instead of shipping a dead link.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping setup-link tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Setup-guide link report ==="

SETUP_REPORT=/tmp/setup-link-report.txt
node - "$SCRIPT_DIR" > "$SETUP_REPORT" 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = process.argv[2];
const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// --- The registry ---
const registrySource = fs.readFileSync(path.join(root, "sources.js"), "utf8").replace(/^\.pragma library\s*/, "");
const registry = {};
vm.createContext(registry);
vm.runInContext(registrySource + "; this.api = { SOURCES };", registry, { filename: "sources.js" });
const sources = registry.api.SOURCES;

// --- The README's heading slugs, the way GitHub builds them ---
// GitHub lowercases the heading, drops everything that is not a word character,
// a space or a hyphen, then turns spaces into hyphens. "Z.ai" therefore slugs to
// "zai" and "opencode Go" to "opencode-go".
const readme = fs.readFileSync(path.join(root, "README.md"), "utf8");
const slug = (heading) => heading.toLowerCase().replace(/[^\w\- ]+/g, "").trim().replace(/ /g, "-");
const headings = [...readme.matchAll(/^#{1,6}\s+(.+?)\s*$/gm)].map((m) => slug(m[1]));
const slugs = new Set(headings);

// --- The card itself ---
const login = fs.readFileSync(path.join(root, "ui/LoginSection.qml"), "utf8");

// The URL is evaluated rather than pattern-matched, so what the test checks is
// what the card would open, slug helper included.
const helper = login.match(/function anchorFor\(name\) \{[\s\S]*?\n    \}/);
const base = login.match(/property string readmeUrl:\s*([^\n]+)/);
const binding = login.match(/property string docsUrl:\s*([\s\S]*?)\n\n/);
check(!!helper, "LoginSection has the heading-slug helper the anchor is built from");
check(!!base, "LoginSection names the README the link opens");
check(!!binding, "LoginSection composes a setup-guide URL");
if (helper && base && binding) {
    const resolve = new Function("ctx",
        "var readmeUrl = " + base[1].trim() + ";\n" + helper[0] +
        "\nreturn (" + binding[1].trim() + ");");
    check(resolve(null) === "", "the URL is empty with no context");
    check(resolve({}) === "", "the URL is empty with no descriptor");
    check(resolve({ descriptor: { labelKey: "Claude" } }) === "https://github.com/blind0wl/dms-ai-usage#claude",
          "the URL is the plugin's README at the Source's own anchor");
    check(resolve({ descriptor: { labelKey: "Z.ai" } }).endsWith("#zai"),
          "a missing Z.ai key lands on the Z.ai instructions, not the README root");
    check(resolve({ descriptor: { labelKey: "opencode Go" } }).endsWith("#opencode-go"),
          "a Source whose name has a space lands on its own section");
    check(!/isCli|credsStatus/.test(binding[1]),
          "the URL does not depend on whether the Source logs in through a CLI");

    // Two independent implementations of GitHub's slug rule, one of them the
    // card's own, have to agree about every Source, or the link is dead.
    for (const d of sources) {
        const url = resolve({ descriptor: d });
        const anchor = url.split("#")[1] || "";
        check(anchor === slug(d.labelKey), `the "${d.id}" link's anchor is its Source name's slug`);
        check(slugs.has(anchor), `the "${d.id}" link lands on a README section that exists`);
        check(headings.filter((h) => h === anchor).length === 1,
              `the README has exactly one section for "${d.labelKey}", so the anchor cannot drift to a later duplicate`);
    }
}

check(/onClicked:\s*Qt\.openUrlExternally\(root\.docsUrl\)/.test(login),
      "the link opens through Qt.openUrlExternally");
check(/visible:\s*root\.docsUrl !== ""/.test(login),
      "the link shows for every Source with a README section, cli or API-key alike");
check(/cursorShape:\s*Qt\.PointingHandCursor/.test(login), "the link advertises itself as clickable");

// The ticket's other half: the link supplements the CLI login button, it does
// not replace it.
check(/visible:\s*root\.isCli/.test(login), "the cli login button is still there beside the link");
check(/onClicked:\s*root\.api\.startLogin\(root\.ctx\.source\.id\)/.test(login),
      "the button still starts the cli login flow");

// --- Copy ---
// tests/test-translations.sh scans the widget and the settings page, not the
// Section components, so the card's own keys are checked here.
const catalog = fs.readFileSync(path.join(root, "translations.js"), "utf8").replace(/^\.pragma library\s*/, "");
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(catalog + "; this.strings = strings;", sandbox, { filename: "translations.js" });
const strings = sandbox.strings;

const keys = [...login.matchAll(/api\.tr\("([^"]+)"\)/g)].map((m) => m[1]);
check(keys.length > 0, "the card's copy goes through the translation catalog");
check(keys.indexOf("Setup guide") >= 0, "the link's label is one of them");
for (const key of new Set(keys)) {
    for (const language of ["fr", "es"]) {
        const entry = strings[key];
        check(entry !== undefined && typeof entry[language] === "string" && entry[language].trim() !== "",
              `the card's "${key}" has a ${language} translation`);
    }
}

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$SETUP_REPORT"

# A Node crash would leave the report empty, which would otherwise look like a
# clean run.
if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "setup-link report produced no results (node failed?) see $SETUP_REPORT"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
