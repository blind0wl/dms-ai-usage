Type: task
Status: closed

## Question

Claude's pill and popout show a pacing indicator (over/under-pace arrow, colored label, ring tick mark) computed via `paceInfo()`/`drawPaceTick()`, driven by the shared `showPacing` setting. ChatGPT's primary/secondary windows show flat percentages only — no pace signal anywhere, despite `get-chatgpt-usage` already emitting real `PRIMARY_WINDOW_SECONDS`/`SECONDARY_WINDOW_SECONDS` (added in [ChatGPT token/model stats](08-chatgpt-token-model-stats.md)'s follow-up commit) that make the same linear-burn math possible. Add ChatGPT pacing to close this parity gap before the upstream PR.

## Answer

Added `chatgptPrimaryPace`/`chatgptSecondaryPace` computed properties in `ClaudeCodeUsageWidget.qml`, calling the existing `paceInfo(util, resetMs, windowMs)` with `chatgptPrimaryWindowSeconds`/`chatgptSecondaryWindowSeconds * 1000` as the window length (dynamic, from the script — more accurate than Claude's hardcoded 18000000/604800000 ms constants, since ChatGPT's window lengths aren't fixed to 5h/7d). No new setting: reuses the existing `showPacing` toggle.

Wired the same three UI touchpoints Claude has:
- Pill (`hRingGpt`/`vRingGpt`): over-pace arrow + colored percent text via new `chatgptPillOverPace`, mirroring `pillOverPace`.
- Popout primary/secondary ring canvases: `drawPaceTick()` call added to `onPaint`, with a `pace` property triggering repaint on change.
- Popout primary/secondary info columns: pace label `StyledText` added, matching Claude's five-hour/seven-day cards exactly (position, visibility condition, color).

Also hardened `paceInfo()` itself: it already treated a missing/empty reset as `unknown`/`over_quota`, but a zero window length (script default when `limit_window_seconds` is absent from the API response, or before the first fetch completes) would have produced `-Infinity` → clamped `timeFrac`, misreporting "over" pace for any nonzero util. Claude's two callers never hit this (their windows are hardcoded, never zero); ChatGPT's are the first callers to pass a dynamic window, so `!resetIso || !windowMs` now routes both failure modes to the same suppressed unknown/over_quota branch.

`qmllint`/`qmlformat` turned out to crash silently (exit 255/1, no output) against this file even *before* any of this ticket's edits (verified against the unmodified `git show HEAD:ClaudeCodeUsageWidget.qml`), so they're not usable as a signal here — a pre-existing environment quirk, not something this change introduced. Verified instead via the project's other established check: a clean `dms restart` (aiUsage loaded on all bars, no QML errors in journalctl) after the `paceInfo` guard landed. Confirmed the pace math itself is live, not a zero-window artifact: `./get-chatgpt-usage` returned real, nonzero `PRIMARY_WINDOW_SECONDS=18000`/`SECONDARY_WINDOW_SECONDS=604800` and real future reset timestamps, matching the pill's live "100% ↑" (genuinely over pace with 100% used well before the 5h window's reset) — a full interactive popout click-through was already ruled out as unreliable in this environment per [Install and verify](07-install-and-verify.md).
