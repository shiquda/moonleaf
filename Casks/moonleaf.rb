cask "moonleaf" do
  version "4.1.0"
  sha256 "c15de2395df5d7f2dbcbf389f9792e0f075000d60e6e39001e3c1013f0ec9e40"

  url "https://github.com/shiquda/moonleaf/releases/download/v#{version}/moonleaf.dmg"
  name "moonleaf"
  desc "Wallpaper engine with shuffling, per-desktop wallpapers and a wallpaper browser"
  homepage "https://github.com/shiquda/moonleaf"

  livecheck do
    url "https://github.com/shiquda/moonleaf/releases/latest/download/latest"
    regex(/^v?(\d+(?:\.\d+)*(?:\.beta\.\d+)?)$/i)
  end

  depends_on macos: :monterey

  app "moonleaf.app"

  zap trash: [
    "~/.config/moonleaf",
    "~/.local/share/macpaper",
    "~/Library/LaunchAgents/com.naomisphere.macpaper.app.plist",
  ]
end
