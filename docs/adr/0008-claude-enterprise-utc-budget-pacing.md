# Claude Enterprise budget pacing uses the UTC calendar month

Claude's member OAuth usage response includes reported spend and allowance, but
no reset or freshness timestamp. The Claude spend-limits documentation says
Enterprise spend resets at 00:00 UTC on the first day of each calendar month.
That documented boundary is enough to compare current spend with the elapsed
share of the month, but not to display an API-reported reset countdown.

The Monthly Budget bar therefore gets a linear pace tick and label derived from
the current UTC calendar month's exact length. The line names its UTC calendar
month basis, follows the existing Show pacing setting, and is suppressed when
the Source reading is stale or the allowance cannot produce a valid percentage.
The Pill and Overview retain their existing use of rate Windows first and the
Monthly Budget only when no rate Window is available.

The member response has no freshness timestamp. The application can suppress
last-known readings after endpoint failures, but a successful short-lived cache
can still straddle a month boundary. In that case a pre-boundary spend amount may
briefly appear against the new month's pace until a live fetch replaces it.

## Considered options

**Leave the Monthly Budget without pacing.** This avoids deriving a period from
documentation, but loses the useful comparison even though the documented reset
boundary is precise. Rejected; the UI states its UTC calendar-month basis.

**Use a fixed 30-day Window or countdown.** Calendar months have 28–31 days and
the response supplies no reset instant. Rejected; use exact UTC month boundaries
for the pace calculation and show no countdown.

## Consequences

Pacing uses a UTC calendar month, including leap February, rather than a rolling
duration. The Monthly Budget still has no reset timer, and users can briefly see
a prior-month cached spend amount after rollover because the OAuth payload gives
no freshness timestamp.

The boundary follows Anthropic's [Claude spend limits API documentation](https://platform.claude.com/docs/en/manage-claude/spend-limits-api).
