.pragma library

.import "sources.js" as Sources

// One Source's State: what its Script's reports leave behind, and how a Section
// reads it back.
//
// The report format is the contract between the Scripts and every surface that
// draws them, so it has one reader here rather than one per surface. The widget
// owns where a State lives - a QML property keyed by Source id - and this owns
// what is in it.
//
// Everything here is pure. readLine() returns new objects rather than writing
// the ones it was given, because a QML property has to be reassigned for its
// bindings to re-evaluate, and because a pure reader can be run line by line in
// a test without a widget around it.

// --- Building a State ---

// A Source that has reported nothing. The status is "unknown" rather than a
// failure: before the first fetch there is nothing to say, and the Pill draws
// at zero rather than flickering through a missing state it was never in.
function empty() {
    return {
        credsStatus: "unknown",
        // The Requirements the Script could not read past, as its
        // BLOCKING_REQUIREMENT report left them. Empty for every state but a
        // Blocked one, and cleared as soon as the Source reports anything else.
        blockingRequirement: "",
        // Consecutive Not installed reports, and the hidden decision they
        // drive. In-memory only: a restart clears them, so every enabled
        // Source shows until its first fetch lands (ADR 0004).
        notInstalledCount: 0,
        hidden: false,
        // True once a fetch has reported a good reading. An endpoint failure
        // with nothing to fall back on shows no Window cards at all rather
        // than a fabricated zero.
        hasData: false,
        plan: "",
        planTier: "",
        extraUsageEnabled: false,
        primary: { util: 0, resetMs: 0, windowSeconds: 0 },
        secondary: { util: 0, resetMs: 0, windowSeconds: 0 },
        weekTokens: 0,
        monthTokens: 0,
        weekCalls: 0,
        weekMessages: 0,
        weekSessions: 0,
        todayCost: 0,
        weekCost: 0,
        monthCost: 0,
        // The currency rate one Script reports and every Source's cost figures
        // are read through. It lands here like any other key; deriving the one
        // the whole widget uses is the widget's job.
        usdEurRate: 0,
        dailyTokens: [0, 0, 0, 0, 0, 0, 0],
        dailyCosts: [0, 0, 0, 0, 0, 0, 0],
        models: [],
        alltime: { sessions: 0, messages: 0, firstSession: "" },
        accounts: []
    };
}

// Whether a State holds a reading the Pill's Ring can draw. This is the
// narrower of the two reading questions: it asks whether the reading is
// current, so a degraded Source goes hollow even when a last-good reading is
// kept for the Window card and the Overview bar (ADR 0002). The broader
// question - is there anything at all to draw - is Sources.hasReading().
function hasCurrentReading(state) {
    if (!state)
        return true;
    return state.credsStatus === "ok" || state.credsStatus === "unknown";
}

// --- Reading a report ---

// One line of one Source's report. Returns the State and the Account overlay
// map the line produced, both new objects, so the caller can publish them
// whole. `accounts` is this Source's own map of Account name to overlay; the
// id-keyed map of every Source's is the caller's.
//
// A line that is not a key/value pair, names a Source the registry does not
// know, or carries a key nothing reads, changes nothing and is returned as it
// came in.
function readLine(state, accounts, id, line) {
    var result = { state: state, accounts: accounts || {} };
    var pair = Sources.wirePair(line);
    if (!pair)
        return result;
    var d = Sources.byId(id);
    if (!d)
        return result;

    // Every key that belongs to an Account is named by the descriptor: the
    // list of Accounts, the two Window slots' Account keys, and the rest of
    // the Account overlay fields. They write the overlay rather than the
    // Source's own figures, so they are dispatched before the switch below.
    if (d.accounts && pair.key === d.accounts.listKey)
        return { state: withState(result.state, id, function (st) {
            st.accounts = Sources.splitList(pair.value);
        }), accounts: result.accounts };

    var window = readWindowKey(result, d, id, pair.key, pair.value);
    if (window)
        return window;
    var account = readAccountKey(result, d, pair.key, pair.value);
    if (account)
        return account;

    return {
        state: withState(result.state, id, function (st) {
            readSourceKey(st, pair.key, pair.value);
        }),
        accounts: result.accounts
    };
}

// A Source's own figures. Returns nothing: it writes the copy it is handed.
function readSourceKey(st, key, val) {
    switch (key) {
    case "PLAN_TYPE":
    case "SUBSCRIPTION_TYPE":
        st.plan = val;
        break;
    case "RATE_LIMIT_TIER":
        st.planTier = val;
        break;
    case "EXTRA_USAGE_ENABLED":
        st.extraUsageEnabled = (val === "true");
        break;
    case "CREDS_STATUS":
        applyCredsStatus(st, val);
        break;
    case "BLOCKING_REQUIREMENT":
        st.blockingRequirement = val;
        break;
    case "WEEK_MESSAGES":
        st.weekMessages = parseInt(val) || 0;
        break;
    case "WEEK_SESSIONS":
        st.weekSessions = parseInt(val) || 0;
        break;
    case "WEEK_CALLS":
        st.weekCalls = parseInt(val) || 0;
        break;
    case "WEEK_TOKENS":
        st.weekTokens = parseFloat(val) || 0;
        break;
    case "MONTH_TOKENS":
        st.monthTokens = parseFloat(val) || 0;
        break;
    case "ALLTIME_SESSIONS":
        st.alltime = Object.assign({}, st.alltime, { sessions: parseInt(val) || 0 });
        break;
    case "ALLTIME_MESSAGES":
        st.alltime = Object.assign({}, st.alltime, { messages: parseInt(val) || 0 });
        break;
    case "FIRST_SESSION":
        st.alltime = Object.assign({}, st.alltime, { firstSession: val });
        break;
    case "WEEK_MODELS":
        st.models = parseModels(val);
        break;
    case "DAILY":
        st.dailyTokens = parseDaily(val);
        break;
    case "DAILY_COSTS":
        st.dailyCosts = parseDaily(val);
        break;
    case "TODAY_COST":
        st.todayCost = parseFloat(val) || 0;
        break;
    case "WEEK_COST":
        st.weekCost = parseFloat(val) || 0;
        break;
    case "MONTH_COST":
        st.monthCost = parseFloat(val) || 0;
        break;
    case "USD_EUR_RATE":
        st.usdEurRate = parseFloat(val) || 0;
        break;
    }
}

// Applies a CREDS_STATUS value. This is the one place a Source-level report
// lands, so it is where the consecutive Not installed count and the hidden
// decision it drives are updated. A good reading is the only thing that counts
// as data; an endpoint failure reports no Window values, so the last good
// reading survives in State and the status card above it marks those values as
// stale rather than current.
function applyCredsStatus(st, val) {
    st.credsStatus = val;
    // A Blocked report is the only one that names Requirements, so any other
    // report clears the list a previous Blocked one left behind. A restored
    // command brings the Source back with no stale commands to name.
    if (val !== Sources.BLOCKED)
        st.blockingRequirement = "";
    st.notInstalledCount = Sources.nextNotInstalledCount(st.notInstalledCount, val);
    st.hidden = Sources.isHidden(st.notInstalledCount);
    if (val === "ok")
        st.hasData = true;
}

// The Window slot keys a Source declares in its descriptor. Returns the new
// pair when the key was one of them, and null otherwise.
function readWindowKey(result, d, id, key, val) {
    var slots = ["primary", "secondary"];
    for (var i = 0; i < slots.length; i++) {
        var which = slots[i];
        var w = d.windows[which];
        if (!w)
            continue;
        var field = null;
        var value = null;
        if (key === w.util) {
            field = "util";
            value = parseFloat(val) || 0;
        } else if (key === w.reset) {
            field = "resetMs";
            value = parseResetMs(val);
        } else if (w.windowSecondsKey && key === w.windowSecondsKey) {
            field = "windowSeconds";
            value = parseFloat(val) || 0;
        }
        if (!field)
            continue;
        return {
            state: withState(result.state, id, function (st) {
                st[which] = Object.assign({ util: 0, resetMs: 0, windowSeconds: 0 }, st[which]);
                st[which][field] = value;
            }),
            accounts: result.accounts
        };
    }
    return null;
}

// The per-Account output keys a Source declares in its descriptor's
// `accounts.fields` map. The field names are the overlay's own, so no Source's
// Window shape leaks into this reader. Returns the new pair when the key was
// one of them, and null otherwise.
function readAccountKey(result, d, key, val) {
    var spec = d.accounts && d.accounts.fields ? d.accounts.fields[key] : null;
    if (!spec)
        return null;

    var values;
    if (spec.type === "series")
        values = Sources.nameValueMap(val.split("|"), parseDaily);
    else if (spec.type === "models")
        values = Sources.nameValueMap(val.split("|"), parseModels);
    else
        values = Sources.nameValueMap(Sources.splitList(val));

    var next = {};
    for (var name in result.accounts)
        next[name] = result.accounts[name];
    for (var who in values) {
        var overlay = Object.assign({}, next[who] || {});
        overlay[spec.field] = readAccountValue(spec.type, values[who]);
        next[who] = overlay;
    }
    return { state: result.state, accounts: next };
}

function readAccountValue(type, value) {
    if (type === "number")
        return parseFloat(value) || 0;
    if (type === "boolean")
        return value === "true";
    return value;
}

// --- Wire value readers ---

// A seven-day series, padded rather than left short: a Source that reports
// fewer days has empty ones, not missing ones.
function parseDaily(val) {
    var parts = String(val).split(",");
    var arr = [];
    for (var i = 0; i < 7; i++)
        arr.push(i < parts.length ? (parseFloat(parts[i]) || 0) : 0);
    return arr;
}

// "model=123,model2=456" - one Source's model breakdown.
function parseModels(val) {
    var out = [];
    if (!val || val.length === 0)
        return out;
    var pairs = String(val).split(",");
    for (var i = 0; i < pairs.length; i++) {
        var eq = pairs[i].indexOf("=");
        if (eq >= 0)
            out.push({
                modelName: pairs[i].substring(0, eq),
                modelTokens: parseInt(pairs[i].substring(eq + 1)) || 0
            });
    }
    return out;
}

// Unix-seconds strings are all-digit; ISO-8601 strings always contain a
// non-digit (dashes, "T", colons), so a digit-only test tells them apart.
function parseResetMs(val) {
    if (!val)
        return 0;
    if (/^[0-9]+$/.test(val))
        return parseFloat(val) * 1000;
    var ms = new Date(val).getTime();
    return isNaN(ms) ? 0 : ms;
}

// A copy of the State with one mutation applied, stamped with the Source it
// belongs to so a surface handed a State alone still knows whose it is.
function withState(state, id, mutate) {
    var st = Object.assign({}, state || empty());
    st.id = id;
    mutate(st);
    return st;
}

// --- Rendering a State ---

// The State a Section renders: the Source's own figures, with the selected
// Account's laid over them when one is selected. `opts` carries what the caller
// knows and the State does not - which Account is selected, and which day of
// the week is today - so neither becomes stale data parsed into the State.
//
// Returns null for a Source that has reported nothing, so a Section can tell
// nothing-read-yet from a State of zeroes.
function render(state, accounts, opts) {
    if (!state)
        return null;
    var options = opts || {};
    var st = Object.assign({}, state);

    // A selection the Source no longer lists is resolved back to the aggregate
    // rather than drawn as an empty overlay: an Account can disappear between
    // one report and the next, and the values on screen must still be someone's.
    var selected = options.selected || "all";
    if (selected !== "all" && (state.accounts || []).indexOf(selected) < 0)
        selected = "all";
    var pd = selected !== "all" ? (accounts || {})[selected] : null;

    if (pd) {
        overlayScalars(st, pd);
        st.primary = overlayWindow(state.primary, pd.primaryUtil, pd.primaryReset);
        st.secondary = overlayWindow(state.secondary, pd.secondaryUtil, pd.secondaryReset);
        // The daily chart keeps the aggregate in dailyTokens and dailyCosts,
        // so its grey bars stay the total and the cost tooltip stays the day
        // total, and carries the Account's own series separately for the
        // coloured share.
        st.accountDaily = pd.daily || [];
        st.models = pd.weekModels || [];
        // All-time figures are only tracked in aggregate.
        st.alltime = { sessions: 0, messages: 0, firstSession: "" };
    }

    // The Today figure follows the selected Account when there is one, and
    // the aggregate otherwise.
    var todaySeries = pd && pd.daily ? pd.daily : st.dailyTokens;
    st.todayTokens = (todaySeries && todaySeries[options.todayIndex || 0]) || 0;
    return st;
}

// The overlay fields that replace a Source's own figure one for one. A field
// the Account did not report leaves the Source's own standing.
var OVERLAY_SCALARS = [
    { from: "weekTokens", to: "weekTokens" },
    { from: "monthTokens", to: "monthTokens" },
    { from: "weekMessages", to: "weekMessages" },
    { from: "weekSessions", to: "weekSessions" },
    { from: "todayCost", to: "todayCost" },
    { from: "weekCost", to: "weekCost" },
    { from: "monthCost", to: "monthCost" },
    { from: "subscriptionType", to: "plan" },
    { from: "rateLimitTier", to: "planTier" },
    { from: "credsStatus", to: "credsStatus" },
    { from: "extraUsageEnabled", to: "extraUsageEnabled" }
];

function overlayScalars(st, pd) {
    for (var i = 0; i < OVERLAY_SCALARS.length; i++) {
        var row = OVERLAY_SCALARS[i];
        if (pd[row.from] !== undefined)
            st[row.to] = pd[row.from];
    }
}

// One Window slot under a selection. The length stays the Source's: a Window is
// the same length whoever is spending it, and only the Utilisation and the reset
// are the Account's own.
function overlayWindow(base, util, reset) {
    var b = base || { util: 0, resetMs: 0, windowSeconds: 0 };
    return {
        util: util !== undefined ? util : b.util,
        resetMs: reset !== undefined ? parseResetMs(reset) : b.resetMs,
        windowSeconds: b.windowSeconds
    };
}
