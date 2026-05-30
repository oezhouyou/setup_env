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

# Sparkle-based apps whose built-in self-updater we can disable from a script,
# so the weekly `brew upgrade --greedy` run below becomes the single update
# point. Each entry is a CFBundleIdentifier; the trailing comment is the cask.
#
# NOTE: the remaining auto-updating casks do not use Sparkle and must be turned
# off from within each app's own settings. See:
#   docs/disable-auto-update-checklist.md
SPARKLE_BUNDLE_IDS=(
  com.googlecode.iterm2   # iterm2
  com.proxyman.NSProxy    # proxyman
  com.tinyapp.TablePlus   # tableplus
  com.brave.Browser       # brave-browser
  com.lujjjh.LinearMouse  # linearmouse
  com.openai.codex        # codex-app
)

# Cask tokens for the same apps. Their cask metadata still has auto_updates=true,
# so a plain `brew upgrade` skips them; once the in-app updater is disabled, brew
# is their only update path and must force them with --greedy. We scope --greedy
# to exactly these (all user-owned) rather than a blanket `brew upgrade --greedy`,
# which would also try to upgrade self-updating apps we left alone (Notion, Teams,
# VS Code, ...) that are root-owned and fail with chown "Operation not permitted".
SPARKLE_CASKS=(
  iterm2
  proxyman
  tableplus
  brave-browser
  linearmouse
  codex-app
)

disable_sparkle_auto_update() {
  for bid in "${SPARKLE_BUNDLE_IDS[@]}"; do
    defaults write "$bid" SUEnableAutomaticChecks -bool false 2>/dev/null || true
    defaults write "$bid" SUAutomaticallyUpdate -bool false 2>/dev/null || true
  done
}

# Force-upgrade only the disabled-self-updater casks that are actually installed.
# A single cask failure must not abort the weekly run, so it is logged and skipped.
upgrade_disabled_self_updaters() {
  local installed cask
  installed="$(/opt/homebrew/bin/brew list --cask 2>/dev/null)"
  for cask in "${SPARKLE_CASKS[@]}"; do
    if printf '%s\n' "$installed" | grep -qx "$cask"; then
      /opt/homebrew/bin/brew upgrade --cask --greedy "$cask" \
        || echo "Warning: failed to upgrade cask $cask; continuing."
    fi
  done
}

mkdir -p "$NPM_CONFIG_PREFIX"

disable_sparkle_auto_update

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
