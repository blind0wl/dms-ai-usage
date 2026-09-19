# Install checklist

Run this before a release that touches install, plugin activation, the Source
registry, or any fetch script. It is the only check that walks the whole path a new
user takes. `tests/` covers the scripts, the QML, the registry and `plugin.json`, and
none of that installs anything.

The method is to make the machine look like it has never had the plugin, then follow
only the README. Two rules make it worth doing:

- **Only the README counts.** Anything you have to work out for yourself is a README
  gap, and gets fixed or filed.
- **Anything that surprises you gets filed**, as its own issue, not as a paragraph in
  a report.

This checklist was written from the run recorded on #56. The traps at the end are
things that run uncovered.

## What you need

- A live DMS session. A dedicated VM is not needed; every step here is reversible on a
  machine you work on.
- `sudo`, for the one step that hides `jq`.
- All four Sources credentialled, so a failure points at the plugin rather than at a
  missing account.
- Eyes on the bar. Several checks are things only you can see.
- About half an hour, most of it waiting for refresh cycles.

## 1. Back up

```bash
STAMP=$(date +%Y%m%dT%H%M%S)
TESTDIR=~/.local/share/aiusage-install-test
mkdir -p "$TESTDIR"
tar czf "$TESTDIR/dms-config-$STAMP.tar.gz" -C ~/.config DankMaterialShell
sha256sum "$TESTDIR/dms-config-$STAMP.tar.gz" > "$TESTDIR/dms-config-$STAMP.tar.gz.sha256"
echo "$STAMP" > "$TESTDIR/STAMP"

tar tvzf "$TESTDIR/dms-config-$STAMP.tar.gz" | grep plugins/aiUsage
```

Do not add `-h`. `plugins/aiUsage` is usually a symlink to your working copy, tar keeps
symlinks as symlinks by default, and `-h` would copy the entire working tree into the
archive instead.

- [ ] The last command shows an `l` in the first column and an arrow pointing at your
      working copy, not the contents of that directory
- [ ] Before each JSON edit in step 2, save the value you remove. The GUI cannot delete
      keys, so a settings walk will not leave the file byte-identical to this backup.

Restore, if you need it:

```bash
STAMP=$(cat "$TESTDIR/STAMP")
systemctl --user stop dms
mv ~/.config/DankMaterialShell ~/.config/DankMaterialShell.pre-restore-$STAMP
tar xzf "$TESTDIR/dms-config-$STAMP.tar.gz" -C ~/.config
systemctl --user start dms
```

## 2. Park the install

This uses `jq`, so do it before step 3 hides it. DMS rewrites some config on exit, so
stop it first.

```bash
TESTDIR=~/.local/share/aiusage-install-test
systemctl --user stop dms
pgrep -x dms || echo "dms is stopped"

# Record where the widget sits before removing it, so you can put it back.
jq '.barConfigs[0].rightWidgets | to_entries[] | select(.value.id == "aiUsage")' \
  ~/.config/DankMaterialShell/settings.json

jq '.aiUsage' ~/.config/DankMaterialShell/plugin_settings.json \
  > "$TESTDIR/removed-plugin_settings.aiUsage.json"

mv ~/.config/DankMaterialShell/plugins/aiUsage "$TESTDIR/parked-aiUsage"
jq 'del(.aiUsage)' ~/.config/DankMaterialShell/plugin_settings.json > /tmp/ps.json \
  && mv /tmp/ps.json ~/.config/DankMaterialShell/plugin_settings.json
jq '.barConfigs[0].rightWidgets |= map(select(.id != "aiUsage"))' \
  ~/.config/DankMaterialShell/settings.json > /tmp/s.json \
  && mv /tmp/s.json ~/.config/DankMaterialShell/settings.json

systemctl --user start dms
grep -rl aiUsage ~/.config/DankMaterialShell/ || echo "no references left"
```

- [ ] The AI Usage pill disappears from the bar
- [ ] `grep` finds no references left
- [ ] `journalctl --user -u dms` shows the plugin no longer loading

## 3. Hide jq

The plugin declares `jq` and `curl` in `plugin.json`. DMS does not read that field, so
nothing enforces it, and the interesting question is what a user without `jq` sees.

```bash
sudo mv /usr/bin/jq /usr/bin/jq.off
command -v jq || echo "jq is gone"
systemctl --user restart dms
```

If you would rather not touch the system, skip to step 4 and note in your report that
the requirement check went unrun. Removing `curl` instead is not equivalent: on Arch it
has reverse dependencies, and `jq` does not.

## 4. Install from the README

Open the README's Installation section and follow it literally. For the manual path:

```bash
git clone https://github.com/blind0wl/dms-ai-usage \
  ~/.config/DankMaterialShell/plugins/aiUsage
systemctl --user restart dms
dms plugins list
```

- [ ] `dms plugins list` shows the plugin
- [ ] No pill appears, because the clone alone is not enough. Check the log and record
      whether the plugin loaded at all:

```bash
journalctl --user -u dms --since "5 minutes ago" | grep -i aiusage
```

## 5. Enable and place

These are two separate steps that write two separate files, and the README has to say
so. Both are GUI only: `dms plugins` has no subcommand for either.

1. `Mod + ,` then Plugins, then enable AI Usage.
2. Then DankBar, and add AI Usage to the right side of the bar.

```bash
jq '.aiUsage' ~/.config/DankMaterialShell/plugin_settings.json
jq '.barConfigs[0].rightWidgets | map(.id)' ~/.config/DankMaterialShell/settings.json
```

- [ ] The enable writes `{"enabled": true}` to `plugin_settings.json`, and the plugin
      loads. Check the log timestamp against the file's.
- [ ] Placing writes the widget entry to `settings.json`
- [ ] The pill appears only after the second step

## 6. Record the state with jq absent

With every Source credentialled and `jq` missing, look at the pill and record what you
see before fixing anything. This state is the evidence for #58 and #59.

- [ ] Z.ai and opencode Go are absent, despite valid keys in `~/.pi/agent/models.json`
      and `~/.pi/agent/auth.json`. The README promises a Source with nothing set up is
      hidden, so the failure hides itself.
- [ ] ChatGPT offers a sign-in and a Setup guide link, on an account whose `~/.codex/auth.json`
      is valid. Run the script to see why:

```bash
~/.config/DankMaterialShell/plugins/aiUsage/get-chatgpt-usage | grep CREDS_STATUS
```

- [ ] Claude shows zeros with no error prompt at all. Its emitted `CREDS_STATUS` is
      empty, which matches neither the login predicate nor the pill's reading predicate,
      so nothing renders.
- [ ] Nothing anywhere names `jq`: not the DMS log, not the widget, not the scripts.
      All four scripts still exit 0.

## 7. Put jq back and watch recovery

```bash
sudo mv /usr/bin/jq.off /usr/bin/jq
```

Watch the pill without touching anything.

- [ ] Claude and ChatGPT correct themselves within one refresh cycle, which is two
      minutes by default
- [ ] Z.ai and opencode Go may stay absent. This is #57: a Source reporting
      `not_installed` is dropped from the set the widget fetches, and no timer asks it
      again. Its Settings toggle still reads on.

Recover them with either:

```bash
systemctl --user restart dms
```

or by changing the Source order or an enable toggle in settings, which refetches every
Source. Neither is discoverable, and that is the point of #57.

- [ ] All four Sources show live figures

## 8. Credential states

Park a credential file to see the Missing card, then put it back. Do not re-run the
OAuth logins; the card is the thing being checked, and re-authenticating a working
machine is a poor trade.

ChatGPT is the cleaner Source to test with, because its fetch has no cache:

```bash
TESTDIR=~/.local/share/aiusage-install-test
cp -p ~/.codex/auth.json "$TESTDIR/codex-auth.json.copy"
mv ~/.codex/auth.json ~/.codex/auth.json.parked
systemctl --user restart dms
~/.config/DankMaterialShell/plugins/aiUsage/get-chatgpt-usage | grep CREDS_STATUS
```

Claude works too, and parking its file is safe: the credential check runs before any
cache logic, so a renamed file reports `missing` at once. What is not safe is testing
Claude by emptying or revoking the token in place, because a rejected token can serve
cached values as `ok` for up to 30 minutes.

- [ ] The script reports `missing` rather than `ok`
- [ ] The Source stays visible rather than hiding, per the vocabulary in `CONTEXT.md`
- [ ] Its tab shows `Not logged in` and `Usage data unavailable until you log in.`, with
      a sign-in button that runs that Source's own login command
- [ ] Its Setup guide link opens that Source's README section, for example
      `https://github.com/blind0wl/dms-ai-usage#chatgpt`
- [ ] Its ring goes hollow rather than drawing a zero
- [ ] Its Overview row keeps a sign-in as well

Then put it back:

```bash
mv ~/.codex/auth.json.parked ~/.codex/auth.json
systemctl --user restart dms
```

- [ ] The Source reports a live reading again

## 9. Settings surface

Every control, once. There is no CLI for any of this, so it is a click-through. No
control here needs a restart; all of them apply live, and any advice to the contrary is
wrong.

1. Refresh interval: drag one notch right, then back to 2.
2. Show pacing: off, then on.
3. Overview: off, then on.
4. Sources: toggle one off, then on.
5. Move that Source back with the arrows.
6. Accounts: add one custom entry of each kind that applies to you, then remove it.

```bash
cat ~/.config/DankMaterialShell/plugin_settings.json
```

- [ ] Each control leaves the key you expect
- [ ] The pill or popout reflects each change
- [ ] The Overview is absent with one Source visible and present with two or more
- [ ] A custom account appears in that Source's popout, and the selector appears once
      there are two real accounts

## 10. Restore the machine

```bash
TESTDIR=~/.local/share/aiusage-install-test
systemctl --user stop dms
rm -rf ~/.config/DankMaterialShell/plugins/aiUsage
mv "$TESTDIR/parked-aiUsage" ~/.config/DankMaterialShell/plugins/aiUsage
jq --slurpfile parked "$TESTDIR/removed-plugin_settings.aiUsage.json" \
  '.aiUsage = $parked[0]' ~/.config/DankMaterialShell/plugin_settings.json > /tmp/ps.json \
  && mv /tmp/ps.json ~/.config/DankMaterialShell/plugin_settings.json
systemctl --user start dms
```

Re-add the widget entry to `settings.json` at the position you recorded in step 2.

- [ ] The pill is back with the Sources and the order you started with

## Traps this checklist exists to catch

- **Enabling and placing are separate.** A user who enables and then looks for the pill
  finds nothing, and the Settings page does not say a second step exists.
- **No setting needs a restart.** Every control saves on change and the widget picks it
  up live.
- **Every settings save refetches every Source**, because the widget reassigns its
  plugin data wholesale. The refresh interval slider saves on each increment, so
  dragging it start to finish runs the scripts once per notch.
- **Re-enabling a Source moves it to the end** of the ring and tab order, with no
  warning. Disabling splices it out of `sources` altogether, which is why the Settings
  list drops it among the disabled rows, and enabling then appends it. Switch a Source
  off and on again and it lands last.
- **A Source that reports `not_installed` stays hidden** until a restart or any settings
  save. Its credentials being fine does not bring it back (#57).
- **`jq` missing produces wrong data, not an error**, and nothing names the cause
  (#58). One fetch script also aborts mid-run and emits an undefined status (#59).
- **A bad API key is accepted** when you add it. The rejection appears later, in the
  popout, once you select that account. Expect `API key rejected` with a pointer at the
  plugin settings.
- **The account selector appears at two real accounts**, not three, because an `all`
  entry is prepended to the list the widget counts.
- **The GUI cannot delete keys.** After a settings walk the file holds explicit
  default-valued keys, so it will not match your backup byte for byte even when every
  value is back to default. Restore from the tarball when that matters.

## Not covered

- The registry install path, `dms plugins install aiUsage`, which depends on the
  listing being current. That is #36.
- Upgrading over an existing install, and uninstalling.
- Compositors other than the one you test on, and distributions other than Arch.
- The OAuth login flows. The cards that offer them are checked; the logins themselves
  are not re-run.
