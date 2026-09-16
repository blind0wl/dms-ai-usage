# Sources are data, not code

Each Source the plugin tracks was hardcoded four times over: its state
properties, its `Process` and stdout parser, its pill ring, and its block of
popout cards. Adding a fourth would have copied all of it again, so a Source
became an entry in a registry (`sources.js`), and the pill, popout tabs and
settings rows are generated from it. The widget now contains no per-Source
branches.

## Considered options

**Copy the pattern a fourth time.** Fastest, and shaped like the change that
added Z.ai, but it makes the deferred refactor four copies wide instead of three.

**A registry holding one QML component per Source.** Each Source keeps a
free-form tab body, which is easy to write, but the four bodies stay four
hand-maintained copies of the same cards and adding a Source still means writing
one.

**A registry holding descriptors, with typed Sections.** Chosen. A Source is data
and a tab is an ordered list of Section types.

## Consequences

A Source's tab can only use the Section types that exist. A genuinely new kind of
card, which opencode Go's plan-and-spend header is, means adding a Section type
once rather than writing a tab body. Per-Source quirks that do not fit a Section
type have to become descriptor fields or a new type.

Descriptors name which script keys feed each Window slot instead of requiring one
shared output contract. This keeps `get-claude-usage` emitting `FIVE_HOUR_UTIL`
while the others emit `PRIMARY_UTIL`, so the refactor could not change what any
Source reports and the scripts stay mergeable against upstream. The cost is a
translation layer that a shared contract would not need.
