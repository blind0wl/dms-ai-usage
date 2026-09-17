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

// The per-Account output keys a Source may emit, and the overlay field each
// fills plus how to read it. Declared as data so no Source's Window shape is
// baked into the widget's Account adapter. A Source picks the subset it emits
// with pickFields().
//
// Claude's keys keep the PROFILE_ prefix because get-claude-usage is upstream's
// file and those names are its existing output contract. Every other Source
// uses ACCOUNT_, because CONTEXT.md makes Account the general term and reserves
// Profile for Claude-facing copy. Both map onto the same overlay fields.
var ACCOUNT_FIELDS = {
    PROFILE_SUBSCRIPTION: { field: "subscriptionType", type: "text" },
    PROFILE_TIER: { field: "rateLimitTier", type: "text" },
    PROFILE_CREDS_STATUS: { field: "credsStatus", type: "text" },
    PROFILE_WEEK_TOKENS: { field: "weekTokens", type: "number" },
    PROFILE_MONTH_TOKENS: { field: "monthTokens", type: "number" },
    PROFILE_WEEK_MESSAGES: { field: "weekMessages", type: "number" },
    PROFILE_WEEK_SESSIONS: { field: "weekSessions", type: "number" },
    PROFILE_TODAY_COST: { field: "todayCost", type: "number" },
    PROFILE_WEEK_COST: { field: "weekCost", type: "number" },
    PROFILE_MONTH_COST: { field: "monthCost", type: "number" },
    PROFILE_EXTRA_USAGE: { field: "extraUsageEnabled", type: "boolean" },
    PROFILE_DAILY: { field: "daily", type: "series" },
    PROFILE_DAILY_COSTS: { field: "dailyCosts", type: "series" },
    PROFILE_WEEK_MODELS: { field: "weekModels", type: "models" },
    PROFILE_FIVE_HOUR_UTIL: { field: "primaryUtil", type: "number" },
    PROFILE_FIVE_HOUR_RESET: { field: "primaryReset", type: "text" },
    PROFILE_SEVEN_DAY_UTIL: { field: "secondaryUtil", type: "number" },
    PROFILE_SEVEN_DAY_RESET: { field: "secondaryReset", type: "text" },
    ACCOUNT_SUBSCRIPTION: { field: "subscriptionType", type: "text" },
    ACCOUNT_CREDS_STATUS: { field: "credsStatus", type: "text" },
    ACCOUNT_WEEK_TOKENS: { field: "weekTokens", type: "number" },
    ACCOUNT_MONTH_TOKENS: { field: "monthTokens", type: "number" },
    ACCOUNT_WEEK_MESSAGES: { field: "weekMessages", type: "number" },
    ACCOUNT_WEEK_SESSIONS: { field: "weekSessions", type: "number" },
    ACCOUNT_DAILY: { field: "daily", type: "series" },
    ACCOUNT_WEEK_MODELS: { field: "weekModels", type: "models" },
    ACCOUNT_PRIMARY_UTIL: { field: "primaryUtil", type: "number" },
    ACCOUNT_PRIMARY_RESET: { field: "primaryReset", type: "text" },
    ACCOUNT_SECONDARY_UTIL: { field: "secondaryUtil", type: "number" },
    ACCOUNT_SECONDARY_RESET: { field: "secondaryReset", type: "text" }
};

// Picks the ACCOUNT_FIELDS rows a descriptor's script emits. An unknown key
// would otherwise be copied through as undefined and dropped from the wire with
// nothing to show for it, so it is named here instead.
function pickFields(id, keys) {
    var out = {};
    for (var i = 0; i < keys.length; i++) {
        var spec = ACCOUNT_FIELDS[keys[i]];
        if (!spec)
            console.warn("sources.js: descriptor \"" + id + "\" declares Account key " + keys[i] + " with no ACCOUNT_FIELDS row");
        out[keys[i]] = spec;
    }
    return out;
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
            argField: "path",
            labelKey: "Profile",
            overlay: true,
            titleKey: "Custom Profiles",
            descriptionKey: "Track extra Claude config directories. Point at a CLAUDE_CONFIG_DIR (the folder containing projects/). ~/.claude, Claude Code Switcher and claude-code-profiles are detected automatically.",
            fieldLabelKey: "Config directory",
            placeholder: "~/.ccp/data/work",
            fields: pickFields("claude", [
                "PROFILE_SUBSCRIPTION", "PROFILE_TIER", "PROFILE_CREDS_STATUS",
                "PROFILE_WEEK_TOKENS", "PROFILE_MONTH_TOKENS", "PROFILE_WEEK_MESSAGES",
                "PROFILE_WEEK_SESSIONS", "PROFILE_TODAY_COST", "PROFILE_WEEK_COST",
                "PROFILE_MONTH_COST", "PROFILE_EXTRA_USAGE", "PROFILE_DAILY",
                "PROFILE_DAILY_COSTS", "PROFILE_WEEK_MODELS",
                "PROFILE_FIVE_HOUR_UTIL", "PROFILE_FIVE_HOUR_RESET",
                "PROFILE_SEVEN_DAY_UTIL", "PROFILE_SEVEN_DAY_RESET"
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
            argField: "path",
            labelKey: "Account",
            titleKey: "Custom ChatGPT Accounts",
            descriptionKey: "Track extra Codex accounts. Point at a CODEX_HOME (the folder containing auth.json). ~/.codex is detected automatically as \"default\".",
            fieldLabelKey: "Config directory",
            placeholder: "~/.codex-work",
            fields: pickFields("chatgpt", [
                "ACCOUNT_SUBSCRIPTION", "ACCOUNT_CREDS_STATUS", "ACCOUNT_WEEK_TOKENS",
                "ACCOUNT_MONTH_TOKENS", "ACCOUNT_WEEK_MESSAGES", "ACCOUNT_WEEK_SESSIONS",
                "ACCOUNT_DAILY", "ACCOUNT_WEEK_MODELS",
                "ACCOUNT_PRIMARY_UTIL", "ACCOUNT_PRIMARY_RESET",
                "ACCOUNT_SECONDARY_UTIL", "ACCOUNT_SECONDARY_RESET"
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
            argField: "key",
            labelKey: "Account",
            titleKey: "Custom opencode Accounts",
            descriptionKey: "Track extra opencode Go Accounts by API key. An API key from the pi coding agent auth store (~/.pi/agent/auth.json) is detected automatically as \"default\".",
            fieldLabelKey: "API key",
            placeholder: "",
            fields: pickFields("opencode", [
                "ACCOUNT_CREDS_STATUS",
                "ACCOUNT_PRIMARY_UTIL", "ACCOUNT_PRIMARY_RESET",
                "ACCOUNT_SECONDARY_UTIL", "ACCOUNT_SECONDARY_RESET"
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
            argField: "key",
            labelKey: "Account",
            titleKey: "Custom Z.ai Accounts",
            descriptionKey: "Track extra Z.ai accounts by API key. A key from the pi coding agent config (~/.pi/agent/models.json) is detected automatically as \"default\".",
            fieldLabelKey: "API key",
            placeholder: "",
            fields: pickFields("zai", [
                "ACCOUNT_CREDS_STATUS",
                "ACCOUNT_PRIMARY_UTIL", "ACCOUNT_PRIMARY_RESET",
                "ACCOUNT_SECONDARY_UTIL", "ACCOUNT_SECONDARY_RESET"
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
