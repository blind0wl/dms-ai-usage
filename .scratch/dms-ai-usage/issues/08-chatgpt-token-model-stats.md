Type: task
Blocked by: 05
Status: resolved
Assignee: blindowl

## Question

ChatGPT's popout section only has the two rate-limit window cards; Claude's has a full token/cost/model/daily-activity breakdown built from local session files, not the OAuth API. Ticket 2 assumed no equivalent local data exists for ChatGPT — that assumption was wrong: `~/.codex/sessions/**/*.jsonl` rollout files carry per-turn `token_count` events (`payload.info.last_token_usage.total_tokens`) and `turn_context` events carrying the active `model`, the same shape CodexBar likely reads for its own "top model"/token stats.

Extend `get-chatgpt-usage` to parse local rollout files (mirroring `get-claude-usage`'s `count_profile_tokens`) and emit `WEEK_TOKENS`, `MONTH_TOKENS`, `WEEK_MESSAGES` (turn count), `WEEK_SESSIONS`, `DAILY` (7-day token chart), `WEEK_MODELS` (model=tokens breakdown) per account. Wire matching cards into `ClaudeCodeUsageWidget.qml`'s ChatGPT tab (Token Consumption, Daily Activity, Models This Week), following the same visual pattern as Claude's cards. Cost/pricing is explicitly out of scope for this ticket — no reliable public price list for Codex/OpenAI models the way LiteLLM covers Claude's; token counts and model breakdown only.

## Answer

Built. `get-chatgpt-usage` gained `count_account_tokens` (mirrors `count_profile_tokens`): a single `jq -n` pass over `~/.codex/sessions/**/*.jsonl` (via `input_filename` to track per-file state) walks each file's `turn_context` events for the active model and `token_count` events for that step's token delta (`payload.info.last_token_usage.total_tokens`), emitting `kind/date/model/tokens/file` TSV rows that an `awk` pass buckets into `WEEK_TOKENS`, `WEEK_MESSAGES` (turn count), `WEEK_SESSIONS` (distinct files touched this week), `MONTH_TOKENS`, `DAILY` (7-day token chart), `WEEK_MODELS`. Runs in ~1.8s across 119 files / 131MB on this machine — fine within the 2-minute refresh interval. Aggregated across accounts the same way Claude's script aggregates across profiles (`ACCOUNT_*` lists, summed into top-level fields).

Wired into `ClaudeCodeUsageWidget.qml`'s ChatGPT tab: Token Consumption card (week/month tokens, session/message counts), Daily Activity bar chart with hover tooltip, Models This Week breakdown — visually matching Claude's equivalent cards, minus cost (no reliable public Codex/OpenAI price list the way LiteLLM covers Claude's, so cost stays explicitly out of scope). Verified: `qmllint` clean, live `dms restart` with no QML errors, and `get-chatgpt-usage`'s output checked directly against known session data on this machine (WEEK_TOKENS=6,929,304, MONTH_TOKENS=1,387,505,425, top model `gpt-5.6-sol`).
