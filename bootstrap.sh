#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_DOTFILES="https://github.com/you-fractional/macbook_setup.git"

echo "==> Installing Xcode CLI tools..."
if ! xcode-select -p &>/dev/null; then
  xcode-select --install
  echo "Xcode CLI tools installation started. Re-run this script after it completes."
  exit 0
fi

echo "==> Installing Homebrew..."
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL --connect-timeout 30 --max-time 300 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)"
fi

echo "==> Installing packages from Brewfile..."
brew bundle --file="$SCRIPT_DIR/Brewfile"

echo "==> Installing oh-my-zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL --connect-timeout 30 --max-time 300 https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> Installing Powerlevel10k theme..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

echo "==> Installing chezmoi..."
if ! command -v chezmoi &>/dev/null; then
  brew install chezmoi
fi

echo "==> Initializing chezmoi from GitHub and applying dotfiles..."
# On first run: clones repo to ~/.local/share/chezmoi and applies dotfiles.
# On subsequent runs (if already initialized): updates from GitHub instead.
if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
  chezmoi update
else
  chezmoi init --apply "$GITHUB_DOTFILES"
fi

echo "==> Configuring macOS system defaults..."
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

echo "==> Configuring git globals..."
# Set delta as git pager for beautiful diffs
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.dark true
git config --global merge.conflictstyle diff3
git config --global diff.colorMoved default
# Useful git defaults
git config --global pull.rebase false
git config --global init.defaultBranch main
# Prompt for identity if not already set
if [ -z "$(git config --global user.name)" ]; then
  printf "Enter your full name for git config: "
  read -r git_name </dev/tty
  git config --global user.name "$git_name"
fi
if [ -z "$(git config --global user.email)" ]; then
  printf "Enter your email for git config: "
  read -r git_email </dev/tty
  git config --global user.email "$git_email"
fi

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

echo "==> Configuring fzf shell integration..."
if command -v fzf &>/dev/null; then
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish 2>/dev/null || true
fi

echo ""
echo "Bootstrap complete! Restart your terminal to apply shell changes."
