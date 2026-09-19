#!/usr/bin/env bash
# Tests for one Source's State: the module that builds it, reads a Script's
# report lines into it, and renders it for a Section.
#
# state.js is a .pragma library like sources.js, so these run the production
# code rather than a copy of it: the report format is the contract between the
# Scripts and every surface, and a fork of the reader could pass while the
# widget failed.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: Node.js not available, skipping Source State tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "=== Reading a Script's report into a Source's State ==="

node - "$SCRIPT_DIR" >/tmp/source-state-report.txt 2>&1 <<'NODE' || true
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const root = process.argv[2];

// QML's own library directives have no meaning under Node: .pragma marks the
// file as a shared library, and .import is how state.js reaches the registry.
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

const Sources = load("sources.js", "; this.api = { SOURCES, byId, wirePair, splitList, nameValueMap, nextNotInstalledCount, isHidden, hasReading, STATUS_KEY, NOT_INSTALLED, BLOCKING_REQUIREMENT, BLOCKED, LIST_KEY };").api;
const State = load("state.js", "; this.api = { empty, readLine, render, hasCurrentReading };", { Sources }).api;

const results = [];
const check = (ok, label) => results.push(`${ok ? "PASS" : "FAIL"}\t${label}`);

// Feeds a whole report to one Source, the way the widget feeds it line by line.
const report = (id, lines, start) => lines.reduce(
    (acc, line) => State.readLine(acc.state, acc.accounts, id, line),
    start || { state: State.empty(), accounts: {} });

// --- The empty State ---
const blank = State.empty();
check(blank.credsStatus === "unknown",
      "a Source that has reported nothing has an unknown status, not a failure");
check(blank.hasData === false && blank.notInstalledCount === 0 && blank.hidden === false,
      "the empty State has no reading, no Not installed count and is not hidden");
check(blank.blockingRequirement === "", "the empty State names no blocking Requirement");
check(blank.primary.util === 0 && blank.primary.resetMs === 0 && blank.primary.windowSeconds === 0 &&
      blank.secondary.util === 0,
      "both Window slots start empty");
check(Array.isArray(blank.accounts) && blank.accounts.length === 0 &&
      blank.dailyTokens.length === 7 && blank.dailyCosts.length === 7,
      "the empty State carries an empty Account list and seven empty days");

// --- readLine is pure ---
const before = State.empty();
const beforeAccounts = {};
const after = State.readLine(before, beforeAccounts, "claude", "WEEK_TOKENS=42");
check(before.weekTokens === 0 && after.state.weekTokens === 42,
      "readLine returns a new State and leaves the one it was given alone");
check(after.state !== before,
      "readLine returns a new State object, so a QML property reassignment re-evaluates bindings");
const overlayRead = State.readLine(before, beforeAccounts, "claude", "ACCOUNT_WEEK_TOKENS=work:1");
check(after.accounts === beforeAccounts && overlayRead.accounts !== beforeAccounts,
      "the Account overlay is only replaced by a line that writes it");
check(State.readLine(before, beforeAccounts, "claude", "no-equals-sign").state === before,
      "a line that is not a key/value pair leaves the State untouched");
check(State.readLine(before, beforeAccounts, "nosuchsource", "WEEK_TOKENS=42").state === before,
      "a report for a Source that is not in the registry is ignored");
check(State.readLine(before, beforeAccounts, "claude", "WHAT_IS_THIS=42").state.weekTokens === 0,
      "an unknown key changes nothing");

// --- A Source's own figures ---
const claude = report("claude", [
    "SUBSCRIPTION_TYPE=max",
    "RATE_LIMIT_TIER=20x",
    "EXTRA_USAGE_ENABLED=true",
    "WEEK_TOKENS=1500",
    "MONTH_TOKENS=6000",
    "WEEK_MESSAGES=12",
    "WEEK_SESSIONS=3",
    "TODAY_COST=1.25",
    "WEEK_COST=8.50",
    "MONTH_COST=30.00",
    "DAILY=1,2,3,4,5,6,7",
    "DAILY_COSTS=0.1,0.2,0.3,0.4,0.5,0.6,0.7",
    "WEEK_MODELS=sonnet=100,opus=50",
    "ALLTIME_SESSIONS=9",
    "ALLTIME_MESSAGES=99",
    "FIRST_SESSION=2024-01-01",
    "CREDS_STATUS=ok"
]).state;
check(claude.plan === "max" && claude.planTier === "20x",
      "the subscription and its tier land on the State");
check(claude.extraUsageEnabled === true, "a boolean key is read as a boolean, not a string");
check(claude.weekTokens === 1500 && claude.monthTokens === 6000 &&
      claude.weekMessages === 12 && claude.weekSessions === 3,
      "the week and month figures land as numbers");
check(claude.todayCost === 1.25 && claude.weekCost === 8.5 && claude.monthCost === 30,
      "the cost figures land as numbers");
check(claude.dailyTokens.join(",") === "1,2,3,4,5,6,7" &&
      claude.dailyCosts.join(",") === "0.1,0.2,0.3,0.4,0.5,0.6,0.7",
      "both seven-day series land in order");
check(claude.models.length === 2 && claude.models[0].modelName === "sonnet" &&
      claude.models[0].modelTokens === 100,
      "the model breakdown is read as name and tokens");
check(claude.alltime.sessions === 9 && claude.alltime.messages === 99 &&
      claude.alltime.firstSession === "2024-01-01",
      "the all-time figures land together");
check(report("claude", ["DAILY=1,2,3"]).state.dailyTokens.join(",") === "1,2,3,0,0,0,0",
      "a short series is padded to seven days rather than leaving holes");
check(report("opencode", ["PLAN_TYPE=pro"]).state.plan === "pro",
      "a Source that names its plan PLAN_TYPE lands in the same field as Claude's SUBSCRIPTION_TYPE");

// The currency rate is reported by one Source's Script but read by every
// Source's cost figures, so it lands on the State like any other key and the
// widget derives its global from there. The reader writes nothing but State.
check(report("claude", ["USD_EUR_RATE=0.92"]).state.usdEurRate === 0.92,
      "the currency rate is a State field, not a write into the widget");

// --- Window keys are named by the Descriptor ---
const windows = report("claude", [
    "FIVE_HOUR_UTIL=42.5",
    "FIVE_HOUR_RESET=2099-01-01T00:00:00Z",
    "SEVEN_DAY_UTIL=10"
]).state;
check(windows.primary.util === 42.5 && windows.secondary.util === 10,
      "each Window slot reads the key its Descriptor names");
check(windows.primary.resetMs === Date.parse("2099-01-01T00:00:00Z"),
      "an ISO-8601 reset is normalised to epoch milliseconds");
check(report("claude", ["FIVE_HOUR_RESET=1735689600"]).state.primary.resetMs === 1735689600000,
      "a Unix-seconds reset is normalised to epoch milliseconds");
check(report("claude", ["FIVE_HOUR_RESET=not a date"]).state.primary.resetMs === 0,
      "an unreadable reset leaves no countdown rather than an invalid one");
check(report("chatgpt", ["PRIMARY_WINDOW_SECONDS=18000"]).state.primary.windowSeconds === 18000,
      "a Source that reports its own Window length keeps it on the slot");

// --- The credential status, and the counting behind Hidden ---
const blocked = report("claude", ["BLOCKING_REQUIREMENT=jq,curl", "CREDS_STATUS=blocked"]).state;
check(blocked.credsStatus === "blocked" && blocked.blockingRequirement === "jq,curl",
      "a Blocked report lands with the commands it could not read past");
check(blocked.notInstalledCount === 0,
      "a Blocked report resets the consecutive Not installed count");
const restored = report("claude", ["CREDS_STATUS=ok"], { state: blocked, accounts: {} }).state;
check(restored.blockingRequirement === "" && restored.hasData === true,
      "a restored Source comes back with its reading and no stale command list");
const once = report("claude", ["CREDS_STATUS=not_installed"]).state;
const twice = report("claude", ["CREDS_STATUS=not_installed"], { state: once, accounts: {} }).state;
check(once.hidden === false && once.notInstalledCount === 1,
      "one Not installed report does not hide a Source (ADR 0004)");
check(twice.hidden === true && twice.notInstalledCount === 2,
      "repeated Not installed reports hide the Source");
check(report("claude", ["CREDS_STATUS=missing"]).state.hasData === false,
      "only a good reading counts as data");
const recovered = report("claude", ["CREDS_STATUS=ok"], { state: twice, accounts: {} }).state;
check(recovered.notInstalledCount === 0 && recovered.hidden === false,
      "a good report resets the count and brings the Source back with no restart");

// An endpoint failure reports no Window values, so the last good reading has to
// survive in the State for the status card to mark stale (ADR 0002). A first
// failure has nothing to fall back on, and the tab says so rather than drawing
// a fabricated zero.
const failed = report("claude", ["CREDS_STATUS=unavailable"], { state: restored, accounts: {} }).state;
check(failed.credsStatus === "unavailable" && failed.hasData === true,
      "an endpoint failure is its own status and keeps the last good reading marked as data");
check(failed.primary.util === restored.primary.util && failed.secondary.util === restored.secondary.util,
      "an endpoint failure does not overwrite the Window values with zeros");
check(report("claude", ["CREDS_STATUS=unavailable"]).state.hasData === false,
      "a first endpoint failure reports no reading to fall back on");
check(report("claude", ["CREDS_STATUS=missing"]).state.credsStatus === "missing",
      "a rejected credential is Missing, which is not the same state as Unavailable");

// --- The Account overlay ---
const acct = report("claude", [
    "ACCOUNTS=work,home",
    "ACCOUNT_WEEK_TOKENS=work:900,home:100",
    "ACCOUNT_EXTRA_USAGE=work:true,home:false",
    "ACCOUNT_DAILY=work:1,2,3,4,5,6,7|home:0,0,0,0,0,0,1",
    "ACCOUNT_WEEK_MODELS=work:opus=80|home:sonnet=20",
    "ACCOUNT_SUBSCRIPTION=work:max,home:pro",
    "ACCOUNT_FIVE_HOUR_UTIL=work:60,home:5"
]);
check(acct.state.accounts.join(",") === "work,home",
      "the Account list lands under the key the Descriptor names");
check(acct.accounts.work.weekTokens === 900 && acct.accounts.home.weekTokens === 100,
      "a per-Account number is read per Account");
check(acct.accounts.work.extraUsageEnabled === true && acct.accounts.home.extraUsageEnabled === false,
      "a per-Account boolean is read as a boolean");
check(acct.accounts.work.daily.join(",") === "1,2,3,4,5,6,7",
      "a per-Account series is split on the pipe, so its commas stay its own");
check(acct.accounts.work.weekModels[0].modelName === "opus" &&
      acct.accounts.work.weekModels[0].modelTokens === 80,
      "a per-Account model breakdown is read per Account");
check(acct.accounts.work.subscriptionType === "max" && acct.accounts.work.primaryUtil === 60,
      "a per-Account text field and Window Utilisation land on the overlay");
check(acct.state.weekTokens === 0,
      "a per-Account key writes the overlay, never the Source's own figures");

// --- Rendering a State for a Section ---
check(State.render(null, {}, { selected: "all", todayIndex: 0 }) === null,
      "a Source that has reported nothing renders as null, not as a State of zeroes");
const agg = State.render(claude, {}, { selected: "all", todayIndex: 2 });
check(agg.id === "claude",
      "a State knows which Source it belongs to, so a Section handed one alone still does");
check(agg.weekTokens === 1500 && agg.todayTokens === 3,
      "with no Account selected the aggregate renders, and Today reads the day index given");
const sel = State.render(acct.state, acct.accounts, { selected: "work", todayIndex: 0 });
check(sel.weekTokens === 900, "a selected Account's figures lay over the Source's own");
check(sel.plan === "max", "a selected Account's subscription lays over the Source's own");
check(sel.primary.util === 60, "a selected Account's Window Utilisation lays over the Source's own");
check(sel.todayTokens === 1, "Today follows the selected Account's own series");
check(sel.accountDaily.join(",") === "1,2,3,4,5,6,7",
      "the chart carries the Account's series beside the aggregate it still draws");
check(sel.alltime.sessions === 0,
      "all-time figures are tracked in aggregate only, so a selection shows none");
// An Account can be listed with nothing of its own yet, and an endpoint failure
// omits an Account from the Window lists entirely. Neither is a reading of
// zero: what the Account has not reported stays the Source's own figure, and
// what it reported before stays its own.
const sparse = report("claude", ["ACCOUNT_CREDS_STATUS=spare:missing"], acct);
const spare = State.render(
    report("claude", ["ACCOUNTS=work,home,spare"], sparse).state,
    sparse.accounts, { selected: "spare", todayIndex: 0 });
check(spare.primary.util === acct.state.primary.util,
      "an Account with no Window reading of its own shows the Source's");
const omitted = report("claude", ["ACCOUNT_FIVE_HOUR_UTIL=home:9"], acct);
check(omitted.accounts.work.primaryUtil === 60,
      "an Account omitted from a run keeps its last good reading rather than reading the silence as zero");

const ghost = State.render(acct.state, acct.accounts, { selected: "deleted-one", todayIndex: 0 });
check(ghost.weekTokens === acct.state.weekTokens && ghost.accountDaily === undefined,
      "a selection the Source no longer lists falls back to the aggregate rather than a ghost overlay");

// --- Whether the Pill has a reading to draw ---
check(State.hasCurrentReading({ credsStatus: "ok" }) === true,
      "a Source with a good reading draws its ring");
check(State.hasCurrentReading({ credsStatus: "unknown" }) === true,
      "a Source that has not reported yet draws at zero rather than flickering");
check(State.hasCurrentReading({ credsStatus: "blocked", hasData: true }) === false,
      "a Blocked Source draws a hollow ring even with a last-good reading kept (ADR 0002)");
check(State.hasCurrentReading({ credsStatus: "missing" }) === false,
      "a Missing Source draws a hollow ring rather than a zero");
check(State.hasCurrentReading({ credsStatus: "unavailable" }) === false,
      "an Unavailable Source draws a hollow ring rather than a stale-looking zero");
check(State.hasCurrentReading({ credsStatus: "expired" }) === false,
      "expired credentials draw no reading");
check(State.hasCurrentReading(undefined) === true,
      "a Source before its first fetch keeps its ring");

// The two reading questions, side by side. The Pill asks whether the reading is
// current; the registry asks whether there is one to draw at all, and a
// last-good reading survives a degraded report for the surfaces that mark it
// stale (ADR 0002).
check(Sources.hasReading({ credsStatus: "unavailable", hasData: true }) === true &&
      State.hasCurrentReading({ credsStatus: "unavailable", hasData: true }) === false,
      "the Pill keeps its hollow ring for a degraded Source the other surfaces draw stale");
check(Sources.hasReading({ credsStatus: "not_installed", hasData: false }) === false,
      "a Not installed Source with no reading has nothing for any surface to draw");

console.log(results.join("\n"));
NODE

while IFS=$'\t' read -r status label; do
    [ -z "${status:-}" ] && continue
    if [ "$status" = "PASS" ]; then
        pass "$label"
    else
        fail "$label"
    fi
done < /tmp/source-state-report.txt

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
    fail "source-state report produced no results (node failed?) see /tmp/source-state-report.txt"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
