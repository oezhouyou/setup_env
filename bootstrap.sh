#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_brew_bundle() {
  local label="$1"
  local brewfile="$2"
  local tolerate_failure="${3:-false}"

  echo "==> Installing $label..."
  if [ "$tolerate_failure" = "true" ]; then
    brew bundle --file="$brewfile" || brew bundle --file="$brewfile" || true
  else
    brew bundle --file="$brewfile" || brew bundle --file="$brewfile"
  fi
}

profile_brewfile_names() {
  case "$1" in
    work|admin)
      printf '%s\n' Brewfile Brewfile.admin Brewfile.user
      ;;
    user)
      printf '%s\n' Brewfile.user
      ;;
    client)
      printf '%s\n' Brewfile Brewfile.client
      ;;
    "")
      printf '%s\n' Brewfile
      ;;
    *)
      printf '%s\n' Brewfile "Brewfile.$1"
      ;;
  esac
}

profile_needs_sudo() {
  case "$1" in
    user)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

SUDO_KEEPALIVE_PID=""

start_sudo_keepalive() {
  # Prompt for sudo once upfront so pkg-based cask installs don't interrupt the process.
  # Refresh every 10s to beat the tty_tickets timeout on macOS.
  echo "==> Requesting sudo access (required for some app installers)..."
  sudo -v
  while true; do sudo -v; sleep 10; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
  if [ -n "$SUDO_KEEPALIVE_PID" ]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
}

install_npm_global() {
  local package="$1"

  if [ "$CURRENT_PROFILE" = "user" ]; then
    mkdir -p "$HOME/.local"
    npm install -g --prefix "$HOME/.local" "$package"
  else
    npm install -g "$package"
  fi
}

install_npm_cli() {
  local command_name="$1"
  local package="$2"

  if [ "$CURRENT_PROFILE" = "user" ] && command -v "$command_name" &>/dev/null; then
    echo "==> $command_name already available; using existing install."
    return 0
  fi

  install_npm_global "$package"
}

if [ "${SETUP_ENV_BOOTSTRAP_LIB_ONLY:-}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

trap stop_sudo_keepalive EXIT

# Repo URL used by chezmoi init. Defaults to the origin of the repo this
# script lives in, so forks work out of the box. Override with:
#   GITHUB_DOTFILES=https://github.com/you/macbook_setup.git ./bootstrap.sh
GITHUB_DOTFILES="${GITHUB_DOTFILES:-$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)}"
if [ -z "$GITHUB_DOTFILES" ]; then
  echo "ERROR: could not determine repo URL. Set GITHUB_DOTFILES or run this script from a cloned repo."
  exit 1
fi

# Git identity is prompted by chezmoi init (.chezmoi.toml.tmpl) and written
# to ~/.gitconfig via dot_gitconfig.tmpl — no pre-flight needed.

echo "==> Installing Xcode CLI tools..."
if ! xcode-select -p &>/dev/null; then
  xcode-select --install
  echo "Xcode CLI tools installation started. Re-run this script after it completes."
  exit 0
fi

echo "==> Setting up Homebrew..."
if ! command -v brew &>/dev/null; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL --connect-timeout 30 --max-time 300 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)"
fi

echo "==> Installing chezmoi..."
if ! command -v chezmoi &>/dev/null; then
  brew install chezmoi
fi

echo "==> Installing oh-my-zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL --connect-timeout 30 --max-time 300 https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> Installing Powerlevel10k theme..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

echo "==> Initializing chezmoi from GitHub and applying dotfiles..."
# Compare the current profile in chezmoi.toml against the last-applied profile.
# If they differ (or first run), reinit to reset chezmoi onchange state so
# profile-specific Brewfile and dotfile conditionals re-run from scratch.
CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
PROFILE_STATE="$HOME/.config/chezmoi/.last_profile"
CURRENT_PROFILE=""
if [ -f "$CHEZMOI_CONFIG" ]; then
  CURRENT_PROFILE=$(grep 'profile' "$CHEZMOI_CONFIG" | sed 's/.*= *"\(.*\)"/\1/')
fi
LAST_PROFILE=""
if [ -f "$PROFILE_STATE" ]; then
  LAST_PROFILE=$(cat "$PROFILE_STATE")
fi

if [ ! -d "$HOME/.local/share/chezmoi/.git" ]; then
  # First run — init prompts for profile via .chezmoi.toml.tmpl
  chezmoi init --apply "$GITHUB_DOTFILES"
  CURRENT_PROFILE=$(grep 'profile' "$CHEZMOI_CONFIG" | sed 's/.*= *"\(.*\)"/\1/')
elif [ -n "$CURRENT_PROFILE" ] && [ "$CURRENT_PROFILE" != "$LAST_PROFILE" ]; then
  # Profile changed — reinit to reset onchange state and apply new profile
  echo "Profile changed ($LAST_PROFILE → $CURRENT_PROFILE), reinitializing chezmoi..."
  chezmoi init --apply "$GITHUB_DOTFILES"
else
  # Same profile — just pull latest from GitHub
  chezmoi update
fi

# Always save current profile and run profile Brewfile explicitly.
# run_onchange_ is unreliable for this since profile changes reset chezmoi state.
echo "$CURRENT_PROFILE" > "$PROFILE_STATE"
if profile_needs_sudo "$CURRENT_PROFILE"; then
  start_sudo_keepalive
else
  echo "==> Skipping sudo preflight for user profile..."
fi

for PROFILE_BREWFILE_NAME in $(profile_brewfile_names "$CURRENT_PROFILE"); do
  PROFILE_BREWFILE="$(chezmoi source-path)/$PROFILE_BREWFILE_NAME"
  if [ -f "$PROFILE_BREWFILE" ]; then
    BREWFILE_PROFILE="${PROFILE_BREWFILE_NAME#Brewfile.}"
    TOLERATE_BREW_FAILURE=true
    if [ "$PROFILE_BREWFILE_NAME" = "Brewfile" ]; then
      TOLERATE_BREW_FAILURE=false
    fi
    run_brew_bundle "$BREWFILE_PROFILE packages" "$PROFILE_BREWFILE" "$TOLERATE_BREW_FAILURE"
  fi
done

# Claude Code install/update intentionally skipped in bootstrap.

# Codex CLI is installed via npm to match the latest CLI release.
echo "==> Installing/updating Codex CLI via npm..."
install_npm_cli codex @openai/codex@latest

echo "==> Configuring macOS system defaults..."
# Dark mode
osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to true'
# Key repeat — faster typing, no press-and-hold popup
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Dock — auto-hide with no delay
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.5
# Finder — show hidden files and full path in title bar
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
# Disable .DS_Store on network and USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
# Restart affected apps to apply
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "==> Setting up SSH key..."
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$HOME/.ssh/id_ed25519" -N ""
  ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519"
  echo ""
  echo "Your SSH public key (add this to GitHub → Settings → SSH Keys):"
  echo "---"
  cat "$HOME/.ssh/id_ed25519.pub"
  echo "---"
else
  echo "SSH key already exists, skipping."
fi

# Remove old cron job if present from previous bootstrap runs
crontab -l 2>/dev/null | grep -v "brew update" | crontab - 2>/dev/null || true
# Note: com.brewupdate launchd agent is managed by chezmoi via
# Library/LaunchAgents/com.brewupdate.plist + run_onchange_load-brewupdate.sh.tmpl

echo "==> Configuring fzf shell integration..."
if command -v fzf &>/dev/null; then
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish 2>/dev/null || true
fi

stop_sudo_keepalive

echo ""
echo "Bootstrap complete! Restart your terminal to apply shell changes."
