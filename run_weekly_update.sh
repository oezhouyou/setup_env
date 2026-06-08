#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
# self-updating apps we left alone (Teams, Granola, Zoom, ...) that are
# root-owned and fail with chown "Operation not permitted". Root-owned apps must
# be adopted by hand first (see docs/disable-auto-update-checklist.md).
MANAGED_UPDATE_CASKS=(
  iterm2
  proxyman
  tableplus
  brave-browser
  linearmouse
  codex-app
  cursor              # VS Code fork; self-updater off via update.mode:none in its settings.json
  visual-studio-code  # self-updater off via update.mode:none in settings.json
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

# Bump Python to the latest stable CPython via pyenv (mirrors the nvm LTS bump).
update_pyenv_python() {
  local latest
  export PYENV_ROOT="$HOME/.pyenv"
  if ! command -v pyenv >/dev/null 2>&1; then
    echo "Skipping Python update; pyenv is not installed."
    return 0
  fi
  latest="$(pyenv install --list 2>/dev/null | grep -E '^[[:space:]]*3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d '[:space:]' || true)"
  if [ -z "$latest" ]; then
    echo "Skipping Python update; could not resolve latest stable version."
    return 0
  fi
  pyenv install --skip-existing "$latest" || { echo "Warning: pyenv install $latest failed; continuing."; return 0; }
  pyenv global "$latest"
}

# Install/upgrade the npm CLI tools listed in Brewfile.npm using the ACTIVE nvm
# npm, so they land in the nvm node's global prefix -- the copy that is first on
# PATH and that `claude upgrade` / `codex update` also manage. Do NOT route these
# through `brew bundle`: it resolves npm to Homebrew's own Node (pulled in as a
# dependency of e.g. neonctl) and installs into /opt/homebrew, where the nvm copy
# shadows it -- so the weekly run would silently update a copy you never execute.
# The `@latest` pins mean each run pulls the newest release and repopulates the
# global prefix after an nvm LTS bump. Requires load_nvm_node to have run first.
install_npm_clis() {
  local brewfile="$1"
  local line
  local -a packages=()
  while IFS= read -r line; do
    [ -n "$line" ] && packages+=("$line")
  done < <(awk -F'"' '/^[[:space:]]*npm[[:space:]]/ { print $2 }' "$brewfile")
  if [ "${#packages[@]}" -eq 0 ]; then
    echo "No npm packages declared in $brewfile; skipping."
    return 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "Skipping npm CLI updates; npm (nvm) is not available."
    return 0
  fi
  echo "==> Updating npm CLI tools..."
  npm install -g "${packages[@]}" || echo "Warning: npm install of CLI tools failed; continuing."
}

disable_sparkle_auto_update
disable_squirrel_auto_update

/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade
upgrade_disabled_self_updaters
/opt/homebrew/bin/chezmoi git -- pull --ff-only || true

if [ -f "$NPM_BREWFILE" ]; then
  if load_nvm_node; then
    install_npm_clis "$NPM_BREWFILE"
  else
    echo "Skipping npm CLI updates; nvm is not installed."
  fi
else
  echo "Skipping npm CLI updates; $NPM_BREWFILE not found."
fi

update_pyenv_python
