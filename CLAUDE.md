# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Margherita** is a native macOS menu-bar app that displays Claude Code rate-limit usage — no auth tokens, no scraping. It turns Claude Code's `statusLine` extension point into a live menu-bar icon. A single Swift Package Manager executable; no third-party Swift dependencies (only the stdlib and system frameworks: `SwiftUI`, `AppKit`, `Combine`, `ServiceManagement`, `UserNotifications`, `Foundation`, `os`).

The `statusLine` hook itself is **not tied to the app running**: Claude Code invokes a standalone copy of `scripts/statusline-indicator.sh` directly from `~/.claude/margherita/` on every turn, which is what produces the compact `"7d 31% · 5h 12%"` line in the terminal. The menu-bar icon is a separate, optional consumer of the same underlying data — quitting/never launching Margherita.app removes the icon but does not affect the console line. See [Hook installation is decoupled from the app](#hook-installation-is-decoupled-from-the-app).

Targets **macOS 13+**. `Package.swift` declares `swift-tools-version:5.9` and does **not** opt into the Swift 6 language mode or strict concurrency — don't assume Swift 6 semantics.

## Repository layout

**This directory (`native/`) is the git repository root and the SwiftPM package root.** Run every command below from here. On the maintainer's machine there is a wrapper directory one level up (`usage-tool/`), but it is *not* part of the repository — keep project guidance (this file) and all paths inside the git root so a fresh clone has them.

## Commands

```bash
make build          # swift build -c release, then assemble + ad-hoc-codesign Margherita.app bundle
make run            # build, killall existing instance, open the .app
make install        # build, copy bundle to /Applications
make dmg            # build, stage into dmg_staging/, hdiutil → Margherita.dmg
make clean          # swift package clean + remove .app/.build/.dmg/dmg_staging
make install-hook   # bash+jq only: installs the statusLine hook without the app at all
make uninstall-hook # bash+jq only: removes the statusLine key (see scripts/*-hook.sh)

swift build -c release           # compile only (bare executable, no bundle)
swift test                       # run the XCTest suite
swift test --filter MargheritaTests/testRecomputePercentage   # single test
swift test --enable-code-coverage
```

- **`make build` is required to actually run the app.** `swift build` alone produces only the bare executable; the app reads its bundled `statusline-indicator.sh` from `Margherita.app/Contents/Resources/` (resolved at runtime by `installHook()` via `Bundle.main.path`) **as the source it copies from** — see [Hook installation is decoupled from the app](#hook-installation-is-decoupled-from-the-app) — and only the Makefile assembles that bundle. (`AppIcon.icns` is copied *conditionally* and is only the Finder bundle icon — the LSUIElement app never reads it; the menu-bar icon is drawn entirely in code.)
- **Incremental-build footgun:** the bundle is a Make target depending only on the release executable + `Info.plist`, and the executable depends only on `Sources/*.swift` + `Package.swift`. Editing `scripts/statusline-indicator.sh` or `resources/AppIcon.icns` alone does **not** retrigger `make build` (they aren't prerequisites) — you get a stale bundle. Touch a source file or `make clean` first.
- Signing is ad-hoc: `codesign --force --deep --sign - Margherita.app`.
- `.build/`, `*.app/`, `*.dmg` are gitignored; `dmg_staging/` is **not**, so a leftover from an interrupted `make dmg` can be accidentally committed.

**Runtime dependency:** the hook script needs `jq` on `PATH` (`brew install jq`). The app surfaces a warning in the popover when `jq` is missing; `checkJqInstallation()` checks common install paths first (Homebrew/system/MacPorts/nix/asdf) and, on a miss, falls back to resolving `jq` through the user's login shell (`$SHELL -lc 'command -v jq'`) on a background thread, then re-checks on popover appear.

## CI & releases

Two GitHub Actions workflows (`.github/workflows/`):

- **`ci.yml`** — on every push to `main` and every PR (concurrency-cancelled per ref). On `macos-14`: `swift --version`, **lints the hook script with `bash -n scripts/statusline-indicator.sh`**, `swift build -c release`, `swift test`, then `make build` as a bundle-assembly gate. It never launches the app.
- **`release.yml`** — on pushing a `v*` tag. Sets the bundle version *from the tag* (`PlistBuddy` → `CFBundleShortVersionString` + `CFBundleVersion`), runs `make dmg`, computes the DMG `sha256`, and `gh release create`s a GitHub Release with the DMG + checksum + re-sign instructions. The in-app update checker polls that release. It does **not** touch the Homebrew tap or the cask `sha256` — both are manual (see [Distribution](#distribution)).

So cutting a release is: **don't hand-edit the version** → push a `v<x.y.z>` tag → CI builds/publishes the DMG → manually sync the `version` + `sha256` from the published release into **both** cask copies (in-repo `resources/margherita.rb` *and* the live tap's `Casks/margherita.rb` — see [Distribution](#distribution)).

## Architecture

The core flow turns Claude Code's `statusLine` extension point into a live menu-bar icon:

```
Claude Code --stdin JSON--> scripts/statusline-indicator.sh --atomic mv--> ~/.claude/indicator.json
   --> RateLimitFileWatcher (DispatchSource on the DIRECTORY) --> IndicatorModel.applyStatusLineData()
   --> @Published percent/resetProgress --> IconRenderer template NSImage + PopoverView
```

Source files (`Sources/Margherita/`), all small and single-responsibility:
- `MargheritaApp.swift` — `@main` `MenuBarExtra` scene; `MenuBarLabel` re-renders the icon on every model change.
- `IndicatorModel.swift` — `@MainActor ObservableObject`, the brain: state, persistence, hook install/uninstall, notifications, Launch-at-Login, GitHub update check.
- `RateLimitFileWatcher.swift` — file watcher + the `IndicatorFile` / `MeterData` Codable structs.
- `IconRenderer.swift` — vector drawing of the template menu-bar `NSImage` (AppKit, Y-up).
- `IndicatorGeometry.swift` — pure-arithmetic `enum` (no state, no drawing) that centralizes the icon math: segment counts, polygon vertices, wedge sweep (degrees *and* radians), and the `resetAlpha` (0.55) / `placeholderAlpha` (0.6) constants. Its Spanish doc comment is load-bearing for intent.
- `Localizer.swift` — hand-rolled en/es string table.
- `PopoverView.swift` — the SwiftUI popover (status, controls, manual-test sliders, update banner). **Also contains `IndicatorPreview`, a second renderer** that mirrors the menu-bar icon in a SwiftUI `Canvas` (`Color.primary` instead of template alpha, Y-down). It is **no longer an independent copy of the geometry**: both it and `IconRenderer` call into `IndicatorGeometry` for the shared math (segment counts, vertices via `polygonVertices(…, yUp:)`, wedge sweep, the alpha constants), so that arithmetic *can't* desync. What is still duplicated is the **drawing itself** — each renderer strokes/fills with its own framework in its own coordinate system — so a change to *how* a shape is painted (stroke width, dash pattern, fill order) must still be made in both. A change to the *math* goes in `IndicatorGeometry` once.

### Non-obvious behaviors — read before editing

- **No data until `rate_limits` exists.** `rate_limits` is present only on Claude.ai Pro/Max sessions, and only after the first API response. The script (`set -euo pipefail`, fail-fast) no-ops — writes nothing, leaves the prior `indicator.json` intact — when `rate_limits` is absent/empty. So the icon can stay on its dashed "no data yet" placeholder indefinitely even with the hook correctly installed. This is the #1 "why is nothing showing" debugging dead-end.

- **Watches the parent directory, not the file.** The shell script writes via `mv` of a temp file, so the inode changes on every update; a watcher bound to the file would go stale. `RateLimitFileWatcher` opens `~/.claude/` with `O_EVTONLY` and re-reads `indicator.json` on each directory event. The `eventMask` is `[.write, .rename, .extend]` — `.rename` is what catches the atomic `mv`; narrowing it to `.write` would silently break live refresh. The watcher `mkdir`s `~/.claude` if absent, and a *missing* `indicator.json` is a silent no-op (only decode failures are logged) — that's the normal pre-first-data path.

- **The script reshapes the payload; meter *names* are dynamic, the per-meter *shape* is not.** `installHook()` edits `~/.claude/settings.json` to add a `statusLine` key pointing at the standalone copy of `statusline-indicator.sh` (see below — **not** the copy inside the bundle). The script iterates every key under `rate_limits` (meter names are **not** hardcoded, so new Claude meters surface automatically), but for each meter it keeps only `used_percentage` and `resets_at_unix` (renamed from the input's `resets_at`), plus top-level `updated_at` and `primary_meter` (chosen dynamically: `seven_day` if present, else the first meter — so the icon still updates on plans without `seven_day`). On the Swift side `recompute()` mirrors this via `effectiveMeterKey` (user's `primaryMeter` → `seven_day` → first available), so a persisted meter choice that's absent from the latest payload won't freeze the icon. Adding a field to `MeterData`/`IndicatorFile` decoding also requires widening the jq map in the script, or the field never reaches the app.

`installHook()`/`uninstallHook()` read `~/.claude/settings.json`, mutate only the `statusLine` key, and write back **atomically** (temp + `replaceItemAt`); if the file exists but can't be parsed they abort and surface `hookError` rather than overwriting (which would destroy the user's other keys).

#### Hook installation is decoupled from the app

The hook Claude Code actually calls does **not** live inside `Margherita.app`. `installHook()` first calls `installStandaloneScript()`, which copies the bundled script out to a stable path, `~/.claude/margherita/statusline-indicator.sh` (`IndicatorModel.standaloneScriptURL`), `chmod`-ing it `0o755`, and only *then* writes `statusLine.command` pointing at **that** path. Consequences:

- The hook keeps working even if `Margherita.app` is later moved, updated in place, or deleted outright — Claude Code never touches the bundle path at runtime, only `~/.claude/margherita/`.
- `installStandaloneScript()` overwrites the standalone copy on every call, so a newer app version always refreshes the deployed script.
- **Migration:** `checkHookInstallation()` (called from `init()` and from `PopoverView.onAppear`) detects a still-installed hook whose `command` is *not* `standaloneScriptURL.path` (i.e., an install from before this existed, pointing inside the bundle) and silently calls `installHook()` to re-point it — one-time, idempotent, no user action needed.
- `scripts/install-hook.sh` / `scripts/uninstall-hook.sh` are a **bash + jq-only** equivalent of `installHook()`/`uninstallHook()` (same destination path, same "abort on unparseable settings.json" safety, using `jq` for the merge instead of `JSONSerialization`) for people who want *only* the statusLine text and never want to install the macOS app at all. `make install-hook` / `make uninstall-hook` wrap them. Keep both implementations in sync if the hook-install logic changes.
- `uninstallHook()` (Swift and shell) only ever removes the `statusLine` key — neither deletes `~/.claude/margherita/statusline-indicator.sh` nor `~/.claude/indicator.json`, consistent with this codebase's general policy of never destructively touching `~/.claude/` beyond the one key it owns.

- **`percent` is availability remaining, inverted from the meter.** The file carries `used_percentage`; `recompute()` stores `percent = 100 - used`. When `percent` hits 0 in statusLine mode the app enters the **`isAwaitingReset`** state (`dataSource == .statusLine && updatedAt != nil && percent == 0`): the menu bar **drops the icon and shows only the time-until-reset as text** (`menuBarText` → `resetETAText`, always non-nil so the bar is never blank/unclickable), and the popover hides its 48×48 preview tile, leaving the "Resets in X" row. The 60s `resetTicker` is the heartbeat for this: it re-runs `recompute()`, which republishes `resetProgress` (`@Published`) every minute and so forces the countdown text to re-evaluate against wall-clock time even with no file change. `resetProgress` (0→100) and its grey wedge are **still computed and persisted** (`hitZeroAt` survives restarts) but are now **only rendered in `.manual` test mode** — in real use the wedge is never drawn. **Magic numbers:** `windowSeconds(for:)` only special-cases `seven_day` (7d) and `five_hour` (5h), else falls back to 5h (this now only skews the manual-mode wedge, since statusLine shows text). `isDataStale` flags data older than **12h**.

- **Two data sources, one set of outputs.** `DataSource` is `.statusLine` (real data) or `.manual` (popover sliders, for testing). `percent`/`resetProgress` are *directly writable* in manual mode but *derived* in statusLine mode by `recompute()`. The two modes also fork notification logic (statusLine: `sendQuotaExceededNotification(for:)` with reset-time text; manual: `sendQuotaExceededNotificationManual()` / `sendQuotaResetNotification()`), and both quota-exceeded notifications share the identifier `Margherita.QuotaExceeded` so the latest coalesces over the prior. Guard logic that writes `percent`/`resetProgress` must respect the current `dataSource`.

- **`@Published` setters self-clamp by re-assigning and early-returning.** `percent`, `resetProgress`, and `polygonSides` write a clamped value back to themselves and `return`, re-triggering `didSet`. This is intentional clamp-on-write — don't "simplify" it into an infinite-loop trap. Most settings persist to `UserDefaults`. Note `IconRenderer` only clamps the polygon *lower* bound (`max(3, …)`); the 3–10 upper bound is enforced solely by the `polygonSides` setter.

- **The menu-bar icon is a template image.** `IconRenderer` draws everything in black with varying alpha and sets `isTemplate = true`, so macOS tints it automatically. Alpha is the only meaningful channel: `1.0` = full tint, `0.55` = grey reset wedge (now reachable only in `.manual` mode — see `isAwaitingReset`), `0.6` = dashed placeholder, undrawn = transparent. Geometry is computed in Y-up coordinates (`NSImage(flipped: false)`): 12 o'clock = 90°, clockwise = decreasing angle. Both `circle` and `polygon` (3–10 sides) shapes plus a dashed placeholder before first data; the circle draws an exact angular wedge while the polygon quantizes the fill to whole segments, so the two encode the same percent slightly differently.

- **App is an agent (`LSUIElement = YES`)** — menu bar only, no Dock icon. Bundle id `local.margherita`, version in `Info.plist` (`CFBundleShortVersionString`, currently `0.2.0`). **Don't hand-bump the version for a release** — `release.yml` overwrites it (and `CFBundleVersion`) from the pushed git tag, so the committed value just records the last tagged release. The update check hits `https://api.github.com/repos/f3r21/Margherita/releases/latest`, strips a leading `v`/`V` from both tags, and compares with `String.compare(options: .numeric)` — a lexical numeric compare, **not** real SemVer (pre-release/multi-segment tags can mis-sort); the version shown in the UI keeps the original tag. (The `CFBundleShortVersionString` lookup has a hardcoded `"0.1.0"` fallback for when the plist read fails — stale, but only reachable if `Info.plist` is unreadable.)

- **`installStandaloneScript()` has a hardcoded fallback source path.** It resolves the script to copy *from* via the running bundle (`Bundle.main.path`), but falls back to `/Applications/Margherita.app/Contents/Resources/statusline-indicator.sh` when not run from a bundle at all (bare `swift build` executable in dev). If neither exists, it returns `nil`, `installHook()` surfaces `hookError` (`hook_error_script_missing`) instead of writing a broken `statusLine` command, and the previously-installed hook (if any) is left untouched. This only affects the *source* to copy from — once installed once, the *destination* Claude Code calls (`~/.claude/margherita/statusline-indicator.sh`) no longer depends on the bundle's location at all (see [above](#hook-installation-is-decoupled-from-the-app)).

- **Localization is code, not `.strings`.** `Localizer` picks es vs en from `Locale.current` at init (default en) and looks up a `[String: [Language: String]]` dictionary; `tr(key, args…)` does `String(format:)` only when `args` is non-empty, and returns the raw key verbatim on a miss. That raw-key fallthrough is exactly what lets unknown meter names render as their key. Add user-facing text here, not in resource files.

### Tests

`Tests/MargheritaTests/` uses **XCTest** (`@MainActor final class … XCTestCase`), not Swift Testing. `IndicatorModel`'s `init` has real side effects on its **default (production) path** — it starts the `~/.claude` directory watcher, a 60s timer, reads/writes `UserDefaults`, checks `jq`/hook installation, fires a network update check, and (via the `isLaunchAtLoginEnabled`/`isNotificationsEnabled` `didSet` observers) can **register/unregister the `SMAppService` login item and trigger a system notification-permission prompt** during construction. The init is `init(startServices: Bool = true)`: passing **`startServices: false`** hydrates state from `UserDefaults` but `guard`s out before starting any of that (and gates the login-item read). Every test constructs the model as `IndicatorModel(startServices: false)` for exactly this reason — keep new tests on that path, and don't assume bare `IndicatorModel()` is side-effect-free.

## Distribution

The app is signed ad-hoc (`codesign --force --deep --sign -`). A pre-built `.dmg`/Homebrew download carries the *builder's* ad-hoc signature, which macOS rejects on other machines (`EXC_BAD_SIGNATURE` / SIGKILL). The fix is to re-sign locally against the installed copy and strip quarantine:

```bash
codesign --force --deep --sign - /Applications/Margherita.app && xattr -d com.apple.quarantine /Applications/Margherita.app 2>/dev/null || true
```

Homebrew distribution **is live**: the public `f3r21/homebrew-tap` repo holds the cask at `Casks/margherita.rb`, and `brew install --cask f3r21/tap/margherita` (or `brew upgrade --cask margherita`) resolves it. **There are two cask copies and `release.yml` keeps neither in sync — both updates are manual.** `resources/margherita.rb` in *this* repo is only a source copy; the file Homebrew actually reads is `Casks/margherita.rb` in the **tap** repo. After each release you must hand-update `version` + `sha256` in **both** to match the published DMG (the cask `url` interpolates `v#{version}`); if they drift from `CFBundleShortVersionString` / the release tag, `brew install --cask` 404s or fails its checksum. The `sha256` is **not** wired up automatically: `release.yml` prints `shasum -a 256 Margherita.dmg` into the release notes, and a maintainer copies that hash into both casks by hand (in-repo copy via PR; tap via `gh api --method PUT …/contents/Casks/margherita.rb` or a clone+push). `brew uninstall --zap` deliberately removes only `~/Library/Preferences/local.margherita.plist` — it leaves `~/.claude/settings.json`, `~/.claude/indicator.json`, and `~/.claude/margherita/statusline-indicator.sh` alone (the hook is cleaned by the app's own `uninstallHook()`, which removes the `statusLine` key but not the standalone script copy — see [Hook installation is decoupled from the app](#hook-installation-is-decoupled-from-the-app)). Full end-user steps are in `README.md`.
