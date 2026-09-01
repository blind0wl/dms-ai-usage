Type: bug
Status: closed

## Question

A ChatGPT "Session expired" notification appeared; clicking "Log in" flipped the button to "Logging in…" and then never resolved — no browser opened, no error, no way out short of reloading the plugin.

## Answer

Root cause: `startLogin`/`startChatgptLogin` spawned `claude auth login --claudeai` / `codex login` as bare `Process { command: [...] }` calls. Quickshell/DMS runs plugin processes with its own minimal inherited PATH (`/usr/local/bin:/usr/bin`, confirmed via `/proc/<quickshell-pid>/environ`), which doesn't include `~/.local/bin` (`claude`) or `~/.npm-global/bin` (`codex`). The process failed to spawn (`QProcess::FailedToStart`), so `onExited` never fired and `loginInProgress`/`chatgptLoginInProgress` stayed `true` forever — the button was stuck on "Logging in…" with no feedback.

`get-claude-usage`/`get-chatgpt-usage` already had this exact PATH-widening fix (with a comment documenting it) for usage fetching; the login actions never got the same treatment.

Fix: both login `Process`es now run via `bash -c` with PATH widened to the same set of common install locations (`~/.local/bin`, `~/.npm-global/bin`, `~/.cargo/bin`, etc.) the usage-fetch scripts already search. Also dropped `loginProcess.environment = {}` on the no-custom-profile path, which would have replaced the process's entire environment (including `$HOME`) rather than leaving it inherited.

Verified two ways:
- Headless repro matching Quickshell's exact restricted env (`env -i PATH="/usr/local/bin:/usr/bin" ... codex login`) went from `No such file or directory` (exit 127) to actually running the CLI once routed through the widened `bash -c`.
- Live test in the running panel: reloaded the plugin via `qs ipc call plugins reload aiUsage`, forced `chatgptCredsStatus` to missing by moving `~/.codex/auth.json` aside, clicked "Log in" in the actual popout, and confirmed via `~/.codex/log/codex-login.log` that `codex login` started, received the OAuth callback, and exchanged the token successfully.

Commit: `daee402` — "fix: widen PATH for CLI login processes so they can actually spawn".
