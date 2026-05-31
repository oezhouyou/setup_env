#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
NPM_CONFIG_PREFIX="$HOME/.local"
export NVM_DIR="$HOME/.nvm"

NPM_BREWFILE="${NPM_BREWFILE:-$SCRIPT_DIR/Brewfile.npm}"

load_nvm_node() {
  local nvm_script=""

  mkdir -p "$NVM_DIR"
  NVM_HOMEBREW_PREFIX="$(/opt/homebrew/bin/brew --prefix nvm 2>/dev/null || /usr/local/bin/brew --prefix nvm 2>/dev/null || true)"
  if [ -z "$NVM_HOMEBREW_PREFIX" ]; then
    return 1
  fi

  nvm_script="$NVM_HOMEBREW_PREFIX/nvm.sh"
  if [ ! -s "$nvm_script" ]; then
    return 1
  fi

  . "$NVM_HOMEBREW_PREFIX/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
  nvm use default
}

# Apps whose built-in self-updater we disable from this script so the weekly brew
# run becomes their single update point. Two mechanisms are used:
#   - Sparkle apps      -> SU* user-defaults keys (SPARKLE_BUNDLE_IDS below)
#   - Squirrel/Electron -> each app's own flag    (disable_squirrel_auto_update)
# Apps with no scriptable switch, and root-owned self-updaters that must be
# adopted by hand (Finder delete + brew reinstall), are documented in
# docs/disable-auto-update-checklist.md.
SPARKLE_BUNDLE_IDS=(
  com.googlecode.iterm2   # iterm2
  com.proxyman.NSProxy    # proxyman
  com.tinyapp.TablePlus   # tableplus
  com.brave.Browser       # brave-browser
  com.lujjjh.LinearMouse  # linearmouse
  com.openai.codex        # codex-app
)

# Cask tokens whose self-updater we disable here, so brew is their only update
# path. Their cask metadata still has auto_updates=true, so a plain `brew upgrade`
# skips them; we force exactly these with --greedy. Every entry must be USER-OWNED
# so brew can replace it -- a blanket `brew upgrade --greedy` would also hit
# self-updating apps we left alone (Notion, Teams, VS Code, ...) that are
# root-owned and fail with chown "Operation not permitted". Root-owned apps must
# be adopted by hand first (see docs/disable-auto-update-checklist.md).
MANAGED_UPDATE_CASKS=(
  iterm2
  proxyman
  tableplus
  brave-browser
  linearmouse
  codex-app
  slack       # Squirrel app; disabled via disable_squirrel_auto_update
  claude      # Squirrel app; disabled via disable_squirrel_auto_update
  notion      # Squirrel app; adopted manually via Finder delete + brew reinstall
)

disable_sparkle_auto_update() {
  for bid in "${SPARKLE_BUNDLE_IDS[@]}"; do
    defaults write "$bid" SUEnableAutomaticChecks -bool false 2>/dev/null || true
    defaults write "$bid" SUAutomaticallyUpdate -bool false 2>/dev/null || true
  done
}

# Squirrel/Electron apps ignore Sparkle SU* keys; each exposes its own flag.
disable_squirrel_auto_update() {
  # slack: vendor-supported flag (com.tinyspeck.slackmacgap)
  defaults write com.tinyspeck.slackmacgap SlackNoAutoUpdates -bool true 2>/dev/null || true
  # claude: Anthropic enterprise key (com.anthropic.claudefordesktop)
  defaults write com.anthropic.claudefordesktop disableAutoUpdates -bool true 2>/dev/null || true
  # notion: official flag (notion.id); only effective while Notion is user-owned
  defaults write notion.id NotionNoAutoUpdates -bool true 2>/dev/null || true
}

# Force-upgrade the disabled-self-updater casks that are installed AND user-owned.
# An app that self-updated with elevation becomes root-owned; a non-root brew
# cannot chown it (and macOS App Management blocks it anyway), which is the chown
# "Operation not permitted" failure -- so such an app is skipped here and must be
# adopted first (Finder delete + brew reinstall; see the checklist doc). A failure
# must not abort the weekly run, so it is logged and skipped.
upgrade_disabled_self_updaters() {
  local installed me cask appname owner
  installed="$(/opt/homebrew/bin/brew list --cask 2>/dev/null)"
  me="$(id -un)"
  for cask in "${MANAGED_UPDATE_CASKS[@]}"; do
    printf '%s\n' "$installed" | grep -qx "$cask" || continue
    appname="$(/opt/homebrew/bin/brew list --cask "$cask" 2>/dev/null | grep -oE '/[^/]+\.app' | head -1 | sed 's#^/##')"
    if [ -n "$appname" ] && [ -d "/Applications/$appname" ]; then
      owner="$(stat -f '%Su' "/Applications/$appname")"
      if [ "$owner" != "$me" ]; then
        echo "Skipping $cask: /Applications/$appname is $owner-owned; adopt via Finder delete + brew reinstall."
        continue
      fi
    fi
    /opt/homebrew/bin/brew upgrade --cask --greedy "$cask" \
      || echo "Warning: failed to upgrade cask $cask; continuing."
  done
}

mkdir -p "$NPM_CONFIG_PREFIX"

disable_sparkle_auto_update
disable_squirrel_auto_update

/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade
upgrade_disabled_self_updaters
/opt/homebrew/bin/chezmoi git -- pull --ff-only || true

if [ -f "$NPM_BREWFILE" ]; then
  if load_nvm_node; then
    NPM_CONFIG_PREFIX="$NPM_CONFIG_PREFIX" /opt/homebrew/bin/brew bundle --file="$NPM_BREWFILE"
  else
    echo "Skipping npm CLI updates; nvm is not installed."
  fi
else
  echo "Skipping npm CLI updates; $NPM_BREWFILE not found."
fi
