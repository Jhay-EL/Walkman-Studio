#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

ARCH="${1:-universal}"
VERSION="2.1.1"
BUILD_NUM="211"

APP_NAME="Walkman Studio"
APP_BUNDLE="$DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "Packaging $APP_BUNDLE (Architecture: $ARCH)..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$DIR/.build/bin"

if [ "$ARCH" = "universal" ]; then
    echo "Building native Swift release binary for Universal (Apple Silicon arm64 + Intel x86_64)..."
    swift build -c release --triple arm64-apple-macosx
    cp "$DIR/.build/out/Products/Release/WalkmanStudio" "$DIR/.build/bin/WalkmanStudio-arm64"
    swift build -c release --triple x86_64-apple-macosx
    cp "$DIR/.build/out/Products/Release/WalkmanStudio" "$DIR/.build/bin/WalkmanStudio-x86_64"
    lipo -create -output "$MACOS_DIR/WalkmanStudio" "$DIR/.build/bin/WalkmanStudio-arm64" "$DIR/.build/bin/WalkmanStudio-x86_64"
elif [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "intel" ]; then
    echo "Building native Swift release binary for Intel x86_64..."
    swift build -c release --triple x86_64-apple-macosx
    cp "$DIR/.build/out/Products/Release/WalkmanStudio" "$MACOS_DIR/WalkmanStudio"
else
    echo "Building native Swift release binary for Apple Silicon arm64..."
    swift build -c release --triple arm64-apple-macosx
    cp "$DIR/.build/out/Products/Release/WalkmanStudio" "$MACOS_DIR/WalkmanStudio"
fi
chmod +x "$MACOS_DIR/WalkmanStudio"

# Copy App Icon & Device Assets
if [ -f "$DIR/assets/AppIcon.icns" ]; then
    cp "$DIR/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -d "$DIR/assets/devices" ]; then
    mkdir -p "$RESOURCES_DIR/devices"
    cp -R "$DIR/assets/devices/"* "$RESOURCES_DIR/devices/"
    cp "$DIR/assets/devices/"*.png "$RESOURCES_DIR/" 2>/dev/null || true
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
if [ -f "$DIR/assets/walkman_logo_emblem.png" ]; then
    cp "$DIR/assets/walkman_logo_emblem.png" "$RESOURCES_DIR/walkman_logo_emblem.png"
fi

# Copy Backend Python Engine & Resources for local 12 Tone SenseMe DSP
if [ -d "$DIR/backend" ]; then
    echo "Bundling backend engine into $RESOURCES_DIR/backend..."
    mkdir -p "$RESOURCES_DIR/backend"
    cp -R "$DIR/backend/"* "$RESOURCES_DIR/backend/"
fi

# Create Info.plist
cat << EOF > "$APP_BUNDLE/Contents/Info.plist"
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
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
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
