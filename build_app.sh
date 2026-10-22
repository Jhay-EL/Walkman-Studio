#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Building native Swift release binary for Apple Silicon..."
swift build -c release

APP_NAME="Walkman Studio"
APP_BUNDLE="$DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$DIR/.build/release/WalkmanStudio" "$MACOS_DIR/WalkmanStudio"
chmod +x "$MACOS_DIR/WalkmanStudio"

# Copy App Icon & Device Assets
if [ -f "$DIR/assets/AppIcon.icns" ]; then
    cp "$DIR/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$DIR/assets/walkman_device_cropped.png" ]; then
    cp "$DIR/assets/walkman_device_cropped.png" "$RESOURCES_DIR/walkman_device_cropped.png"
fi
if [ -f "$DIR/assets/walkman_device.png" ]; then
    cp "$DIR/assets/walkman_device.png" "$RESOURCES_DIR/walkman_device.png"
fi
if [ -f "$DIR/assets/hires_audio_logo.png" ]; then
    cp "$DIR/assets/hires_audio_logo.png" "$RESOURCES_DIR/hires_audio_logo.png"
fi
if [ -f "$DIR/assets/hires_audio_logo.svg" ]; then
    cp "$DIR/assets/hires_audio_logo.svg" "$RESOURCES_DIR/hires_audio_logo.svg"
fi

# Create Info.plist
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WalkmanStudio</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.sony.walkmanstudio</string>
    <key>CFBundleName</key>
    <string>Walkman Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.1</string>
    <key>CFBundleVersion</key>
    <string>201</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign app bundle for local execution
echo "Signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Successfully built $APP_BUNDLE"
