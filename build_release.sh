#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="3.0.1"
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
# Walkman Studio v3.0.1

Walkman Studio v3.0.1 delivers critical resilience fixes and model identification accuracy improvements for Sony Walkman users alongside the complete Optical Liquid Glass Design System, CoreAudio Trim & Cut Studio, and Duplicates Studio across Apple Silicon (`arm64`) and Intel-based Macs (`x86_64`).

---

## What's New in v3.0.1

### Standalone MicroSD Card Model Accuracy Fix
* **Decoupled MicroSD Capacity Heuristics:** Resolved an issue where standalone MicroSD cards (e.g. 256GB / 237GB) caused Walkman Studio to misidentify an authentic `NW-A55` as an `NW-A57` when internal storage was unmounted or ejected.
* **Session & Persistent Device Memory:** Walkman Studio now securely caches authentically identified device models in memory and macOS preferences across volume unmounts, restarts, and ejects.
* **Strict Heuristic Upper Bounds:** Applied hardware capacity safety bounds across all series (`A50`, `A40`, `A30`, `A100`, `A300`, `ZX300`, `ZX500`, `ZX700`, `WM1`) so SD expansion storage never forces higher internal tiers.

### Local Music Library Resilience & Missing Folder Auto-Resolution
* **Real-Time Missing & Renamed Folder Detection:** Monitored folders moved, renamed, or deleted in Finder are instantly detected instead of silently failing or leaving stale ghost tracks.
* **Liquid Glass Amber Warning Banner:** Surfaces an ambient amber alert with one-click actions:
  * **"Relocate Folder...":** Re-links moved or renamed folders in Finder, instantly updating all track paths, relative indices, album art, and 12-Tone SensMe mood channels without re-scanning or re-importing.
  * **"Remove Missing":** Safely purges missing folders and orphaned ghost tracks from the SQLite library database with a single click.
* **Missing Audio File Playback Guard:** Double-clicking or attempting to preview an audio file that was moved or deleted on disk now displays a clear *"Audio File Not Found"* alert with the missing path and a direct relocation shortcut.
* **Manage Folders Enhancements:** `ManageLocalFoldersSheet` displays `MISSING OR RENAMED` status badges and dedicated **"Relocate..."** picker buttons.

### Safe Eject Deadlock & Ejection Hang Fix
* **Dynamic Binary Discovery:** Dynamically locates `dot_clean` across `/usr/sbin` and `/usr/bin`, eliminating launch errors on modern macOS releases.
* **10-Second Watchdog Timeout:** Safe Eject is guarded with timeout watchdogs to prevent Foundation deadlocks when unmounting sluggish FAT32/exFAT drives.

---

## Core v3.0 Capabilities

### Optical Liquid Glass Design System Language
* **Sony Signature Series Obsidian Chassis:** Solid obsidian surfaces (`#101114`), refraction glass lenses, specular edge highlights, and tactile spring physics.
* **Standardized 38pt Baseline Height & 28pt Capsule Pills:** All primary interactive controls share a uniform 38pt height baseline and 28pt compact action pills.
* **Responsive Toolbars & Layout Protection:** Dynamic `ViewThatFits` adaptations with minimum $1320\times 720$ window constraints to fit 13" Intel and Apple Silicon MacBooks seamlessly.

### Interactive Trim & Cut Audio Studio
* **Native CoreAudio DSP Waveform Engine:** Precision audio editing with gapless looping and non-destructive preview auditioning.
* **Stereo Channel Routing:** Invert Left/Right stereo channels, downmix to Mono, isolate single channels, or invert phase 180°.
* **Smooth Envelopes & Gain Trim:** Configurable fade-in/fade-out curves and -12dB to +12dB gain adjustment with strict ID3v2.3/Vorbis preservation.

### Partition-Isolated Duplicate Music Detection (Duplicates Studio)
* **Strict Same-Storage Scoping:** Partition-isolated duplicate comparison strictly within the same storage partition (Internal Flash, MicroSD, or Local Library).
* **Smart Quality Auto-Resolution:** Automatically preserves higher-resolution lossless files (e.g. 24-bit Hi-Res FLAC) over lossy copies while purging AppleDouble `._*` shadow files.

### Android Walkman Ecosystem Support
* **Full Modern Android DAP Detection:** Auto-detects Android-based Walkmans (NW-A100, NW-A300, NW-ZX500, NW-ZX700, NW-WM1AM2/ZM2).
* **Dynamic Artwork & Tag Adaptation:** Formats tags for Sony W.Music and eliminates Android MediaStore 0:00 ghost tracks.

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-3.0.1-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-3.0.1-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-3.0.1-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 13.0+) |

### Alternative Mirror
* **Google Drive:** [Download v3.0.1 Release Files on Google Drive](https://drive.google.com/drive/folders/1kb0z4Doik4ETlugIEnmDuMV1ZSYat-df?usp=share_link)

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v3.0.1</h1>

<p>Walkman Studio v3.0.1 delivers critical resilience fixes and model identification accuracy improvements for Sony Walkman users alongside the complete Optical Liquid Glass Design System, CoreAudio Trim &amp; Cut Studio, and Duplicates Studio across Apple Silicon (<code>arm64</code>) and Intel-based Macs (<code>x86_64</code>).</p>

<hr>

<h2>What's New in v3.0.1</h2>

<h3>Standalone MicroSD Card Model Accuracy Fix</h3>
<ul>
  <li><strong>Decoupled MicroSD Capacity Heuristics:</strong> Resolved an issue where standalone MicroSD cards (e.g. 256GB / 237GB) caused Walkman Studio to misidentify an authentic <code>NW-A55</code> as an <code>NW-A57</code> when internal storage was unmounted or ejected.</li>
  <li><strong>Session &amp; Persistent Device Memory:</strong> Walkman Studio now securely caches authentically identified device models in memory and macOS preferences across volume unmounts, restarts, and ejects.</li>
  <li><strong>Strict Heuristic Upper Bounds:</strong> Applied hardware capacity safety bounds across all series (<code>A50</code>, <code>A40</code>, <code>A30</code>, <code>A100</code>, <code>A300</code>, <code>ZX300</code>, <code>ZX500</code>, <code>ZX700</code>, <code>WM1</code>) so SD expansion storage never forces higher internal tiers.</li>
</ul>

<h3>Local Music Library Resilience &amp; Missing Folder Auto-Resolution</h3>
<ul>
  <li><strong>Real-Time Missing &amp; Renamed Folder Detection:</strong> Monitored folders moved, renamed, or deleted in Finder are instantly detected instead of silently failing or leaving stale ghost tracks.</li>
  <li><strong>Liquid Glass Amber Warning Banner:</strong> Surfaces an ambient amber alert with one-click actions:
    <ul>
      <li><strong>&ldquo;Relocate Folder...&rdquo;:</strong> Re-links moved or renamed folders in Finder, instantly updating all track paths, relative indices, album art, and 12-Tone SensMe mood channels without re-scanning or re-importing.</li>
      <li><strong>&ldquo;Remove Missing&rdquo;:</strong> Safely purges missing folders and orphaned ghost tracks from the SQLite library database with a single click.</li>
    </ul>
  </li>
  <li><strong>Missing Audio File Playback Guard:</strong> Double-clicking or attempting to preview an audio file that was moved or deleted on disk now displays a clear <em>&ldquo;Audio File Not Found&rdquo;</em> alert with the missing path and a direct relocation shortcut.</li>
  <li><strong>Manage Folders Enhancements:</strong> <code>ManageLocalFoldersSheet</code> displays <code>MISSING OR RENAMED</code> status badges and dedicated <strong>&ldquo;Relocate...&rdquo;</strong> picker buttons.</li>
</ul>

<h3>Safe Eject Deadlock &amp; Ejection Hang Fix</h3>
<ul>
  <li><strong>Dynamic Binary Discovery:</strong> Dynamically locates <code>dot_clean</code> across <code>/usr/sbin</code> and <code>/usr/bin</code>, eliminating launch errors on modern macOS releases.</li>
  <li><strong>10-Second Watchdog Timeout:</strong> Safe Eject is guarded with timeout watchdogs to prevent Foundation deadlocks when unmounting sluggish FAT32/exFAT drives.</li>
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
      <td><strong><code>Walkman-Studio-3.0.1-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.0.1-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.0.1-universal.dmg</code></strong></td>
      <td>Universal 2 (<code>arm64</code> + <code>x86_64</code>)</td>
      <td>Universal package running natively on all Macs (macOS 13.0+)</td>
    </tr>
  </tbody>
</table>

<h3>Alternative Mirror</h3>
<p><strong>Google Drive:</strong> <a href="https://drive.google.com/drive/folders/1kb0z4Doik4ETlugIEnmDuMV1ZSYat-df?usp=share_link" target="_blank" rel="noopener noreferrer">Download v3.0.1 Release Files on Google Drive</a></p>

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
