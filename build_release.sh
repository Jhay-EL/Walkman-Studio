#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="3.0.0"
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
# Walkman Studio v3.0.0

Walkman Studio v3.0.0 is a major milestone release introducing the complete Optical Liquid Glass Design System, the CoreAudio-powered Trim & Cut Audio Studio, partition-isolated same-storage duplicate music deduplication, rapid sequential metadata navigation, and resilient transfer queue architecture across both Apple Silicon (`arm64`) and Intel-based Macs (`x86_64`).

---

## What's New in v3.0.0

### Optical Liquid Glass Design System Language
* **Sony Signature Series Obsidian Chassis:** Complete UI visual overhaul embracing solid obsidian surfaces (`#101114`), refraction glass lenses, specular edge highlights, and tactile spring physics (`.spring(response: 0.38, dampingFraction: 0.75)`).
* **Standardized 38pt Baseline Height:** All primary interactive controls, search bars, sort menus, and action buttons now share a uniform 38pt height baseline.
* **Standardized 28pt Capsule Pills:** Compact in-row actions and status indicators are consistently sized with tactile feedback and 0.8pt hairline borders.
* **Responsive Toolbars & Layout Protection:** Responsive layout adaptation using `ViewThatFits` with zero element clipping or wrapping, backed by an enforced $1366\times 768$ minimum window dimension constraint.

### Interactive Trim & Cut Audio Studio
* **Native CoreAudio DSP Waveform Engine:** Built-in precision audio editor supporting non-destructive preview auditioning and gapless looping across local and Walkman tracks.
* **Multi-Zoom Waveform Canvas:** Zoom scale from `1x` to `20x` with millisecond-precision boundary steppers (`±0.1s`, `±1s`, `±5s`) and playhead snapping.
* **Stereo Channel Routing & Phase Inversion:** Invert Left/Right stereo channels, downmix to Mono, isolate single channel to dual ears, or invert audio phase 180°.
* **Smooth Envelopes & Gain Trim:** Configurable fade-in and fade-out curves to prevent clicks, with -6dB to +6dB gain adjustment while strictly preserving ID3v2.3/Vorbis metadata and Baseline RGB JPEG cover art.

### Partition-Isolated Duplicate Music Detection (Duplicates Studio)
* **Strict Same-Storage Scoping:** Prevents accidental deletion of tracks across distinct drives by scoping duplicate comparisons strictly within the same storage partition (Internal Flash, MicroSD Expansion, or Local Library).
* **Dual Matching Scopes:**
  * **Exact Same Album (Safe):** Matches identical audio files and duplicate tracks within the same album without breaking complete releases.
  * **Include Cross-Album (Loose):** Identifies duplicate songs across Studio Albums, Singles, Greatest Hits, and Compilations.
* **High-Precision Acoustic & Metadata Clustering:** Matches tracks via normalized titles/artists and $\pm 4.0$s duration clustering, ISRC identifiers, and bit-exact MD5 checksums.
* **Smart Quality Auto-Resolution:** Automatically preserves higher-resolution lossless files (e.g. 24-bit Hi-Res FLAC) over lossy copies while safely cleaning orphan companion `.lrc` lyrics and AppleDouble `._*` shadow files.

### Rapid Sequential Metadata & Playlist Navigation
* **Previous & Next Track Steppers:** Edit metadata for an entire album or playlist continuously with previous/next navigation buttons embedded directly within the Song Metadata Editor without closing the sheet.
* **Smart Scoped Track Sequencing:** Navigation strictly respects the active album or playlist ordering.
* **Overhauled Playlists Modal (`AddTracksModal`):** Modernized playlist track selection dialog with 28pt action pills, "In Playlist" status indicators, and 38pt Liquid Glass chassis actions.

### Transfer & Convert Queue Optimization
* **Dedicated Hardware Compliance Bar:** Dedicated 6-chip compliance bar (`Baseline RGB Art`, `.LRC Lyrics`, `Auto-Tags`, `folder.jpg`, `EBU R128 Leveling`, `12 Tone / SenseMe`).
* **Optimized Queue Header:** Relocated batch operations (`✦ Optimize All`, `💬 Fetch Lyrics`, `🗑 Clear`) into a responsive header bar with zero visual overlap.
* **Hardware Compliance Enforcement:** Enforces strict ID3v2.3 UTF-16, Baseline JPEG ($\le 800\times 800$), and FLAC `SMFM` Block 2 hardware compliance.

### Android Walkman Ecosystem Support
* **Full Modern Android DAP Detection:** Auto-detects and configures Android-based Walkmans including NW-A100 series (A105), NW-A300 series (A306/A307), NW-ZX500 series (ZX507), NW-ZX700 series (ZX707), and Signature Series NW-WM1AM2 and NW-WM1ZM2.
* **Dynamic Android Hardware Compliance:** Dynamically adapts artwork constraints (up to 1280×720 RGB), formats ID3v2.3 tags for Sony W.Music, and purges AppleDouble `._*` files to eliminate Android MediaStore 0:00 ghost tracks.

### Playlist Batch Reorganization & "Move to Top"
* **Multi-Track Selection:** Dedicated selection checkmarks with Shift-click range selection, Command-click toggle, and "Select All" header button.
* **Liquid Glass Batch Action Bar:** Floating action bar providing one-click "Move to Top" batch reorganization, group Up/Down shifting, "To Bottom", and batch removal with instant Walkman M3U/M3U8 file synchronization.

### Single-Pass Accelerated Music Import
* **Zero Redundant Scanning:** Single-pass concurrent metadata analysis eliminates the 2x wait time on multi-track imports with detected duplicates.
* **Streamlined Transfer Experience:** Immediate 1-click transfer start with real-time transfer progress feedback.

### Performance & Engine Upgrades
* **Non-Blocking Asynchronous Imports:** Background folder import engine with real-time `ImportProgressBar` and cancellation support.
* **macOS Dotfile Purging:** Automatic `dot_clean -m` AppleDouble shadow file cleanup on drive unmount.
* **Universal macOS Support:** Native binaries for Apple Silicon (`arm64`) and Intel (`x86_64`) on macOS 13.0+ (Ventura, Sonoma, Sequoia).

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-3.0.0-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-3.0.0-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-3.0.0-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 13.0+) |

### Alternative Mirror
* **Google Drive:** [Download v3.0.0 Release Files on Google Drive](https://drive.google.com/drive/folders/1kb0z4Doik4ETlugIEnmDuMV1ZSYat-df?usp=share_link)

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v3.0.0</h1>

<p>Walkman Studio v3.0.0 is a major milestone release introducing the complete Optical Liquid Glass Design System, the CoreAudio-powered Trim &amp; Cut Audio Studio, partition-isolated same-storage duplicate music deduplication, rapid sequential metadata navigation, and resilient transfer queue architecture across both Apple Silicon (<code>arm64</code>) and Intel-based Macs (<code>x86_64</code>).</p>

<hr>

<h2>What's New in v3.0.0</h2>

<h3>Optical Liquid Glass Design System Language</h3>
<ul>
  <li><strong>Sony Signature Series Obsidian Chassis:</strong> Complete UI visual overhaul embracing solid obsidian surfaces (<code>#101114</code>), refraction glass lenses, specular edge highlights, and tactile spring physics.</li>
  <li><strong>Standardized 38pt Baseline Height:</strong> All primary interactive controls, search bars, sort menus, and action buttons now share a uniform 38pt height baseline.</li>
  <li><strong>Standardized 28pt Capsule Pills:</strong> Compact in-row actions and status indicators are consistently sized with tactile feedback and 0.8pt hairline borders.</li>
  <li><strong>Responsive Toolbars &amp; Layout Protection:</strong> Responsive layout adaptation using <code>ViewThatFits</code> with zero element clipping or wrapping, backed by an enforced 1366&times;768 minimum window dimension constraint.</li>
</ul>

<h3>Interactive Trim &amp; Cut Audio Studio</h3>
<ul>
  <li><strong>Native CoreAudio DSP Waveform Engine:</strong> Built-in precision audio editor supporting non-destructive preview auditioning and gapless looping across local and Walkman tracks.</li>
  <li><strong>Multi-Zoom Waveform Canvas:</strong> Zoom scale from <code>1x</code> to <code>20x</code> with millisecond-precision boundary steppers (<code>&plusmn;0.1s</code>, <code>&plusmn;1s</code>, <code>&plusmn;5s</code>) and playhead snapping.</li>
  <li><strong>Stereo Channel Routing &amp; Phase Inversion:</strong> Invert Left/Right stereo channels, downmix to Mono, isolate single channel to dual ears, or invert audio phase 180&deg;.</li>
  <li><strong>Smooth Envelopes &amp; Gain Trim:</strong> Configurable fade-in and fade-out curves to prevent clicks, with -6dB to +6dB gain adjustment while strictly preserving ID3v2.3/Vorbis metadata and Baseline RGB JPEG cover art.</li>
</ul>

<h3>Partition-Isolated Duplicate Music Detection (Duplicates Studio)</h3>
<ul>
  <li><strong>Strict Same-Storage Scoping:</strong> Prevents accidental deletion of tracks across distinct drives by scoping duplicate comparisons strictly within the same storage partition (Internal Flash, MicroSD Expansion, or Local Library).</li>
  <li><strong>Dual Matching Scopes:</strong> Exact Same Album (Safe) and Include Cross-Album (Loose) matching.</li>
  <li><strong>High-Precision Acoustic &amp; Metadata Clustering:</strong> Matches tracks via normalized titles/artists and &plusmn;4.0s duration clustering, ISRC identifiers, and bit-exact MD5 checksums.</li>
  <li><strong>Smart Quality Auto-Resolution:</strong> Automatically preserves higher-resolution lossless files (e.g. 24-bit Hi-Res FLAC) over lossy copies while safely cleaning orphan companion <code>.lrc</code> lyrics and AppleDouble <code>._*</code> shadow files.</li>
</ul>

<h3>Rapid Sequential Metadata &amp; Playlist Navigation</h3>
<ul>
  <li><strong>Previous &amp; Next Track Steppers:</strong> Edit metadata for an entire album or playlist continuously with previous/next navigation buttons embedded directly within the Song Metadata Editor without closing the sheet.</li>
  <li><strong>Smart Scoped Track Sequencing:</strong> Navigation strictly respects the active album or playlist ordering.</li>
  <li><strong>Overhauled Playlists Modal (<code>AddTracksModal</code>):</strong> Modernized playlist track selection dialog with 28pt action pills, "In Playlist" status indicators, and 38pt Liquid Glass chassis actions.</li>
</ul>

<h3>Transfer &amp; Convert Queue Optimization</h3>
<ul>
  <li><strong>Dedicated Hardware Compliance Bar:</strong> Dedicated 6-chip compliance bar (<code>Baseline RGB Art</code>, <code>.LRC Lyrics</code>, <code>Auto-Tags</code>, <code>folder.jpg</code>, <code>EBU R128 Leveling</code>, <code>12 Tone / SenseMe</code>).</li>
  <li><strong>Optimized Queue Header:</strong> Relocated batch operations (<code>✦ Optimize All</code>, <code>💬 Fetch Lyrics</code>, <code>🗑 Clear</code>) into a responsive header bar with zero visual overlap.</li>
  <li><strong>Hardware Compliance Enforcement:</strong> Enforces strict ID3v2.3 UTF-16, Baseline JPEG (&le; 800&times;800), and FLAC <code>SMFM</code> Block 2 hardware compliance.</li>
</ul>

<h3>Android Walkman Ecosystem Support</h3>
<ul>
  <li><strong>Full Modern Android DAP Detection:</strong> Auto-detects and configures Android-based Walkmans including NW-A100 series (A105), NW-A300 series (A306/A307), NW-ZX500 series (ZX507), NW-ZX700 series (ZX707), and Signature Series NW-WM1AM2 and NW-WM1ZM2.</li>
  <li><strong>Dynamic Android Hardware Compliance:</strong> Dynamically adapts artwork constraints (up to 1280&times;720 RGB), formats ID3v2.3 tags for Sony W.Music, and purges AppleDouble <code>._*</code> files to eliminate Android MediaStore 0:00 ghost tracks.</li>
</ul>

<h3>Playlist Batch Reorganization &amp; &ldquo;Move to Top&rdquo;</h3>
<ul>
  <li><strong>Multi-Track Selection:</strong> Dedicated selection checkmarks with Shift-click range selection, Command-click toggle, and &ldquo;Select All&rdquo; header button.</li>
  <li><strong>Liquid Glass Batch Action Bar:</strong> Floating action bar providing one-click &ldquo;Move to Top&rdquo; batch reorganization, group Up/Down shifting, &ldquo;To Bottom&rdquo;, and batch removal with instant Walkman M3U/M3U8 file synchronization.</li>
</ul>

<h3>Single-Pass Accelerated Music Import</h3>
<ul>
  <li><strong>Zero Redundant Scanning:</strong> Single-pass concurrent metadata analysis eliminates the 2x wait time on multi-track imports with detected duplicates.</li>
  <li><strong>Streamlined Transfer Experience:</strong> Immediate 1-click transfer start with real-time transfer progress feedback.</li>
</ul>

<h3>Performance &amp; Engine Upgrades</h3>
<ul>
  <li><strong>Non-Blocking Asynchronous Imports:</strong> Background folder import engine with real-time <code>ImportProgressBar</code> and cancellation support.</li>
  <li><strong>macOS Dotfile Purging:</strong> Automatic <code>dot_clean -m</code> AppleDouble shadow file cleanup on drive unmount.</li>
  <li><strong>Universal macOS Support:</strong> Native binaries for Apple Silicon (<code>arm64</code>) and Intel (<code>x86_64</code>) on macOS 13.0+ (Ventura, Sonoma, Sequoia).</li>
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
      <td><strong><code>Walkman-Studio-3.0.0-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.0.0-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.0.0-universal.dmg</code></strong></td>
      <td>Universal 2 (<code>arm64</code> + <code>x86_64</code>)</td>
      <td>Universal package running natively on all Macs (macOS 13.0+)</td>
    </tr>
  </tbody>
</table>

<h3>Alternative Mirror</h3>
<p><strong>Google Drive:</strong> <a href="https://drive.google.com/drive/folders/1kb0z4Doik4ETlugIEnmDuMV1ZSYat-df?usp=share_link" target="_blank" rel="noopener noreferrer">Download v3.0.0 Release Files on Google Drive</a></p>

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
