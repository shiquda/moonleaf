cask "moonleaf" do
  version "4.2.0"
  sha256 "5cffe451bb2c7cab147387e5aef861632a5b8ba075987b1bd7b67ecc96abf59b"

  url "https://github.com/shiquda/moonleaf/releases/download/v#{version}/moonleaf.dmg"
  name "moonleaf"
  desc "Wallpaper engine with shuffling, per-desktop wallpapers and a wallpaper browser"
  homepage "https://shiquda.github.io/moonleaf"

  livecheck do
    url "https://github.com/shiquda/moonleaf/releases/latest/download/latest"
    regex(/^v?(\d+(?:\.\d+)*(?:\.beta\.\d+)?)$/i)
  end

  auto_updates true
  depends_on macos: :monterey

  app "moonleaf.app"

  zap trash: [
    "~/.config/moonleaf",
    "~/.local/share/macpaper",
    "~/Library/LaunchAgents/com.naomisphere.macpaper.app.plist",
  ]
end
