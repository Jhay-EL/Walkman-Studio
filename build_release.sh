#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="3.1.1"
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
# Walkman Studio v3.1.1

Walkman Studio v3.1.1 is a comprehensive UI responsiveness, performance, playlist management, and lyrics synchronization release across Apple Silicon (`arm64`) and Intel-based Macs (`x86_64`), featuring an in-window Track Details panel at a compact `1200×660` minimum window, strict duplicate track detection and cleanup on the *Playlists* tab, smooth inspector animations across large Artists and Hi-Res Audio libraries, acoustic `.lrc` pregap calibration, and interactive library cross-navigation.

---

## What's New in v3.1.1

### Responsive In-Window Inspector & Compact Window Layout
* **In-Window Sliding Track Details Panel:** Track Details now opens smoothly inside the main window (`300pt`) without resizing or shifting your macOS window frame, with full-height divider alignment and automatic hiding on *Device Overview*, *Duplicates*, *Transfer & Convert*, and *Backup & Restore*.
* **Compact `1200×660` Minimum Window Support:** Reduced minimum window size constraints (default `1360×820`) while keeping every library toolbar single-lane via adaptive Liquid Glass dropdown menus and compact segmented control tiers across *Local Music Library*, *All Songs*, *Recently Added*, *Albums*, *Artists*, *Hi-Res Audio*, *Language Study*, and *Duplicates*.
* **Consistent Liquid Glass Controls:** Standardized circular Liquid Glass Play buttons, native `.menu` dropdown styling, compact *SenseMe* toolbar fallback during scanning, and unclipped multi-tier segmented bars on narrow layouts.

### Artists & Hi-Res Audio Performance + Table Layout Fixes
* **Lag-Free Inspector Toggling:** Eliminated UI stutter when toggling Track Details on large *Artists* and *Hi-Res Audio* collections through container-level discrete width tiers, `LazyVStack` virtualization, cached artist discography metadata, `Equatable` row diff pruning, and single-pane active mode rendering.
* **Table Horizontal Scrollbar Anchoring:** Fixed `TableScrollInsetModifier` across *Local Music Library*, *All Songs*, and *Recently Added* so horizontal scrollbars stay anchored cleanly at the bottom edge instead of floating over track rows.

### Acoustic Lyrics Alignment & Sample-Accurate Playback
* **Acoustic Lead-In Pregap Calibration (`AudioAcousticAligner`):** Inspects leading audio streams via `AVAssetReader` to detect mastering pregap silence and automatically calibrate `.lrc` `[offset:...]` timestamps in **LRC Fetcher** and the **Transfer Queue Item Editor**.
* **Strict LRCLIB Duration Guard:** Enforces candidate scoring and `<= 3.5s` duration verification in `LyricsService` to prevent synced timestamps from mismatched edits or radio versions.
* **Sample-Accurate `.LRC` Seeking & Expandable Lyrics Card:** Fixed `.lrc` timestamp synchronization on scrubber advances in Track Details and Fullscreen Now Playing, and added an expandable / compact lyrics view toggle in the Track Details inspector.

### Playlists Tab: Duplicate Track Detection & Non-Destructive Cleanup
* **Strict Same-Playlist Duplicate Detection (`PlaylistDuplicateDetector`):** Automatically scans each playlist independently to detect both canonical file path repeats (across slash, casing, `./`, `MUSIC/`, and `LEARNING/` prefixes) and exact-title cross-file copies (`exactTextKey` preserving `(Remastered)`, `(feat. ...)`, `(Live)`, and version suffixes with `<= 4.0s` duration matching).
* **Sidebar Badges, Inline Row Pills & Filtering:** Displays duplicate count badges per playlist in the sidebar, inline `Keep` / `Dup` sequence indicators on playlist rows, a **Show Duplicates Only** filter toggle, and one-click **Select Extras** batch selection.
* **Liquid Glass Cleanup Review & Addition Guardrails:** Includes an interactive **Review Playlist Duplicates** modal with a sliding **Keep Highest Quality** vs **Keep First Position** segmented bar that removes selected entries strictly from `.m3u8` / `.m3u` playlist files while keeping all audio files on Walkman storage untouched, plus duplicate confirmation alerts and bulk-add skipping.

### Interactive Library Navigation & Device Setup Improvements
* **Direct Artist & Album Cross-Navigation:** Track table Artist and Album cells in *All Songs* and *Recently Added* now link directly to the matching discography or album detail view.
* **Expanded LRC Fetcher Coverage:** Added batch `.LRC` lyrics fetching directly into *Local Music Library* and Album / Artist context menus.
* **Redesigned Device Connection & Android MTP View:** Unified the disconnected device dashboard and Android Walkman MTP guidance card with cleaner sidebar synchronization.

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-3.1.1-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-3.1.1-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-3.1.1-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 13.0+) |

### Alternative Mirror
* **Google Drive:** [Download v3.1.1 Release Files on Google Drive](https://drive.google.com/drive/folders/1wC3F0Cdy_iJwdWQvR1VFc5VnvdhyULhd?usp=share_link)

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v3.1.1</h1>

<p>Walkman Studio v3.1.1 is a comprehensive UI responsiveness, performance, playlist management, and lyrics synchronization release across Apple Silicon (<code>arm64</code>) and Intel-based Macs (<code>x86_64</code>), featuring an in-window Track Details panel at a compact <code>1200&times;660</code> minimum window, strict duplicate track detection and cleanup on the <em>Playlists</em> tab, smooth inspector animations across large Artists and Hi-Res Audio libraries, acoustic <code>.lrc</code> pregap calibration, and interactive library cross-navigation.</p>

<hr>

<h2>What's New in v3.1.1</h2>

<h3>Responsive In-Window Inspector &amp; Compact Window Layout</h3>
<ul>
  <li><strong>In-Window Sliding Track Details Panel:</strong> Track Details now opens smoothly inside the main window (<code>300pt</code>) without resizing or shifting your macOS window frame, with full-height divider alignment and automatic hiding on <em>Device Overview</em>, <em>Duplicates</em>, <em>Transfer &amp; Convert</em>, and <em>Backup &amp; Restore</em>.</li>
  <li><strong>Compact <code>1200&times;660</code> Minimum Window Support:</strong> Reduced minimum window size constraints (default <code>1360&times;820</code>) while keeping every library toolbar single-lane via adaptive Liquid Glass dropdown menus and compact segmented control tiers across <em>Local Music Library</em>, <em>All Songs</em>, <em>Recently Added</em>, <em>Albums</em>, <em>Artists</em>, <em>Hi-Res Audio</em>, <em>Language Study</em>, and <em>Duplicates</em>.</li>
  <li><strong>Consistent Liquid Glass Controls:</strong> Standardized circular Liquid Glass Play buttons, native <code>.menu</code> dropdown styling, compact <em>SenseMe</em> toolbar fallback during scanning, and unclipped multi-tier segmented bars on narrow layouts.</li>
</ul>

<h3>Artists &amp; Hi-Res Audio Performance + Table Layout Fixes</h3>
<ul>
  <li><strong>Lag-Free Inspector Toggling:</strong> Eliminated UI stutter when toggling Track Details on large <em>Artists</em> and <em>Hi-Res Audio</em> collections through container-level discrete width tiers, <code>LazyVStack</code> virtualization, cached artist discography metadata, <code>Equatable</code> row diff pruning, and single-pane active mode rendering.</li>
  <li><strong>Table Horizontal Scrollbar Anchoring:</strong> Fixed <code>TableScrollInsetModifier</code> across <em>Local Music Library</em>, <em>All Songs</em>, and <em>Recently Added</em> so horizontal scrollbars stay anchored cleanly at the bottom edge instead of floating over track rows.</li>
</ul>

<h3>Acoustic Lyrics Alignment &amp; Sample-Accurate Playback</h3>
<ul>
  <li><strong>Acoustic Lead-In Pregap Calibration (<code>AudioAcousticAligner</code>):</strong> Inspects leading audio streams via <code>AVAssetReader</code> to detect mastering pregap silence and automatically calibrate <code>.lrc</code> <code>[offset:...]</code> timestamps in <strong>LRC Fetcher</strong> and the <strong>Transfer Queue Item Editor</strong>.</li>
  <li><strong>Strict LRCLIB Duration Guard:</strong> Enforces candidate scoring and <code>&le; 3.5s</code> duration verification in <code>LyricsService</code> to prevent synced timestamps from mismatched edits or radio versions.</li>
  <li><strong>Sample-Accurate <code>.LRC</code> Seeking &amp; Expandable Lyrics Card:</strong> Fixed <code>.lrc</code> timestamp synchronization on scrubber advances in Track Details and Fullscreen Now Playing, and added an expandable / compact lyrics view toggle in the Track Details inspector.</li>
</ul>

<h3>Playlists Tab: Duplicate Track Detection &amp; Non-Destructive Cleanup</h3>
<ul>
  <li><strong>Strict Same-Playlist Duplicate Detection (<code>PlaylistDuplicateDetector</code>):</strong> Automatically scans each playlist independently to detect both canonical file path repeats (across slash, casing, <code>./</code>, <code>MUSIC/</code>, and <code>LEARNING/</code> prefixes) and exact-title cross-file copies (preserving <code>(Remastered)</code>, <code>(feat. ...)</code>, <code>(Live)</code>, and version suffixes with <code>&le; 4.0s</code> duration matching).</li>
  <li><strong>Sidebar Badges, Inline Row Pills &amp; Filtering:</strong> Displays duplicate count badges per playlist in the sidebar, inline <code>Keep</code> / <code>Dup</code> sequence indicators on playlist rows, a <strong>Show Duplicates Only</strong> filter toggle, and one-click <strong>Select Extras</strong> batch selection.</li>
  <li><strong>Liquid Glass Cleanup Review &amp; Addition Guardrails:</strong> Includes an interactive <strong>Review Playlist Duplicates</strong> modal with a sliding <strong>Keep Highest Quality</strong> vs <strong>Keep First Position</strong> segmented bar that removes selected entries strictly from <code>.m3u8</code> / <code>.m3u</code> playlist files while keeping all audio files on Walkman storage untouched, plus duplicate confirmation alerts and bulk-add skipping.</li>
</ul>

<h3>Interactive Library Navigation &amp; Device Setup Improvements</h3>
<ul>
  <li><strong>Direct Artist &amp; Album Cross-Navigation:</strong> Track table Artist and Album cells in <em>All Songs</em> and <em>Recently Added</em> now link directly to the matching discography or album detail view.</li>
  <li><strong>Expanded LRC Fetcher Coverage:</strong> Added batch <code>.LRC</code> lyrics fetching directly into <em>Local Music Library</em> and Album / Artist context menus.</li>
  <li><strong>Redesigned Device Connection &amp; Android MTP View:</strong> Unified the disconnected device dashboard and Android Walkman MTP guidance card with cleaner sidebar synchronization.</li>
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
      <td><strong><code>Walkman-Studio-3.1.1-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.1.1-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.1.1-universal.dmg</code></strong></td>
      <td>Universal 2 (<code>arm64</code> + <code>x86_64</code>)</td>
      <td>Universal package running natively on all Macs (macOS 13.0+)</td>
    </tr>
  </tbody>
</table>

<h3>Alternative Mirror</h3>
<p><strong>Google Drive:</strong> <a href="https://drive.google.com/drive/folders/1wC3F0Cdy_iJwdWQvR1VFc5VnvdhyULhd?usp=share_link" target="_blank" rel="noopener noreferrer">Download v3.1.1 Release Files on Google Drive</a></p>

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
