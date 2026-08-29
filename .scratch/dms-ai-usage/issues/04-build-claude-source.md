Type: task
Blocked by: 01, 03-fork-and-extend-plugin (resolved)
Status: resolved
Assignee: blindowl

## Question

Build the Claude Source's fetch script: call `https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`) using a Bearer token found from `~/.claude/.credentials.json` first, falling back to Claude Desktop's credential location (per ticket 1's answer), output `FIVE_HOUR_UTIL`/`FIVE_HOUR_RESET`/`SEVEN_DAY_UTIL`/`SEVEN_DAY_RESET`/subscription info as KEY=VALUE lines matching `dms-claudecode`'s convention. Support multiple Accounts (profiles) per the domain model, even if only one is configured today. Handle the "no usable credentials anywhere" case by emitting an unavailable/empty state rather than erroring.

## Answer

**Already satisfied — no new script needed.** The fork inherited `dms-claudecode`'s `get-claude-usage` script (repo root, `/home/dave/dev/dms-ai-usage/get-claude-usage`), and it already does everything this ticket asked for:

- Calls `https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20` and a Bearer token read from each profile's `.credentials.json` (`fetch_profile_usage()`), default profile being `~/.claude/.credentials.json`.
- Outputs `SUBSCRIPTION_TYPE`/`RATE_LIMIT_TIER`/`FIVE_HOUR_UTIL`/`FIVE_HOUR_RESET`/`SEVEN_DAY_UTIL`/`SEVEN_DAY_RESET` as KEY=VALUE, plus the whole existing pacing/cost/profile-breakdown output the destination wants kept.
- Already supports multiple Accounts: auto-discovers `~/.ccs/instances/*`, `~/.ccp/profiles/*.env`, plus manual `name=path` args from plugin settings, aggregating into `PROFILES`/`PROFILE_*` lists — this satisfies the domain model's Account concept without new work.
- Verified live on this machine: ran the script directly, got real data back (`SUBSCRIPTION_TYPE=pro`, `FIVE_HOUR_UTIL=54.0`, `SEVEN_DAY_UTIL=58.0`, etc.) — confirms it's not just inherited code, it actually works end-to-end here.

**Not implemented, correctly:** the Claude Desktop credential fallback this ticket originally described. [Claude Desktop credential location](01-claude-desktop-credential-location.md) already ruled that out — Desktop's token is encrypted at rest, no script-readable fallback exists. The script's current behavior (CLI credentials only) matches that finding.

**One real gap carried forward, deliberately not fixed here:** when credentials are missing/expired, `fetch_profile_usage()` currently emits `FIVE_HOUR_UTIL=0` etc. with no signal distinguishing "genuinely 0% used" from "no usable token" — this is the exact bug [Claude login action](04-claude-login-action.md) exists to fix (needs a distinct availability signal plus the login affordance), so it's left to that ticket rather than duplicated here.
