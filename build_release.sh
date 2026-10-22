#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="2.0.0"
DIST_DIR="$DIR/dist"

echo "=== Building Walkman Studio v$VERSION Release Artifacts ==="

# 1. Build release app bundle
./build_app.sh

APP_BUNDLE="$DIR/Walkman Studio.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle $APP_BUNDLE does not exist!"
    exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 2. Package .zip distribution
ZIP_NAME="Walkman-Studio-${VERSION}-arm64.zip"
echo "Packaging $ZIP_NAME..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/$ZIP_NAME"

# 3. Package .dmg installer
DMG_NAME="Walkman-Studio-${VERSION}-arm64.dmg"
echo "Packaging $DMG_NAME..."
DMG_TEMP_DIR="$(mktemp -d /tmp/walkman-dmg-XXXXXX)"
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"
ln -s /Applications "$DMG_TEMP_DIR/Applications"
hdiutil create -volname "Walkman Studio" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "$DIST_DIR/$DMG_NAME"
rm -rf "$DMG_TEMP_DIR"

# 4. Generate SHA256 Checksums
echo "Generating SHA256 checksums..."
cd "$DIST_DIR"
shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > SHA256SUMS.txt

# 5. Generate Release Notes
cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.md"
# Walkman Studio v2.0.0

A high-performance, native macOS manager and hardware optimization suite designed exclusively for non-Android Sony Walkman DAPs (NW-A55, NW-A50, NW-A40 series).

---

## What's New in v2.0.0

### 🚀 Supercharged "Transfer & Convert" Tab
* **In-Line Audio Preview Playback**: Preview audio tracks directly in the transfer queue with playback controls, scrub bar, waveform visualization, and real-time audio format specifications.
* **Universal Multi-Strategy Tag Extraction**: High-fidelity metadata preservation across FLAC Vorbis comments (including `ALBUMARTIST`, `ALBUM_ARTIST`, multiple artists, track/year), ID3v2.2 / ID3v2.3 / ID3v2.4 with extended header skipping, and native macOS `AVURLAsset` / CoreAudio fallbacks.
* **Auto-Routing to Walkman Album Directories**: Automatically creates `/MUSIC/<Artist>/<Album>/<NN - Title>.<ext>` folder structures, completely resolving "Unknown Artist" and "Unknown Album" issues.
* **Non-Destructive Tag Writing**: Safely writes Sony Walkman-compliant metadata without ever overwriting existing embedded tags with blank values.
* **Online Metadata & Artwork Fetching**: Cleans noisy file names (removes `[Official Video]`, `(Remastered)`, track prefixes) and queries Apple iTunes & Deezer APIs for missing tags and original 800×800 artwork with zero API keys required.
* **Baseline RGB JPEG Optimizer**: Enforces Sony Walkman hardware compliance (Baseline RGB JPEG, $\le 800\times 800$ px at 92% quality) to eliminate device database freezes and blank artwork tiles.
* **Synchronized Companion Lyrics (.LRC)**: Automatically searches and downloads synchronized `.lrc` lyrics from LRCLIB/Lyrics.ovh, saving paired timestamped lyrics alongside the audio file.
* **Extended Conversion Presets**:
  * *Optimize Metadata Only (Direct Pass-Through)*: 100% bit-perfect audio passthrough with strict Sony ID3v2.3 / Vorbis tagging and companion files.
  * Lossless FLAC (16-bit / 44.1kHz up to 24-bit / 192kHz).
  * MP3 (320 kbps, 256 kbps, VBR V0).
  * Apple & PCM Audio (AAC 320/256 kbps, ALAC 16-bit, WAV 16-bit PCM).
  * Optional EBU R128 loudness leveling (`-af loudnorm`).

### 📱 Responsive Layout & UI Sizing
* **Responsive Hardware Options Toolbar**: Automatically adapts from a single-line horizontal bar on wide displays into a clean, un-cramped list on compact screens.
* **Responsive Device Overview**: Dynamic reflow for the Hero Device Card, vertical stacking for Internal and MicroSD drive storage meters, and compact action card rows.
* **Symmetrical Top Navigation Cards**: Mathematical 3-column width distribution via `GeometryReader` ensuring identical width and height across all window sizes.
* **Zero-Lag Window Resizing**: Precomputed library statistics running on background tasks, delivering a fluid 120 FPS window resizing experience on Apple Silicon.

### 🧹 Native macOS Junk & Shadow File Purging
* Automatic merging and cleaning of AppleDouble fork files (`._*`, `.DS_Store`, `com.apple.TextEncoding`) to ensure pristine Walkman FAT32/exFAT databases.
* Clean and safe hardware ejection directly from the app.

---

## Installation & Requirements

* **Operating System**: macOS Sonoma (14.0) or later.
* **Architecture**: Apple Silicon (M1, M2, M3, M4).
* **Supported Devices**: Sony Walkman NW-A55, NW-A55L, NW-A56, NW-A57, NW-A50 Series, NW-A40 Series, NW-A30 Series, NW-ZX300, and non-Android Linux-based Walkman DAPs.

### Installation Steps
1. Download **`Walkman-Studio-2.0.0-arm64.dmg`** below.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman via USB Mass Storage mode and launch Walkman Studio!
EOF

echo ""
echo "=== Release Artifacts Generated Successfully ==="
ls -lh "$DIST_DIR"
echo ""
echo "Checksums:"
cat "$DIST_DIR/SHA256SUMS.txt"
