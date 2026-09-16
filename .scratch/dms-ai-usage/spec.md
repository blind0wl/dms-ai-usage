Status: ready-for-agent

## Problem Statement

The plugin tracks three Sources, but I can only turn each one on or off. I cannot
choose the order they appear in, on the Pill or in the Popout, and the order is
fixed in code.

Every Source is also written out four times in the widget: its state properties,
its process and output parser, its Ring, and its block of Popout cards. The three
Popout sections are near-copies that differ only in which properties their
bindings name. Adding a fourth Source means copying all of that again, which
makes each addition slower and each future change riskier.

I want to add opencode Go as a fourth Source, and I want adding it to be cheap
rather than another copy. I also want to decide in the settings GUI which Sources
appear and in what order, instead of editing code or living with a fixed order.

## Solution

Sources become data. A registry holds one descriptor per Source, and the Pill,
the Popout tabs, their Sections, and the settings rows are generated from it.
Adding a Source means adding a descriptor and a script, and nothing in the
widget changes.

Settings gain an ordered list of Sources in place of the three enable toggles.
The list order sets the Pill Ring order and the Popout tab order, and removing a
Source from the list turns it off. A Source added to the registry later appears
on its own, enabled, without the user editing anything.

opencode Go arrives as the first Source added under the new model, and it tracks
the Go subscription's account-level 5-hour and weekly allowance in dollars rather
than tokens.

## User Stories

### Choosing what appears

1. As a plugin user, I want to see one row per Source in settings, so that I can
   tell at a glance what the plugin can track.
2. As a plugin user, I want to turn a Source off without uninstalling anything,
   so that a provider I stopped paying for disappears from my bar.
3. As a plugin user, I want to turn a Source back on and have it appear
   immediately, so that I do not have to restart the shell.
4. As a plugin user, I want to move a Source up or down the list, so that the
   Ring I care about most sits first in the Pill.
5. As a plugin user, I want the Pill Ring order to follow my list, so that what I
   configured is what I see.
6. As a plugin user, I want the Popout tab order to follow the same list, so that
   the two never disagree.
7. As a plugin user, I want my list to survive a shell restart, so that I set it
   once.
8. As a plugin user, I want a Source I turned off to stop running its script, so
   that I am not making needless network requests for a provider I do not use.
9. As a plugin user, I want the Pill to hide entirely when I turn every Source
   off, so that an empty ring does not sit in my bar.
10. As a plugin user, I want to be able to turn off the last remaining Source
    without it silently coming back, so that my choice sticks.
11. As a plugin user, I want a Source added by a plugin update to appear on its
    own, enabled, so that I do not have to discover it in settings.
12. As a plugin user, I want a stale Source id in my saved list to be ignored
    rather than break the plugin, so that an upgrade cannot leave me with a
    broken bar.
13. As a plugin user, I want a Source whose credentials are absent to stay hidden
    rather than showing a Ring at zero, so that I am not misled about usage I do
    not have.

### Adding a Source as a maintainer

14. As a maintainer, I want to add a Source by writing one descriptor entry plus
    its script, so that I can add providers without editing the widget.
15. As a maintainer, I want the widget to contain no per-Source branches, so that
    adding a Source cannot regress an existing one.
16. As a maintainer, I want a descriptor to name which script output keys feed
    each Window slot, so that I can add a Source whose script uses its own key
    names without rewriting the existing scripts.
17. As a maintainer, I want a descriptor to declare which Sections its tab
    renders, in order, so that a Source's tab is data rather than a layout.
18. As a maintainer, I want a descriptor to declare how its Accounts work, so
    that the settings editor for a Source's Account list is generated rather than
    written per Source.
19. As a maintainer, I want a descriptor to declare how a Source offers to fix
    missing credentials, so that a CLI-backed Source gets a login button and an
    API-key Source gets an explanation without special-casing either.
20. As a maintainer, I want a Section type to be added once and reused by every
    Source, so that a new kind of card does not need writing three times.
21. As a maintainer, I want the registry's contract covered by a test, so that a
    descriptor that names a Section type nobody implements, or a state key
    nobody produces, fails the build instead of rendering an empty card.
22. As a maintainer, I want the three existing scripts to keep their current
    output keys, so that adding the registry cannot change what any Source
    reports and the refactor stays reviewable.

### The three existing Sources

23. As an existing user, I want Claude, ChatGPT and Z.ai to render exactly as
    they do today, so that an internal refactor does not change my bar.
24. As an existing user, I want the Pill to be pixel-identical after the upgrade,
    so that I can trust the change.
25. As an existing user, I want Claude's Account selector, cost rows and all-time
    footer to survive, so that the refactor does not quietly drop features.
26. As a maintainer, I want every string the registry introduces to be
    translated, so that French and Spanish users do not see raw keys.

### opencode Go

27. As an opencode Go subscriber, I want a Ring showing my account's 5-hour
    Utilisation, so that I can see at a glance how close I am to being throttled.
28. As an opencode Go subscriber, I want the weekly Window beside it, so that I
    can see the slower-moving limit too.
29. As an opencode Go subscriber, I want a countdown to each Window's reset, so
    that I know when to retry.
30. As an opencode Go subscriber, I want Pacing on both Windows, so that I can
    tell whether I am burning allowance faster than the Window is elapsing.
31. As an opencode Go subscriber, I want the plan named on the tab, so that I can
    confirm which subscription is being tracked.
32. As an opencode Go subscriber, I want my spend shown in dollars, because that
    is the unit Go's allowance is denominated in, rather than a token count that
    does not relate to my limit.
33. As an opencode Go subscriber, I want today's, this week's and this month's
    spend, so that I can see how fast I am consuming the monthly allowance.
34. As an opencode Go subscriber, I want a per-model spend breakdown for the
    week, so that I can see which model is consuming my allowance.
35. As an opencode Go subscriber with more than one Go key, I want each Account
    reported, so that work and personal keys do not blur together.
36. As an opencode Go subscriber, I want my key discovered from opencode's own
    credentials file, so that I do not have to enter it twice.
37. As an opencode Go subscriber, I want an environment variable to work as a
    fallback, so that I can track Go on a machine where opencode is not
    connected.
38. As an opencode Go subscriber, I want to add a key in the plugin settings, so
    that I can track a key that is not on this machine at all.
39. As an opencode Go subscriber, I want the Source hidden when no key exists
    anywhere, so that a Source I cannot use stays out of the way.
40. As an opencode Go subscriber, I want the Source to appear on a machine that
    does not run opencode, because I am paying for Go and want to watch it from
    anywhere.
41. As an opencode Go subscriber, I want a rejected key to show a card telling me
    to fix it in settings, rather than a silent zero, so that I can tell the
    difference between no usage and no access.
42. As an opencode Go subscriber, I want the Source to keep working if the usage
    endpoint disappears, so that an undocumented endpoint going away does not
    remove the feature.
43. As an opencode Go subscriber, I want my local opencode session data used as
    that fallback, so that the tab still reports something real.

## Implementation Decisions

### The registry module

A new registry module holds one descriptor per Source. It is pure data plus pure
functions, with no dependency on the QML runtime, so it can be loaded and tested
directly.

The descriptor shape is the interface between the registry and the renderer, so
it is recorded here. It came out of the design session rather than a prototype.

```
{
  id,                       // stable key, persisted in settings
  labelKey,                 // translation key for the display name
  script,                   // script filename
  windows: {
    primary:   { util, reset, windowSeconds | windowSecondsKey, labelKey? },
    secondary: { ... }
  },
  accounts: {               // absent when the Source has no Account list
    settingKey, argField, labelKey,
    titleKey, descriptionKey, fieldLabelKey, placeholder,
    overlay                 // true when this Source reports per-Account values
  },
  login:                    // absent when the Source cannot be logged into
    { kind: "cli", action } | { kind: "text", titleKey, bodyKey },
  planStyle: "subscription" | "plan",
  sections: [ { type, ...options } ]
}
```

Window slots name the script keys that feed them rather than requiring one shared
output contract. This is deliberate: it keeps the three existing scripts
unchanged, so the refactor cannot alter what any Source reports, and the scripts
stay mergeable against upstream. The cost is a translation layer a shared
contract would not need. A window declares either a fixed length or the key its
script reports the length under, since Claude's script reports no length at all.

### Per-Source state

State moves from flat per-Source properties to one object per Source, keyed by
its id, so that Sections can read a uniform shape:

```
sourceData[id] = {
  credsStatus, plan, planTier,
  primary:   { util, resetMs, windowSeconds },
  secondary: { util, resetMs, windowSeconds },
  weekTokens, monthTokens, weekCalls, weekMessages, weekSessions,
  todayCost, weekCost, monthCost,
  dailyTokens[7], dailyCosts[7],
  models: [{ modelName, modelTokens }],
  alltime: { sessions, messages, firstSession },
  accounts: [ ... ]
}
```

Two normalisations happen at parse time so no Section has to know about them.
Reset times become epoch milliseconds, because Claude's script reports ISO-8601
and the others report unix seconds. Window length stays optional, because a
Source that reports none still needs to render, and the label degrades to a
generic one rather than a wrong one.

Account-level reporting is a per-Account overlay on this shape rather than a
parallel set of display properties. When an Account is selected, the Source's
aggregate values are overlaid with that Account's, and all-time figures are
zeroed because they are only tracked in aggregate.

### Sections

A Section is a typed card. Eight types cover every tab: `header`, `accounts`,
`login`, `windows`, `stats`, `chart`, `models`, `alltime`. A Section component
receives its own descriptor entry plus a shared context object holding the
resolved Source state, the formatters, and the actions it may invoke. Both are
bound rather than assigned, so cards stay reactive when the selected Source or
the fetched data changes.

`alltime` is its own type rather than an option on `stats`, which differs from
the option list sketched during design. Claude's all-time footer renders as a
separate card after the model breakdown, and an option on `stats` would move it
inside the token card and change what the user sees. Rendering identically wins
over a shorter type list.

`stats` takes a declared column list rather than fixed periods, because Sources
report different periods in different units. A column is a label plus a value
spec and an optional sub-line, where a value spec is a kind (`tokens`, `cost`,
`count`) and the state key it reads.

### Settings

The three enable toggles are replaced by one ordered list, persisted under a
single key as an array of Source ids:

```json
["claude", "chatgpt", "opencode", "zai"]
```

Rules on load:

- An absent key means the list was never configured, so every Source starts on.
- An explicitly empty list stays empty, so the last Source can be turned off.
- Ids not in the registry are dropped.
- Registry ids missing from a non-empty list are appended, enabled, in registry
  order, so a newly added Source appears without the user touching anything.

The settings page renders one row per Source, enabled Sources first in
configured order and disabled ones after, each with a toggle and move buttons.
Only Sources holding a position can move.

The three custom Account list editors collapse into one editor driven by each
descriptor's `accounts` block. They previously existed three times over,
differing only in the setting key, the labels, and whether the value is a config
directory or an API key. All of those are descriptor data now.

### The plugin id

The settings page declared a plugin id that did not match the manifest, so
settings written from the GUI landed under a key the widget never read. The
settings page must declare the manifest's id. This is a prerequisite for the new
list behaving at all, and it resets anything previously set in the GUI to
defaults, which is acceptable because the mismatch meant those values were
probably never reaching the widget.

### Pill

The Pill renders one Ring and one percentage per visible Source, in list order,
separated by a divider. A Source is visible when it is enabled and its script has
not reported that it is not installed. The over-pace arrow and colour rule is
unchanged.

### Fetching

One timer starts every visible Source's script on the configured interval. Each
Source keeps its own last-good output and falls back to it when a fetch fails, so
one failing endpoint cannot freeze another Source's numbers. Two extra triggers
are preserved per Source: a gap long enough to mean the machine woke from sleep
refetches everything, and a Window whose reset time has passed refetches that
Source immediately rather than leaving it on "Resetting...".

### opencode Go

The Source tracks the Go subscription: a monthly fee in exchange for a
dollar-denominated allowance per model, with the 5-hour allowance at 20% of the
monthly cap and the weekly allowance at 50%.

The account-level utilisation the web console shows is readable from an
undocumented usage endpoint under the Go API path. Without a key it answers 401,
so it exists and takes a key; the sibling paths that suggest themselves for
limits and balance return 404. No usage or balance endpoint is documented, and
the Zen equivalent is an open feature request upstream.

Because the endpoint is undocumented, the parser is written against a captured
response rather than a guess, and this is the one fact the implementation is
missing. If the endpoint goes away, the Source falls back to local data:
opencode's own database carries one row per message with its model, provider,
cost and full token counts, which is enough to report spend and a per-model
breakdown without any API.

The console reports utilisation at the account level, not per model, and the Ring
follows that: one account-level ring rather than one per model.

Key discovery order, first hit wins: the Go entry in opencode's own credentials
file, which is where its connect flow writes it; then an environment variable;
then a key added in the plugin settings. No key anywhere means the Source is not
installed and stays hidden. The opencode binary is not required, because the
Source tracks a paid plan and should work on a machine that only watches it.

Because Go is denominated in dollars, this Source's `stats` Section uses the
dollar unit and reports spend against the allowance. The other Sources keep
tokens. No Source displays a number its data cannot support.

## Testing Decisions

A good test here exercises an external contract and would survive a rewrite of
the implementation. For this feature that means asserting on the registry's
published output, on each script's stdout, and on static properties of the QML,
rather than reaching into internals. Two traps to avoid: asserting on the shape
of private state objects instead of the descriptor contract, and asserting on
rendering via grep, which cannot distinguish a card that renders from one that
does not.

Four seams, of which only the first is new.

**The registry module (new, primary).** Because it has no QML dependency, it
loads directly in Node. This is the highest available seam for "is the registry
correct", and it covers descriptor completeness, that every Section type named is
one the renderer implements, that every state key a Section reads is actually
produced, that every descriptor label is translated, and the settings list rules
including the empty and stale-id cases. It catches registry-to-renderer drift
without instantiating QML.

**Each script's stdout contract (existing, unchanged).** The four script suites
already cover this by running each script against mocked binaries and temporary
home directories and asserting on its key-value output. Because the refactor
froze the scripts' output keys, these suites double as the proof that no Source's
reported data changed. The opencode Go script gets a suite in the same style, with
recorded fixtures for the captured usage response.

**The QML function harness (existing).** Pure functions extracted from the widget
are tested in Node. The pacing, countdown and formatting functions already live
here, and the reset-time normalisation belongs here too, since it is the one
piece of the parse path that is pure.

**Static QML checks (existing, weakest).** File discovery must recurse into the
new component directory so Section components are checked at all, and the
existing guards for syntax, required imports, and 32-bit token declarations
continue to apply.

There is no seam for rendering, and none was available. Quickshell offers no
headless render harness, so the Popout and the settings GUI rest on static
checks plus a manual visual pass. This is a known gap rather than a decision: it
is why the Popout comparison remains outstanding.

## Out of Scope

- Per-Source refresh intervals. One shared timer drives every Source.
- Multiple bar instances of the widget, and per-Source colour or icon theming.
- A QML render or screenshot seam. It would close the manual-pass gap but needs
  new machinery rather than a seam, and Quickshell does not support it today.
- Rewriting the three existing scripts' output keys. The descriptor translation
  layer exists precisely to avoid it.
- opencode Zen credits or balance. Only the Go plan is tracked.
- Local opencode session data as the primary source. It is the fallback for when
  the usage endpoint is unavailable, not the main path.
- GitHub Copilot, declined earlier and still declined.

## Further Notes

**One fact is missing.** The response shape of the Go usage endpoint is not
recorded, so the opencode Go parser cannot be written yet. Everything else about
that Source is decided. A single authenticated request to the endpoint unblocks
it.

**A DMS bug affects development, not use.** Reloading this plugin through the
shell's IPC reload call fails about half the time, alternating with no code
change, because the shell unloads and reloads within one call and a directory
import does not survive that cycle. Cold start and disable followed by enable are
reliable, verified repeatedly, so the plugin always appears. Reloading twice, or
using disable then enable, clears it. It is recorded because it will confuse
whoever next iterates on this plugin, and because it rules out a file layout the
design originally assumed.

**The refactor is already built.** The registry half of this spec is implemented
and committed on a branch, with the pill verified pixel-identical to the previous
build and the full suite green. The opencode Go half is not started. The spec
covers both so that it is the single record of the feature.

**One verification step is outstanding.** The Popout tabs and the settings GUI
have not been visually compared against the previous build. Opening the Popout
could not be driven from outside the shell, so this is a manual pass.

**This repo's skills configuration is missing.** The issue tracker and triage
label vocabulary are not recorded, so skills have to re-derive where work is
tracked. Running the setup skill once would fix that for every future run.

**A vocabulary conflict was resolved.** The effort map carries domain notes from
an earlier round that define Source as a local fetch mechanism and give Provider
a distinct role. The glossary written after the registry refactor wins: a Source
is a provider's usage data tracked independently, and Provider is not used as a
synonym for it. The map's notes should be brought into line with the glossary
rather than the other way round.
