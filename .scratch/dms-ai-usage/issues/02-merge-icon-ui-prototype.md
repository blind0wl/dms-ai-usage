Type: prototype
Status: open

## Question

What should the merged bar pill and popout actually look like for 2 Sources (Claude, ChatGPT)?

Covers:
- The merged pill's default appearance (icon/ring/percent for whichever Source is "active"), and how switching between Sources works (click to cycle? two click targets side by side?).
- The settings toggle that splits the merged pill into one pill per Source instead.
- Popout layout per Source: which windows to show (Claude: 5h + 7d; ChatGPT: primary + secondary), reset countdown display, "unavailable" state appearance when a Source's data can't be fetched.

Build a rough QML/UI mockup (or borrow/adapt `dms-claudecode`'s `ClaudeCodeUsageWidget.qml` pill+popout structure as a starting skeleton) to react to, rather than describing it in prose only.
