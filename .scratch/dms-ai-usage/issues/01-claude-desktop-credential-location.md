Type: research
Status: open

## Question

Where does Claude Desktop store its own OAuth credentials/access token locally (on Linux, this install), and are they in a format a bash script can read and use as a Bearer token against `https://api.anthropic.com/api/oauth/usage` (the same endpoint `dms-claudecode` calls using `~/.claude/.credentials.json`)?

Context: the OAuth usage endpoint is account-level, so it should reflect usage from both Claude Code CLI and Claude Desktop as long as a valid token is available. `dms-claudecode` only looks in `~/.claude/.credentials.json` (CLI's own credential file). If Desktop stores its own token elsewhere (e.g. under `~/.config/Claude/`), the new Claude Source script should try both locations — CLI's file first, falling back to Desktop's — so usage tracking works regardless of which app the user is actively using.

Investigate:
- Search `~/.config/Claude/` for anything resembling an OAuth access/refresh token (check `config.json`'s `oauth:tokenCacheV2`/`oauth:tokenCache` keys noticed this session — decode their structure).
- Confirm the token's format/scopes are compatible with a direct call to `api.anthropic.com/api/oauth/usage` (same header shape as `dms-claudecode`'s script: `anthropic-beta: oauth-2025-04-20`, `Authorization: Bearer <token>`).
- If Desktop's token needs different handling (different beta header, different endpoint, encrypted at rest, etc.), note that precisely.
- If no usable Desktop-side credential exists at all, say so plainly — the fallback in that case is to only use `~/.claude/.credentials.json` and treat "no CLI auth" as the Claude Source's unavailable state.

Report findings as a comment on this ticket file's `## Answer` section per the resolve convention.
