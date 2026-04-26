# MacBook Setup Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a one-time bootstrap script that reproduces a full MacBook developer environment (Homebrew packages, GUI apps, oh-my-zsh + Powerlevel10k, dotfiles) from scratch using `brew bundle` and `chezmoi`.

**Architecture:** A single `bootstrap.sh` entry point installs Homebrew, runs `brew bundle` from a `Brewfile`, sets up oh-my-zsh + Powerlevel10k, then uses `chezmoi` to apply dotfiles from `home/`. Dotfiles live in `home/` with chezmoi's `dot_` prefix convention so `chezmoi apply --source=$(pwd)/home` maps them to the correct locations in `~`.

**Tech Stack:** Bash, Homebrew, Homebrew Bundle, chezmoi, oh-my-zsh, Powerlevel10k

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `Brewfile` | Create | Declares all formulae, casks, and editor extensions |
| `home/dot_zshrc` | Create | chezmoi-managed copy of `~/.zshrc` |
| `home/dot_p10k.zsh` | Create | chezmoi-managed copy of `~/.p10k.zsh` |
| `bootstrap.sh` | Create | Entry point — runs all setup steps in order |

No `.chezmoi.toml.tmpl` needed — we pass `--source` directly on the CLI, which is sufficient for a one-time local bootstrap.

---

### Task 1: Initialize git repository

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Init git repo**

```bash
cd ~/wkspace/macbook_setup
git init
```

Expected: `Initialized empty Git repository in .../macbook_setup/.git/`

- [ ] **Step 2: Create .gitignore**

```
.DS_Store
```

Save as `~/wkspace/macbook_setup/.gitignore`.

- [ ] **Step 3: Stage and commit**

```bash
git add .gitignore docs/
git commit -m "chore: init repo with design spec"
```

---

### Task 2: Create Brewfile

**Files:**
- Create: `Brewfile`

- [ ] **Step 1: Write Brewfile**

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

Save as `~/wkspace/macbook_setup/Brewfile`.

- [ ] **Step 2: Verify Brewfile syntax and check current install status**

```bash
brew bundle check --file=./Brewfile --verbose
```

Expected: Lines like `Using node`, `Using uv`, etc. for already-installed items. This validates the Brewfile is parseable and all cask names are valid.

- [ ] **Step 3: Commit**

```bash
git add Brewfile
git commit -m "feat: add Brewfile with formulae, casks, and editor extensions"
```

---

### Task 3: Copy dotfiles into chezmoi source directory

**Files:**
- Create: `home/dot_zshrc`
- Create: `home/dot_p10k.zsh`

- [ ] **Step 1: Create home/ directory and copy dotfiles**

```bash
mkdir -p ~/wkspace/macbook_setup/home
cp ~/.zshrc ~/wkspace/macbook_setup/home/dot_zshrc
cp ~/.p10k.zsh ~/wkspace/macbook_setup/home/dot_p10k.zsh
```

- [ ] **Step 2: Verify chezmoi dry-run applies them correctly**

```bash
chezmoi apply --dry-run --verbose --source=~/wkspace/macbook_setup/home 2>&1
```

Expected output includes lines like:
```
install ~/.zshrc
install ~/.p10k.zsh
```
(or "unchanged" if already identical to current dotfiles — both are valid)

- [ ] **Step 3: Commit**

```bash
git add home/
git commit -m "feat: add chezmoi-managed dotfiles (zshrc, p10k)"
```

---

### Task 4: Write bootstrap.sh

**Files:**
- Create: `bootstrap.sh`

- [ ] **Step 1: Write bootstrap.sh**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing Xcode CLI tools..."
if ! xcode-select -p &>/dev/null; then
  xcode-select --install
  echo "Xcode CLI tools installation started. Re-run this script after it completes."
  exit 0
fi

echo "==> Installing Homebrew..."
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)"
fi

echo "==> Installing packages from Brewfile..."
brew bundle --file="$SCRIPT_DIR/Brewfile" --no-lock

echo "==> Installing oh-my-zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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

echo "==> Applying dotfiles with chezmoi..."
chezmoi apply --source="$SCRIPT_DIR/home"

echo ""
echo "Bootstrap complete! Restart your terminal to apply shell changes."
```

Save as `~/wkspace/macbook_setup/bootstrap.sh`.

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/wkspace/macbook_setup/bootstrap.sh
```

- [ ] **Step 3: Syntax check**

```bash
bash -n ~/wkspace/macbook_setup/bootstrap.sh
```

Expected: No output (clean syntax).

- [ ] **Step 4: Verify SCRIPT_DIR resolves correctly**

```bash
cd ~/wkspace/macbook_setup && bash -c 'source bootstrap.sh; echo $SCRIPT_DIR' 2>/dev/null || true
# Alternatively just spot-check the variable expansion manually
bash -c 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; echo "$SCRIPT_DIR"' 
```

Expected: Prints a valid absolute path (current directory or similar).

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: add bootstrap.sh entry point"
```

---

### Task 5: Smoke test end-to-end (non-destructive)

- [ ] **Step 1: Verify all cask names resolve in brew**

```bash
cd ~/wkspace/macbook_setup
brew bundle check --file=./Brewfile --verbose 2>&1 | grep -E "(Using|Installing|not installed)"
```

Expected: All entries show `Using ...` (already installed). No errors about unknown cask names.

- [ ] **Step 2: Verify chezmoi apply is idempotent**

```bash
chezmoi apply --dry-run --verbose --source=~/wkspace/macbook_setup/home 2>&1
```

Expected: All files show as unchanged (since they match the current dotfiles exactly).

- [ ] **Step 3: Verify bootstrap.sh reports clean on a pre-installed machine**

```bash
cd ~/wkspace/macbook_setup
bash bootstrap.sh 2>&1
```

Expected: All steps print their `==>` header and skip installation (already installed). Final line: `Bootstrap complete! Restart your terminal to apply shell changes.`

- [ ] **Step 4: Final commit**

```bash
git add -A
git status  # confirm nothing unexpected is staged
git commit -m "chore: verified bootstrap smoke test passes"
```
