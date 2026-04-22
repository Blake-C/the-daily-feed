#!/usr/bin/env bash
# Builds NewsApp and packages it as a proper macOS .app bundle.
# Usage:
#   ./build_app.sh           (debug build)
#   ./build_app.sh release   (optimised release build)
#
# The resulting bundle is placed at: ./NewsApp.app
# Launch with: open NewsApp.app

set -euo pipefail

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
	BUILD_FLAGS="--configuration release"
else
	BUILD_FLAGS=""
fi

echo "Building ($CONFIG)..."
swift build $BUILD_FLAGS

BINARY=".build/$CONFIG/NewsApp"
CONTENTS="TheDailyFeed.app/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Packaging app bundle..."
rm -rf TheDailyFeed.app
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "$BINARY" "$MACOS/NewsApp"

BUNDLE_SRC=".build/$CONFIG/NewsApp_NewsApp.bundle"
if [ -d "$BUNDLE_SRC" ]; then
	cp -R "$BUNDLE_SRC" "$RESOURCES/"
fi

# Compile app icon: copy appiconset PNGs into a temporary iconset and run iconutil
ICONSET_SRC="Sources/NewsApp/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_TMP"
cp "$ICONSET_SRC"/icon_*.png "$ICONSET_TMP/"
iconutil -c icns "$ICONSET_TMP" -o "$RESOURCES/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_TMP")"

# Remove any leftover old bundle name
rm -rf NewsApp.app

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>The Daily Feed</string>
	<key>CFBundleDisplayName</key>
	<string>The Daily Feed</string>
	<key>CFBundleIdentifier</key>
	<string>com.newsapp.dailyfeed</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>NewsApp</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.news</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Your location is used to display current weather conditions.</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<false/>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
</dict>
</plist>
PLIST

echo "Done. Launch with:"
echo "  open TheDailyFeed.app"
