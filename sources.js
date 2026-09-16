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
                labelKey: "7-Day Usage",
                counts: true
            }
        },
        accounts: {
            settingKey: "customProfiles",
            argField: "path",
            labelKey: "Profile",
            overlay: true,
            titleKey: "Custom Profiles",
            descriptionKey: "Track extra Claude config directories. Point at a CLAUDE_CONFIG_DIR (the folder containing projects/). ~/.claude, Claude Code Switcher and claude-code-profiles are detected automatically.",
            fieldLabelKey: "Config directory",
            placeholder: "~/.ccp/data/work"
        },
        login: {
            kind: "cli",
            action: "claudeLogin"
        },
        planStyle: "subscription",
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
            argField: "path",
            labelKey: "Account",
            titleKey: "Custom ChatGPT Accounts",
            descriptionKey: "Track extra Codex accounts. Point at a CODEX_HOME (the folder containing auth.json). ~/.codex is detected automatically as \"default\".",
            fieldLabelKey: "Config directory",
            placeholder: "~/.codex-work"
        },
        login: {
            kind: "cli",
            action: "chatgptLogin"
        },
        planStyle: "plan",
        sections: [
            { type: "header" },
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
            argField: "key",
            labelKey: "Account",
            titleKey: "Custom opencode Accounts",
            descriptionKey: "Track extra opencode Go keys by API key. A key from the pi coding agent auth store (~/.pi/agent/auth.json) is detected automatically as \"default\".",
            fieldLabelKey: "API key",
            placeholder: ""
        },
        login: {
            // There is no CLI login flow to shell out to, and the opencode
            // binary is not required. The fix is an API key in the settings.
            kind: "text",
            titleKey: "API key rejected",
            bodyKey: "Check your opencode Go key in the plugin settings."
        },
        planStyle: "plan",
        // The response carries no plan name and no spend, so the tab holds the
        // Source name and its two Window cards, with no stats, chart or models.
        sections: [
            { type: "header" },
            { type: "login" },
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
            argField: "key",
            labelKey: "Account",
            titleKey: "Custom Z.ai Accounts",
            descriptionKey: "Track extra Z.ai accounts by API key. A key from the pi coding agent config (~/.pi/agent/models.json) is detected automatically as \"default\".",
            fieldLabelKey: "API key",
            placeholder: ""
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

// Reconciles a persisted Source list against the registry. Unknown ids are
// dropped, registry ids missing from the list are appended, and the caller's
// order is preserved. Returns an array of ids.
function reconcileList(stored) {
    var known = ids();
    var out = [];
    if (Array.isArray(stored)) {
        for (var i = 0; i < stored.length; i++) {
            if (known.indexOf(stored[i]) >= 0 && out.indexOf(stored[i]) < 0)
                out.push(stored[i]);
        }
    }
    for (var j = 0; j < known.length; j++) {
        if (out.indexOf(known[j]) < 0)
            out.push(known[j]);
    }
    return out;
}

// The ordered list of enabled Sources, from whatever was persisted.
//
// An absent value means the user has never configured the list, so every Source
// starts on. An explicitly empty list means they turned them all off, and is
// respected rather than refilled, otherwise the last Source could never be
// switched off.
function resolveList(stored) {
    if (stored === null || stored === undefined)
        return ids();
    if (Array.isArray(stored) && stored.length === 0)
        return [];
    return reconcileList(stored);
}
