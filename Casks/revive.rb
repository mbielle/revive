# Homebrew cask for Revive. Publish it in a tap (github.com/mbielle/homebrew-tap) so users can run:
#   brew install --cask mbielle/tap/revive
# Update `version` and `sha256` (printed by scripts/make-dmg.sh) for each release.
cask "revive" do
  version "0.4.0"
  sha256 :no_check

  url "https://github.com/mbielle/revive/releases/download/v#{version}/Revive-#{version}.dmg"
  name "Revive"
  desc "Free and open source Mac cleaner, optimizer and malware scanner"
  homepage "https://github.com/mbielle/revive"

  depends_on macos: ">= :sonoma"

  app "Revive.app"

  uninstall launchctl: "io.github.mbielle.Revive.Helper",
            quit:      "io.github.mbielle.Revive"

  zap trash: [
    "~/Library/Application Support/Revive",
    "~/Library/Preferences/io.github.mbielle.Revive.plist",
    "~/Library/Caches/io.github.mbielle.Revive",
  ]
end
