#!/usr/bin/env bash
set -euo pipefail
spike_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$spike_dir/../../.." && pwd)"
output_dir="${1:?Usage: build.sh OUTPUT_DIRECTORY}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
ghostty_dir="$repo_dir/ThirdParty/ghostty"
export DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer
if git -C "$ghostty_dir" apply --check "$spike_dir/ghostty-snapshot.patch" 2>/dev/null; then
  git -C "$ghostty_dir" apply "$spike_dir/ghostty-snapshot.patch"
elif ! git -C "$ghostty_dir" apply --reverse --check "$spike_dir/ghostty-snapshot.patch" 2>/dev/null; then
  echo 'The Ghostty checkout does not match the spike patch.' >&2
  exit 1
fi
(
  cd "$ghostty_dir"
  mise exec -- zig build -Doptimize=ReleaseFast -Demit-xcframework=true \
    -Dxcframework-target=native -Demit-macos-app=false -Dsentry=false
)
app="$output_dir/Remote Surface Spike.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.onevcat.prowl.remote-surface-spike</string>
<key>CFBundleName</key><string>Remote Surface Spike</string>
<key>CFBundleExecutable</key><string>spike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xcrun clang -fobjc-arc -fblocks -I "$ghostty_dir/include" "$spike_dir/main.m" \
  "$ghostty_dir/macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a" \
  -framework AppKit -framework QuartzCore -framework Metal -framework MetalKit \
  -framework CoreText -framework CoreGraphics -framework CoreVideo -framework Carbon \
  -framework IOKit -framework IOSurface -lc++ -o "$app/Contents/MacOS/spike"
codesign --force --sign - "$app"
echo "$app"
