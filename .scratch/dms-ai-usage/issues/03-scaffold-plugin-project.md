Type: task
Status: closed (out of scope)

## Question

Scaffold the new plugin project at `/home/dave/dev/dms-ai-usage` (git repo already initialized): `plugin.json` manifest (id, name, type:widget, capabilities:[dankbar-widget], component/settings paths, requires:[curl, jq], permissions:[settings_read, settings_write]), directory layout for two source scripts (e.g. `sources/get-claude-usage`, `sources/get-chatgpt-usage`), and the local dev/test loop (symlink or copy into `~/.config/DankMaterialShell/plugins/`, `dms restart`, Settings → Plugins → Scan for Plugins, `dms kill && dms run` for logs).

No source-fetching logic yet — just a scaffold that loads in DMS without crashing (an empty/placeholder widget is fine).
