cask "margherita" do
  version "0.3.0"
  sha256 "db9592b7f75d3fe65c1de74a5fbb2379b85953a8e90d1a96efb5a8a4bec31449"

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
