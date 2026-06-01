cask "margherita" do
  version "0.2.0"
  sha256 "79f3b5f629d4e5fb1106aa49ea6ec92e1ff3d08fd60fd7680473de439e8bb8bd"

  url "https://github.com/f3r21/Margherita/releases/download/v#{version}/Margherita.dmg"
  name "Margherita"
  desc "Native macOS menu bar Claude Code rate limits indicator"
  homepage "https://github.com/f3r21/Margherita"

  app "Margherita.app"

  caveats <<~EOS
    Margherita is ad-hoc signed. After installing, run this once to fix the
    "damaged / unidentified developer" launch error:
      codesign --force --deep --sign - /Applications/Margherita.app && xattr -d com.apple.quarantine /Applications/Margherita.app
  EOS

  zap trash: [
    "~/Library/Preferences/local.margherita.plist",
  ]
end
