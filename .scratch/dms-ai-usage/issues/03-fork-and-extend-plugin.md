Type: task
Status: resolved

## Question

Set up `/home/dave/dev/dms-ai-usage` as a real git fork of `dms-claudecode` (github.com/titeya/dms-claudecode, MIT): add it as an `upstream` remote, merge its history in with `--allow-unrelated-histories` so the existing `.scratch/` tracking stays alongside the fetched code. Rename the plugin identity to reflect multi-provider scope (id/name/description in `plugin.json` — e.g. `aiUsage`/"AI Usage" or similar; pick something reasonable, this is a low-stakes naming call). Point the local DMS install at this fork instead of the separate upstream clone at `~/.config/DankMaterialShell/plugins/claudeCodeUsage` (symlink the plugins-dir entry to this repo, or replace the directory outright) so day-to-day dev/test happens against the fork.

No feature changes yet — just the fork scaffold, renamed identity, and confirmation the renamed plugin still loads in DMS (bar pill shows, even if functionally identical to upstream at this point).

## Answer

Done. `/home/dave/dev/dms-ai-usage` is a real fork: `upstream` remote added (`github.com/titeya/dms-claudecode`), merged via `--allow-unrelated-histories` so upstream's full history sits alongside the `.scratch/` tracking already committed there. `plugin.json` renamed: id `claudeCodeUsage` → `aiUsage`, name → "AI Usage", description updated to mention ChatGPT/Codex, version reset to `0.1.0`, author credits the fork.

Local DMS install repointed: removed the old registry clone at `~/.config/DankMaterialShell/plugins/claudeCodeUsage`, symlinked `~/.config/DankMaterialShell/plugins/aiUsage` → the fork repo, updated `plugin_settings.json` and the toolbar's `rightWidgets` entry in `settings.json` from `claudeCodeUsage` to `aiUsage`. Ran `dms restart` — confirmed via `journalctl --user`: `DankBar: Plugin loaded: aiUsage`, no errors. Pill is live on the toolbar, functionally identical to upstream (no feature work done yet, as scoped).
