# Spec: Source registry

Status: agreed, not yet implemented.

## Problem

`ClaudeCodeUsageWidget.qml` is 3610 lines and hardcodes three Sources (Claude,
ChatGPT, Z.ai). Each Source appears four times: its state properties, its
`Process` and stdout parser, its pill ring, and its block of popout cards. The
three popout sections are near-copies that differ only in which properties their
bindings name. Adding a fourth Source copies all of that again.

The plugin also has no way to choose which Sources appear or in what order.
`enableClaude` / `enableChatgpt` / `enableZai` are three fixed toggles, and the
tab order is fixed in code.

## Goals

- A Source is data, not code. Adding one adds a descriptor entry and a script.
- Settings let the user pick which Sources appear, and in what order.
- The pill and popout are generated from the registry.
- The three existing Sources render exactly as they do today.

## Non-goals

- Changing what the three existing tabs report.
- Per-Source refresh intervals. One shared timer drives every Source.
- Multiple bar instances of the widget, or per-Source colour theming.
- Rewriting the three existing scripts' output keys (see Script contract).

## Vocabulary

See `CONTEXT.md`. The load-bearing terms are Source, Account, Window,
Utilisation, Pacing, Section and Descriptor.

## Files

```
ClaudeCodeUsageWidget.qml      pill, popout shell, fetch and parse
ClaudeCodeUsageSettings.qml    settings GUI
sources.js                     the registry: one descriptor per Source
SourceTab.qml                  renders a descriptor's Sections into cards
sections/WindowsSection.qml    one file per Section type
sections/HeaderSection.qml
sections/StatsSection.qml
sections/ChartSection.qml
sections/ModelsSection.qml
sections/AccountsSection.qml
sections/LoginSection.qml
sections/AlltimeSection.qml
translations.js                unchanged
```

`ClaudeCodeUsageWidget.qml` keeps its filename because `plugin.json` names it as
the component entry point. Subdirectory QML is reached with a relative import
(`import "sections"`), which Quickshell resolves against the component's
`file://` URL.

## Descriptor

`sources.js` exports an ordered array of descriptors. Field meanings:

| Field | Meaning |
| --- | --- |
| `id` | Stable key. Persisted in settings, so it must not change. |
| `labelKey` | Translation key for the display name. |
| `script` | Script filename in the plugin directory. |
| `windows.primary` / `.secondary` | Which script keys feed each Window slot. |
| `windows.*.labelKey` | Optional fixed card title. Absent means use the window length. |
| `accounts` | How the Source's Account selector works, or absent for none. |
| `login` | How the Source offers to fix missing credentials, or absent. |
| `sections` | Ordered Sections that make up the popout tab. |

The Window slots name script keys rather than requiring every script to emit the
same names. This keeps the three existing script contracts frozen, so the
refactor cannot change what any Source reports, and it keeps the scripts
mergeable against upstream.

```js
{
  id: "claude",
  labelKey: "Claude",
  script: "get-claude-usage",
  windows: {
    primary:   { util: "FIVE_HOUR_UTIL",  reset: "FIVE_HOUR_RESET",  labelKey: "5h Rate Window" },
    secondary: { util: "SEVEN_DAY_UTIL",  reset: "SEVEN_DAY_RESET",  labelKey: "7-Day Usage" },
  },
  accounts: { kind: "profiles", settingKey: "customProfiles", labelKey: "Profile", overlay: true },
  login: { kind: "cli", action: "startClaudeLogin" },
  sections: [
    { type: "header" },
    { type: "accounts" },
    { type: "login" },
    { type: "windows", which: "primary" },
    { type: "windows", which: "secondary" },
    { type: "stats", unit: "tokens", opts: { cost: true, sessions: true } },
    { type: "chart" },
    { type: "models" },
    { type: "alltime" },
  ],
}
```

## Per-Source state

State moves from flat per-Source properties (`fiveHourUtil`, `chatgptPrimaryUtil`,
`zaiPrimaryUtil`) to one object per Source, keyed by `id`:

```js
sourceData["claude"] = {
  credsStatus: "ok",            // ok | missing | expired | not_installed
  plan: "Max", planTier: "max_20x",
  primary:   { util: 41, resetMs: 1774612064741, windowSeconds: 18000 },
  secondary: { util: 12, resetMs: 1775216864741, windowSeconds: 604800 },
  weekTokens: 0, monthTokens: 0, weekCalls: 0, weekMessages: 0, weekSessions: 0,
  todayCost: 0, weekCost: 0, monthCost: 0, usdEurRate: 0,
  dailyTokens: [0,0,0,0,0,0,0], dailyCosts: [0,0,0,0,0,0,0],
  models: [{ modelName: "Opus", modelTokens: 0 }],
  alltime: { sessions: 0, messages: 0, firstSession: "" },
  accounts: [],
}
```

Two normalisations happen at parse time so every Section sees one shape:

- **Reset times are epoch milliseconds.** Claude's script emits ISO-8601 and the
  others emit unix seconds. `parseResetMs` already handles both and runs at parse
  time, so no Section needs to know.
- **Plan and Window length are optional.** A Source that reports neither leaves
  `plan` empty and `windowSeconds` at 0. `formatWindowLabel` already degrades a
  missing length to the generic label rather than a wrong one.

A Source with no data yet, or whose script reported `CREDS_STATUS=not_installed`,
has no entry and is not rendered.

## Sections

A Section is a typed card. `SourceTab.qml` walks the descriptor's `sections` and
instantiates one component per entry, passing `source` (the resolved state
object) and the entry's options.

| Type | Renders | Options |
| --- | --- | --- |
| `header` | Source name, plan and subscription line | none |
| `accounts` | Account selector, plus the tab or dropdown switch | none; driven by the descriptor's `accounts` |
| `login` | Credentials card. A button for CLI Sources, text only for API-key Sources | none; driven by the descriptor's `login` |
| `windows` | One rate Window card: ring, percentage, pacing line, countdown | `which: "primary" \| "secondary"` |
| `stats` | Token Consumption card, one column per period | `unit: "tokens" \| "dollars" \| "calls"`, `opts.cost`, `opts.sessions` |
| `chart` | Daily activity card, Monday to Sunday, with hover tooltip | none |
| `models` | Per-model table for the current week | none |
| `alltime` | All-time footer card | none |

`alltime` is its own type rather than an option on `stats`, which differs from
the option list sketched during design. Claude's all-time footer renders as a
separate card *after* the model breakdown, and an option on `stats` would move
it inside the Token Consumption card and change what the user sees. Rendering
identically wins over a shorter type list.

`header` is not needed by any current Source's layout: Claude's plan line sits
inside its first Window card. It stays in the type list because the opencode Go
tab needs a card that reports plan and spend with no rate windows at all.

## Settings

The three enable toggles are replaced by one ordered list, persisted under the
single key `sources` as an array of Source ids:

```json
["claude", "chatgpt", "opencode", "zai"]
```

Rules on load:

- Ids not present in the registry are dropped.
- Registry ids missing from the list are appended, enabled, in registry order.
- The list order sets both pill ring order and popout tab order.
- An empty list hides the pill entirely, as three disabled Sources does today.

The settings page renders one row per Source with an enable toggle and up/down
move buttons. DMS ships no reorder widget, so the row is built from the existing
`ToggleSetting` and icon buttons.

Every existing DMS setting-widget type is available (`ToggleSetting`,
`SliderSetting`, `StringSetting`, `SelectionSetting`, `ListSetting`,
`ListSettingWithInput`, `ColorSetting`); none of them reorders, hence the
custom row.

### pluginId

`ClaudeCodeUsageSettings.qml` currently declares `pluginId: "claudeCodeUsage"`,
but `plugin.json` declares `id: "aiUsage"` and the widget loads its data as
`aiUsage`. Settings written from the GUI therefore land under a key the widget
never reads. The settings page must declare `pluginId: "aiUsage"`.

This is a prerequisite, and it resets anything previously set in the GUI to
defaults. That is acceptable because the mismatch means those values were
probably never reaching the widget anyway.

## Pill

The pill renders one ring and one percentage label per visible Source, in list
order, separated by a 1px divider. Visibility is the Source's own enable state
AND its script reporting credentials that are present.

A Source is hidden when its script reports `CREDS_STATUS=not_installed`. For
Claude and ChatGPT that means the CLI is absent. For an API-key Source it means
no key was found anywhere.

The over-pace arrow and colour rule is unchanged: shown when `showPacing` is on
and the Source's primary Window is over or over quota.

## Fetching

One timer at the configured interval (2 to 15 minutes) starts every visible
Source's script. Each Source keeps its own last-good output and falls back to it
when a fetch fails, as Claude's script already does today, so one failing
endpoint cannot freeze another Source's numbers.

Two extra triggers are unchanged in behaviour but become per-Source:

- A gap over two minutes between ticks means the machine woke from sleep, so
  every visible Source refetches.
- A Window's reset time passing locally refetches that Source immediately rather
  than leaving it on "Resetting..." until the next tick.

Sources are spawned only when visible, so a disabled Source makes no network
calls.

## Acceptance criteria

While the refactor is in progress, each Section type lands one at a time and the
plugin reloads cleanly (`dms ipc plugins reload aiUsage`, then no QML errors in
the journal).

Branch `refactor/source-registry` is done when:

1. The registry drives the pill and the popout with no per-Source branches
   outside `sources.js`.
2. Claude, ChatGPT and Z.ai render identically to the current build. Verified by
   reloading and comparing each tab against `screenshot.png`.
3. Settings show one ordered row per Source, and reordering changes pill and tab
   order.
4. `tests/test-qml-functions.sh` covers descriptor lookup, Section resolution and
   the settings list rules.
5. `tests/test-qml-syntax.sh` recurses into `sections/`.
6. The suite passes and `qmllint` reports no `[syntax]` diagnostics.

Branch `feat/opencode-go-source` is done when:

1. `get-opencode-usage` reports opencode Go's 5-hour and weekly utilisation.
2. One descriptor entry adds the Source with no new widget code.
3. `tests/test-get-opencode-usage.sh` covers its parser against recorded
   fixtures.

## opencode Go

The fourth Source tracks the opencode Go subscription: 10 USD per month giving a
dollar-denominated allowance per model, with the 5-hour allowance at 20% of the
monthly cap and the weekly allowance at 50%.

### Data source

`https://opencode.ai/zen/go/v1/usage` returns the account-level 5-hour and weekly
utilisation that the web console shows. It is undocumented. Without a key it
answers `401 {"type":"error","error":{"type":"AuthError","message":"Missing API
key."}}`, so it exists and takes an API key. The sibling paths
`/zen/go/v1/limits`, `/zen/v1/usage` and `/zen/v1/balance` all return 404.

**Open item:** the response body shape is not yet recorded. The parser is written
against a real response captured with a live key, not against a guess. If the
endpoint disappears, the Source falls back to the local path below.

Everything else opencode exposes is local: `~/.local/share/opencode/opencode.db`
holds one row per message whose JSON carries `modelID`, `providerID`, `cost` and
`tokens{input,output,reasoning,cache{read,write}}`. That is enough to report
tokens, spend and per-model breakdown without any API, and it is the fallback if
the usage endpoint goes away.

The console reports utilisation at the account level, not per model, and the pill
follows that: it shows one account-level ring, not one per model.

### Credentials

Discovery order, first hit wins:

1. The `opencode-go` entry's key in `~/.local/share/opencode/auth.json`, which is
   where opencode's own `/connect` writes it.
2. `$OPENCODE_GO_KEY`, then `$OPENCODE_API_KEY`.
3. A key added under Custom opencode Accounts in the plugin settings.

No key anywhere means `CREDS_STATUS=not_installed`, and the Source stays hidden.
The opencode binary is not required: the Source tracks a paid plan, so it should
appear on a machine that only watches it.

### Reporting

opencode Go is denominated in dollars, so its `stats` Section uses
`unit: "dollars"` and reports spend against the allowance. The other Sources keep
tokens. No Source displays a number its data cannot support.

## Deliverables not code

- `CONTEXT.md` with the vocabulary.
- `docs/adr/0001-sources-as-data.md` recording why Sources became data.
- `README.md` updated for the fourth Source and the new settings.
