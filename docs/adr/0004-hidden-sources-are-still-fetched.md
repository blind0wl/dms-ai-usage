# Hidden Sources are still fetched

The widget used to derive the set of Sources it fetched from the set of Sources it
showed. That made `not_installed` a one-way door: a Source whose report said it
was not installed left the displayed set, and because the fetch set was read off
the displayed set, nothing ever asked it again. Its credentials could be perfectly
good and it stayed hidden for the life of the process, since the per-Source state
is memory-only.

The two sets are now separate. Every enabled Source is fetched on every scheduled
cycle, and visibility is a display filter over data that keeps arriving.

## Considered options

**Keep the coupling and add a slower re-check over hidden Sources.** Preserves the
current fetch behaviour and bounds the cost, at the price of a second scheduling
concept whose only job is to paper over the coupling. Rejected once the re-check
turned out to be an early exit in every Script: 3–7 ms each, about 17 ms for the
four Sources, and no network call. A slower cadence would have saved roughly 13 ms
a cycle.

**Delay hiding without changing the fetch set.** Absorbs a transient absence
without ever hiding a Source on one report, but does not recover one that has
already been hidden. It is a complement to the decision above, not an alternative
to it, and it is adopted alongside: a Source is hidden after two consecutive
`not_installed` reports.

## Consequences

A genuinely absent Source runs its Script every cycle for as long as it is
enabled. That is deliberate, and it is what makes the hidden state provisional
rather than permanent: a later report that contradicts it brings the Source back
with no restart and no settings write.

`not_installed` therefore means "nothing was readable when we looked", not "this
machine has nothing for this Source". The two cases are indistinguishable from a
single report, and the widget no longer pretends otherwise.

Because visibility is a display concern it must be decided once and consumed by
the Pill, the Popout's tab strip and the Overview alike, so those three cannot
disagree about whether a Source is showing. The counting rule is a pure function
over the consecutive-report count and the last status, which keeps it in the
JavaScript test harness rather than the QML one.
