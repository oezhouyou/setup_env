#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

active_entries() {
  awk 'NF && $1 !~ /^#/ { print }' "$1" | sort
}

admin_entries="$(mktemp)"
base_entries="$(mktemp)"
user_entries="$(mktemp)"
trap 'rm -f "$admin_entries" "$base_entries" "$user_entries"' EXIT

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

client_zsh="$(chezmoi execute-template --override-data '{"profile":"client"}' < "$ROOT/dot_zshrc.tmpl")"

if ! grep -q '\.client_aliases' <<<"$client_zsh"; then
  echo "client profile should source ~/.client_aliases."
  exit 1
fi
