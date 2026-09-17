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
