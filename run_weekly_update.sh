#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NPM_CONFIG_PREFIX="$HOME/.local"

NPM_BREWFILE="${NPM_BREWFILE:-$SCRIPT_DIR/Brewfile.npm}"

mkdir -p "$NPM_CONFIG_PREFIX"

/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade
/opt/homebrew/bin/chezmoi git -- pull --ff-only || true

if [ -f "$NPM_BREWFILE" ]; then
  /opt/homebrew/bin/brew bundle --file="$NPM_BREWFILE"
else
  echo "Skipping npm CLI updates; $NPM_BREWFILE not found."
fi
