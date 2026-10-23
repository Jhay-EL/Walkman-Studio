#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="2.0.3"
DIST_DIR="$DIR/dist"
APP_NAME="Walkman Studio"
APP_BUNDLE="$DIR/$APP_NAME.app"

echo "=== Building Walkman Studio v$VERSION Release Artifacts (Apple Silicon & Intel) ==="

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

package_dist() {
    local ARCH="$1"
    local SUFFIX="$2"
    echo ""
    echo "=========================================================="
    echo " Building & Packaging for $ARCH ($SUFFIX)..."
    echo "=========================================================="
    
    ./build_app.sh "$ARCH"
    
    if [ ! -d "$APP_BUNDLE" ]; then
        echo "Error: App bundle $APP_BUNDLE does not exist!"
        exit 1
    fi
    
    local ZIP_NAME="Walkman-Studio-${VERSION}-${SUFFIX}.zip"
    echo "Packaging $ZIP_NAME..."
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/$ZIP_NAME"
    
    local DMG_NAME="Walkman-Studio-${VERSION}-${SUFFIX}.dmg"
    echo "Packaging $DMG_NAME..."
    local DMG_TEMP_DIR="$(mktemp -d /tmp/walkman-dmg-XXXXXX)"
    cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"
    ln -s /Applications "$DMG_TEMP_DIR/Applications"
    hdiutil create -volname "Walkman Studio" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "$DIST_DIR/$DMG_NAME"
    rm -rf "$DMG_TEMP_DIR"
}

# 1. Package Apple Silicon (arm64) distribution
package_dist "arm64" "arm64"

# 2. Package Intel-based Mac (x86_64) distribution
package_dist "x86_64" "intel"

# 3. Package Universal Binary (arm64 + x86_64) distribution
package_dist "universal" "universal"

# 4. Generate SHA256 Checksums
echo ""
echo "Generating SHA256 checksums..."
cd "$DIST_DIR"
shasum -a 256 *.zip *.dmg > SHA256SUMS.txt

# 5. Generate Release Notes (Markdown & HTML)
cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.md"
# Walkman Studio v2.0.3

Walkman Studio v2.0.3 brings native **Intel-based MacBook and Mac support (`x86_64`)**, alongside Apple Silicon (`arm64`), standalone popup **Song and Album Metadata Editors**, full **Cover Art Extraction & Export to Mac**, and streamlined **Language Study & Audiobooks (`/LEARNING`)** workflows.

---

## What's New in v2.0.3

### 🖥️ Native Intel-based MacBook & Mac Support
* **Multi-Architecture Support:** Walkman Studio now runs natively on both **Intel-based Macs (Core i5, i7, i9, Xeon)** and **Apple Silicon Macs (M1, M2, M3, M4)**.
* **Dedicated & Universal DMGs:** Available as dedicated `.dmg` installers for Apple Silicon (`arm64`), Intel (`intel`), and an all-in-one Universal binary (`universal`).

### 🎵 Standalone Popup Song Metadata Editor
* **Right-Click Metadata Editor:** Right-click any track in the **Library**, **Albums**, **Artists**, **Recently Added**, or **Hi-Res Audio** views to open the full Song Metadata Editor popup window.
* **Integrated Lyrics Editor:** Edit synchronized `.LRC` or plain text lyrics in a dedicated editor pane, or fetch them automatically from online databases.
* **Artwork Replacement & Compliance:** Inspect, replace, and validate album cover art against the Sony Walkman 800×800 Baseline RGB JPEG standard.
* **50% Enlarged Layout:** Two-column responsive layout optimized for comfortable editing with spacious fields and high-resolution artwork preview.

### 💿 Standalone Popup Album Metadata Editor
* **Album-Wide Tagging:** Edit album title, album artist, release year, and genre across all tracks simultaneously.
* **Batch Artwork Writing:** Automatically embeds compliant Baseline RGB JPEG artwork into every track in the album and updates `folder.jpg` and `cover.jpg` in the album folder.
* **Tracklist Auto-Numbering & Reordering:** Auto-number tracks (`1..N`), pad numbers with leading zeros (`01..N`), and reorder tracks with interactive up/down controls.
* **Ergonomic Window:** Expanded 50% larger with comfortable button spacing and balanced bottom action bar.

### 🖼️ Cover Art Extraction & Direct Mac Export
* **Extract & Save to Mac:** Extract embedded artwork (or companion folder art) from any song or album and save it directly onto your Mac via a native macOS `NSSavePanel` dialog.
* **Finder Reveal:** Automatically highlights the exported `Artist - Album Cover.jpg` file in Finder upon completion.
* **Universal Access:** Export cover art from right-click context menus anywhere in the app, or from the right sidebar and popup editor sheets.

### 📚 Language Study & Audiobooks (`/LEARNING`) Polish
* **Distraction-Free Controls:** Automatically disables `.LRC Lyrics` and `Auto-Tags` buttons in Language Study mode, preventing unwanted music tag lookups from overwriting audiobook chapter titles and author names.
* **Automatic M3U8 Playlist Sync:** Transferred audiobooks and podcast episodes automatically generate ready-to-play `.m3u8` playlists inside `/LEARNING/`.

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-2.0.3-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-2.0.3-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-2.0.3-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 14.0+) |

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v2.0.3</h1>

<p>Walkman Studio v2.0.3 brings native <strong>Intel-based MacBook and Mac support (<code>x86_64</code>)</strong>, alongside Apple Silicon (<code>arm64</code>), standalone popup <strong>Song and Album Metadata Editors</strong>, full <strong>Cover Art Extraction &amp; Export to Mac</strong>, and streamlined <strong>Language Study &amp; Audiobooks (<code>/LEARNING</code>)</strong> workflows.</p>

<hr>

<h2>What's New in v2.0.3</h2>

<h3>🖥️ Native Intel-based MacBook &amp; Mac Support</h3>
<ul>
  <li><strong>Multi-Architecture Support:</strong> Walkman Studio now runs natively on both <strong>Intel-based Macs (Core i5, i7, i9, Xeon)</strong> and <strong>Apple Silicon Macs (M1, M2, M3, M4)</strong>.</li>
  <li><strong>Dedicated &amp; Universal DMGs:</strong> Available as dedicated <code>.dmg</code> installers for Apple Silicon (<code>arm64</code>), Intel (<code>intel</code>), and an all-in-one Universal binary (<code>universal</code>).</li>
</ul>

<h3>🎵 Standalone Popup Song Metadata Editor</h3>
<ul>
  <li><strong>Right-Click Metadata Editor:</strong> Right-click any track in the <strong>Library</strong>, <strong>Albums</strong>, <strong>Artists</strong>, <strong>Recently Added</strong>, or <strong>Hi-Res Audio</strong> views to open the full Song Metadata Editor popup window.</li>
  <li><strong>Integrated Lyrics Editor:</strong> Edit synchronized <code>.LRC</code> or plain text lyrics in a dedicated editor pane, or fetch them automatically from online databases.</li>
  <li><strong>Artwork Replacement &amp; Compliance:</strong> Inspect, replace, and validate album cover art against the Sony Walkman 800&times;800 Baseline RGB JPEG standard.</li>
  <li><strong>50% Enlarged Layout:</strong> Two-column responsive layout optimized for comfortable editing with spacious fields and high-resolution artwork preview.</li>
</ul>

<h3>💿 Standalone Popup Album Metadata Editor</h3>
<ul>
  <li><strong>Album-Wide Tagging:</strong> Edit album title, album artist, release year, and genre across all tracks simultaneously.</li>
  <li><strong>Batch Artwork Writing:</strong> Automatically embeds compliant Baseline RGB JPEG artwork into every track in the album and updates <code>folder.jpg</code> and <code>cover.jpg</code> in the album folder.</li>
  <li><strong>Tracklist Auto-Numbering &amp; Reordering:</strong> Auto-number tracks (<code>1..N</code>), pad numbers with leading zeros (<code>01..N</code>), and reorder tracks with interactive up/down controls.</li>
  <li><strong>Ergonomic Window:</strong> Expanded 50% larger with comfortable button spacing and balanced bottom action bar.</li>
</ul>

<h3>🖼️ Cover Art Extraction &amp; Direct Mac Export</h3>
<ul>
  <li><strong>Extract &amp; Save to Mac:</strong> Extract embedded artwork (or companion folder art) from any song or album and save it directly onto your Mac via a native macOS <code>NSSavePanel</code> dialog.</li>
  <li><strong>Finder Reveal:</strong> Automatically highlights the exported <code>Artist - Album Cover.jpg</code> file in Finder upon completion.</li>
  <li><strong>Universal Access:</strong> Export cover art from right-click context menus anywhere in the app, or from the right sidebar and popup editor sheets.</li>
</ul>

<h3>📚 Language Study &amp; Audiobooks (<code>/LEARNING</code>) Polish</h3>
<ul>
  <li><strong>Distraction-Free Controls:</strong> Automatically disables <code>.LRC Lyrics</code> and <code>Auto-Tags</code> buttons in Language Study mode, preventing unwanted music tag lookups from overwriting audiobook chapter titles and author names.</li>
  <li><strong>Automatic M3U8 Playlist Sync:</strong> Transferred audiobooks and podcast episodes automatically generate ready-to-play <code>.m3u8</code> playlists inside <code>/LEARNING/</code>.</li>
</ul>

<hr>

<h2>Downloads</h2>

<table>
  <thead>
    <tr>
      <th>Installer</th>
      <th>Architecture</th>
      <th>Target System</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong><code>Walkman-Studio-2.0.3-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-2.0.3-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-2.0.3-universal.dmg</code></strong></td>
      <td>Universal 2 (<code>arm64</code> + <code>x86_64</code>)</td>
      <td>Universal package running natively on all Macs (macOS 14.0+)</td>
    </tr>
  </tbody>
</table>

<hr>

<h2>Installation</h2>
<ol>
  <li>Download the <code>.dmg</code> corresponding to your Mac architecture above.</li>
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
