Type: task
Blocked by: 01, 03
Status: open

## Question

Build the Claude Source's fetch script: call `https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`) using a Bearer token found from `~/.claude/.credentials.json` first, falling back to Claude Desktop's credential location (per ticket 1's answer), output `FIVE_HOUR_UTIL`/`FIVE_HOUR_RESET`/`SEVEN_DAY_UTIL`/`SEVEN_DAY_RESET`/subscription info as KEY=VALUE lines matching `dms-claudecode`'s convention. Support multiple Accounts (profiles) per the domain model, even if only one is configured today. Handle the "no usable credentials anywhere" case by emitting an unavailable/empty state rather than erroring.
