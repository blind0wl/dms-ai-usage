.pragma library

// The Source registry. Every Source the plugin can show is one entry here, and
// the pill, popout tabs and settings rows are generated from this list.
//
// Field notes:
//   id            Stable key. Persisted in settings, so never change one.
//   windows.*     Which script output keys feed each Window slot. Descriptors
//                 name keys rather than requiring one shared output contract,
//                 so the scripts keep emitting what they already emit.
//   accounts      How this Source's Account selector works, if it has one.
//   login         How this Source offers to fix missing credentials, if it can.
//   sections      Ordered Sections making up the popout tab.

// The per-Account output keys a Source may emit, keyed by the unprefixed
// concept, and the overlay field each fills plus how to read it. Declared as
// data so no Source's Window shape is baked into the widget's Account adapter.
// A descriptor picks the subset it emits with pickFields() and declares the
// prefix its own wire keys wear, so the two prefixes share one row per concept.
var ACCOUNT_FIELDS = {
    SUBSCRIPTION: { field: "subscriptionType", type: "text" },
    TIER: { field: "rateLimitTier", type: "text" },
    CREDS_STATUS: { field: "credsStatus", type: "text" },
    WEEK_TOKENS: { field: "weekTokens", type: "number" },
    MONTH_TOKENS: { field: "monthTokens", type: "number" },
    WEEK_MESSAGES: { field: "weekMessages", type: "number" },
    WEEK_SESSIONS: { field: "weekSessions", type: "number" },
    TODAY_COST: { field: "todayCost", type: "number" },
    WEEK_COST: { field: "weekCost", type: "number" },
    MONTH_COST: { field: "monthCost", type: "number" },
    EXTRA_USAGE: { field: "extraUsageEnabled", type: "boolean" },
    DAILY: { field: "daily", type: "series" },
    DAILY_COSTS: { field: "dailyCosts", type: "series" },
    WEEK_MODELS: { field: "weekModels", type: "models" },
    // Two genuinely different wire names for the same slot, not a prefix pair.
    FIVE_HOUR_UTIL: { field: "primaryUtil", type: "number" },
    FIVE_HOUR_RESET: { field: "primaryReset", type: "text" },
    SEVEN_DAY_UTIL: { field: "secondaryUtil", type: "number" },
    SEVEN_DAY_RESET: { field: "secondaryReset", type: "text" },
    PRIMARY_UTIL: { field: "primaryUtil", type: "number" },
    PRIMARY_RESET: { field: "primaryReset", type: "text" },
    SECONDARY_UTIL: { field: "secondaryUtil", type: "number" },
    SECONDARY_RESET: { field: "secondaryReset", type: "text" }
};

// Builds a descriptor's wire-key map from its prefix and the bare suffixes its
// script emits. An unknown suffix would otherwise be copied through as
// undefined and dropped from the wire with nothing to show for it, so the full
// wire key is named here instead.
function pickFields(id, prefix, suffixes) {
    var out = {};
    for (var i = 0; i < suffixes.length; i++) {
        var key = prefix + suffixes[i];
        var spec = ACCOUNT_FIELDS[suffixes[i]];
        if (!spec)
            console.warn("sources.js: descriptor \"" + id + "\" declares Account key " + key + " with no ACCOUNT_FIELDS row for suffix \"" + suffixes[i] + "\"");
        out[key] = spec;
    }
    return out;
}

// The origin tag a Source's Script puts on an Account it took from the Custom
// Account list rather than detecting. Every other origin names where the
// credential was found: a file's path, or an environment variable's name. Both
// are the user's own words for it, so they are shown as they come.
var CUSTOM_ORIGIN = "custom";

// What a Script is asked for when the settings page wants its Account list and
// the origins behind it, without any usage fetch. Detection is the Script's
// own, so the settings editor asks it rather than re-deriving it: a second
// implementation could disagree with the selector about what exists.
var LIST_ACCOUNTS_FLAG = "--list-accounts";

// The path to a Source's Script under the plugin directory DMS installs plugins
// in. Built here rather than at each call site because the widget's fetch and
// the settings editor's listing call have to reach the same file.
function scriptPath(pluginDirectory, pluginId, descriptor) {
    if (!pluginDirectory || !pluginId || !descriptor || !descriptor.script)
        return "";
    return pluginDirectory + "/" + pluginId + "/" + descriptor.script;
}

// Builds the "name=value" arguments a Source's Script is invoked with, one per
// Account in the settings list that carries both halves. The descriptor's
// argField says whether the value is a config directory or an API key.
//
// The widget's fetch and the settings editor's listing both build their
// arguments here, because the Script keeps the first registration of a name or
// of a value: different arguments could list an Account under a name the
// selector does not show it under, which is the disagreement this whole path
// exists to avoid.
function accountArgs(descriptor, list) {
    if (!descriptor || !descriptor.accounts || !Array.isArray(list))
        return [];
    var field = descriptor.accounts.argField;
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var a = list[i];
        if (a && a.name && a[field])
            out.push(a.name + "=" + a[field]);
    }
    return out;
}

// The Accounts a Source's Script reports from outside the Custom Account list,
// in the order the Script reported them, each with the place it was detected.
// These are the Accounts the Popout's selector offers and the settings editor
// cannot edit - plus, marked `overridden`, the detected registrations the Script
// refused because a Custom Account had already taken their name or their value.
//
// `names` is the Script's Account list (the descriptor's listKey), `origins` its
// "name:origin" pairs (its originsKey) and `shadowed` the registrations it
// refused (its shadowedKey), all comma-separated as the wire has them. A refused
// registration is "<winner>|<name>:<origin>": what kept the name or the value,
// then what lost and where it came from. An Account the Custom Account list
// provided is reported with the CUSTOM_ORIGIN tag and dropped from the first
// list: it is the editor's own row already.
//
// An overridden registration matters as much as a live one. The Script keeps the
// first registration of a name or of a value, so a Custom Account that takes a
// detected one's place changes which credential the Source authenticates with,
// and the user has to be able to see that rather than meeting it as a rejected
// key. The winner is carried so the editor can name it: on a clash of values the
// two names differ, and a row that only says "a Custom Account" would leave the
// user guessing which of their rows did it.
//
// An Account the Script lists without an origin is still reported, with an empty
// origin. It is detected - the Custom Account list did not provide it - and
// dropping it would put the selector and the editor back where they started,
// which is worse than admitting the Script did not say where it found it.
function detectedAccounts(names, origins, shadowed) {
    var listed = splitList(names);
    var byName = originsByName(origins);

    var out = [];
    for (var i = 0; i < listed.length; i++) {
        var name = listed[i];
        var known = Object.prototype.hasOwnProperty.call(byName, name);
        if (known && byName[name] === CUSTOM_ORIGIN)
            continue;
        out.push({ name: name, origin: known ? byName[name] : "", overridden: false, winner: "" });
    }

    var pairs = splitList(shadowed);
    for (var j = 0; j < pairs.length; j++) {
        var entry = pairs[j];
        var bar = entry.indexOf("|");
        var winner = bar < 0 ? "" : entry.substring(0, bar);
        var lost = bar < 0 ? entry : entry.substring(bar + 1);
        var at = lost.indexOf(":");
        if (at < 0)
            continue;
        var lostName = lost.substring(0, at);
        var lostOrigin = lost.substring(at + 1);
        // A Custom Account the Script refused is the editor's own row's business,
        // and a detected Account still registered under that name was not lost.
        if (lostOrigin === CUSTOM_ORIGIN)
            continue;
        var live = Object.prototype.hasOwnProperty.call(byName, lostName);
        if (live && byName[lostName] !== CUSTOM_ORIGIN)
            continue;
        out.push({ name: lostName, origin: lostOrigin, overridden: true, winner: winner });
    }
    return out;
}

// The origin of the detected Account a Custom Account row displaced, or "" when
// the row displaced nothing. `detected` is what detectedAccounts() returned, so
// the two lists cannot disagree about which row is authenticating instead.
function displacedOrigin(detected, name) {
    for (var i = 0; Array.isArray(detected) && i < detected.length; i++) {
        if (detected[i].overridden && detected[i].winner === name)
            return detected[i].origin;
    }
    return "";
}

// The detected Account that kept the name or the value a Custom Account row was
// refused for, or null when no detected Account did: the row's registration can
// also be refused for something the Script cannot name, such as a config
// directory that does not exist, or because another Custom row took the name.
// `origins` and `shadowed` are the Script's own listing, so the Account this
// names is the one the Source authenticates with in the row's place.
function shadowingAccount(origins, shadowed, name) {
    var byName = originsByName(origins);
    var pairs = splitList(shadowed);
    for (var i = 0; i < pairs.length; i++) {
        var bar = pairs[i].indexOf("|");
        if (bar < 0)
            continue;
        var winner = pairs[i].substring(0, bar);
        var lost = pairs[i].substring(bar + 1);
        var at = lost.indexOf(":");
        if (at < 0)
            continue;
        // Only the registration the Custom row itself asked for is its business.
        if (lost.substring(0, at) !== name || lost.substring(at + 1) !== CUSTOM_ORIGIN)
            continue;
        var origin = Object.prototype.hasOwnProperty.call(byName, winner) ? byName[winner] : "";
        if (origin === "" || origin === CUSTOM_ORIGIN)
            return null;
        return { name: winner, origin: origin };
    }
    return null;
}

// The rows of a Custom Account list a Script did not register, by their index in
// that list, so the editor marks a row rather than a name: two rows can carry the
// same name, and only the first of them is one the Script kept. The Popout's
// selector offers only what the Script kept, so these rows do nothing - the
// Script resolves the clash by keeping the first registration of a name or of a
// value, and only it can say which those were, which is why its listing reports
// where every Account came from.
//
// `list` is the Custom Account list from the plugin settings, the form the
// editor holds it in.
//
// A Script that reports no Account at all resolves no clash, so it is given no
// verdict to hand out: that is an uninstalled Source, a listing still in flight,
// or a Script that failed. Blaming the user's rows for a Source that never
// registered an Account would be the same lie as calling a failed listing an
// empty one.
function unregisteredRows(names, origins, list) {
    var listed = splitList(names);
    if (listed.length === 0)
        return [];
    var byName = originsByName(origins);
    var seen = {};
    var out = [];
    for (var i = 0; Array.isArray(list) && i < list.length; i++) {
        var row = list[i];
        if (!row || !row.name)
            continue;
        // A name the Script registered as a Custom Account is the one the
        // selector offers, and only its first row is that registration.
        var first = !Object.prototype.hasOwnProperty.call(seen, row.name);
        seen[row.name] = true;
        var kept = first && listed.indexOf(row.name) >= 0 && byName[row.name] === CUSTOM_ORIGIN;
        if (!kept)
            out.push(i);
    }
    return out;
}

// One comma-separated wire list as an array. An absent or empty value is no
// entries rather than one empty one.
function splitList(value) {
    if (typeof value !== "string" || value.length === 0)
        return [];
    return value.split(",");
}

// One comma-separated origin list as a name -> origin map. A pair with no colon
// names no origin, so it is skipped rather than guessed at.
function originsByName(origins) {
    return nameValueMap(splitList(origins));
}

// One "name:value" entry list as a name -> value map. The Scripts' per-Account
// keys, their origins and their model breakdowns all wear this shape, so it is
// parsed in one place; only the separator differs by key, and the caller splits
// on its own. `mapValue` transforms each value on the way in, for a value that is
// itself a list. An entry with no colon names no value, so it is skipped rather
// than guessed at.
function nameValueMap(entries, mapValue) {
    var out = {};
    for (var i = 0; Array.isArray(entries) && i < entries.length; i++) {
        var at = entries[i].indexOf(":");
        if (at < 0)
            continue;
        var value = entries[i].substring(at + 1);
        out[entries[i].substring(0, at)] = mapValue ? mapValue(value) : value;
    }
    return out;
}

// The command that runs a Source's Script: a watchdog around bash, because a run
// that never exits (a hung CLI, a stalled curl) would otherwise leave a fetch or
// a settings page waiting on it. Built here so the widget's fetch and the
// settings editor's listing are started the same way, `args` being whatever that
// caller passes the Script.
function scriptCommand(pluginDirectory, pluginId, descriptor, args) {
    return ["timeout", "120", "bash", scriptPath(pluginDirectory, pluginId, descriptor)].concat(args || []);
}

// One line of a Script's output split into its key and its value, or null when
// the line carries no "=". Both the widget's fetch parser and the settings
// editor's listing parser read the same wire, so they split it the same way.
function wirePair(line) {
    if (!line)
        return null;
    var at = line.indexOf("=");
    if (at < 0)
        return null;
    return { key: line.substring(0, at), value: line.substring(at + 1) };
}

var SOURCES = [
    {
        id: "claude",
        labelKey: "Claude",
        script: "get-claude-usage",
        // Claude's script reports its Windows under different names and emits
        // ISO-8601 reset strings. The parser normalises both to epoch ms.
        // It reports no window length, so the fixed 5h and 7d lengths are
        // declared here instead; the others read theirs from their script.
        windows: {
            primary: {
                util: "FIVE_HOUR_UTIL",
                reset: "FIVE_HOUR_RESET",
                windowSeconds: 18000,
                labelKey: "5h Rate Window"
            },
            secondary: {
                util: "SEVEN_DAY_UTIL",
                reset: "SEVEN_DAY_RESET",
                windowSeconds: 604800,
                labelKey: "7-Day Usage"
            }
        },
        accounts: {
            settingKey: "customProfiles",
            // Claude lists its Accounts under PROFILES; every other Source uses
            // ACCOUNTS. The widget reads whichever the descriptor names.
            listKey: "PROFILES",
            // Where each Profile was found, one "name:origin" pair per entry.
            // The settings editor reads it to show what it does not own.
            originsKey: "PROFILE_ORIGINS",
            // The registrations the Script refused, one "name:origin" pair per
            // entry. A Custom Profile that took a detected one's place is here,
            // and the editor shows the detected one as overridden by it.
            shadowedKey: "PROFILE_SHADOWED",
            // What the editor calls that state on Claude's page, where an
            // Account is a Profile throughout the copy.
            overriddenKey: "overridden by your Custom Profile",
            // The heading the settings editor gives the read-only list of what
            // the Script found. It follows the Source's own word for an
            // Account, so Claude's page says Profiles throughout.
            detectedTitleKey: "Detected Profiles",
            // Claude's per-Account keys keep PROFILE_ because get-claude-usage
            // is upstream's file and those names are its existing output
            // contract. Every other Source declares ACCOUNT_, the general term
            // CONTEXT.md reserves over Profile.
            keyPrefix: "PROFILE_",
            argField: "path",
            labelKey: "Profile",
            overlay: true,
            titleKey: "Custom Profiles",
            descriptionKey: "Track extra Claude config directories. Point at a CLAUDE_CONFIG_DIR (the folder containing projects/). ~/.claude, Claude Code Switcher and claude-code-profiles are detected automatically.",
            fieldLabelKey: "Config directory",
            placeholder: "~/.ccp/data/work",
            fields: pickFields("claude", "PROFILE_", [
                "SUBSCRIPTION", "TIER", "CREDS_STATUS",
                "WEEK_TOKENS", "MONTH_TOKENS", "WEEK_MESSAGES",
                "WEEK_SESSIONS", "TODAY_COST", "WEEK_COST",
                "MONTH_COST", "EXTRA_USAGE", "DAILY",
                "DAILY_COSTS", "WEEK_MODELS",
                "FIVE_HOUR_UTIL", "FIVE_HOUR_RESET",
                "SEVEN_DAY_UTIL", "SEVEN_DAY_RESET"
            ])
        },
        login: {
            kind: "cli",
            program: "claude",
            args: ["auth", "login", "--claudeai"],
            // The selected Account's config directory is exported for the CLI,
            // so logging into one Account does not touch another.
            env: {
                variable: "CLAUDE_CONFIG_DIR",
                accountField: "path"
            }
        },
        planStyle: "subscription",
        sections: [
            { type: "header" },
            { type: "accounts" },
            { type: "login" },
            { type: "windows", which: "primary" },
            { type: "windows", which: "secondary", counts: true },
            {
                type: "stats",
                columns: [
                    {
                        labelKey: "Today",
                        value: { kind: "tokens", key: "todayTokens" },
                        sub: { kind: "cost", key: "todayCost" },
                        accent: true
                    },
                    {
                        labelKey: "Week",
                        value: { kind: "tokens", key: "weekTokens" },
                        sub: { kind: "cost", key: "weekCost" }
                    },
                    {
                        labelKey: "Month",
                        value: { kind: "tokens", key: "monthTokens" },
                        sub: { kind: "cost", key: "monthCost" }
                    }
                ]
            },
            { type: "chart", overlay: true },
            { type: "models", nameStyle: "short" },
            { type: "alltime" }
        ]
    },
    {
        id: "chatgpt",
        labelKey: "ChatGPT",
        script: "get-chatgpt-usage",
        windows: {
            primary: {
                util: "PRIMARY_UTIL",
                reset: "PRIMARY_RESET",
                windowSecondsKey: "PRIMARY_WINDOW_SECONDS"
            },
            secondary: {
                util: "SECONDARY_UTIL",
                reset: "SECONDARY_RESET",
                windowSecondsKey: "SECONDARY_WINDOW_SECONDS"
            }
        },
        accounts: {
            settingKey: "customChatgptAccounts",
            listKey: "ACCOUNTS",
            originsKey: "ACCOUNT_ORIGINS",
            shadowedKey: "ACCOUNT_SHADOWED",
            overriddenKey: "overridden by your Custom Account",
            detectedTitleKey: "Detected Accounts",
            keyPrefix: "ACCOUNT_",
            argField: "path",
            labelKey: "Account",
            titleKey: "Custom ChatGPT Accounts",
            descriptionKey: "Track extra Codex accounts. Point at a CODEX_HOME (the folder containing auth.json). ~/.codex is detected automatically as \"default\".",
            fieldLabelKey: "Config directory",
            placeholder: "~/.codex-work",
            fields: pickFields("chatgpt", "ACCOUNT_", [
                "SUBSCRIPTION", "CREDS_STATUS", "WEEK_TOKENS",
                "MONTH_TOKENS", "WEEK_MESSAGES", "WEEK_SESSIONS",
                "DAILY", "WEEK_MODELS",
                "PRIMARY_UTIL", "PRIMARY_RESET",
                "SECONDARY_UTIL", "SECONDARY_RESET"
            ])
        },
        login: {
            kind: "cli",
            program: "codex",
            args: ["login"]
        },
        planStyle: "plan",
        sections: [
            { type: "header" },
            { type: "accounts" },
            { type: "login" },
            { type: "windows", which: "primary" },
            { type: "windows", which: "secondary" },
            {
                type: "stats",
                columns: [
                    {
                        labelKey: "Week",
                        value: { kind: "tokens", key: "weekTokens" },
                        accent: true
                    },
                    {
                        labelKey: "Month",
                        value: { kind: "tokens", key: "monthTokens" }
                    },
                    {
                        labelKey: "This Week",
                        value: { kind: "count", key: "weekSessions", unitKey: "sessions" },
                        sub: { kind: "count", key: "weekMessages", unitKey: "msgs" },
                        text: true
                    }
                ]
            },
            { type: "chart" },
            { type: "models", nameStyle: "short" },
            { type: "alltime" }
        ]
    },
    {
        id: "opencode",
        labelKey: "opencode Go",
        script: "get-opencode-go-usage",
        // The endpoint reports ISO-8601 reset times and no window length, so
        // the fixed 5h and 7d lengths are declared here for Pacing. Its two
        // windows are the response's `rolling` and `weekly` entries; the
        // response's `monthly` entry is not modelled.
        windows: {
            primary: {
                util: "PRIMARY_UTIL",
                reset: "PRIMARY_RESET",
                windowSeconds: 18000,
                labelKey: "5h Window"
            },
            secondary: {
                util: "SECONDARY_UTIL",
                reset: "SECONDARY_RESET",
                windowSeconds: 604800,
                labelKey: "Weekly Window"
            }
        },
        accounts: {
            // opencode Go is keyed rather than directory-backed, so Accounts
            // are passed to the script as name=api-key, like Z.ai.
            settingKey: "customOpencodeAccounts",
            listKey: "ACCOUNTS",
            originsKey: "ACCOUNT_ORIGINS",
            shadowedKey: "ACCOUNT_SHADOWED",
            overriddenKey: "overridden by your Custom Account",
            detectedTitleKey: "Detected Accounts",
            keyPrefix: "ACCOUNT_",
            argField: "key",
            labelKey: "Account",
            titleKey: "Custom opencode Accounts",
            descriptionKey: "Track extra opencode Go Accounts by API key. An API key from the pi coding agent auth store (~/.pi/agent/auth.json) is detected automatically as \"default\".",
            fieldLabelKey: "API key",
            placeholder: "",
            fields: pickFields("opencode", "ACCOUNT_", [
                "CREDS_STATUS",
                "PRIMARY_UTIL", "PRIMARY_RESET",
                "SECONDARY_UTIL", "SECONDARY_RESET"
            ])
        },
        login: {
            // There is no CLI login flow to shell out to, and the opencode
            // binary is not required. The fix is an API key in the settings.
            kind: "text",
            titleKey: "API key rejected",
            bodyKey: "Check your opencode Go key in the plugin settings."
        },
        // The endpoint is undocumented, so it can fail in ways the user cannot
        // fix. That state gets its own card, deliberately without a settings
        // pointer, and the Window cards stay as the last known values.
        status: {
            titleKey: "Usage endpoint unavailable",
            bodyKey: "opencode's usage endpoint could not be reached. Showing the last known values.",
            emptyBodyKey: "opencode's usage endpoint could not be reached. No usage data to show yet."
        },
        planStyle: "plan",
        // The response carries no plan name and no spend, so the tab holds the
        // Source name and its two Window cards, with no stats, chart or models.
        sections: [
            { type: "header" },
            { type: "accounts" },
            { type: "login" },
            { type: "status" },
            { type: "windows", which: "primary" },
            { type: "windows", which: "secondary" }
        ]
    },
    {
        id: "zai",
        labelKey: "Z.ai",
        script: "get-zai-usage",
        windows: {
            primary: {
                util: "PRIMARY_UTIL",
                reset: "PRIMARY_RESET",
                windowSecondsKey: "PRIMARY_WINDOW_SECONDS"
            },
            secondary: {
                util: "SECONDARY_UTIL",
                reset: "SECONDARY_RESET",
                windowSecondsKey: "SECONDARY_WINDOW_SECONDS"
            }
        },
        accounts: {
            // Z.ai has no local config directory to point at, so Accounts are
            // passed to the script as name=api-key rather than name=path.
            settingKey: "customZaiAccounts",
            listKey: "ACCOUNTS",
            originsKey: "ACCOUNT_ORIGINS",
            shadowedKey: "ACCOUNT_SHADOWED",
            overriddenKey: "overridden by your Custom Account",
            detectedTitleKey: "Detected Accounts",
            keyPrefix: "ACCOUNT_",
            argField: "key",
            labelKey: "Account",
            titleKey: "Custom Z.ai Accounts",
            descriptionKey: "Track extra Z.ai accounts by API key. A key from the pi coding agent config (~/.pi/agent/models.json) is detected automatically as \"default\".",
            fieldLabelKey: "API key",
            placeholder: "",
            fields: pickFields("zai", "ACCOUNT_", [
                "CREDS_STATUS",
                "PRIMARY_UTIL", "PRIMARY_RESET",
                "SECONDARY_UTIL", "SECONDARY_RESET"
            ])
        },
        login: {
            // Text only: there is no CLI login flow to shell out to. The fix is
            // an API key in the plugin settings.
            kind: "text",
            titleKey: "API key rejected",
            bodyKey: "Check your Z.ai API key in the plugin settings."
        },
        planStyle: "plan",
        sections: [
            { type: "header" },
            { type: "accounts" },
            { type: "login" },
            { type: "windows", which: "primary" },
            { type: "windows", which: "secondary" },
            {
                type: "stats",
                columns: [
                    {
                        labelKey: "Week",
                        value: { kind: "tokens", key: "weekTokens" },
                        accent: true
                    },
                    {
                        labelKey: "Month",
                        value: { kind: "tokens", key: "monthTokens" }
                    },
                    {
                        labelKey: "This Week",
                        value: { kind: "count", key: "weekCalls", unitKey: "Model calls" },
                        text: true
                    }
                ]
            },
            { type: "chart" },
            { type: "models", nameStyle: "raw" }
        ]
    }
];

// The Overview's tab entry. The Overview is not a Source: it has no provider, no
// credentials and nothing of its own to fetch, so it is not in SOURCES and the
// checks that pin a Descriptor's shape do not claim it is one (ADR 0003). It is
// still a tab entry carrying a Section, so the popout's strip and SourceTab's
// Section list are generated from one list rather than from a second,
// hand-written path that could disagree with the first.
var OVERVIEW_TAB = {
    id: "overview",
    labelKey: "Overview",
    sections: [
        { type: "overview" }
    ]
};

function byId(id) {
    for (var i = 0; i < SOURCES.length; i++) {
        if (SOURCES[i].id === id)
            return SOURCES[i];
    }
    return null;
}

function ids() {
    return SOURCES.map(function (s) {
        return s.id;
    });
}

// Reconciles a persisted Source list against the registry. Unknown ids and
// duplicates are dropped and the caller's order is preserved. Registry ids the
// list omits are *not* added here; resolveList decides which omissions mean a
// deliberately disabled Source and which mean a newly added one.
function reconcileList(stored) {
    var knownIds = ids();
    var out = [];
    if (Array.isArray(stored)) {
        for (var i = 0; i < stored.length; i++) {
            if (knownIds.indexOf(stored[i]) >= 0 && out.indexOf(stored[i]) < 0)
                out.push(stored[i]);
        }
    }
    return out;
}

// The ordered list of enabled Sources, from whatever was persisted.
//
// An absent list means the user has never configured it, so every Source starts
// on. An explicitly empty list means they turned them all off, and is respected
// so the last Source can be switched off.
//
// `known` is the set of registry ids the user has already been shown. It is what
// separates a Source they deliberately switched off from one the registry gained
// since they last saved: a Source that is absent but known stays off, while one
// they have never seen is appended, enabled. Without it, an omission is
// ambiguous, so every missing id is appended and no Source can be switched off.
function resolveList(stored, known) {
    if (stored === null || stored === undefined)
        return ids();
    if (Array.isArray(stored) && stored.length === 0)
        return [];

    var enabled = reconcileList(stored);
    var seen = Array.isArray(known) ? known : null;
    var all = ids();
    for (var i = 0; i < all.length; i++) {
        if (enabled.indexOf(all[i]) >= 0)
            continue;
        // No `known` means the caller has no memory of earlier registry ids, so
        // a missing id is treated as newly added and switched on. This keeps a
        // config written before `known` existed working the way it did.
        if (seen === null || seen.indexOf(all[i]) < 0)
            enabled.push(all[i]);
    }
    return enabled;
}

// The Source's Tightest Window: whichever of its Windows carries the highest
// Utilisation, so the limit that will stop the user first is the one a row
// names. Which Window that is varies by Source and over time, so callers read
// `window` rather than assuming a slot. A tie goes to the primary Window, the
// slot the Pill's Ring already draws.
//
// Returns { window, util, resetMs }, or null when the state carries no Window
// reading at all.
function tightestWindow(state) {
    if (!state)
        return null;
    var slots = ["primary", "secondary"];
    var best = null;
    for (var i = 0; i < slots.length; i++) {
        var w = state[slots[i]];
        if (!w || typeof w.util !== "number")
            continue;
        if (best === null || w.util > best.util)
            best = { window: slots[i], util: w.util, resetMs: w.resetMs || 0 };
    }
    return best;
}

// One Overview row. It carries everything the Overview tab draws, so the tab is
// a dumb repeater and every ranking rule stays testable here.
//
// A Source that has reported a reading is ranked, except a Missing one:
// credentials can lapse after a good fetch, and the row offers the login
// affordance instead of a stale bar. An Unavailable Source keeps its last known
// reading and flags it stale, because a stale reading is still a reading. A
// Source with no reading yet carries no Tightest Window, so the row cannot
// draw a fabricated zero.
//
// Returns null for a Not installed Source: it stays hidden everywhere else, so
// it produces no row here either.
function overviewRow(state) {
    if (!state || !state.id || state.credsStatus === "not_installed")
        return null;

    var d = byId(state.id);
    var missing = state.credsStatus === "missing" || state.credsStatus === "expired";
    var unavailable = state.credsStatus === "unavailable";
    var hasReading = state.hasData === true;
    var tightest = hasReading ? tightestWindow(state) : null;
    var which = tightest ? tightest.window : null;
    var declared = which && d && d.windows[which] ? d.windows[which] : null;
    var win = which ? state[which] || {} : {};

    return {
        id: state.id,
        // The display name stays a key: translation is the renderer's job.
        labelKey: d ? d.labelKey : state.id,
        // Which Window was tightest, and the label the descriptor gives it. The
        // label follows the Window; when the descriptor names none, windowSeconds
        // lets the renderer fall back to its own duration formatting.
        window: which,
        windowLabelKey: declared && declared.labelKey ? declared.labelKey : null,
        windowSeconds: win.windowSeconds || (declared && declared.windowSeconds) || 0,
        util: tightest ? tightest.util : 0,
        resetMs: tightest ? tightest.resetMs : 0,
        // Ranked means the row holds a current-enough reading to sort by.
        ranked: hasReading && !missing,
        // Stale marks an Unavailable Source's last known reading as not current.
        stale: hasReading && unavailable,
        // Missing and Unavailable are the two degraded states, and each renders
        // differently: a login affordance, or a dimmed stale bar.
        missing: missing,
        unavailable: unavailable,
        degraded: missing || unavailable,
        // The sign-in a Missing row mirrors from the Source tab's Login Section:
        // the descriptor says whether the Source has a CLI flow to run or only a
        // key to point at. Carried here so the row can be drawn by a repeater
        // that knows nothing about descriptors.
        loginKind: d && d.login ? d.login.kind : null,
        loginBodyKey: d && d.login && d.login.bodyKey ? d.login.bodyKey : null
    };
}

// The Overview's rows, in the order the tab renders them.
//
// `states` is the ordered list of visible Sources in settings order, each
// carrying its own Source id (stateFor() sets it). Settings order is what ties
// fall back to, so rows do not jitter between fetches. Ranked rows come first,
// by Tightest Window Utilisation descending, so the scarcest budget is the top
// line; every Source with no reading follows them in settings order.
//
// Fewer than two rows means there is nothing to compare, so the Overview is
// absent: a comparison of one is noise.
function overviewRows(states) {
    if (!Array.isArray(states))
        return [];

    var ranked = [];
    var unranked = [];
    for (var i = 0; i < states.length; i++) {
        var row = overviewRow(states[i]);
        if (!row)
            continue;
        if (row.ranked)
            ranked.push({ row: row, at: i });
        else
            unranked.push(row);
    }

    ranked.sort(function (a, b) {
        if (b.row.util !== a.row.util)
            return b.row.util - a.row.util;
        return a.at - b.at;
    });

    var out = ranked.map(function (entry) {
        return entry.row;
    }).concat(unranked);
    return out.length >= 2 ? out : [];
}
