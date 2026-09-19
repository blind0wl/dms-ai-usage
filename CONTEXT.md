# AI Usage

A DMS taskbar plugin that reports subscription usage for the AI coding agents on
this machine. Each provider it tracks is a Source, and every Source is optional.

## Language

**Source**:
One provider's usage data, tracked independently of the others. Claude, ChatGPT,
Z.ai and opencode Go are Sources.
_Avoid_: provider, integration, service, backend

**Account**:
One set of credentials belonging to a Source, which the plugin queries and
reports separately from the Source's other Accounts. A Source with no Account
breakdown has exactly one implicit Account.
_Avoid_: profile, user, login, key

**Profile**:
The Claude UI's word for an Account, because Claude's Accounts are config
directories rather than credentials. Use it only in Claude-facing copy.
_Avoid_: using it as the general term; that is Account.

**Script**:
One Source's own program: the file the plugin runs to find that Source's Accounts,
report them under their Origins and fetch their usage. The widget and the settings
page ask the same Script the same questions, so the two cannot disagree about what
exists.
_Avoid_: helper, executable, plugin binary

**State**:
What a Source's Script reports leave behind: its Window Utilisations, its
figures, its status and the counting behind Hidden. One State per Source, built
from the report lines and read back with the selected Account's values laid over
it. Which Account is selected is not part of it, because that is the user's
choice rather than the Source's answer.
_Avoid_: data, model, store, cache

**Requirement**:
A command-line program the plugin cannot read any Source without, because every
Script invokes it: `jq` and `curl`. The plugin declares its Requirements but
cannot install them, and no plugin setting supplies one.
_Avoid_: dependency, prerequisite, package

**Detected Account**:
An Account a Source's Script finds for itself rather than being handed one: a
credential or config directory the machine already had, in the Source's own
config, another tool's config, or the environment. The plugin cannot add or
remove one, so the settings page lists Detected Accounts read-only, each under
the Origin it was found at. Describing the detection as automatic is fine; it is
the Account that is Detected, not automatic.
_Avoid_: auto, built-in, hidden, automatic account

**Custom Account**:
An Account the user added to a Source's setting list. The plugin owns it: the
settings page can edit it, and the Script is handed it as an argument instead of
finding it itself. A Script resolves a clash between two Accounts - a Custom one
and a Detected one, or two Custom ones - by keeping the first registration of a
name or of a value, and reports the Origin it kept. The Account that lost stays
listed: a Custom one as not in use, a Detected one as overridden, because either
way the Source is authenticating with something the user did not expect.
_Avoid_: manual account, user account, settings account

**Origin**:
Where a Detected Account's credential was found, as the user would look for it:
a file's path, a directory a profile manager keeps, or an environment variable's
name. A Script reports one per Account it lists, and _custom_ for an Account that
came from the Custom Account list rather than detection.
_Avoid_: source, discovery, provider

**Window**:
A rate-limited period a Source allows usage in, with a length, a Utilisation and
a reset time. A Source has up to two, called primary and secondary. A length
follows the provider: 5 hours and 7 days for Claude, Z.ai and opencode Go,
whatever the API reports for ChatGPT.
_Avoid_: period, limit, quota, bucket

**Utilisation**:
How much of a Window has been consumed, as a percentage of the Window's
allowance.
_Avoid_: usage, consumption, burn

**Brand Colour**:
The fixed colour that identifies a Source, independent of the shell theme:
Claude's clay, ChatGPT's green, Z.ai's blue, opencode Go's violet. It is the
colour a Utilisation reads at or under 50%; above that the theme's warning colour
takes over, and above 80% its error colour. It marks a Source in the Popout: its
tab chip, its header, its Overview bar, and its own tab's Window bars, chart and
model bars. The Pill keeps the theme's colours instead.
_Avoid_: accent, tint, source colour, theme colour

**Tightest Window**:
The one of a Source's Windows with the highest Utilisation: the limit that will
stop the user first. Which of the two it is varies by Source and over time.
_Avoid_: worst, nearest, critical, primary

**Pacing**:
Whether a Window's Utilisation is ahead of or behind the linear burn rate for the
elapsed part of that Window. Being ahead is over pace.
_Avoid_: rate, speed, forecast

**Ring**:
The circular progress indicator for one Source in the Pill, showing that Source's
primary Window Utilisation.
_Avoid_: dial, gauge, circle, indicator

**Pill**:
The widget's always-visible presence in the taskbar, holding one Ring per visible
Source.
_Avoid_: badge, chip, widget

**Popout**:
The panel opened from the Pill, holding the Overview followed by one tab per
visible Source.
_Avoid_: dropdown, panel, flyout

**Overview**:
The Popout's first tab, ranking every visible Source by its Tightest Window so
the scarcest budget is the top line. It is not a Source: it has no provider, no
credentials and nothing of its own to fetch. It is absent when fewer than two
Sources are visible, because a comparison of one is noise.
_Avoid_: summary, dashboard, all-tab, home

**Section**:
One typed card in a popout tab. A Source's tab is an ordered list of Sections.
_Avoid_: block, widget, component, card

**Descriptor**:
A Source's single entry in the registry: its identity, how to fetch it, and the
Sections its tab renders.
_Avoid_: config, definition, entry

**Registry**:
The ordered list of Descriptors that the Pill and popout are generated from.
_Avoid_: catalogue, manifest, sources file

**Not installed**:
A Source that is not in use on this machine at all, because its CLI is absent or
no credential exists anywhere. Being Not installed is provisional: a Not
installed Source is still asked, and a later report that contradicts it brings
the Source back with no restart and no settings write.
_Avoid_: unavailable, disabled, missing

**Hidden**:
A Source kept out of the Pill, the Popout and the Overview. A Source is hidden
only after repeated Not installed reports, never on the strength of one, because
a single report cannot tell a genuine absence from a transient one. The state is
in memory, so a restart shows every enabled Source until each one reports again.
Hidden is not disabled: a hidden Source's Script still runs.
_Avoid_: disabled, off, removed

**Missing**:
Credentials a Source needs are absent or expired, but the Source is installed. A
missing Source stays visible and offers a way to fix it: a login action, a pointer
at the settings, or a link into its own setup guide. It does not silently sit at
zero.
_Avoid_: not installed, logged out, unauthenticated

**Unavailable**:
A Source whose credentials are present but whose data could not be fetched
because its endpoint failed, timed out or answered with an unexpected body. The
user cannot fix it, so the Source does not point at settings and the widget
marks its last known values stale instead of showing them as current.
_Avoid_: missing, not installed, error, offline

**Blocked**:
A Source whose Script could not read its data because a Requirement is missing
or failed, so no credential was read. A Blocked Source stays visible and names
the command, because installing or repairing it is the fix and no plugin
setting is.
_Avoid_: unavailable, missing, not installed
