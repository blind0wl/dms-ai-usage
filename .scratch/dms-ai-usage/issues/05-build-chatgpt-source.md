Type: task
Blocked by: 03
Status: open

## Question

Build the ChatGPT Source's fetch script: read `~/.codex/auth.json` for `tokens.access_token` + `tokens.account_id`, call `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <token>`, `ChatGPT-Account-Id: <account_id>`, `User-Agent: codex-cli`, output `plan_type`, primary/secondary window `used_percent`/`reset_at`, and credits as KEY=VALUE lines. On a stale/expired token (per CodexBar's approach: 8-day `last_refresh` rule or JWT `exp` within 5 min), shell out to `codex` once to force a refresh rather than attempting to refresh the token directly. Support multiple Accounts per the domain model, even if only one is configured today.
