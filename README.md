# Margherita

Margherita is a high-performance, native macOS menu bar application designed to display real-time Claude Code rate limits and usage statistics. Operating with zero authentication tokens, reverse engineering, or scraping, it hooks directly into Claude Code's official `statusLine` extension point.

The application automatically localizes its entire interface and native notifications to English or Spanish based on your macOS system language.

---

## Technical Architecture

```
Claude Code  --[stdin JSON]--->  statusline-indicator.sh
                                         |
                                         v atomic mv
                                ~/.claude/indicator.json
                                         |
                                         v DispatchSourceFileSystemObject
                                RateLimitFileWatcher (Swift)
                                         |
                                         v @Published
                                IndicatorModel  --->  Menu bar icon & popover
```

1. **Claude Code Hook**: When queries are processed, Claude Code feeds rate limit JSON payload directly to our custom `statusline-indicator.sh` script via standard input.
2. **Atomic Storage**: The script processes and writes the limits to `~/.claude/indicator.json` using atomic temporary moves to avoid file-read conflicts.
3. **Directory Watcher**: Margherita's Swift-based `RateLimitFileWatcher` monitors the file in `~/.claude/` asynchronously without taking CPU cycles.
4. **Adaptive UI Rendering**: The `IndicatorModel` updates percentages, triggers native notifications, and redraws the template vector menu bar icon.

---

## Key Features

* **Live Visual Indicator**: A template vector icon in the menu bar that dynamically updates to show your weekly (`seven_day`) or session (`five_hour`) Claude quota.
* **Multilingual Support**: Automatic localization for English and Spanish system locales.
* **Automatic Update Checker**: Periodic, non-blocking check against GitHub Releases to notify you of newer versions using a sleek gradient banner in the popover.
* **Native macOS Notifications**: Notifications that warn you when your usage reaches 100% or when your quota has been fully reset.
* **Launch at Login**: Integrates with the macOS Service Management framework to launch automatically on startup.
* **Interactive Manual Mode**: A testing slider inside the popover to manually adjust percentages, shapes (circle or 3-10 sided polygons), and notification events.

---

## Managing Menu Bar Space

When both Margherita and Claude Desktop are running you will see **two separate icons** in the macOS menu bar. This is expected, not a bug: Margherita and Claude Desktop are independent applications, and macOS does not provide any API for one app to render inside another app's menu bar item. The two icons cannot be merged into one — that is a platform constraint, not a limitation of Margherita.

Margherita is designed to take the smallest footprint possible, and the menu bar stays easy to keep tidy:

* **Minimal by default.** Out of the box Margherita shows only its compact vector icon — no text. Leaving **"Show percent"** *off* in the popover keeps the smallest possible footprint. Turn it on only if you want the numeric percentage next to the icon.
* **Reorder or tuck it away natively.** Hold **⌘ (Command)** and drag any menu bar icon to reorder it, or drag it off the visible strip to hide it. No extra software required.
* **Use a menu bar manager.** When the menu bar gets crowded, a manager can collapse or hide icons on demand. [**Ice**](https://github.com/jordanbaird/Ice) is a free, open-source option; **Bartender** is a paid alternative. Margherita works seamlessly with both, precisely because it keeps a single, always-present icon they can manage.
* **Skip the icon entirely — just the console line, no app.** The menu bar icon and the compact `"7d 31% · 5h 12%"` line printed inside your Claude Code terminal come from the same hook, but they're independent: the line doesn't need the app running at all. If you only want the line, install just the hook, no macOS app required:

  ```bash
  git clone https://github.com/f3r21/Margherita.git
  cd Margherita/native
  make install-hook       # or: ./scripts/install-hook.sh
  ```

  This only needs `bash` + `jq` (`brew install jq`). It copies the hook script to `~/.claude/margherita/` and points Claude Code's `statusLine` at it — no Xcode, no Swift, no `/Applications` entry, no menu bar icon. To remove it later: `make uninstall-hook`.

---

## Free & Native Local Distribution

To distribute and run Margherita without a paid Apple Developer Account, follow these instructions to compile, sign, and install it locally.

### 1. Build and Ad-hoc Sign the App
The provided `Makefile` automatically runs native Swift Package Manager compilations in release mode and applies ad-hoc codesigning directly via standard macOS tools:

```bash
# Clone the repository
git clone https://github.com/f3r21/Margherita.git
cd Margherita/native

# Compile, sign and install to /Applications
make install
```

The application is signed locally using:
```bash
codesign --force --deep --sign - Margherita.app
```
This is fully secure, completely free, and recognized by macOS for local command execution.

### 2. Free Gatekeeper & Signature Bypass for Pre-built Binaries

If you or other users download the pre-built `Margherita.dmg` or install it via the **Homebrew Cask**, the binary carries an ad-hoc signature created on the builder's machine. macOS treats this signature as invalid on other hardware, which causes the application to crash immediately on launch with a `SIGKILL` (`EXC_BAD_SIGNATURE`) error.

To resolve this completely and securely, users must re-sign the app locally and strip the quarantine attribute:

#### The One-Step Terminal Fix (Recommended)
Open your terminal and run the following command to re-sign and un-quarantine the app in a single step:
```bash
codesign --force --deep --sign - /Applications/Margherita.app && xattr -d com.apple.quarantine /Applications/Margherita.app 2>/dev/null || true
```

#### Manual Steps
Alternatively, you can run the steps individually:

1. **Re-sign Locally**: Re-sign the app with your own machine's local ad-hoc identity to fix the `EXC_BAD_SIGNATURE` crash:
   ```bash
   codesign --force --deep --sign - /Applications/Margherita.app
   ```
2. **Un-quarantine (Bypass Gatekeeper)**: Clear the system download flag to prevent the "unidentified developer" prompt:
   ```bash
   xattr -d com.apple.quarantine /Applications/Margherita.app
   ```
   *(Or **Right-click** `Margherita.app` in Finder, select **Open**, and click **Open** on the prompt).*

---

### 3. Homebrew Tap Installation
You can distribute Margherita as a Homebrew Cask to other machines using a personal Homebrew Tap.

1. Create a public GitHub repository named `homebrew-tap` (e.g., `github.com/f3r21/homebrew-tap`).
2. Add the custom Cask file (`margherita.rb` located in `resources/margherita.rb`) into a folder named `Casks/margherita.rb` inside that repository.
3. Users will now be able to install Margherita with a single command:
   ```bash
   brew tap f3r21/tap
   brew install --cask margherita
   ```
4. **Important**: Because the downloaded binary is pre-built, they must run the local re-signing command right after installation:
   ```bash
   codesign --force --deep --sign - /Applications/Margherita.app && xattr -d com.apple.quarantine /Applications/Margherita.app 2>/dev/null || true
   ```

---

## Local Development

```bash
make run             # Compile in release mode, bundle as .app, and run Margherita
make build           # Compile the application bundle
make clean           # Clean build cache and temporary DMG stages
make dmg             # Package the application into a distribution-ready Margherita.dmg
make install-hook    # Install just the statusLine hook (bash + jq, no app needed)
make uninstall-hook  # Remove the statusLine hook
```

### Project Layout
```
.
├── Package.swift                            SwiftPM manifest
├── Info.plist                               App manifest (LSUIElement = YES for agent/menubar status)
├── Makefile                                 Automation for compilation and packaging
├── scripts/
│   ├── statusline-indicator.sh              Claude Code stdin processing hook
│   ├── install-hook.sh                      Standalone hook installer (no app required)
│   └── uninstall-hook.sh                    Standalone hook remover
├── resources/
│   ├── AppIcon.icns                         The compiled high-resolution icon bundle
│   └── margherita.rb                        Homebrew Cask recipe file
└── Sources/Margherita/
    ├── MargheritaApp.swift                  App lifecycle & MenuBarExtra extra scene
    ├── IndicatorModel.swift                 Main actor model, settings, update checks & alerts
    ├── Localizer.swift                      English/Spanish key-value mapping struct
    ├── IconRenderer.swift                   Vector rendering of template icons
    ├── RateLimitFileWatcher.swift           DispatchSource folder filesystem watcher
    └── PopoverView.swift                    Dynamic SwiftUI layout with update banners
```

---

## License

MIT — see [LICENSE](LICENSE).
