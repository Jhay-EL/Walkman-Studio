#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="2.0.1"
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

# 5. Generate Release Notes (Markdown & HTML)
cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.md"
# Walkman Studio v2.0.1

This update resolves the issue where importing explicit songs caused them to be renamed or displayed as "Unknown" on Sony Walkman devices, alongside hardware optimizations and stability fixes.

---

### Bug Fixes & Hardware Optimizations

* **Explicit Song "Unknown" Display Fix**: Resolved an issue where explicit badges (such as 4-byte UTF-8 symbols like `🅴` and suffix markers like `[Explicit]`) triggered the Sony Walkman RTOS media parser fault, causing songs to be renamed or displayed as "Unknown".
* **Basic Multilingual Plane (BMP) Tag Sanitization**: Automatically strips non-BMP Unicode characters and variation selectors across Vorbis comments, ID3v2 frames, and filenames while preserving foreign language characters, accents, and umlauts.
* **Non-Destructive Tag Writing**: Embedded tags are preserved when transferring music, preventing accidental overwriting with blank or unknown values.
* **Native M3U8 Playlist Sync**: Formats playlists with UTF-8 BOM and CRLF line endings in `/MUSIC/` for native recognition on Sony Walkman players.
* **Responsive Window Optimization**: Layout reflows smoothly when resized to compact dimensions with zero frame drops.

---

### Core Features

* **Direct Music Transfer**: Automatically routes tracks into the standard `/MUSIC/<Artist>/<Album>/` folder structure.
* **In-Line Audio Preview**: Listen to tracks with waveform scrubbing and audio specs before transferring.
* **Baseline RGB JPEG Cover Art**: Enforces the 800x800 Baseline RGB JPEG standard to prevent device crashes and blank artwork tiles.
* **Online Metadata & Artwork Enrichment**: Automatic retrieval of missing tags and high-resolution cover art via iTunes and Deezer.
* **Synchronized Lyrics (.LRC)**: Automatically pairs timestamped lyrics with audio tracks.
* **macOS Junk File Purging**: Strips `._*` AppleDouble shadow files and extended attributes before safe ejection.

---

### Installation
1. Download **`Walkman-Studio-2.0.1-arm64.dmg`** below.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v2.0.1</h1>

<p>This update resolves the issue where importing explicit songs caused them to be renamed or displayed as "Unknown" on Sony Walkman devices, alongside hardware optimizations and stability fixes.</p>

<hr>

<h2>Bug Fixes &amp; Hardware Optimizations</h2>
<ul>
  <li><strong>Explicit Song "Unknown" Display Fix:</strong> Resolved an issue where explicit badges (such as 4-byte UTF-8 symbols like <code>&#x1F174;</code> and suffix markers like <code>[Explicit]</code>) triggered the Sony Walkman RTOS media parser fault, causing songs to be renamed or displayed as "Unknown".</li>
  <li><strong>Basic Multilingual Plane (BMP) Tag Sanitization:</strong> Automatically strips non-BMP Unicode characters and variation selectors across Vorbis comments, ID3v2 frames, and filenames while preserving foreign language characters, accents, and umlauts.</li>
  <li><strong>Non-Destructive Tag Writing:</strong> Embedded tags are preserved when transferring music, preventing accidental overwriting with blank or unknown values.</li>
  <li><strong>Native M3U8 Playlist Sync:</strong> Formats playlists with UTF-8 BOM and CRLF line endings in <code>/MUSIC/</code> for native recognition on Sony Walkman players.</li>
  <li><strong>Responsive Window Optimization:</strong> Layout reflows smoothly when resized to compact dimensions with zero frame drops.</li>
</ul>

<hr>

<h2>Core Features</h2>
<ul>
  <li><strong>Direct Music Transfer:</strong> Automatically routes tracks into the standard <code>/MUSIC/&lt;Artist&gt;/&lt;Album&gt;/</code> folder structure.</li>
  <li><strong>In-Line Audio Preview:</strong> Listen to tracks with waveform scrubbing and audio specs before transferring.</li>
  <li><strong>Baseline RGB JPEG Cover Art:</strong> Enforces the 800&times;800 Baseline RGB JPEG standard to prevent device crashes and blank artwork tiles.</li>
  <li><strong>Online Metadata &amp; Artwork Enrichment:</strong> Automatic retrieval of missing tags and high-resolution cover art via iTunes and Deezer.</li>
  <li><strong>Synchronized Lyrics (.LRC):</strong> Automatically pairs timestamped lyrics with audio tracks.</li>
  <li><strong>macOS Junk File Purging:</strong> Strips <code>._*</code> AppleDouble shadow files and extended attributes before safe ejection.</li>
</ul>

<hr>

<h2>Installation</h2>
<ol>
  <li>Download <code>Walkman-Studio-2.0.1-arm64.dmg</code> below.</li>
  <li>Open the disk image and drag <strong>Walkman Studio</strong> into your <strong>Applications</strong> folder.</li>
  <li>Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.</li>
</ol>
EOF

echo ""
echo "=== Release Artifacts Generated Successfully ==="
ls -lh "$DIST_DIR"
echo ""
echo "Checksums:"
cat "$DIST_DIR/SHA256SUMS.txt"
