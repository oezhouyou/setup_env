# Disabling app auto-update

Goal: make Homebrew the single update point for cask apps by turning off each
app's *own* self-updater. Apps fall into three buckets.

## 1. Automated by `run_weekly_update.sh` (nothing to do)

Disabled on every weekly run, then force-upgraded via `brew upgrade --cask --greedy`:

- **Sparkle apps** — `defaults write <id> SUEnableAutomaticChecks/SUAutomaticallyUpdate false`:
  iterm2, proxyman, tableplus, brave-browser, linearmouse, codex-app
- **Squirrel/Electron apps** — each app's own flag:
  - Slack (`com.tinyspeck.slackmacgap` → `SlackNoAutoUpdates`)
  - Claude (`com.anthropic.claudefordesktop` → `disableAutoUpdates`, Anthropic's
    enterprise key; documented as MDM-only, so verify it sticks on your build)

VS Code and Cursor are handled declaratively via `"update.mode": "none"` in their
tracked `settings.json` (not by the weekly script).

## 2. Root-owned self-updaters — manual one-time "adopt" (Finder + brew)

Some apps install **root-owned** and self-update with elevated privileges. The
weekly run skips them (its upgrade step is ownership-aware): a non-root `brew`
cannot chown them, and on macOS 13+ **App Management blocks the chown even with
`sudo`**, so there is no scripted way to take them over. Adopt one by hand, once:

1. Quit the app.
2. In **Finder**, drag the app from `/Applications` to the Trash (authenticate),
   then empty the Trash. Finder may remove protected bundles; the terminal can't.
3. Reinstall fresh — now user-owned:
   ```bash
   brew reinstall --cask <cask>
   ```
4. Disable its self-updater (key below) so it never re-roots, then add `<cask>`
   to `MANAGED_UPDATE_CASKS` in `run_weekly_update.sh`; the ownership guard will
   now let the weekly run keep it current.

Per-app self-updater keys:

- **Notion** (`notion.id` → `NotionNoAutoUpdates`) — already adopted & in the weekly list.
- **Zoom** (`sudo defaults write /Library/Preferences/us.zoom.config AU2_EnableAutoUpdate -bool false`; Zoom ≥ 5.10.6)
- **Docker Desktop** (`/Library/Application Support/com.docker.docker/admin-settings.json`
  → `disableUpdate`, sudo; officially Business-tier, best-effort otherwise). Docker
  is usually already user-owned, so it can skip the Finder step.

## 3. No clean off switch (manual / network-level only)

No scriptable toggle exists for these as of 2026:

- [ ] **Microsoft Teams** (`com.microsoft.teams2`) — only lever is the *global*
      Microsoft AutoUpdate `HowToCheck=Manual` (affects all Office apps, deprecated)
      and Teams hard-blocks sign-in after ~3 months stale. Manage via Microsoft
      AutoUpdate.app; not worth scripting.
- [ ] **Raycast** (`com.raycast.macos`) — custom in-house updater (not Sparkle/
      Squirrel). No toggle/key. Only option: block its release host in LuLu /
      Little Snitch.
- [ ] **Granola** (`com.granola.app`) — Electron/Squirrel, no key. Block
      `download.granola.ai` + `dr2v7l5emb758.cloudfront.net`, or `chmod 000` its
      `Squirrel.framework/.../ShipIt`.
- [ ] **Ollama** (`com.electron.ollama`) — no in-app disable (issues #4498/#6024/
      #11804). Cleanest fix: drop the menu-bar app and use the Homebrew **formula**
      CLI so updates come only from brew. (Blocking `ollama.com` also breaks
      `ollama pull`.)

## Notes

- The weekly script does NOT run a blanket `brew upgrade --greedy`. That would
  force-upgrade every self-updating cask, including the root-owned ones above,
  failing with chown "Operation not permitted". It scopes `--greedy` to the
  curated `MANAGED_UPDATE_CASKS` list (all user-owned).
- Disabling defaults are re-applied on every weekly run, since apps sometimes
  rewrite these keys on launch/update.
- Re-check after any major app reinstall — ownership and settings can reset.
