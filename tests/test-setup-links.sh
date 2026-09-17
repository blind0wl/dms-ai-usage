#!/usr/bin/env bash
# Tests for the setup-guide link, on the credentials card and on the Overview.
#
# A Source whose credentials are missing explains the fix in prose, so it carries
# a "Setup guide" link into the README section for that Source. Both surfaces draw
# the one link component (ui/SetupGuideLink.qml), whose anchor is the GitHub slug
# of the Source's own name, which makes the contract this: every Source's name
# heads exactly one section in README.md. The slug rule, the URL and its two call
# sites are all read from the files themselves, so renaming a Source, rewording
# its README heading or growing a second copy of the rule fails here instead of
# shipping a dead or drifting link.
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
const link = fs.readFileSync(path.join(root, "ui/SetupGuideLink.qml"), "utf8");
const login = fs.readFileSync(path.join(root, "ui/LoginSection.qml"), "utf8");
const overview = fs.readFileSync(path.join(root, "ui/OverviewSection.qml"), "utf8");
const loginButton = fs.readFileSync(path.join(root, "ui/LoginButton.qml"), "utf8");

// A property's expression, read off the declaration rather than pattern-matched
// against its formatting: the body is whatever follows the colon until the next
// declaration at any indent or a blank line.
function propertyBody(source, name) {
    const lines = source.split("\n");
    const at = lines.findIndex((line) => line.trim().startsWith("readonly property string " + name + ":"));
    if (at < 0)
        return null;
    const marker = ":";
    const body = [lines[at].slice(lines[at].indexOf(marker) + 1)];
    for (let i = at + 1; i < lines.length; i++) {
        if (lines[i].trim() === "" || /^\s*(readonly\s+)?(property|function|signal)\b/.test(lines[i]))
            break;
        body.push(lines[i]);
    }
    return body.join("\n").trim();
}

// The URL is evaluated rather than pattern-matched, so what the test checks is
// what the card would open, its slug helper included.
const helper = link.match(/function anchorFor\(name\) \{[\s\S]*?\n    \}/);
const base = propertyBody(link, "readmeUrl");
const docsUrl = propertyBody(link, "docsUrl");
check(!!helper, "SetupGuideLink has the heading-slug helper the anchor is built from");
check(!!base, "SetupGuideLink names the README the link opens");
check(!!docsUrl, "SetupGuideLink composes a setup-guide URL");
if (helper && base && docsUrl) {
    // `docsUrl` reads the Source's name and the README it appends the anchor to
    // as properties of the component, so the harness hands it the README the
    // component declares plus a stand-in for the Source's name.
    const readme = new Function("return (" + base + ");")();
    const resolve = new Function("root",
        helper[0] + "\nreturn (" + docsUrl + ");");
    const urlFor = (labelKey) => resolve({ labelKey, readmeUrl: readme });
    check(urlFor("") === "", "the URL is empty with no Source name");
    check(urlFor("Claude") === "https://github.com/blind0wl/dms-ai-usage#claude",
          "the URL is the plugin's README at the Source's own anchor");
    check(urlFor("Z.ai").endsWith("#zai"),
          "a missing Z.ai key lands on the Z.ai instructions, not the README root");
    check(urlFor("opencode Go").endsWith("#opencode-go"),
          "a Source whose name has a space lands on its own section");
    check(!/isCli|credsStatus/.test(docsUrl),
          "the URL does not depend on whether the Source logs in through a CLI");

    // The component's slug helper has to agree with the rule the README headings
    // are measured by. Drift between the two is a link that goes nowhere.
    for (const d of sources) {
        const url = urlFor(d.labelKey);
        const anchor = url.split("#")[1] || "";
        check(anchor === slug(d.labelKey), `the "${d.id}" link's anchor is its Source name's slug`);
        check(slugs.has(anchor), `the "${d.id}" link lands on a README section that exists`);
        check(headings.filter((h) => h === anchor).length === 1,
              `the README has exactly one section for "${d.labelKey}", so the anchor cannot drift to a later duplicate`);
    }
}

check(/onClicked:\s*Qt\.openUrlExternally\(root\.docsUrl\)/.test(link),
      "the link opens through Qt.openUrlExternally");
check(/visible:\s*root\.docsUrl !== ""/.test(link),
      "the link shows itself on the URL it opens");
check(/cursorShape:\s*Qt\.PointingHandCursor/.test(link), "the link advertises itself as clickable");

// The link reaches both places a Missing Source is met: its own tab's card and
// its Overview row, each handing over its own Source's name. A second slug rule
// or a second copy of the URL would be the drift this file exists to catch.
check(/SetupGuideLink\s*\{/.test(login), "the credentials card draws the shared Setup guide link");
check(/labelKey:\s*root\.labelKey/.test(login), "the card's link uses the Source's own name");
check(/SetupGuideLink\s*\{/.test(overview), "an Overview row draws the shared Setup guide link");
check(/labelKey:\s*modelData\.labelKey/.test(overview), "the Overview's link uses that row's Source name");
for (const [name, source] of [["credentials card", login], ["Overview", overview]]) {
    check(!/anchorFor|openUrlExternally|dms-ai-usage/.test(source),
          `the ${name} keeps no second slug, URL or URL-opening path`);
}
// The ticket's other half: the link supplements the CLI login button, it does
// not replace it. The button itself is one component, drawn by both surfaces.
check(!!loginButton, "the login button is its own component");
check(/enabled:\s*!root\.inProgress/.test(loginButton),
      "the button disables itself while that Source's login is running");
check(/signal clicked/.test(loginButton) && /MouseArea\s*\{/.test(loginButton),
      "the button owns the click area once");
check(/Logging in…/.test(loginButton) && /"Log in"/.test(loginButton),
      "the button owns its progress copy once");
check(/LoginButton\s*\{/.test(login), "the credentials card draws the shared login button");
check(/visible:\s*root\.isCli/.test(login), "the cli login button is still there beside the link");
check(/onClicked:\s*root\.api\.startLogin\(root\.ctx\.source\.id\)/.test(login),
      "the button still starts the cli login flow");
check(/LoginButton\s*\{/.test(overview) && /onClicked:\s*root\.api\.startLogin\(row\.sourceId\)/.test(overview),
      "an Overview row's button starts that row's login");
// The duplicate #40 inherited is retired, not added to: neither surface may
// carry its own copy of the button's geometry or its progress copy.
for (const [name, source] of [["credentials card", login], ["Overview", overview]]) {
    check(!/Logging in…/.test(source) && !/radius:\s*16/.test(source) && !/Theme\.primaryText/.test(source),
          `the ${name} keeps no second copy of the button's geometry or progress copy`);
}
check(/radius:\s*16/.test(loginButton) && /Theme\.primaryText/.test(loginButton) && /Logging in…/.test(loginButton),
      "the shared button still carries the one copy of them");

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
