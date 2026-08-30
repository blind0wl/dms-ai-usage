Type: task
Blocked by: 03-fork-and-extend-plugin (resolved)
Status: resolved

## Question

Build the ChatGPT Source's fetch script, added alongside the existing `get-claude-usage` in the forked plugin: read `~/.codex/auth.json` for `tokens.access_token` + `tokens.account_id`, call `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <token>`, `ChatGPT-Account-Id: <account_id>`, `User-Agent: codex-cli`, output `plan_type`, primary/secondary window `used_percent`/`reset_at`, and credits as KEY=VALUE lines (matching the existing script's output convention so the widget's parser can handle both). On a stale/expired token (per CodexBar's approach: 8-day `last_refresh` rule or JWT `exp` within 5 min), shell out to `codex` once to force a refresh rather than attempting to refresh the token directly — same login-action spirit as ticket 4's fix for Claude. Support multiple Accounts per the domain model, even if only one is configured today.

## Resolution

Built `get-chatgpt-usage`, mirroring `get-claude-usage`'s structure and output convention (`fetch_account_usage` per-account, KEY=VALUE stdout, `CREDS_STATUS` of missing/expired/ok).

- Reads `~/.codex/auth.json` (or a per-account `CODEX_HOME`-style dir, `name=/path` from script args — same manual-entry convention as Claude's profiles) for `tokens.access_token` + `tokens.account_id` + `last_refresh`.
- Staleness check implemented as specified: `last_refresh` ≥ 8 days old, OR the JWT's own `exp` claim (decoded locally, no signature check) within 5 minutes. On stale, shells out to `CODEX_HOME=<dir> codex login status` (confirmed non-interactive, ~0.6s, no browser launch) rather than refreshing the token directly, then re-reads the auth file in case it force-refreshed.
- Calls `GET https://chatgpt.com/backend-api/wham/usage` with the required headers — verified live against this machine's real Codex credentials (HTTP 200, `plan_type=plus`, real `rate_limit.primary_window`/`secondary_window` with `used_percent`/`reset_at`/`limit_window_seconds`, `credits.balance`).
- Outputs `PLAN_TYPE`, `PRIMARY_UTIL`/`PRIMARY_RESET`/`PRIMARY_WINDOW_SECONDS`, `SECONDARY_UTIL`/`SECONDARY_RESET`/`SECONDARY_WINDOW_SECONDS`, `CREDITS_BALANCE`/`CREDITS_HAS`, `CREDS_STATUS`, plus `ACCOUNTS` and `ACCOUNT_*` per-account lists (comma-joined `name:value`, same delimiter convention as Claude's `PROFILE_*` lists) — the default account's values also drive the top-level aggregate fields, matching how `get-claude-usage` treats its default profile.
- Verified the missing-credentials path (`CREDS_STATUS=missing` when the auth dir doesn't exist) and multi-account fallback (a second, unconfigured account correctly reports `missing` while `default` still fetches live) by running the script directly with synthetic account args.
- `reset_at` here is a **unix timestamp** (seconds), unlike Claude's ISO-8601 reset strings — the widget (ticket 6) needs to handle both formats when computing countdowns.
- No test file added: no prior ticket in this fork established a tests/ convention for new scripts (ticket 4's Claude login-action work didn't add one either), so this stays consistent rather than introducing one unilaterally.
