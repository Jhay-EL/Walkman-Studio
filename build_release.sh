#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="2.0.2"
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
# Walkman Studio v2.0.2

This update introduces dedicated Language Study (語学学習) mode support for podcasts and audiobooks, instant on-device song & album deletion without confirmation, flexible album sorting, and a redesigned Transfer & Convert interface.

---

## New Features & Hardware Optimizations

* **Language Study (`/LEARNING/`) Mode:** Directly transfer audiobooks, podcasts, and language lessons to the Sony Walkman's dedicated `/LEARNING/` system directory with automatic classification under the `"Language Learning"` genre.
* **Hardware 5-View Optimization:** Spoken-word audio is fully formatted and indexed across all 5 Walkman hardware screens (Album with 800×800 Baseline RGB JPEG artwork & `folder.jpg`, Artist grouping, All Songs chronological sorting, auto-generated M3U8 Playlists in `/LEARNING/`, and chronologically ordered Recent Transfers via staggered `mtime` timestamps).
* **Auto-Remux `.m4b` Audiobooks:** Automatically remuxes `.m4b` audiobook files into `.m4a` containers with lossless audio and full metadata, ensuring immediate playback on Walkman firmware without external tools.
* **Speech-Optimized Presets:** Added dedicated voice conversion presets including `MP3 128 kbps Spoken Word`, `MP3 192 kbps Voice Master`, and `AAC 128 kbps Spoken Audio` for crisp voice clarity and compact storage.
* **Instant On-Device Deletion:** Right-click any track in the **All Songs** tab or any album in the **Albums** tab to delete it directly from the Walkman hardware without confirmation dialogs.
* **Album Sorting & Management:** Sort albums by Recently Added, Album Name (A–Z / Z–A), Artist Name, Track Count, and Release Year, with instant album inspection.
* **Redesigned Transfer & Convert Deck:** Streamlined 3-column control deck with Target Volume switcher, Library Mode toggle (`/MUSIC` vs `/LEARNING`), and responsive queue item cards with real-time audio specs.
* **Explicit "Save to Walkman" & Playlist Sync:** Formats playlists with strict POSIX paths, NFC Unicode normalization, and CRLF line endings, paired with a tactile **Save to Walkman** button and `⌘S` keyboard shortcut.
* **Multi-Directory USB Scanner:** High-speed library scanner now concurrently indexes both `/MUSIC` and `/LEARNING` directories over USB, with full metadata support for `.m4b` and `.aac` files.

---

## Installation

1. Download `Walkman-Studio-2.0.2-arm64.dmg` below.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v2.0.2</h1>

<p>This update introduces dedicated Language Study (語学学習) mode support for podcasts and audiobooks, instant on-device song &amp; album deletion without confirmation, flexible album sorting, and a redesigned Transfer &amp; Convert interface.</p>

<hr>

<h2>New Features &amp; Hardware Optimizations</h2>
<ul>
  <li><strong>Language Study (<code>/LEARNING/</code>) Mode:</strong> Directly transfer audiobooks, podcasts, and language lessons to the Sony Walkman's dedicated <code>/LEARNING/</code> system directory with automatic classification under the <code>"Language Learning"</code> genre.</li>
  <li><strong>Hardware 5-View Optimization:</strong> Spoken-word audio is fully formatted and indexed across all 5 Walkman hardware screens (Album with 800&times;800 Baseline RGB JPEG artwork &amp; <code>folder.jpg</code>, Artist grouping, All Songs chronological sorting, auto-generated M3U8 Playlists in <code>/LEARNING/</code>, and chronologically ordered Recent Transfers via staggered <code>mtime</code> timestamps).</li>
  <li><strong>Auto-Remux <code>.m4b</code> Audiobooks:</strong> Automatically remuxes <code>.m4b</code> audiobook files into <code>.m4a</code> containers with lossless audio and full metadata, ensuring immediate playback on Walkman firmware without external tools.</li>
  <li><strong>Speech-Optimized Presets:</strong> Added dedicated voice conversion presets including <code>MP3 128 kbps Spoken Word</code>, <code>MP3 192 kbps Voice Master</code>, and <code>AAC 128 kbps Spoken Audio</code> for crisp voice clarity and compact storage.</li>
  <li><strong>Instant On-Device Deletion:</strong> Right-click any track in the <strong>All Songs</strong> tab or any album in the <strong>Albums</strong> tab to delete it directly from the Walkman hardware without confirmation dialogs.</li>
  <li><strong>Album Sorting &amp; Management:</strong> Sort albums by Recently Added, Album Name (A&ndash;Z / Z&ndash;A), Artist Name, Track Count, and Release Year, with instant album inspection.</li>
  <li><strong>Redesigned Transfer &amp; Convert Deck:</strong> Streamlined 3-column control deck with Target Volume switcher, Library Mode toggle (<code>/MUSIC</code> vs <code>/LEARNING</code>), and responsive queue item cards with real-time audio specs.</li>
  <li><strong>Explicit "Save to Walkman" &amp; Playlist Sync:</strong> Formats playlists with strict POSIX paths, NFC Unicode normalization, and CRLF line endings, paired with a tactile <strong>Save to Walkman</strong> button and <code>&#x2318;S</code> keyboard shortcut.</li>
  <li><strong>Multi-Directory USB Scanner:</strong> High-speed library scanner now concurrently indexes both <code>/MUSIC</code> and <code>/LEARNING</code> directories over USB, with full metadata support for <code>.m4b</code> and <code>.aac</code> files.</li>
</ul>

<hr>

<h2>Installation</h2>
<ol>
  <li>Download <code>Walkman-Studio-2.0.2-arm64.dmg</code> below.</li>
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
