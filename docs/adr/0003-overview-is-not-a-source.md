# The Overview is a tab, not a Source

ADR 0001 made the Pill and Popout generated output: everything on screen comes
from a Descriptor in the registry. The Overview breaks that shape, because it
ranks Sources against each other rather than reporting one, and has no provider,
no credentials and nothing to fetch. It is modelled as its own concept with its
own enable flag rather than as a Descriptor, so `Source` keeps meaning "one
provider's usage data".

## Considered options

**A Descriptor with no fetch.** One concept and one registry, and `SourceTab.qml`
renders it with no new plumbing. Rejected because it makes `Source` a word that
covers a thing with no provider, and because the enabled-Sources list is an
ordered array that `resolveList` appends unseen ids to the end of: a Source that
must always be first is a special case inside logic that exists to avoid special
cases.

**A hand-written tab outside the registry.** No abstraction to bend. Rejected
because the tab strip would then have two sources of truth, which is the
duplication ADR 0001 removed.

**A separate concept, rendered by the same machinery.** Chosen. The Overview is
one more Section type, so `SourceTab.qml` stays the only renderer, but it is
stored and configured on its own terms.

## Consequences

The Overview is persisted as its own boolean setting rather than as a member of
the enabled-Sources array, so existing installs need no migration and the array
keeps meaning exactly what it means today. The settings UI gains a pinned row
above the draggable Source list: toggleable, never movable.

Ranking is a property of the whole set, not of any one Source, so it cannot live
in a Descriptor. It is a pure function over the resolved states in `sources.js`,
which keeps it in the cheap JS test harness rather than the QML one.

Two Sources visible is the floor. Below it the tab is absent, so the single-Source
users inherited from upstream get no new tab in a Popout they already know.
