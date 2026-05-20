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

### 2. Free Gatekeeper Bypass
Since Margherita is ad-hoc signed, launching it for the first time will trigger a Gatekeeper security warning ("unidentified developer"). 

You can bypass this instantly and safely using one of these two methods:

#### Method A: Right-Click Open (Recommended)
1. Open Finder and navigate to `/Applications`.
2. **Right-click** (or Control-click) `Margherita.app` and choose **Open**.
3. A confirmation dialog will appear. Click **Open**. Margherita will now be trusted by your system and open normally on all future launches.

#### Method B: Terminal Command
Alternatively, remove the quarantine attribute directly via your terminal:
```bash
xattr -d com.apple.quarantine /Applications/Margherita.app
```

---

### 3. Homebrew Tap Installation
You can distribute Margherita as a Homebrew Cask to other machines using a personal Homebrew Tap.

1. Create a public GitHub repository named `homebrew-tap` (e.g., `github.com/f3r21/homebrew-tap`).
2. Add the custom Cask file (`margherita.rb` located in `resources/margherita.rb`) into a folder named `Casks/margherita.rb` inside that repository.
3. Users will now be able to install Margherita with a single, simple command:
   ```bash
   brew tap f3r21/tap
   brew install --cask margherita
   ```
4. To run Margherita after a Brew installation, simply right-click it in `/Applications` once to bypass Gatekeeper.

---

## Local Development

```bash
make run       # Compile in release mode, bundle as .app, and run Margherita
make build     # Compile the application bundle
make clean     # Clean build cache and temporary DMG stages
make dmg       # Package the application into a distribution-ready Margherita.dmg
```

### Project Layout
```
.
├── Package.swift                            SwiftPM manifest
├── Info.plist                               App manifest (LSUIElement = YES for agent/menubar status)
├── Makefile                                 Automation for compilation and packaging
├── scripts/
│   └── statusline-indicator.sh              Claude Code stdin processing hook
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
