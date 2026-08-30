Type: prototype
Status: resolved
Assignee: blindowl

## Question

What should the merged bar pill and popout look like once ChatGPT is added alongside Claude in the forked widget (`ClaudeCodeUsageWidget.qml`)?

Covers:
- How the existing Claude pill (ring + %) becomes a switchable pill between Claude and ChatGPT — click to cycle? Two click targets? A settings toggle to split into separate pills instead (still wanted per the earlier merge-icons decision)?
- Popout layout when ChatGPT is selected: which of its windows to show (primary/secondary per the `wham/usage` response) alongside Claude's existing 5h/7d cards, reset countdown display, "unavailable" state with the login-action button (ticket 4) when a Source's credentials are missing/expired.
- Whether/how Claude's existing pacing, cost, profile-breakdown, and daily-chart cards adapt to a second Source, or stay Claude-only for now with ChatGPT getting a simpler initial view.

Build a rough QML mockup by adapting the existing widget file directly (it's the real starting point now, not a from-scratch skeleton) to react to.

## Answer

**Chosen: Variant B — merged dual-ring pill, always visible; popout stacks both Sources' sections.**

Three structurally different mockups were built as a standalone HTML prototype (not real QML — see the throwaway `prototype/merge-icon-ui` branch, commit `e18c8c2`, `.scratch/dms-ai-usage/prototypes/02-merge-icon-ui-prototype.html`) and shown to the user:

- **A** — single ring, click-to-cycle between Sources, popout as tabs.
- **B** — two small rings side by side in one pill (Claude | ChatGPT), always both visible, no clicking needed to see either Source's status. Popout is a single scrolling panel with both Sources' cards stacked under their own section header (no tabs, no switching).
- **C** — a "smart" single ring that auto-shows whichever Source is closer to its ceiling, with a settings toggle to split into two independent pills; popout as an accordion.

User picked **B** outright ("B looks good"), no mixing with the others requested.

Design implications for [Build widget](06-build-widget.md):
- The bar pill becomes two small rings (Claude, ChatGPT) in one pill, divided by a hairline — not a cycling/switching interaction. No settings toggle for merge-vs-split is needed (split-pill was C's idea, not adopted).
- Popout: two stacked sections, each with its own header (`Claude`, `ChatGPT`) and its own set of window cards (5h/7d for Claude, primary/secondary for ChatGPT) — both always rendered, no tab/profile-style switching between Sources.
- Existing Claude-only cards (pacing, cost, profile breakdown, daily chart) stay under the Claude section, unchanged; ChatGPT's section only needs its window cards for now (no equivalent pacing/cost UI exists for it).
- Unavailable-Source state (ticket 4's login action) renders as its own card within that Source's section, not a separate global state — matches the "unavailable" card style prototyped in variant B/C.

## Amendment (post-ticket-7)

After using the real widget on this machine's actual screen, variant B's "always both sections stacked" popout proved too tall. **Pill stays B** (dual-ring, both always visible, no change), but the **popout adopts A's tab-strip idea**: a Claude/ChatGPT tab row at the top of the popout, only the selected Source's cards render below it. Implemented directly in `ClaudeCodeUsageWidget.qml` (`popoutSourceTab` property, defaults to "claude"; each section's existing Column got a `visible: root.popoutSourceTab === "..."` binding rather than a redesign of the cards themselves). Verified via `qmllint` (clean) and a live `dms restart` (plugin loads with no QML errors). No settings persistence for the tab choice — matches how `selectedProfile` already resets per session.
