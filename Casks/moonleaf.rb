cask "moonleaf" do
  version "4.1.0.beta.1"
  sha256 "b3c5f2f674af2e14b3988a4d1eeff9862d32557b4ecfe60923ef511fd412b092"

  url "https://github.com/shiquda/moonleaf/releases/download/v4.1.0.beta.1/moonleaf.dmg",
      verified: "github.com/shiquda/moonleaf/"
  name "moonleaf"
  desc "Wallpaper engine with shuffling, per-desktop wallpapers and a wallpaper browser"
  homepage "https://github.com/shiquda/moonleaf"

  livecheck do
    url "https://github.com/shiquda/moonleaf/releases/latest/download/latest"
    regex(/^v?(\d+(?:\.\d+)*(?:\.beta\.\d+)?)$/i)
  end

  depends_on macos: ">= :monterey"

  app "moonleaf.app"

  zap trash: [
    "~/.config/moonleaf",
    "~/.local/share/macpaper",
    "~/Library/LaunchAgents/com.naomisphere.macpaper.app.plist",
  ]
end
