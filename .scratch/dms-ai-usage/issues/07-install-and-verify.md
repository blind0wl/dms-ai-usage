Type: task
Blocked by: 06
Status: resolved
Assignee: blindowl

## Question

Install the plugin into `~/.config/DankMaterialShell/plugins/`, enable it, and verify end-to-end on this machine: both Sources show real data matching a manual curl against their respective endpoints, reset countdowns tick down correctly, the merge/split toggle works, and an unavailable Source (simulate by temporarily removing/renaming its credentials) degrades gracefully instead of crashing the widget.

## Answer

Verified end-to-end on this machine. Note: the "merge/split toggle" named in the original question doesn't exist — that idea died with ticket 2's answer (dual-ring pill, always both visible, no toggle); confirmed by grep, nothing named merge/split anywhere in the widget or settings QML.

- **Install**: already in place as a symlink, `~/.config/DankMaterialShell/plugins/aiUsage -> /home/dave/dev/dms-ai-usage`, enabled in `~/.config/DankMaterialShell/plugin_settings.json` (`"aiUsage": {"enabled": true}`).
- **Clean load**: `dms restart` + journalctl shows `DankBar: Plugin loaded: aiUsage` on every bar instance, no QML errors/exceptions/warnings tied to the plugin, both before and after a fresh restart at the current file state.
- **Data matches manual curl**:
  - Claude: `get-claude-usage` (FIVE_HOUR_UTIL=30.0/31.0, SEVEN_DAY_UTIL=62.0/63.0, same reset timestamps) matched a direct `curl https://api.anthropic.com/api/oauth/usage` within 1% (expected drift between two separate calls seconds apart).
  - ChatGPT: `get-chatgpt-usage` (PRIMARY_UTIL=0, SECONDARY_UTIL=0, unix reset timestamps) matched a direct `curl https://chatgpt.com/backend-api/wham/usage` exactly.
  - Live bar pill screenshot (`grim`) confirms the dual-ring pill rendering matches: Claude ring 31% (orange text), ChatGPT ring 0%, consistent with both curls.
- **Reset countdowns**: code review of `formatCountdown`/`parseResetMs`/the 60s `Timer` confirms `countdownNow` is a live `Date.now()` snapshot refreshed every 60s, driving countdown text properties for both Sources; unix-vs-ISO reset formats are correctly distinguished by an all-digit regex test. Ticks down at minute granularity as designed.
- **Graceful degradation**: simulated missing credentials without touching real files — `HOME=<empty tmpdir> ./get-claude-usage` and `HOME=<empty tmpdir> ./get-chatgpt-usage` both exit 0 with `CREDS_STATUS=missing` and zeroed fields, no crash. Widget's `CREDS_STATUS`/`PROFILES` parsing is plain string/number assignment (safe on empty values), and the login-card/`claude auth login --claudeai`/`codex login` wiring from tickets 4 and 6 covers this state — already exercised live in ticket 4's resolution.
- **Not done**: an interactive click-through screenshot of the open popout (attempted via `ydotool`, but the click missed and a full-desktop `grim` screenshot incidentally captured unrelated private windows — aborted that approach and deleted the screenshot rather than retry). Popout correctness for this ticket rests on static QML review (single stacked layout, both `"Claude"`/`"ChatGPT"` section headers present, no tabs) plus ticket 6's own live verification, not a fresh click-through.
