# MacBook Setup Bootstrap — Design Spec
Date: 2026-04-07

## Overview

A one-time bootstrap script to reproduce a full MacBook developer environment from scratch. Combines `brew bundle` for app/tool installs with `chezmoi` for dotfile management.

## Repo Structure

```
macbook_setup/
├── bootstrap.sh          # Entry point — run this on a fresh Mac
├── Brewfile              # All formulae, casks, and editor extensions
├── home/
│   ├── dot_zshrc         # chezmoi-managed ~/.zshrc
│   └── dot_p10k.zsh      # chezmoi-managed ~/.p10k.zsh
└── .chezmoi.toml.tmpl    # chezmoi config pointing source to home/
```

chezmoi maps `dot_` prefix files to their dotfile equivalents on `chezmoi apply` (e.g. `dot_zshrc` → `~/.zshrc`).

## Bootstrap Flow (`bootstrap.sh`)

1. Install Xcode CLI tools (`xcode-select --install`) — required for git and compilers
2. Install Homebrew if not already present
3. Run `brew bundle --file=./Brewfile` — installs all formulae, casks, and editor extensions
4. Install oh-my-zsh if not already installed (non-interactive)
5. Install Powerlevel10k theme into `~/.oh-my-zsh/custom/themes/`
6. Install chezmoi via brew
7. `chezmoi init --source=$(pwd)` — point chezmoi at this repo
8. `chezmoi apply` — copies dotfiles to home directory

### Usage

On a fresh Mac, run either:
```bash
# If cloned locally
./bootstrap.sh

# Or directly from GitHub (once pushed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOU/macbook_setup/main/bootstrap.sh)"
```

## Brewfile Contents

```ruby
# CLI tools
brew "node"
brew "uv"
brew "neonctl"

# Apps
cask "iterm2"
cask "brave-browser"
cask "cursor"
cask "claude"
cask "slack"
cask "zoom"
cask "notion"
cask "microsoft-teams"
cask "fathom"
cask "granola"
cask "linearmouse"

# Cursor extensions (VS Code compatible)
vscode "anthropic.claude-code"
```

## Dotfiles

- `home/dot_zshrc` — copy of current `~/.zshrc` (oh-my-zsh + Powerlevel10k theme, git plugin, PATH exports)
- `home/dot_p10k.zsh` — copy of current `~/.p10k.zsh` (1720-line Powerlevel10k prompt config)

## Error Handling

- Each bootstrap step checks for prior installation before running (idempotent where possible)
- `set -e` in bootstrap.sh ensures the script stops on any failure
- Brew bundle is run with `--no-lock` to avoid committing a lock file

## Out of Scope

- Multi-machine sync (this is one-time bootstrap, not ongoing chezmoi sync)
- Mac App Store apps (mas not installed; GarageBand, iMovie, Keynote, etc. are system apps)
- SSH key generation or git credential setup
