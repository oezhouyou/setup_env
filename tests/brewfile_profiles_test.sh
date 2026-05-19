#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

active_entries() {
  awk 'NF && $1 !~ /^#/ { print }' "$1" | sort
}

admin_entries="$(mktemp)"
base_entries="$(mktemp)"
user_entries="$(mktemp)"
temp_home="$(mktemp -d)"
trap 'rm -f "$admin_entries" "$base_entries" "$user_entries"; rm -rf "$temp_home"' EXIT

active_entries "$ROOT/Brewfile" > "$base_entries"
active_entries "$ROOT/Brewfile.admin" > "$admin_entries"
active_entries "$ROOT/Brewfile.user" > "$user_entries"

base_admin_overlap="$(comm -12 "$base_entries" "$admin_entries")"
if [ -n "$base_admin_overlap" ]; then
  echo "Brewfile and Brewfile.admin must not repeat active entries:"
  echo "$base_admin_overlap"
  exit 1
fi

admin_user_overlap="$(comm -12 "$admin_entries" "$user_entries")"
if [ -n "$admin_user_overlap" ]; then
  echo "Brewfile.admin and Brewfile.user must not repeat active entries:"
  echo "$admin_user_overlap"
  exit 1
fi

if ! grep -q 'Brewfile.user' "$ROOT/Brewfile.admin"; then
  echo "Brewfile.admin should document that Brewfile.user runs separately."
  exit 1
fi

if ! grep -q '^brew "azure-cli"$' "$ROOT/Brewfile.admin"; then
  echo "Brewfile.admin should include azure-cli as a formula."
  exit 1
fi

if grep -q '^cask "azure-cli"$' "$ROOT/Brewfile.admin" "$ROOT/Brewfile.client"; then
  echo "azure-cli should be declared as a formula, not a cask."
  exit 1
fi

if ! grep -q '^cask "codex-app"$' "$ROOT/Brewfile.admin"; then
  echo "Brewfile.admin should include the Codex desktop app."
  exit 1
fi

if ! grep -q '^cask "codex-app"$' "$ROOT/Brewfile.client"; then
  echo "Brewfile.client should include the Codex desktop app."
  exit 1
fi

if ! grep -q '^vscode "openai.chatgpt"$' "$ROOT/Brewfile.user"; then
  echo "Brewfile.user should include the OpenAI Codex VS Code extension."
  exit 1
fi

if ! grep -q '^vscode "openai.chatgpt"$' "$ROOT/Brewfile.client"; then
  echo "Brewfile.client should include the OpenAI Codex VS Code extension."
  exit 1
fi

if [ ! -e "$ROOT/Brewfile.npm" ]; then
  echo "Brewfile.npm should exist for npm-managed CLI tools."
  exit 1
fi

for npm_package in '@anthropic-ai/claude-code@latest' '@openai/codex@latest'; do
  if ! grep -q "^npm \"$npm_package\"$" "$ROOT/Brewfile.npm"; then
    echo "Brewfile.npm should include $npm_package."
    exit 1
  fi

  if grep -q "$npm_package" "$ROOT/bootstrap.sh"; then
    echo "bootstrap.sh should install $npm_package through Brewfile.npm, not hardcoded npm install calls."
    exit 1
  fi
done

if ! grep -q 'Brewfile.npm' "$ROOT/.chezmoiignore"; then
  echo ".chezmoiignore should keep Brewfile.npm in the source repo only."
  exit 1
fi

if ! grep -q '\$HOME/.local/share/chezmoi/run_weekly_update.sh' "$ROOT/Library/LaunchAgents/com.brewupdate.plist"; then
  echo "weekly brew update agent should delegate to run_weekly_update.sh."
  exit 1
fi

if grep -q '/opt/homebrew/bin/brew update' "$ROOT/Library/LaunchAgents/com.brewupdate.plist"; then
  echo "weekly brew update agent should not duplicate the update flow inline."
  exit 1
fi

if ! grep -q '/usr/bin/logger -t brew-upgrade' "$ROOT/Library/LaunchAgents/com.brewupdate.plist"; then
  echo "weekly brew update agent should preserve brew-upgrade logging."
  exit 1
fi

if [ ! -x "$ROOT/run_weekly_update.sh" ]; then
  echo "run_weekly_update.sh should exist and be executable for manual weekly updates."
  exit 1
fi

for weekly_pattern in \
  'SCRIPT_DIR=' \
  'chezmoi git -- pull --ff-only' \
  'PATH=.*\$HOME/.local/bin.*/opt/homebrew/bin' \
  'NPM_CONFIG_PREFIX="\$HOME/.local"' \
  'NPM_BREWFILE="\${NPM_BREWFILE:-\$SCRIPT_DIR/Brewfile.npm}"'
do
  if ! grep -q "$weekly_pattern" "$ROOT/run_weekly_update.sh"; then
    echo "run_weekly_update.sh should include weekly flow pattern: $weekly_pattern"
    exit 1
  fi
done

if ! grep -q 'run_weekly_update.sh' "$ROOT/.chezmoiignore"; then
  echo ".chezmoiignore should keep run_weekly_update.sh in the source repo only."
  exit 1
fi

if [ -e "$ROOT/Brewfile.personal" ]; then
  echo "Brewfile.personal should be removed."
  exit 1
fi

if [ ! -e "$ROOT/Brewfile.client" ]; then
  echo "Brewfile.client should exist."
  exit 1
fi

old_profile="con""sult"

if [ -e "$ROOT/Brewfile.$old_profile" ]; then
  echo "Old client profile Brewfile should be renamed."
  exit 1
fi

if grep -q 'personal' "$ROOT/.chezmoi.toml.tmpl" "$ROOT/.chezmoiignore"; then
  echo "chezmoi profile config should not advertise Brewfile.personal."
  exit 1
fi

if rg -n "$old_profile" --hidden -g '!.git' "$ROOT"; then
  echo "Old client profile keyword should not remain in the repo."
  exit 1
fi

if ! grep -q '^profile_brewfile_names()' "$ROOT/bootstrap.sh"; then
  echo "bootstrap.sh should expose profile_brewfile_names for testable Brewfile sequencing."
  exit 1
fi

SETUP_ENV_BOOTSTRAP_LIB_ONLY=1 . "$ROOT/bootstrap.sh"

assert_sequence() {
  local profile="$1"
  local expected="$2"
  local actual

  actual="$(profile_brewfile_names "$profile" | tr '\n' ' ' | sed 's/ $//')"
  if [ "$actual" != "$expected" ]; then
    echo "Unexpected Brewfile sequence for profile '$profile'"
    echo "Expected: $expected"
    echo "Actual:   $actual"
    exit 1
  fi
}

assert_sequence admin "Brewfile Brewfile.admin Brewfile.user"
assert_sequence work "Brewfile Brewfile.admin Brewfile.user"
assert_sequence user "Brewfile.user"
assert_sequence client "Brewfile Brewfile.client"

assert_effective_profile() {
  local profile="$1"
  local can_sudo="$2"
  local expected="$3"
  local actual

  actual="$(effective_profile "$profile" "$can_sudo")"
  if [ "$actual" != "$expected" ]; then
    echo "Unexpected effective profile for profile '$profile' with can_sudo=$can_sudo"
    echo "Expected: $expected"
    echo "Actual:   $actual"
    exit 1
  fi
}

assert_effective_profile admin true admin
assert_effective_profile work true work
assert_effective_profile client true client
assert_effective_profile user true user
assert_effective_profile admin false user
assert_effective_profile work false user
assert_effective_profile client false user
assert_effective_profile user false user

if profile_needs_sudo user; then
  echo "user profile should not request sudo preflight."
  exit 1
fi

for privileged_profile in admin work client ""; do
  if ! profile_needs_sudo "$privileged_profile"; then
    echo "profile '$privileged_profile' should request sudo preflight."
    exit 1
  fi
done

saved_home="$HOME"
HOME="$temp_home"
captured_brew_args=""
captured_npm_prefix=""
brew() {
  captured_brew_args="$*"
  captured_npm_prefix="${NPM_CONFIG_PREFIX:-}"
}

run_npm_brewfile "$ROOT/Brewfile.npm"
HOME="$saved_home"

if [ "$captured_brew_args" != "bundle --file=$ROOT/Brewfile.npm" ]; then
  echo "npm Brewfile should be installed through brew bundle."
  echo "Actual: $captured_brew_args"
  exit 1
fi

if [ "$captured_npm_prefix" != "$temp_home/.local" ]; then
  echo "npm Brewfile should install CLI tools into ~/.local for predictable user-level updates."
  echo "Actual: $captured_npm_prefix"
  exit 1
fi

if [ ! -d "$temp_home/.local" ]; then
  echo "npm Brewfile should create ~/.local before using it as npm prefix."
  exit 1
fi
unset -f brew

mkdir -p "$temp_home/bin"

cat > "$temp_home/bin/code" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CODE_CALLS"
EOF
chmod +x "$temp_home/bin/code"

cat > "$temp_home/bin/brew" <<'EOF'
#!/bin/sh
echo "brew should not be called for Brewfile.user" >&2
exit 42
EOF
chmod +x "$temp_home/bin/brew"

code_calls="$temp_home/code_calls"
CODE_CALLS="$code_calls" PATH="$temp_home/bin:$PATH" run_profile_brewfile user Brewfile.user "$ROOT/Brewfile.user" "user packages" true

if ! grep -q -- '--install-extension openai.chatgpt' "$code_calls"; then
  echo "Brewfile.user should install the OpenAI Codex extension through the editor CLI."
  exit 1
fi

if ! grep -q -- '--install-extension anthropic.claude-code' "$code_calls"; then
  echo "Brewfile.user should install VS Code-compatible extensions through the editor CLI."
  exit 1
fi

user_brew_hook="$(chezmoi execute-template --override-data '{"profile":"user"}' < "$ROOT/run_onchange_brew-bundle.sh.tmpl")"
if grep -q '^brew bundle ' <<<"$user_brew_hook"; then
  echo "user profile should not run the base Brewfile onchange hook."
  exit 1
fi

admin_brew_hook="$(chezmoi execute-template --override-data '{"profile":"admin"}' < "$ROOT/run_onchange_brew-bundle.sh.tmpl")"
if ! grep -q '^brew bundle --file=' <<<"$admin_brew_hook"; then
  echo "admin profile should run the base Brewfile onchange hook."
  exit 1
fi

client_zsh="$(chezmoi execute-template --override-data '{"profile":"client"}' < "$ROOT/dot_zshrc.tmpl")"

if ! grep -q 'eza --version' <<<"$client_zsh"; then
  echo "zsh aliases should verify eza is runnable before aliasing ls."
  exit 1
fi

if ! grep -q '\.client_aliases' <<<"$client_zsh"; then
  echo "client profile should source ~/.client_aliases."
  exit 1
fi
