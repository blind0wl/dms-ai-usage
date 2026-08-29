Type: task
Blocked by: 03-fork-and-extend-plugin (resolved)
Status: open

## Question

Build the ChatGPT Source's fetch script, added alongside the existing `get-claude-usage` in the forked plugin: read `~/.codex/auth.json` for `tokens.access_token` + `tokens.account_id`, call `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <token>`, `ChatGPT-Account-Id: <account_id>`, `User-Agent: codex-cli`, output `plan_type`, primary/secondary window `used_percent`/`reset_at`, and credits as KEY=VALUE lines (matching the existing script's output convention so the widget's parser can handle both). On a stale/expired token (per CodexBar's approach: 8-day `last_refresh` rule or JWT `exp` within 5 min), shell out to `codex` once to force a refresh rather than attempting to refresh the token directly — same login-action spirit as ticket 4's fix for Claude. Support multiple Accounts per the domain model, even if only one is configured today.
