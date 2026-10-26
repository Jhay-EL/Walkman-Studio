#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="2.1.0"
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
# Walkman Studio v2.1.0

Walkman Studio v2.1.0 is a major milestone release introducing **Multi-Device & Dual-Storage Architecture**, a redesigned **Track Details Inspector with Device Lyrics Viewer**, the **Interactive Trim & Cut Audio Studio**, **Cross-Drive Duplicate Music Detection**, and the **Walkman Backup & Restore Studio**, alongside native compilation for both **Apple Silicon (`arm64`)** and **Intel-based Macs (`x86_64`)**.

---

## What's New in v2.1.0

### 📱 Multi-Device & Dual-Storage Architecture
* **Simultaneous Multi-Walkman Connection:** Plug in and manage multiple physical Sony Walkman players at the same time (e.g. NW-A55, NW-ZX300, NW-WM1A).
* **Dynamic Sidebar Hierarchy & Model Icons:** Automatically discovers and categorizes each connected device with authentic hardware artwork and paired Internal Flash and MicroSD expansion drives.
* **Instant Device Switching:** Easily switch active devices in both the sidebar and Device Overview header with isolated library browsing, transfer queues, and duplicate management.

### 🔍 Redesigned View-Only Track Details Inspector & Lyrics Viewer
* **View-Only Inspection:** Streamlined the right sidebar for safe, non-destructive track inspection. Modifying inputs are redirected to the dedicated Song Metadata Editor modal.
* **Anti-Clipping 2x2 Quick Stats Grid:** Redesigned Duration, Quality, Bitrate, and File Size tiles into a balanced 2x2 grid, eliminating text truncation and awkward label wrapping (`DURATI`/`ON`) on narrow sidebar widths.
* **Multi-Source Device Lyrics Viewer:** Automatically detects and displays lyrics stored on your Walkman:
  * Companion `.lrc` and `.txt` files with auto-decoding (UTF-8, Windows-1252, ISO-8859-1, UTF-16).
  * Embedded FLAC Vorbis comments (`LYRICS`, `UNSYNCEDLYRICS`, `SYNCEDLYRICS`).
  * Embedded MP4 / M4A / ALAC `©lyr` atoms.
  * Embedded MP3 ID3v2 `USLT`, `SYLT`, and `ULT` frames.
* **Synchronized Lyrics Card:** Displays timestamp badges and clean line-by-line typography for `.LRC` files.
* **Technical Audio Specs & Path Copy:** View container tag standard (`ID3v2.3 (UTF-16)`, `Vorbis Comments`), baseline artwork compliance, and copy POSIX file paths in one click.

### ✂️ Interactive Trim & Cut Audio Studio
* **Waveform Audio Studio:** Right-click any track in any view and choose **"Trim & Cut..."** to launch the popup waveform editor.
* **Trim (Keep Selection) & Cut (Remove Selection):** Keep the selected region or cleanly remove unwanted sections with gapless preview auditioning.
* **Millisecond Steppers & Boundary Controls:** Fine-tune start and end markers (`±0.1s`, `±1s`, `±5s`) or lock to the current playhead.
* **Audio Channel Routing & Inversion:** Invert Left/Right channels, downmix to Mono, force 2-channel Stereo, isolate channels, or invert phase 180°.
* **Smooth Fades & Gain Adjustment:** Configurable fade-in/fade-out curves and -6dB to +6dB gain adjustment while preserving ID3v2.3/Vorbis tags and Baseline JPEG artwork.

### 🔎 Cross-Drive Duplicate Music Detection Engine
* **Cross-Storage Inspection:** Simultaneously scans `/Volumes/WALKMAN` (internal flash) and `/Volumes/SD_CARD` (microSD card) to find duplicates across partitions as well as on the same drive.
* **Intelligent Matching & Recoverable Space:** Normalizes titles and artist names combined with $\pm 4.0$s duration clustering, displaying total recoverable gigabytes.
* **Smart Resolution:** One-click "Keep Best Quality" (preserves 24-bit Hi-Res FLAC over MP3) and "Keep on SD Card" (saves precious internal flash memory). Includes built-in audition player and Finder reveal.

### 💾 Walkman Backup & Restore Studio
* **Local & External Destinations:** Back up directly to Local Mac Storage (`~/Music/Walkman Studio Backups`), connected external USB/SD drives, or custom folders without cloud dependency.
* **5 Flexible Scopes:** Full Library, Playlists Scope, Language Study (`/LEARNING`), Selected Albums, or Selected Tracks.
* **Slow High-Security Cryptographic Encryption:** Optional PBKDF2-HMAC-SHA256 (100,000 rounds) key derivation and AES-256-GCM authenticated encryption for tamper-proof privacy.
* **Safe Walkman Restoration:** Restores backups into any connected Walkman partition with capacity verification, directory reconstruction, and automatic `dot_clean -m` cleanup.

### 🖥️ Native Intel-based MacBook & Mac Support
* **Multi-Architecture Support:** Runs natively on both **Intel-based Macs (Core i5, i7, i9, Xeon)** and **Apple Silicon Macs (M1, M2, M3, M4)**.
* **Dedicated & Universal DMGs:** Available as standalone `.dmg` packages for Apple Silicon (`arm64`), Intel (`intel`), and Universal 2 (`universal`).

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-2.1.0-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-2.1.0-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-2.1.0-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 14.0+) |

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v2.1.0</h1>

<p>Walkman Studio v2.1.0 is a major milestone release introducing <strong>Multi-Device &amp; Dual-Storage Architecture</strong>, a redesigned <strong>Track Details Inspector with Device Lyrics Viewer</strong>, the <strong>Interactive Trim &amp; Cut Audio Studio</strong>, <strong>Cross-Drive Duplicate Music Detection</strong>, and the <strong>Walkman Backup &amp; Restore Studio</strong>, alongside native compilation for both <strong>Apple Silicon (<code>arm64</code>)</strong> and <strong>Intel-based Macs (<code>x86_64</code>)</strong>.</p>

<hr>

<h2>What's New in v2.1.0</h2>

<h3>📱 Multi-Device &amp; Dual-Storage Architecture</h3>
<ul>
  <li><strong>Simultaneous Multi-Walkman Connection:</strong> Plug in and manage multiple physical Sony Walkman players at the same time (e.g. NW-A55, NW-ZX300, NW-WM1A).</li>
  <li><strong>Dynamic Sidebar Hierarchy &amp; Model Icons:</strong> Automatically discovers and categorizes each connected device with authentic hardware artwork and paired Internal Flash and MicroSD expansion drives.</li>
  <li><strong>Instant Device Switching:</strong> Easily switch active devices in both the sidebar and Device Overview header with isolated library browsing, transfer queues, and duplicate management.</li>
</ul>

<h3>🔍 Redesigned View-Only Track Details Inspector &amp; Lyrics Viewer</h3>
<ul>
  <li><strong>View-Only Inspection:</strong> Streamlined the right sidebar for safe, non-destructive track inspection. Modifying inputs are redirected to the dedicated Song Metadata Editor modal.</li>
  <li><strong>Anti-Clipping 2x2 Quick Stats Grid:</strong> Redesigned Duration, Quality, Bitrate, and File Size tiles into a balanced 2x2 grid, eliminating text truncation and awkward label wrapping on narrow sidebar widths.</li>
  <li><strong>Multi-Source Device Lyrics Viewer:</strong> Automatically detects and displays lyrics stored on your Walkman across companion <code>.lrc</code>/<code>.txt</code> files, Vorbis comments, MP4 atoms, and ID3 frames.</li>
  <li><strong>Synchronized Lyrics Card:</strong> Displays timestamp badges and clean line-by-line typography for <code>.LRC</code> files.</li>
  <li><strong>Technical Audio Specs &amp; Path Copy:</strong> View container tag standard, baseline artwork compliance, and copy POSIX file paths in one click.</li>
</ul>

<h3>✂️ Interactive Trim &amp; Cut Audio Studio</h3>
<ul>
  <li><strong>Waveform Audio Studio:</strong> Right-click any track in any view and choose <strong>"Trim &amp; Cut..."</strong> to launch the popup waveform editor.</li>
  <li><strong>Trim (Keep Selection) &amp; Cut (Remove Selection):</strong> Keep the selected region or cleanly remove unwanted sections with gapless preview auditioning.</li>
  <li><strong>Millisecond Steppers &amp; Boundary Controls:</strong> Fine-tune start and end markers (<code>±0.1s</code>, <code>±1s</code>, <code>±5s</code>) or lock to the current playhead.</li>
  <li><strong>Audio Channel Routing &amp; Inversion:</strong> Invert Left/Right channels, downmix to Mono, force 2-channel Stereo, isolate channels, or invert phase 180&deg;.</li>
  <li><strong>Smooth Fades &amp; Gain Adjustment:</strong> Configurable fade-in/fade-out curves and -6dB to +6dB gain adjustment while preserving tags and artwork.</li>
</ul>

<h3>🔎 Cross-Drive Duplicate Music Detection Engine</h3>
<ul>
  <li><strong>Cross-Storage Inspection:</strong> Simultaneously scans internal flash and microSD cards to find duplicates across partitions as well as on the same drive.</li>
  <li><strong>Intelligent Matching &amp; Recoverable Space:</strong> Normalizes titles and artist names combined with duration clustering, displaying total recoverable gigabytes.</li>
  <li><strong>Smart Resolution:</strong> One-click "Keep Best Quality" and "Keep on SD Card" resolution with built-in audition player.</li>
</ul>

<h3>💾 Walkman Backup &amp; Restore Studio</h3>
<ul>
  <li><strong>Local &amp; External Destinations:</strong> Back up directly to Local Mac Storage, connected external USB/SD drives, or custom folders.</li>
  <li><strong>5 Flexible Scopes:</strong> Full Library, Playlists Scope, Language Study, Selected Albums, or Selected Tracks.</li>
  <li><strong>Slow High-Security Cryptographic Encryption:</strong> Optional PBKDF2-HMAC-SHA256 (100,000 rounds) key derivation and AES-256-GCM authenticated encryption.</li>
  <li><strong>Safe Walkman Restoration:</strong> Restores backups into any connected Walkman partition with capacity verification and <code>dot_clean -m</code> cleanup.</li>
</ul>

<h3>🖥️ Native Intel-based MacBook &amp; Mac Support</h3>
<ul>
  <li><strong>Multi-Architecture Support:</strong> Runs natively on both <strong>Intel-based Macs (Core i5, i7, i9, Xeon)</strong> and <strong>Apple Silicon Macs (M1, M2, M3, M4)</strong>.</li>
  <li><strong>Dedicated &amp; Universal DMGs:</strong> Available as standalone <code>.dmg</code> packages for Apple Silicon (<code>arm64</code>), Intel (<code>intel</code>), and Universal 2 (<code>universal</code>).</li>
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
      <td><strong><code>Walkman-Studio-2.1.0-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-2.1.0-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-2.1.0-universal.dmg</code></strong></td>
      <td>Universal 2 (<code>arm64</code> + <code>x86_64</code>)</td>
      <td>Universal package running natively on all Macs (macOS 13.0+)</td>
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
