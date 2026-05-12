#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

active_entries() {
  awk 'NF && $1 !~ /^#/ { print }' "$1" | sort
}

admin_entries="$(mktemp)"
user_entries="$(mktemp)"
trap 'rm -f "$admin_entries" "$user_entries"' EXIT

active_entries "$ROOT/Brewfile.admin" > "$admin_entries"
active_entries "$ROOT/Brewfile.user" > "$user_entries"

overlap="$(comm -12 "$admin_entries" "$user_entries")"
if [ -n "$overlap" ]; then
  echo "Brewfile.admin and Brewfile.user must not repeat active entries:"
  echo "$overlap"
  exit 1
fi

if ! grep -q 'Brewfile.user' "$ROOT/Brewfile.admin"; then
  echo "Brewfile.admin should document that Brewfile.user runs separately."
  exit 1
fi

if ! grep -q '^cask "azure-cli"$' "$ROOT/Brewfile.admin"; then
  echo "Brewfile.admin should include azure-cli."
  exit 1
fi

if [ -e "$ROOT/Brewfile.personal" ]; then
  echo "Brewfile.personal should be removed."
  exit 1
fi

if grep -q 'personal' "$ROOT/.chezmoi.toml.tmpl" "$ROOT/.chezmoiignore"; then
  echo "chezmoi profile config should not advertise Brewfile.personal."
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
assert_sequence consult "Brewfile Brewfile.consult"
