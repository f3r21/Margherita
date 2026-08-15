#!/usr/bin/env bash
#
# uninstall-hook.sh
#
# Removes the `statusLine` key installed by install-hook.sh (or by the
# Margherita app) from ~/.claude/settings.json, leaving every other key
# untouched. Does NOT delete ~/.claude/margherita/statusline-indicator.sh
# or ~/.claude/indicator.json — only the hook wiring is removed.
#
# Usage: ./scripts/uninstall-hook.sh
#
# Dependencies: bash + jq only.

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required (brew install jq)" >&2
  exit 1
}

claude_dir="$HOME/.claude"
settings="$claude_dir/settings.json"

if [[ ! -f "$settings" ]]; then
  echo "Nothing to uninstall: $settings doesn't exist."
  exit 0
fi

tmp="$(mktemp "$claude_dir/.settings.json.XXXXXX.tmp")"
trap 'rm -f "$tmp"' EXIT

# Fails fast (set -e) on invalid JSON rather than clobbering the user's
# other Claude Code settings.
jq 'del(.statusLine)' "$settings" > "$tmp"
mv "$tmp" "$settings"

echo "Hook removed from $settings"
