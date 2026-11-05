#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="3.1.0"
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
# Walkman Studio v3.1.0

Walkman Studio v3.1.0 is headlined by the all-new **LRC Fetcher (Batch Synchronized Lyrics Generator)**, enabling high-speed multi-threaded retrieval of timestamp-accurate `.lrc` lyrics across your entire library or selected playlists and albums, accompanied by targeted UI enhancements, playback refinements, and minor fixes across Apple Silicon (`arm64`) and Intel-based Macs (`x86_64`).

---

## Headline Feature: LRC Fetcher (Batch Synchronized Lyrics Generator)

* **Universal Library Integration:** Dedicated circular 38×38pt Liquid Glass lyrics buttons (`quote.bubble`) built into every library view header: *All Songs*, *Recently Added*, *Albums*, *Artists*, *Hi-Res Audio*, *Playlists*, and *Language Study*.
* **Flexible Contextual Selection Scopes:**
  * **All Tracks in View:** Scans and fetches lyrics for all tracks in the currently selected view.
  * **Selected Track(s):** Scopes fetching strictly to rows highlighted or checked in the song table.
  * **Active Item:** Scopes fetching directly to the currently opened Album, Artist, or Playlist.
  * **Choose Specific...:** Interactive Liquid Glass checklist sheet featuring live search, "Select All" / "Deselect All" shortcuts, real-time candidate track counts, and missing-lyrics diagnostics.
* **Concurrent Multi-Worker Engine:** High-throughput asynchronous worker pool querying the open-source **LRCLIB** API (`/api/get` & `/api/search`) with exact millisecond duration matching and automatic fallback to **Lyrics.ovh**.
* **Live Progress & Interactive Metric Dashboard:** Real-time animated progress bar, speed/ETA calculations, and interactive status metric pills (**Synced .LRC**, **Plain Text**, **Skipped**, **Not Found**) with a searchable per-track result breakdown card.
* **Strict Timestamp & Date Added Preservation:** Original audio file modification dates and internal timestamps are strictly preserved, preventing existing library tracks from falsely jumping to the top of "Recently Added" smart playlists.
* **Compliant Companion .LRC Files:** Automatically writes standardized companion `.lrc` files directly adjacent to audio tracks for instant recognition on Sony Walkman hardware and the built-in Now Playing player.

---

## Minor Fixes & Improvements

* **Language Study Studio:** Added dedicated support for Sony Walkman's root `/LEARNING` directory for audiobooks, podcasts, and language lessons, complete with instant format filters (MP3, M4A/AAC, FLAC) and $O(1)$ cached segmented views.
* **Authentic Sony SensMe™ Highlight Playback:** Audio surfing now tunes in directly at the 12-Tone acoustic climax position (`senseMeHighlightSec`) with zero audio leakage from 0:00, paired with *Highlight (45s)* vs *Full Track* range toggles and active gold chorus badges.
* **Fluid Window Expansion on Track Detail:** Opening the Track Detail panel (Inspector) smoothly widens the macOS window by +300pt, preserving 100% of the table and grid space for your music library, with screen-edge boundary protection.
* **Static Navigation Sidebar:** Navigation sidebar is locked at 260pt and never collapses or auto-hides when opening or closing inspector views.
* **Expandable Liquid Glass Search Bar:** Compact search icon morphs into a translucent liquid glass search bar with fluid spring physics, synchronized fade transitions, and click-outside collapse.
* **Android Walkman Heuristics & Detection:** Improved capacity heuristics, USB composite PID matching, and broader audio format support across Android Walkman models.

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-3.1.0-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-3.1.0-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-3.1.0-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 13.0+) |

### Alternative Mirror
* **Google Drive:** [Download v3.1.0 Release Files on Google Drive](https://drive.google.com/drive/folders/1KjkVl7U-FBZ0Ics4OuttyOj6HanPajpg?usp=share_link)

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v3.1.0</h1>

<p>Walkman Studio v3.1.0 is headlined by the all-new <strong>LRC Fetcher (Batch Synchronized Lyrics Generator)</strong>, enabling high-speed multi-threaded retrieval of timestamp-accurate <code>.lrc</code> lyrics across your entire library or selected playlists and albums, accompanied by targeted UI enhancements, playback refinements, and minor fixes across Apple Silicon (<code>arm64</code>) and Intel-based Macs (<code>x86_64</code>).</p>

<hr>

<h2>Headline Feature: LRC Fetcher (Batch Synchronized Lyrics Generator)</h2>
<ul>
  <li><strong>Universal Library Integration:</strong> Dedicated circular 38&times;38pt Liquid Glass lyrics buttons (<code>quote.bubble</code>) built into every library view header: <em>All Songs</em>, <em>Recently Added</em>, <em>Albums</em>, <em>Artists</em>, <em>Hi-Res Audio</em>, <em>Playlists</em>, and <em>Language Study</em>.</li>
  <li><strong>Flexible Contextual Selection Scopes:</strong>
    <ul>
      <li><strong>All Tracks in View:</strong> Scans and fetches lyrics for all tracks in the currently selected view.</li>
      <li><strong>Selected Track(s):</strong> Scopes fetching strictly to rows highlighted or checked in the song table.</li>
      <li><strong>Active Item:</strong> Scopes fetching directly to the currently opened Album, Artist, or Playlist.</li>
      <li><strong>Choose Specific...:</strong> Interactive Liquid Glass checklist sheet featuring live search, &ldquo;Select All&rdquo; / &ldquo;Deselect All&rdquo; shortcuts, real-time candidate track counts, and missing-lyrics diagnostics.</li>
    </ul>
  </li>
  <li><strong>Concurrent Multi-Worker Engine:</strong> High-throughput asynchronous worker pool querying the open-source <strong>LRCLIB</strong> API (<code>/api/get</code> &amp; <code>/api/search</code>) with exact millisecond duration matching and automatic fallback to <strong>Lyrics.ovh</strong>.</li>
  <li><strong>Live Progress &amp; Interactive Metric Dashboard:</strong> Real-time animated progress bar, speed/ETA calculations, and interactive status metric pills (<strong>Synced .LRC</strong>, <strong>Plain Text</strong>, <strong>Skipped</strong>, <strong>Not Found</strong>) with a searchable per-track result breakdown card.</li>
  <li><strong>Strict Timestamp &amp; Date Added Preservation:</strong> Original audio file modification dates and internal timestamps are strictly preserved, preventing existing library tracks from falsely jumping to the top of &ldquo;Recently Added&rdquo; smart playlists.</li>
  <li><strong>Compliant Companion .LRC Files:</strong> Automatically writes standardized companion <code>.lrc</code> files directly alongside audio tracks for instant recognition on Sony Walkman hardware and the built-in Now Playing player.</li>
</ul>

<hr>

<h2>Minor Fixes &amp; Improvements</h2>
<ul>
  <li><strong>Language Study Studio:</strong> Added dedicated support for Sony Walkman's root <code>/LEARNING</code> directory for audiobooks, podcasts, and language lessons, complete with instant format filters (MP3, M4A/AAC, FLAC) and O(1) cached segmented views.</li>
  <li><strong>Authentic Sony SensMe&trade; Highlight Playback:</strong> Audio surfing now tunes in directly at the 12-Tone acoustic climax position (<code>senseMeHighlightSec</code>) with zero audio leakage from 0:00, paired with <em>Highlight (45s)</em> vs <em>Full Track</em> range toggles and active gold chorus badges.</li>
  <li><strong>Fluid Window Expansion on Track Detail:</strong> Opening the Track Detail panel (Inspector) smoothly widens the macOS window by +300pt, preserving 100% of the table and grid space for your music library, with screen-edge boundary protection.</li>
  <li><strong>Static Navigation Sidebar:</strong> Navigation sidebar is locked at 260pt and never collapses or auto-hides when opening or closing inspector views.</li>
  <li><strong>Expandable Liquid Glass Search Bar:</strong> Compact search icon morphs into a translucent liquid glass search bar with fluid spring physics, synchronized fade transitions, and click-outside collapse.</li>
  <li><strong>Android Walkman Heuristics &amp; Detection:</strong> Improved capacity heuristics, USB composite PID matching, and broader audio format support across Android Walkman models.</li>
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
      <td><strong><code>Walkman-Studio-3.1.0-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.1.0-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.1.0-universal.dmg</code></strong></td>
      <td>Universal 2 (<code>arm64</code> + <code>x86_64</code>)</td>
      <td>Universal package running natively on all Macs (macOS 13.0+)</td>
    </tr>
  </tbody>
</table>

<h3>Alternative Mirror</h3>
<p><strong>Google Drive:</strong> <a href="https://drive.google.com/drive/folders/1KjkVl7U-FBZ0Ics4OuttyOj6HanPajpg?usp=share_link" target="_blank" rel="noopener noreferrer">Download v3.1.0 Release Files on Google Drive</a></p>

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
