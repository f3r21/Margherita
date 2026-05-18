# claude-usage-menubar

A native macOS menu bar app that shows live Claude usage from Claude
Code, with no auth tokens, API reverse-engineering, or scraping. It
hooks into Claude Code's documented `statusLine` extension point.

> Personal portfolio project — not affiliated with Anthropic.

<!-- TODO: add screenshots (light menu bar + dark menu bar + popover) -->

## What it does

Renders a small adaptive icon (default 18×18 pt) showing your weekly
(`seven_day`) or session (`five_hour`) Claude quota at a glance. The
icon is a **template image**: macOS tints it to match the menu bar
background — same behavior as the system icons like CPU/RAM/battery.

Two states:

- **Available** — opaque clockwise wedge from 12 o'clock representing
  what's still in your bucket. 100% available = full disc, 0% = empty.
- **Waiting for reset** — translucent (alpha 0.55) wedge growing
  clockwise from 12 as the reset window approaches. A ghost of the
  full disc reappears the closer you are to the reset.

Click the icon for a popover with the live percentage, the meter
picker (5 h / 7 d), an "updated X ago" stamp, a manual-slider mode for
testing, and shape options (circle / 3–10-sided polygon).

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon or Intel
- [Claude Code](https://claude.com/code) ≥ 2.1.x signed into a Pro or
  Max Claude.ai account (the `rate_limits` field in the statusLine
  payload is subscriber-only)
- `jq` — preinstalled on macOS; `brew install jq` if missing
- Xcode Command Line Tools: `xcode-select --install`

You do **not** need to install Xcode itself. The build uses `swift
build` and a `Makefile` that assembles the `.app` bundle by hand.

## Install

```bash
git clone https://github.com/<your-user>/claude-usage-menubar
cd claude-usage-menubar
make install
```

`make install` compiles in release mode, wraps the binary in
`ClaudeIndicator.app`, and copies it to `/Applications`. Launch it
once so it appears in the menu bar.

Then wire up the statusLine hook in `~/.claude/settings.json` (merge
with whatever else you already have under that key):

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/claude-usage-menubar/scripts/statusline-indicator.sh"
  }
}
```

After your next prompt in Claude Code the script writes
`~/.claude/indicator.json` and the menu bar app picks it up via a
directory watcher.

To uninstall: remove the `statusLine` key from `~/.claude/settings.json`
(or flip the popover into manual mode) and delete `/Applications/ClaudeIndicator.app`.

## How it works

```
Claude Code  ─[stdin JSON]─►  statusline-indicator.sh
                                       │
                                       ▼ atomic mv
                              ~/.claude/indicator.json
                                       │
                                       ▼ DispatchSourceFileSystemObject
                              RateLimitFileWatcher (Swift)
                                       │
                                       ▼ @Published
                              IndicatorModel  ──►  menu bar icon
```

1. `scripts/statusline-indicator.sh` is registered as the statusLine
   command. On each prompt cycle Claude Code passes a JSON payload via
   stdin containing `.rate_limits.{five_hour,seven_day}.used_percentage`
   and reset timestamps (for subscribers, after the first API
   response).
2. The script normalizes the payload and writes `~/.claude/indicator.json`
   atomically (write-to-tmp + rename). Pure `bash` + `jq`, no other
   dependencies.
3. The app's `RateLimitFileWatcher` watches `~/.claude` with a
   `DispatchSourceFileSystemObject` (watching the **directory**, not
   the file — the atomic mv replaces the inode and a file-level watch
   misses the event).
4. `IndicatorModel` computes `percent = 100 − used_percentage` from
   the primary meter and republishes; the `MenuBarLabel` view
   re-renders the icon as an `NSImage` template.

Schema of `~/.claude/indicator.json`:

```json
{
  "updated_at": "2026-05-18T12:34:56Z",
  "primary_meter": "seven_day",
  "rate_limits": {
    "seven_day": { "used_percentage": 31.0, "resets_at_unix": 1747000000 },
    "five_hour": { "used_percentage": 12.0, "resets_at_unix": 1746500000 }
  }
}
```

When `percent` hits 0, the app anchors the moment (`hitZeroAt`,
persisted in `UserDefaults`) and interpolates `resetProgress` against
`resets_at_unix`. A 60 s `Timer` advances the reset wedge even while
the underlying JSON doesn't change.

## Configuration

All exposed in the popover and persisted in `UserDefaults` under the
bundle id `local.claude-indicator`:

- **Data source**: `statusLine` (default if the JSON file exists at
  launch) or `manual` (slider-driven, for testing).
- **Primary meter**: `seven_day` (default — the weekly cap on Max) or
  `five_hour` (the session window).
- **Shape**: circle (smooth wedge) or regular polygon with 3–10 sides
  (discrete segments).

## Design decisions

The non-obvious calls behind the implementation, in case you're
reading this as a portfolio piece.

**statusLine over the API.** Claude Code stores OAuth credentials in
the macOS Keychain (`Claude Code-credentials-*`). The actual `/usage`
data lives in HTTP response headers (`anthropic-ratelimit-unified-*`)
returned by the messages endpoint — there is no dedicated public
endpoint. Reverse-engineering would mean extracting the access token
from Keychain and replaying a request. Possible but brittle, and the
shape of the unofficial headers could change without notice. The
statusLine hook is a documented extension point that delivers the same
data via stdin. Strictly more robust, and it sidesteps the auth
problem entirely.

**Template image (`isTemplate = true`).** Without this, the icon
renders the literal colors I draw (white wedge on transparent). White
disappears on a light menu bar; pure black disappears on a dark one.
Setting `isTemplate = true` tells macOS to treat the image as an alpha
mask and tint it with the correct system foreground color for the
current context — identical behavior to the built-in CPU/battery
icons. The drawing code uses only black with varying alpha (1.0 for
"available", 0.55 for "reset progress", 0.0 for transparent). Color
choice is delegated to the OS.

**Directory watcher, not file watcher.** The statusLine script writes
atomically (`mv tmp final`). On macOS the rename replaces the inode,
so a `DispatchSourceFileSystemObject` opened against the **file path**
keeps watching the old (now-orphaned) inode and never sees an event.
Watching the parent directory with `.write | .rename | .extend` and
re-stat'ing on each event catches both atomic and non-atomic writers.

**Two coordinate-system conventions in the codebase.** `NSImage(size:
flipped: false)` gives the drawing block a Y-up math-convention
context: 12 o'clock is angle `+π/2`, clockwise visual sweep means
decreasing angle. SwiftUI `Canvas` gives a Y-down screen-convention
context: 12 o'clock is `-π/2`, clockwise visual sweep is increasing
angle. Both renderers (the menu bar icon and the popover preview) draw
the same shapes but with opposite signs. The code marks each
convention explicitly at the top of the relevant function.

**Alpha for "gray", not a fixed gray color.** The reset-progress wedge
uses `alpha: 0.55` instead of `NSColor(white: 0.55, alpha: 1.0)`. With
the template-image mode above, macOS applies the system foreground
color regardless. The wedge therefore reads as "medium translucent
foreground" — `~55% white` on a dark menu bar, `~55% black` on a light
one — without me ever hardcoding a color value.

## Caveats

- Quota data refreshes **only when you send a message in Claude Code**
  (that's when the statusLine fires). Between prompts the indicator
  reflects the last observed state.
- Right after a window resets, Claude Code's `rate_limits` may briefly
  carry stale values until the next API response repopulates them.
  The indicator inherits that lag — it shows "still capped" for the
  few seconds between reset and the next prompt.
- If the app launches when `used_percentage` is already 100%, there is
  no way to know when the cap was hit; `hitZeroAt` is approximated by
  anchoring at `resets_at − window_size` (7 d or 5 h).
- This is wired to a documented but evolving Claude Code extension
  point. If Anthropic changes the statusLine JSON shape, the script
  needs an update (the Swift app is shape-agnostic and would still
  parse what it knows).

## Development

```bash
make run       # build release, package as .app, launch
make build     # build without launching
make clean     # remove .build/ and the .app bundle
```

Project layout:

```
.
├── Package.swift                            SwiftPM manifest
├── Info.plist                               LSUIElement = YES (menu bar only)
├── Makefile                                 build / run / install
├── scripts/
│   └── statusline-indicator.sh              Claude Code hook
└── Sources/ClaudeIndicator/
    ├── ClaudeIndicatorApp.swift             @main, MenuBarExtra
    ├── IndicatorModel.swift                 ObservableObject + UserDefaults
    ├── IconRenderer.swift                   NSImage / NSBezierPath drawing
    ├── RateLimitFileWatcher.swift           DispatchSource directory watcher
    └── PopoverView.swift                    Popover UI + Canvas preview
```

Manual-slider mode (popover toggle) ignores the statusLine file —
useful for designing the icon at any percentage without waiting for
real data.

## License

MIT — see [LICENSE](LICENSE).
