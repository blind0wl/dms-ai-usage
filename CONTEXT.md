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

**Window**:
A rate-limited period a Source allows usage in, with a length, a Utilisation and
a reset time. A Source has up to two, called primary and secondary. A length
follows the provider: 5 hours and 7 days for Claude, whatever the API reports for
ChatGPT.
_Avoid_: period, limit, quota, bucket

**Utilisation**:
How much of a Window has been consumed, as a percentage of the Window's
allowance.
_Avoid_: usage, consumption, burn

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
no credential exists anywhere. Not installed Sources stay hidden.
_Avoid_: unavailable, disabled, missing

**Missing**:
Credentials a Source needs are absent or expired, but the Source is installed. A
missing Source stays visible and offers a login action, so it does not silently
sit at zero.
_Avoid_: not installed, logged out, unauthenticated

**Unavailable**:
A Source whose credentials are present but whose data could not be fetched
because its endpoint failed, timed out or answered with an unexpected body. The
user cannot fix it, so the Source does not point at settings and the widget
marks its last known values stale instead of showing them as current.
_Avoid_: missing, not installed, error, offline
