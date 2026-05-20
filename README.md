# Margherita 🍕🌎

A premium, native macOS menu bar application that displays your live Claude rate limits and usage from Claude Code in real time — with zero authentication tokens, reverse engineering, or scraping. It seamlessly hooks into Claude Code's official `statusLine` extension point.

> [!NOTE]
> Margherita is dynamic and automatically localizes its entire user interface and native notifications to English or Spanish based on your macOS system language.

---

## Key Features

- **Live Visual Indicator**: Renders a sleek, adaptive vector icon in the menu bar showing your weekly (`seven_day`) or session (`five_hour`) Claude quota.
- **Multilingual Support**: Automatically detects and adapts to English and Spanish locales dynamically.
- **Automatic GitHub Update Checker**: Automatically checks GitHub Releases for new updates without external dependencies and shows a beautifully styled green/teal gradient banner directly inside the popover.
- **Native macOS Notifications**: Beautifully formatted local alerts that warn you when you consume 100% of your usage or when your quota gets reset.
- **Launch at Login**: Simple macOS system toggle to launch Margherita automatically on startup.
- **Interactive Manual Mode**: Manual slider options to test different indicator states, quota values, and geometries (circle vs. 3-10 sided polygon).

---

## How It Works

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
                              IndicatorModel  ──►  menu bar icon & popover
```

1. **Claude Code statusLine Hook**: Whenever you run a query, Claude Code feeds rate limit JSON data directly to our custom `statusline-indicator.sh` script via standard input.
2. **Atomic JSON Storage**: The script processes and writes the limits to `~/.claude/indicator.json` using atomic temporary moves.
3. **Directory Watcher**: Margherita's swift-based `RateLimitFileWatcher` monitors files in the `~/.claude/` directory without taking CPU cycles.
4. **Adaptive UI Render**: The `IndicatorModel` updates percentages, triggers native notifications, and redraws the template vector menu bar icon.

---

## Free & Native Local Distribution Setup

To distribute and run Margherita 100% for free without a paid Apple Developer Account, follow these instructions.

### 1. Build and Ad-hoc Sign the App
The provided `Makefile` automatically runs native Swift Package Manager compilations in release mode and applies **ad-hoc codesigning** directly via the macOS standard system tools:

```bash
# Clone the repository
git clone https://github.com/f3r21/claude-usage-menubar.git
cd claude-usage-menubar/native

# Compile, sign and install to /Applications
make install
```

The app is signed locally using:
```bash
codesign --force --deep --sign - Margherita.app
```
This is fully secure, completely free, and recognized by macOS for local command execution.

---

### 2. Free Gatekeeper Bypass
Since Margherita is ad-hoc signed, launching it for the first time on a machine will prompt a Gatekeeper security warning ("unidentified developer"). 

You can bypass this instantly and safely using one of these two free methods:

#### Method A: Right-Click Open (Recommended)
1. Open Finder and go to `/Applications`.
2. **Right-click** (or Control-click) `Margherita.app` and choose **Open**.
3. A dialog will appear asking you to confirm. Click **Open**. Margherita will now be fully trusted by your system and open normally on all future launches.

#### Method B: Terminal Command
Alternatively, remove the quarantine attribute directly via your terminal:
```bash
xattr -d com.apple.quarantine /Applications/Margherita.app
```

---

### 3. Homebrew Tap Installation
You can distribute Margherita as a Homebrew Cask to your friends or teammates for free using a **personal Homebrew Tap**.

1. Create a public GitHub repository named `homebrew-tap` (e.g., `github.com/your-username/homebrew-tap`).
2. Add the custom Cask file (`margherita.rb` located in `resources/margherita.rb`) into a folder named `Casks/margherita.rb` inside that repository.
3. Users will now be able to install Margherita with a single, simple command:
   ```bash
   brew tap your-username/tap
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
│   ├── AppIcon.icns                         The compiled 4096px high-res icons
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
