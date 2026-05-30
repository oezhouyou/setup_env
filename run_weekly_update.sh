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

disable_sparkle_auto_update() {
  for bid in "${SPARKLE_BUNDLE_IDS[@]}"; do
    defaults write "$bid" SUEnableAutomaticChecks -bool false 2>/dev/null || true
    defaults write "$bid" SUAutomaticallyUpdate -bool false 2>/dev/null || true
  done
}

mkdir -p "$NPM_CONFIG_PREFIX"

disable_sparkle_auto_update

/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade --greedy
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
