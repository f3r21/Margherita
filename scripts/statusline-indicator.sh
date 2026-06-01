#!/usr/bin/env bash
#
# statusline-indicator.sh
#
# Claude Code invokes this as its `statusLine` command, piping the session
# JSON payload on stdin. The script extracts the rate-limit meters and writes
# them atomically to ~/.claude/indicator.json, which the Margherita menu
# bar app watches. It also prints a compact usage line as the visible status.
#
# Dependencies: bash + jq only. No network access.

set -euo pipefail

input="$(cat)"

# `rate_limits` is only present for Claude.ai (Pro/Max) sessions, and only
# after the first API response. When absent, leave the output file untouched
# and emit nothing.
if ! printf '%s' "$input" | jq -e '(.rate_limits // {}) | length > 0' >/dev/null 2>&1; then
  exit 0
fi

out="$HOME/.claude/indicator.json"
tmp="$HOME/.claude/.indicator.json.tmp"
trap 'rm -f "$tmp"' EXIT

# Build indicator.json. Meter names are not hardcoded: every key under
# `rate_limits` is carried through so future meters surface automatically.
printf '%s' "$input" | jq '{
  updated_at: (now | todateiso8601),
  primary_meter: (
    if (.rate_limits | has("seven_day")) then "seven_day"
    else (.rate_limits | keys | sort | .[0])
    end
  ),
  rate_limits: (
    .rate_limits
    | to_entries
    | map({
        key: .key,
        value: {
          used_percentage: (.value.used_percentage // 0),
          resets_at_unix: (.value.resets_at // 0)
        }
      })
    | from_entries
  )
}' > "$tmp"

# Atomic replace: the app watches the parent directory for this rename.
mv "$tmp" "$out"

# Visible status line: compact per-meter usage, e.g. "7d 31% · 5h 12%".
printf '%s' "$input" | jq -r '
  def meterName(k):
    if k == "seven_day" then "7d"
    elif k == "five_hour" then "5h"
    else k end;
  .rate_limits
  | to_entries
  | map("\(meterName(.key)) \(.value.used_percentage // 0 | floor)%")
  | join(" · ")
'
