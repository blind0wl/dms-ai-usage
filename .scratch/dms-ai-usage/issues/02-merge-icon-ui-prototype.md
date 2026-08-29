Type: prototype
Status: open

## Question

What should the merged bar pill and popout look like once ChatGPT is added alongside Claude in the forked widget (`ClaudeCodeUsageWidget.qml`)?

Covers:
- How the existing Claude pill (ring + %) becomes a switchable pill between Claude and ChatGPT — click to cycle? Two click targets? A settings toggle to split into separate pills instead (still wanted per the earlier merge-icons decision)?
- Popout layout when ChatGPT is selected: which of its windows to show (primary/secondary per the `wham/usage` response) alongside Claude's existing 5h/7d cards, reset countdown display, "unavailable" state with the login-action button (ticket 4) when a Source's credentials are missing/expired.
- Whether/how Claude's existing pacing, cost, profile-breakdown, and daily-chart cards adapt to a second Source, or stay Claude-only for now with ChatGPT getting a simpler initial view.

Build a rough QML mockup by adapting the existing widget file directly (it's the real starting point now, not a from-scratch skeleton) to react to.
