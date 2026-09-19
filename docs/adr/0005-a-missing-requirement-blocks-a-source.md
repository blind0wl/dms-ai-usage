# A missing Requirement is its own Source state

The plugin declares `jq` and `curl` under `requires` in `plugin.json`, but DMS
never reads that field and no Script checked it. When `jq` was absent, each
Script swallowed the failure and reported a credential verdict instead: ChatGPT
reported **Missing**, so the widget offered a sign-in for credentials that were
present and valid, and Z.ai and opencode Go reported **Not installed**, so they
vanished from the Pill. Nothing anywhere named `jq`, so the user's only clue was
a login prompt that could not help.

Every Script now checks the Requirements the manifest declares before it does
anything else. It reads them from `plugin.json` with `sed`, `grep` and `tr`,
because the program doing the checking is the one that may be missing. When a
Requirement is absent the Script reports `CREDS_STATUS=blocked` with
`MISSING_REQUIREMENT` naming every command that is missing, and exits without
reading a credential or making a request.

**Blocked** is a fourth Source state, beside Not installed, Missing and
Unavailable. It stays visible with a hollow ring, its tab carries a card naming
the missing commands, its Overview row carries a compact line saying the same,
and the settings page's Accounts editor shows the notice instead of an empty
Account list. Because every enabled Source is still fetched on every cycle
(ADR 0004), installing the command brings the Source back with no restart.

## Considered options

**A plugin-level preflight in the widget.** One check instead of four, and one
notice instead of four cards. But the settings page and a Script run by hand
would still mis-report, since both ask the Scripts directly, and the widget would
carry a second copy of the detection the Scripts already do.

**Widening Unavailable.** No new state, but Unavailable promises that the user
cannot fix the condition and that the last known values are stale. Here the fix
is to install a command, and there are no last known values to mark.

**Leaving it as Not installed.** Hiding already means "nothing was readable when
we looked" (ADR 0004), which is what a missing `jq` produces. But the Source is
in use and the user has credentials for it, so hiding it removes the only surface
that could explain why it left.

**Presence only, not capability.** The guard asks `command -v`, not whether the
installed `jq` can do what a Script needs. A `jq` that exists and fails still
yields the old wrong states in the three Scripts that swallow it, and that is a
separate concern from a Requirement that is absent.
