Type: task
Blocked by: 03-fork-and-extend-plugin (resolved)
Status: closed

## Question

Fix the actual bug that motivated this whole effort: `get-claude-usage` currently goes silently to all-zeros when `~/.claude/.credentials.json` is missing or the token is expired, with no way to fix it from the widget. Add a login action, matching CodexBar's confirmed mechanism: shell out to `claude auth login --claudeai` (the CLI's real login command, same public OAuth client the CLI itself uses) and surface a "Log in" affordance in the widget/popout when credentials are missing/invalid, watching for the CLI's login-success output before re-fetching usage.

## Resolution

Built and verified:

- **`get-claude-usage`**: `fetch_profile_usage` now derives a `CREDS_STATUS` per profile (`missing` / `expired` / `ok`) — missing when there's no credentials file or no usable access token in it, expired when a token exists but neither the live API call nor a matching cache produced usage data, ok once real usage data is confirmed. Emitted as a top-level `CREDS_STATUS` (from the default profile) and a per-profile `PROFILE_CREDS_STATUS` list, following the script's existing per-profile output convention. Verified all three states directly against the function (missing creds file, present-but-bad token, present-but-empty token) plus the live `ok` case against this machine's real credentials, and the full existing test suite (95 tests) still passes unmodified.
- **`ClaudeCodeUsageWidget.qml`**: parses `CREDS_STATUS`/`PROFILE_CREDS_STATUS` into `credsStatus`/`displayCredsStatus` (profile-aware, same pattern as the other display* properties). A new popout card — visible only when the selected profile's status is `missing` or `expired` — replaces the silent 0% with an explicit "Not logged in" / "Session expired" message and a "Log in" button. The button calls `startLogin(profileName)`, which resolves the right `CLAUDE_CONFIG_DIR` for the profile (via `customProfiles`, empty for default/unrecognized profiles) and runs a new `loginProcess` (`claude auth login --claudeai`) with that env. Per the map's login-action Note, no stdout pattern-matching for a success marker — the CLI's own login flow exits 0/non-zero, and `onExited` re-triggers `usageProcess` regardless (a fresh fetch is cheap and self-corrects either way).
- Added EN/FR/ES strings for the new UI text to `translations.js`, following the existing convention.
- Verified end-to-end: symlinked plugin reloaded live via `dms restart`, confirmed "Plugin loaded: aiUsage" in journalctl with no QML errors, and confirmed `CREDS_STATUS=ok` end-to-end against this machine's real (valid) credentials, so the new card correctly stays hidden when nothing is wrong.
- Did not build a dedicated "watch for login completion" state machine beyond `onExited` — the ticket's own CodexBar reference and the map's login Note both point at exit-code-driven re-fetch as the intended mechanism, not stdout scraping (the CLI's exact success string isn't a stable public contract to match against).
