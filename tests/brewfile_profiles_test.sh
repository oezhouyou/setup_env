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

if ! grep -q '@openai/codex@latest' "$ROOT/bootstrap.sh"; then
  echo "bootstrap.sh should install Codex CLI via npm."
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

captured_npm_args=""
npm() {
  captured_npm_args="$*"
}

saved_home="$HOME"
HOME="$temp_home"
CURRENT_PROFILE=user
install_npm_global @example/tool@latest
HOME="$saved_home"
if [ "$captured_npm_args" != "install -g --prefix $temp_home/.local @example/tool@latest" ]; then
  echo "user profile should install global npm tools into ~/.local."
  echo "Actual: $captured_npm_args"
  exit 1
fi

CURRENT_PROFILE=admin
install_npm_global @example/tool@latest
if [ "$captured_npm_args" != "install -g @example/tool@latest" ]; then
  echo "privileged profiles should keep the normal global npm install path."
  echo "Actual: $captured_npm_args"
  exit 1
fi

mkdir -p "$temp_home/bin"
touch "$temp_home/bin/sharedtool"
chmod +x "$temp_home/bin/sharedtool"

saved_path="$PATH"
PATH="$temp_home/bin:$PATH"
captured_npm_args=""
CURRENT_PROFILE=user
install_npm_cli sharedtool @example/shared@latest >/dev/null
PATH="$saved_path"
if [ -n "$captured_npm_args" ]; then
  echo "user profile should use an existing shared CLI instead of installing locally."
  echo "Actual: $captured_npm_args"
  exit 1
fi

PATH="$temp_home/bin:$PATH"
CURRENT_PROFILE=admin
install_npm_cli sharedtool @example/shared@latest >/dev/null
PATH="$saved_path"
if [ "$captured_npm_args" != "install -g @example/shared@latest" ]; then
  echo "privileged profiles should update shared CLIs even when the command already exists."
  echo "Actual: $captured_npm_args"
  exit 1
fi
unset -f npm

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
