# Disabling app auto-update (manual checklist)

Goal: make the weekly `run_weekly_update.sh` (`brew upgrade --greedy`) the single
update point for cask apps, by turning off each app's *own* self-updater.

The script handles the Sparkle-based apps automatically (iterm2, proxyman,
tableplus, brave-browser, linearmouse, codex-app) via `defaults write … SUEnableAutomaticChecks false`.
The apps below do **not** use Sparkle, so they can't be scripted and must be
turned off by hand. Tick each one once done.

## Settings-file controllable (VSCode family)

These can be set in your user `settings.json` and committed to dotfiles —
no clicking needed:

- [ ] **Visual Studio Code** (`com.microsoft.VSCode`) — set `"update.mode": "none"`
- [ ] **Cursor** (`com.todesktop.230313mzl4w4u92`) — set `"update.mode": "none"`
      (Cursor is VSCode-based; same setting. Note Cursor may still nag about
      app-level updates separately.)

## In-app toggle only

Open each app and flip the setting:

- [ ] **Zoom** (`us.zoom.xos`) — Settings → General → uncheck
      "Automatically keep Zoom Desktop Client up to date"
- [ ] **Docker Desktop** — Settings (gear) → Software updates → uncheck
      "Automatically check for updates"
- [ ] **Raycast** (`com.raycast.macos`) — Settings → Advanced → "Auto-update" →
      turn off automatic updates
- [ ] **Microsoft Teams** (`com.microsoft.teams2`) — no reliable user toggle;
      new Teams auto-updates. Best effort: managed via org policy / MAU.
- [ ] **Slack** (`com.tinyspeck.slackmacgap`) — no user toggle; Slack updates
      silently on restart. Cannot be fully disabled without MDM.
- [ ] **Notion** (`notion.id`) — no user toggle; updates on relaunch.
- [ ] **Claude** (`com.anthropic.claudefordesktop`) — no user toggle; auto-updates.
- [ ] **Granola** (`com.granola.app`) — no user toggle exposed; auto-updates.
- [ ] **Ollama** (`com.electron.ollama`) — no user toggle exposed; auto-updates.

## Notes

- Apps marked "no user toggle" cannot be reliably stopped without MDM/profiles.
  For those, `brew upgrade --greedy` simply keeps the cask metadata in sync; the
  app may have already updated itself.
- Re-check this list after any major app reinstall — settings can reset.
- The Sparkle apps are re-disabled on every weekly run (the script re-applies the
  `defaults` each time), since apps sometimes rewrite these keys on launch/update.
