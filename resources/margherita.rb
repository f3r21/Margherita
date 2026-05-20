cask "margherita" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/f3r21/Margherita/releases/download/v#{version}/Margherita.dmg"
  name "Margherita"
  desc "Native macOS menu bar Claude Code rate limits indicator"
  homepage "https://github.com/f3r21/Margherita"

  app "Margherita.app"

  zap trash: [
    "~/.claude/settings.json",
    "~/Library/Preferences/local.margherita.plist",
  ]
end
