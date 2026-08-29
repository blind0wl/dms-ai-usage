Type: map

## Destination

A working DankMaterialShell (DMS/Quickshell) toolbar plugin, installed and running on this machine (Arch/niri), showing usage meters + reset countdowns for two Sources: **Claude** and **ChatGPT**. Scope matches CodexBar's "basics": a merged bar pill (switchable per Source, splittable into separate pills in settings), a popout with per-Source detail, no cost/spend tracking, no incident/status badges. This is a build effort — the map carries execution, not just decisions (see Notes).

## Notes

- **This map carries execution.** Tickets include real implementation work (Task type), not only decisions. Resolve build tickets by doing the work and recording what was built/verified.
- Domain (from grilling + domain-modeling this session):
  - **Provider**: a vendor grouping (Anthropic, OpenAI) used only for icon/color/ordering — not itself a unit of data-fetching.
  - **Source**: one local data-fetch mechanism with its own script + parsing. Exactly two in scope: **Claude** (Anthropic OAuth usage API) and **ChatGPT** (Codex CLI's stored OAuth token against the ChatGPT backend). A Source is app-agnostic where possible — Claude's Source should reflect usage regardless of whether it came from CLI or Desktop, since the underlying rate limit is per-account.
  - **Account**: a credential set within a Source (e.g. multiple Claude profiles). Modeled generally on every Source from the start, even though ChatGPT only has one today.
  - **Usage figure**: a single "% of quota used" shown in the pill, taken from whichever window is nearest to resetting. The popout may show all of a Source's windows.
  - **Window**: a rolling quota period a Source's usage resets against (Claude: 5h + 7d; ChatGPT: primary + secondary per the `wham/usage` response). Not every Source needs the same window shapes.
  - **Reset countdown**: only meaningful where a Source's data actually carries a reset timestamp. Claude Desktop's local file (`plan-usage-history.json`) does NOT carry one (rolling window, no clock-boundary reset) — the Anthropic OAuth usage API does. ChatGPT's `wham/usage` response does (`reset_at` per window).
- If a Source's data genuinely can't be fetched, show it as "unavailable" in the UI rather than dropping it from the plugin.
- Reference facts gathered this session (don't re-research):
  - DMS plugin shape confirmed via the installed example `~/.config/DankMaterialShell/plugins/claudeCodeUsage` (github.com/titeya/dms-claudecode): `plugin.json` manifest, QML `PluginComponent` with `horizontalBarPill`/`verticalBarPill` + `popoutContent`, `Process`+`SplitParser` running a bundled bash script on a `Timer`, KEY=VALUE stdout parsing, `PluginService`/`pluginData` for settings.
  - Claude: `dms-claudecode`'s script calls `GET https://api.anthropic.com/api/oauth/usage` with header `anthropic-beta: oauth-2025-04-20` and a bearer token from `~/.claude/.credentials.json`, returning `FIVE_HOUR_UTIL`/`FIVE_HOUR_RESET`/`SEVEN_DAY_UTIL`/`SEVEN_DAY_RESET`. This is account-level, so should reflect Desktop usage too IF a valid token is available — the open question is where Desktop stores its own OAuth token, for use as a fallback credential source (see ticket 1).
  - Claude Desktop also writes `~/.config/Claude/plan-usage-history.json` locally: time-series samples `{t, org, u:{fh, sd, xu}}`. Confirmed `fh`=5h util%, `sd`=7d util%, both 0-100, rolling (not fixed-clock) windows — no reset timestamp field anywhere in the file. `xu` ("extra usage"?) is unreliable — present in <4% of samples, not in current data. Useful only as a fallback signal, not for countdowns.
  - ChatGPT: `~/.codex/auth.json` has `tokens.access_token` (JWT) + `tokens.account_id`. `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <token>`, `ChatGPT-Account-Id: <account_id>`, `User-Agent: codex-cli` — verified live on this machine, HTTP 200, returns `plan_type`, `rate_limit.primary_window`/`secondary_window` (each with `used_percent`, `reset_at`), `credits`. CodexBar deliberately never refreshes this token itself (races the `codex` CLI's own writer) — treat a stale/expired token as "run `codex` once to force a refresh," not as something to POST to refresh directly.
  - Dead ends already ruled out: ChatGPT desktop app (official, `/usr/lib/chatgpt`) has never been launched on this machine, no local data. `codex-desktop`'s "ChatGPT" Electron app (`/opt/codex-desktop`, config at `~/.config/Codex`) has no usage/quota file, only generic browser storage. CodexBar's actual ChatGPT-web path is Keychain/WKWebView/browser-cookie decryption — macOS-only, not needed here since the OAuth endpoint above already covers it.
  - User does not want GitHub Copilot CLI included.

## Decisions so far

(none yet — tickets below are the first frontier)

## Not yet specified

- Exact merge-icon switcher interaction (click to cycle? separate click targets? keyboard shortcut?) once the prototype ticket resolves.
- Whether to submit to the DMS plugin registry (`plugins.danklinux.com`) or keep this local-only — not decided, revisit once the plugin works.

## Out of scope

- Cost/spend tracking (CodexBar's Usage & Spend view) — ruled out during destination-naming.
- Incident/status badges — ruled out during destination-naming.
- GitHub Copilot CLI as a third Source — user declined during scoping.
- ChatGPT desktop app as a distinct data source — ruled out after research confirmed no local usage data exists there; ChatGPT's Source is satisfied entirely by the Codex CLI's stored auth against `wham/usage`.
