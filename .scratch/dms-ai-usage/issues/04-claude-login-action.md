Type: task
Blocked by: 03-fork-and-extend-plugin (resolved)
Status: open

## Question

Fix the actual bug that motivated this whole effort: `get-claude-usage` currently goes silently to all-zeros when `~/.claude/.credentials.json` is missing or the token is expired, with no way to fix it from the widget. Add a login action, matching CodexBar's confirmed mechanism: shell out to `claude auth login --claudeai` (the CLI's real login command, same public OAuth client the CLI itself uses) and surface a "Log in" affordance in the widget/popout when credentials are missing/invalid, watching for the CLI's login-success output before re-fetching usage.
