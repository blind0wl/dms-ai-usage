Type: task
Blocked by: 02, 04, 05
Status: open

## Question

Build the QML widget per the prototype's design (ticket 2): merged bar pill switching between the Claude and ChatGPT Sources (splittable into separate pills via settings), popout showing per-Source window detail + reset countdowns, "unavailable" state for a Source whose script reports no data. Wire both source scripts via `Process`+`SplitParser` on a `Timer`, matching `dms-claudecode`'s pattern. Persist settings (merge vs split, refresh interval, per-Account config) via `pluginData`.
