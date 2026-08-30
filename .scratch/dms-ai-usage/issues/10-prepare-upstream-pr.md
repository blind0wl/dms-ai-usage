Type: task
Blocked by: 09, 11
Status: open

## Question

Package the fork for submission as a PR to `github.com/titeya/dms-claudecode`. Scoped separately from [Optional Source support](09-optional-source-support.md) so that behavioral work doesn't get tangled with documentation/packaging — this ticket is mostly mechanical, done once 09's behavior is final.

Covers:
- Rewrite `README.md`: still describes the original Claude-only plugin (title "Claude Code Usage", no mention of ChatGPT/Codex, the new settings toggles, or the `codex` optional requirement). Needs a title/description update, a ChatGPT features section mirroring the existing Claude one, and a note that both Sources are optional (Requirements section currently implies Claude Code is mandatory).
- Update `screenshot.png` to show the dual-ring pill (currently shows the original single-ring Claude-only pill).
- Decide/confirm `plugin.json` naming (`aiUsage`/"AI Usage") is what actually gets proposed upstream — the maintainer may want a different id/name than the personal fork's, or may want it as a separate plugin rather than a rename of the existing one. This is a real open question for the PR description, not something to silently decide here.
- Write the PR body itself: what changed, why (the original silent-zeros bug plus the ChatGPT addition), and call out the Q4 asymmetry decision from this round's grilling (Claude and ChatGPT are both optional/symmetric) explicitly, since a maintainer may push back and prefer Claude stay mandatory.
- Check for anything else a reviewer would flag: `plugin.json`'s `requires` list (`jq`, `curl`) is fine since `codex`/`claude` binaries are optional per ticket 09, not hard requirements.

## Answer

