# Homebrew cask for Lucent. Publish it in a tap (github.com/mbielle/homebrew-tap) so users can run:
#   brew install --cask mbielle/tap/lucent
# Update `version` and `sha256` (printed by scripts/make-dmg.sh) for each release.
cask "lucent" do
  version "0.4.0"
  sha256 :no_check

  url "https://github.com/mbielle/lucent/releases/download/v#{version}/Lucent-#{version}.dmg"
  name "Lucent"
  desc "Free and open source Mac cleaner, optimizer and malware scanner"
  homepage "https://github.com/mbielle/lucent"

  depends_on macos: ">= :sonoma"

  app "Lucent.app"

  uninstall launchctl: "io.github.mbielle.Lucent.Helper",
            quit:      "io.github.mbielle.Lucent"

  zap trash: [
    "~/Library/Application Support/Lucent",
    "~/Library/Preferences/io.github.mbielle.Lucent.plist",
    "~/Library/Caches/io.github.mbielle.Lucent",
  ]
end
