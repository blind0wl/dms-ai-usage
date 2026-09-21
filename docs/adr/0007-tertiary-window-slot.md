# The tertiary Window slot is generic; only opencode Go populates it

The opencode Go endpoint enforces three allowances — `rolling` (5 hours),
`weekly` and `monthly` — while the plugin modelled two Window slots and left
the `monthly` entry unreported. After a week of light use the weekly Window is
barely touched while the provider dashboard shows half the monthly allowance
gone, and the plugin gave no place to see that coming.

The registry gains a generic third Window slot called **tertiary**, following
the existing slot abstraction end to end rather than adding a monthly-specific
one: Script report keys (`TERTIARY_UTIL` / `TERTIARY_RESET`, per-Account under
the shared `ACCOUNT_` prefix) → Registry Descriptor slot → State slot →
Windows Section rows / Tightest Window. Only the opencode Go Descriptor
declares it, with label **Monthly Window** and a declared length of about 30
days (2592000 seconds); resets fall on boundaries, so the length is declared
rather than derived like the 5h and 7d ones. The other Sources declare no
tertiary slot and render nothing new.

**Tightest Window** is the maximum Utilisation over all reported Windows, so
the monthly Window competes for it: the Overview ranks and names it when it
binds, with ties going to primary as before. The Pill **Ring** stays on the
primary Window Utilisation by definition, so its meaning (what stops the user
right now) does not change.

The Windows Section iterates all three slots generically and drops slots with
no reading rather than drawing zeros, so two-Window Sources render exactly as
before. Every row shows its pacing tick and pacing label, tertiary included:
the monthly pace line is what tells a heavy session to slow down.
Session/message counts stay on the secondary row. The Go tab carries a
one-line caption under the Windows card noting that monthly Utilisation is
quota-weighted by model, so weekly and monthly legitimately diverge; no
per-model table, formula or spend figure is imported.

Per-Account aggregation for tertiary follows the existing binding-max rule
with its reset, and unavailable/Blocked Accounts are omitted from the Window
lists rather than zeroed, matching the other Windows. A rejected key reports
its own zero behind the settings card like the other Windows (still **Missing**,
never zero-as-ok); a failed endpoint reports no Window values at all, so the
last-good reading stays stale.

## Considered options

**A Go-specific monthly card beside the generic Windows card.** Less generic
iteration, but a second card shape for one allowance that still competes for
Tightest Window, and every future third allowance would need its own card.

**Showing no pacing on the tertiary row.** Hides the tick and label on a 30-day
linear burn, but the monthly pace line is what tells a heavy session to slow
down, so it stays. Rejected in favour of pacing on all three rows.

**Deriving the tertiary length from the endpoint.** The response carries reset
times, not durations, and the resets fall on boundaries; declaring ~30 days
keeps the existing precedence (reported length, else Descriptor, else zero).

## Consequences

The wire contract gains the `TERTIARY_UTIL` / `TERTIARY_RESET` pair (and the
`ACCOUNT_` prefixed per-Account lists). Responses without the `monthly` entry
report no tertiary keys, so older or partial responses render two rows with no
fabricated zero. Upstream quota arithmetic (visible cost scaled by
model allowance) is not reimplemented; the plugin reports the endpoint
percentages as-is and only captions their existence.
