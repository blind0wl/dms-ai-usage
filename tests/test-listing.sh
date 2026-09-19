#!/usr/bin/env bash
# Tests for the Listing module: the conversation with a Source's Script about
# its Accounts (#80).
#
# listing.js is a .pragma library like sources.js and state.js, so these run
# the production code: the tests feed exactly the lines and exit codes the
# settings editor's two Processes feed, and assert the actions it gets back.
# Every sequencing rule — which question goes out when, which answer routes
# where, when a verdict is stale to the Script, when a queued Add is re-asked —
# is pinned here rather than lived out in QML where nothing can reach it.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping listing tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

if [ ! -f "$SCRIPT_DIR/listing.js" ]; then
    fail "listing.js does not exist yet"
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi

echo "=== Driving the Listing conversation the way the editor's Processes do ==="

node - "$SCRIPT_DIR" >/tmp/listing-report.txt 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const root = process.argv[2];

// QML's own library directives have no meaning under Node: .pragma marks the
// file as a shared library, and .import is how listing.js reaches the registry.
// Both are stripped, and the imported library is handed to the sandbox instead.
const read = (file) => fs.readFileSync(path.join(root, file), "utf8")
    .replace(/^\.pragma library\s*/, "")
    .replace(/^\.import\s+"[^"]+"\s+as\s+\w+\s*$/gm, "");

const load = (file, suffix, extra) => {
    const sandbox = Object.assign({ console }, extra || {});
    vm.createContext(sandbox);
    vm.runInContext(read(file) + suffix, sandbox, { filename: file });
    return sandbox;
};

const Sources = load("sources.js", "; this.api = { scriptCommand, accountArgs, wirePair, splitList, nameValueMap, listing, addOutcome, refusedRegistration, detectedWinner, LIST_KEY, ORIGINS_KEY, SHADOWED_KEY, STATUS_KEY, NOT_INSTALLED, BLOCKING_REQUIREMENT, BLOCKED, LIST_ACCOUNTS_FLAG, CUSTOM_ORIGIN };").api;
const Listing = load("listing.js", "; this.api = { create };", { Sources }).api;

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// A fake Descriptor: only the wiring the conversation reads is declared. The
// command assertions lean on scriptCommand's shape:
// ["timeout", "120", "bash", <script path>, ...args].
const descriptor = { id: "test", script: "get-test-usage", accounts: { argField: "path" } };
const machine = Listing.create("/plugins", "aiUsage", descriptor);

// --- Creation ---
check(machine.listing.answered === false && machine.listing.failed === false,
      "a fresh machine has no listing and no failure");

// --- The listing flow ---
const firstAsk = machine.askList([{ name: "a", path: "/x" }]);
check(firstAsk.kind === "run" && firstAsk.command[0] === "timeout" &&
      firstAsk.command[4] === Sources.LIST_ACCOUNTS_FLAG && firstAsk.command[5] === "a=/x",
      "askList runs the Script in listing mode with the list's Account arguments");

check(machine.askList([{ name: "a", path: "/x" }]).kind === "queued",
      "askList while a listing is out queues instead of asking");

machine.onListLine(Sources.LIST_KEY + "=work,home");
machine.onListLine(Sources.ORIGINS_KEY + "=work:~/.claude,home:custom");
machine.onListLine(Sources.STATUS_KEY + "=ok");

const firstExit = machine.onListExit(0);
check(firstExit.kind === "committed" && firstExit.rerun === true,
      "a listing that lands while another was asked commits and says to re-ask");
check(machine.listing.names === "work,home" &&
      machine.listing.origins === "work:~/.claude,home:custom" &&
      machine.listing.answered === true && machine.listing.absent === false &&
      machine.listing.blocked === false,
      "the committed listing carries the Script's whole answer");

machine.askList([]);
machine.onListLine(Sources.STATUS_KEY + "=" + Sources.NOT_INSTALLED);
machine.onListExit(0);
check(machine.listing.absent === true,
      "a Not installed report commits as an absent Source");

machine.askList([]);
machine.onListLine(Sources.STATUS_KEY + "=" + Sources.BLOCKED);
machine.onListLine(Sources.BLOCKING_REQUIREMENT + "=jq,curl");
machine.onListExit(0);
check(machine.listing.blocked === true && machine.listing.requirement === "jq,curl",
      "a Blocked report commits with the commands the Script could not read past");

const goodNames = machine.listing.names;
machine.askList([]);
machine.onListLine(Sources.LIST_KEY + "=ghost");
const failedExit = machine.onListExit(1);
check(failedExit.kind === "failed" && failedExit.rerun === false &&
      machine.listing.failed === true && machine.listing.names === goodNames,
      "a listing that fails is marked failed and leaves the last answer standing");

machine.askList([]);
machine.onListLine(Sources.LIST_KEY + "=work");
machine.onListExit(0);

check(machine.onListLine(Sources.LIST_KEY + "=stray") === undefined,
      "a line arriving with no question out is ignored");

// --- The Add guard: two questions, one verdict ---
const runAdd = (name, value, list, baselineLines, candidateLines, baseCode, candCode) => {
    const asked = machine.askAdd(name, value, list);
    if (asked.kind !== "run")
        return { asked };
    (baselineLines || []).forEach((l) => machine.onProbeLine(l));
    const afterBase = machine.onProbeExit(baseCode === undefined ? 0 : baseCode);
    if (afterBase.kind !== "run")
        return { asked, afterBase };
    (candidateLines || []).forEach((l) => machine.onProbeLine(l));
    return { asked, afterBase, verdict: machine.onProbeExit(candCode === undefined ? 0 : candCode) };
};

const listingOf = (names, origins, shadowed) => [
    Sources.LIST_KEY + "=" + (names || ""),
    Sources.ORIGINS_KEY + "=" + (origins || ""),
    Sources.SHADOWED_KEY + "=" + (shadowed || "")
];

const safe = runAdd("n", "/v", [{ name: "a", path: "/x" }],
    listingOf("work", "work:~/.claude", ""),
    listingOf("work", "work:~/.claude", ""));
check(safe.asked.kind === "run" && safe.asked.command[5] === "a=/x",
      "askAdd first asks for the list as it stands");
check(safe.afterBase.kind === "run" && safe.afterBase.command[5] === "a=/x" &&
      safe.afterBase.command[6] === "n=/v",
      "the candidate question is the snapshot list plus the candidate row on the end");
check(safe.afterBase.name === "n" && safe.afterBase.value === "/v",
      "the candidate question names the row it was asked about, so the editor can decline it");
check(safe.verdict.kind === "outcome" && safe.verdict.outcome === null &&
      safe.verdict.name === "n" && safe.verdict.value === "/v",
      "a row that clashes with nothing is reported safe, tagged with its own row");

const wins = runAdd("n", "/v", [{ name: "a", path: "/x" }],
    listingOf("work", "work:~/.claude", ""),
    listingOf("work", "work:~/.claude", "n|work:~/.claude-work"));
check(wins.verdict.outcome !== null && wins.verdict.outcome.reason === "taken" &&
      wins.verdict.outcome.lost === true && wins.verdict.outcome.name === "work" &&
      wins.verdict.outcome.origin === "~/.claude-work",
      "a row that would displace a detected Account is refused, naming what it replaces");

const loses = runAdd("n", "/v", [{ name: "a", path: "/x" }],
    listingOf("work", "work:~/.claude", ""),
    listingOf("work", "work:~/.claude", "work|n:custom"));
check(loses.verdict.outcome !== null && loses.verdict.outcome.reason === "taken" &&
      loses.verdict.outcome.lost === false && loses.verdict.outcome.name === "work",
      "a row the Script would drop in favour of a detected Account is refused");

const preClash = runAdd("n", "/v", [{ name: "a", path: "/x" }],
    listingOf("work", "work:~/.claude", "n|work:~/.w"),
    listingOf("work", "work:~/.claude", "n|work:~/.w"));
check(preClash.verdict.outcome === null,
      "a clash the list already had is not blamed on the new row");

const noAnswer = runAdd("n", "/v", [{ name: "a", path: "/x" }], [], []);
check(noAnswer.verdict.outcome !== null && noAnswer.verdict.outcome.reason === "unreadable",
      "a Script that never answered yields an unreadable verdict, not a save");

const baseFailed = runAdd("n", "/v", [{ name: "a", path: "/x" }],
    listingOf("work", "work:~/.claude", ""), null, 1);
check(baseFailed.afterBase.kind === "outcome" &&
      baseFailed.afterBase.outcome.reason === "unreadable",
      "a baseline that exits non-zero is unreadable, and no candidate is asked");

const candFailed = runAdd("n", "/v", [{ name: "a", path: "/x" }],
    listingOf("work", "work:~/.claude", ""),
    listingOf("work", "work:~/.claude", ""), 0, 3);
check(candFailed.verdict.kind === "outcome" && candFailed.verdict.outcome.reason === "unreadable",
      "a candidate run that exits non-zero is unreadable");

// --- Queueing ---
machine.askAdd("first", "/one", []);
const queued = machine.askAdd("second", "/two", []);
check(queued.kind === "queued", "an Add pressed while a probe is out is queued");

machine.onProbeLine(listingOf("work", "work:~/.claude", "")[0]);
machine.onProbeExit(0);
const queueRan = machine.onProbeExit(0);
check(queueRan.kind === "outcome" && queueRan.queued === true,
      "the verdict of a probe says when a queued Add is waiting to be re-asked");

// --- The editor declining the candidate question ---
const declined = machine.askAdd("n", "/v", [{ name: "a", path: "/x" }]);
machine.onProbeLine(listingOf("work", "work:~/.claude", "")[0]);
const offer = machine.onProbeExit(0);
check(offer.kind === "run" && offer.name === "n",
      "the machine offers the candidate question on a clean baseline");
const reset = machine.abandonAdd();
check(reset.kind === "reset" && reset.queued === false,
      "abandonAdd resets the probe when the fields moved on");
const afterReset = runAdd("n", "/v2", [{ name: "a", path: "/x" }],
    listingOf("work", "work:~/.claude", ""),
    listingOf("work", "work:~/.claude", ""));
check(afterReset.asked.kind === "run" && afterReset.verdict.outcome === null,
      "a fresh Add works after an abandoned one");

// --- Two conversations at once ---
const probeOut = machine.askAdd("n", "/v", [{ name: "a", path: "/x" }]);
const duringProbe = machine.askList([]);
check(probeOut.kind === "run" && duringProbe.kind === "run",
      "the listing and the probe run as two independent conversations");
machine.onListExit(0);
machine.onProbeLine(listingOf("work", "work:~/.claude", "")[0]);
check(machine.onProbeExit(0).kind === "run",
      "a listing landing does not disturb the probe's stage");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then
        pass "$label"
    else
        fail "$label"
    fi
done < /tmp/listing-report.txt

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "listing report produced no results (node failed?) see /tmp/listing-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
