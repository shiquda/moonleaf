cask "moonleaf" do
  version "4.1.1"
  sha256 "d3d6a806b3d27296ac42a81766892ef25466ee7d7dfddfca2f273c1ea278ebbc"

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
