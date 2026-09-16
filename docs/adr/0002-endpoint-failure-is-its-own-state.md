# Endpoint failure is its own state

opencode Go is the only Source whose data comes from an undocumented endpoint, so
it fails in ways the user cannot fix. A single `missing` state reported every
failure the same way, which sent the user to settings to check a key that was
perfectly good.

The two failure modes are now separate. A key the endpoint rejects is **Missing**.
The user fixes it in settings, so the tab shows the settings card. Every other
failure, whether a 404, a 5xx, a timeout or a body that does not carry the two
Windows, is **Unavailable**. It gets a `status` Section whose copy never mentions
settings, the Pill draws its slot with no reading, and the tab shows its last
known Window values only under a card that says they are stale. A failure with no
prior reading draws no Window cards at all, rather than a fabricated zero.

## Considered options

**Keep one state with different copy.** Cheapest, but it leaves the state and the
copy disagreeing. The state says "missing credentials" while the card says the
endpoint failed, and everything keyed on the state still treats a dead endpoint
as a fixable key.

**Hide the Source when the endpoint fails.** Treats an outage like "not
installed", so a Source that is still set up disappears with no explanation for
why its numbers stopped.

**A separate state and a Section type, chosen.** The state is what the widget
keys on; the Section is the copy. Both are reusable by any Source whose endpoint
can fail.

## Consequences

`get-opencode-go-usage` reports no Window values on an Unavailable run, so the
widget keeps the previous reading instead of parsing the failure as a fresh zero.
The Pill keeps every installed Source's slot and draws a hollow ring with no
percentage when there is no reading, for Unavailable and Missing alike. The
Source never vanishes, so the card that explains it stays reachable, and no stale
percentage reads as current. This refines the registry's last-good fallback
rather than replacing it. The values are still kept, but the card labels them
instead of presenting them as current.
