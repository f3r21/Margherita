#!/usr/bin/env bash
#
# install-hook.sh
#
# Installs the Margherita statusLine hook into Claude Code WITHOUT requiring
# the macOS menu bar app. Copies statusline-indicator.sh to a stable location
# (~/.claude/margherita/) and points ~/.claude/settings.json's `statusLine`
# key at it. Useful if you only want the compact usage line in your terminal
# and don't want a menu bar icon at all.
#
# Usage: ./scripts/install-hook.sh
#
# Dependencies: bash + jq only. No network access, no Xcode/Swift required.

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required (brew install jq)" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_script="$script_dir/statusline-indicator.sh"
if [[ ! -f "$source_script" ]]; then
  echo "error: couldn't find statusline-indicator.sh next to this script" >&2
  exit 1
fi

claude_dir="$HOME/.claude"
hook_dir="$claude_dir/margherita"
dest_script="$hook_dir/statusline-indicator.sh"
settings="$claude_dir/settings.json"

mkdir -p "$hook_dir"
cp "$source_script" "$dest_script"
chmod +x "$dest_script"

mkdir -p "$claude_dir"
tmp="$(mktemp "$claude_dir/.settings.json.XXXXXX.tmp")"
trap 'rm -f "$tmp"' EXIT

if [[ -f "$settings" ]]; then
  # Fails fast (set -e) on invalid JSON rather than clobbering the user's
  # other Claude Code settings (model, env, other hooks...).
  jq --arg cmd "$dest_script" '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp"
else
  jq -n --arg cmd "$dest_script" '{statusLine: {type: "command", command: $cmd}}' > "$tmp"
fi
mv "$tmp" "$settings"

echo "Hook installed: $dest_script"
echo "Ask Claude Code a question in your terminal to see the usage line appear."
