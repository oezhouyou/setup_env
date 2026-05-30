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

mkdir -p "$NPM_CONFIG_PREFIX"

/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade
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
