Type: task
Blocked by: 02, 04, 05
Status: open

## Question

Extend `ClaudeCodeUsageWidget.qml` per the prototype's design (ticket 2): wire the ChatGPT source script (ticket 5) alongside the existing Claude one via a second `Process`+`SplitParser` on the same/a second `Timer`, add the merged/switchable pill and split-pill settings toggle, wire the login action (ticket 4) into the popout's unavailable state for both Sources. Persist new settings (merge vs split, per-Account config for ChatGPT) via `pluginData`, following the existing settings patterns already in `ClaudeCodeUsageSettings.qml`.
