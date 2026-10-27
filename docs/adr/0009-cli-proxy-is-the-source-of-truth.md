# cli-proxy is the source of truth, the local reading is the fallback

The user routes Claude, ChatGPT and opencode Go through cli-proxy (CLIProxyAPI),
which holds the credentials those requests are made with. Its auths, not the
config directories on this machine, are what is being spent, so the plugin reads
usage for them. cli-proxy's management API lists its auths and offers an
`api-call` route that makes a request with an auth's own token, substituted for
`$TOKEN$`. The usage endpoints are the ones the Scripts already call, so only the
transport changes and the parsing is shared.

When cli-proxy is switched on and answers with at least one auth for a Source,
those auths are the Source's Accounts and the local and Custom Accounts are not
used. Any other answer - unset, unreachable, a rejected key, an unexpected body,
or no auth for the Source - leaves that Source on its local path for that
refresh. A disabled auth stays an Account with the Disabled status and is never
asked for usage, because the user switched it off rather than removed it; with
every auth disabled the Source reports Disabled instead of falling back.

The management key reaches curl on stdin, not as an argument, so it never shows
in the process list. It is stored in the plugin settings like the other keys.

## Considered options

**Merge cli-proxy's auths with the local Accounts.** Shows everything, but the
same subscription appears twice under two names whenever it is logged in both
places. Rejected.

**cli-proxy only, with no fallback.** Simpler, but an unreachable proxy would
take every routed Source down. Rejected.

**Fall back when every auth is disabled.** Would keep a reading on screen, but
from credentials the user did not choose. Rejected.

## Consequences

Token counts, costs and the chart still come from local session logs, which no
cli-proxy auth maps onto, so they are totalled for the Source and not reported
per cli-proxy Account. The Source's Ring and Overview row use the first enabled
auth's reading, as they used the `default` Account's locally. A sign-in for a
cli-proxy Account opens cli-proxy's management page, because a local login would
not reach the credential it holds.
