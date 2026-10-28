#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="2.1.1"
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
# Walkman Studio v2.1.1

Walkman Studio v2.1.1 resolves reported playback, metadata, and synchronization issues for Sony Walkman DAPs, introducing pure Swift SensMe 12-Tone acoustic analysis, automated companion `.lrc` timestamp synthesis, and conversion preset hardening across both Apple Silicon (`arm64`) and Intel-based Macs (`x86_64`).

---

## What's New in v2.1.1

### Walkman Companion Lyrics Display Fix
* **Automated Chronological Timestamping:** Plain-text and unsynced lyrics are now synthesized with sequential `[mm:ss.xx]` timestamps, enabling the Walkman firmware "Lyrics" display button instead of leaving it greyed out.
* **Universal Audio Format Support:** Companion `.lrc` files are generated for all supported audio formats (`FLAC`, `MP3`, `M4A`, `AAC`, `ALAC`, `WAV`, `AIFF`, `DSD`).
* **DOS CRLF Line Endings:** Enforced strict `\r\n` line endings and stripped macOS metadata shadow files (`._*`) and `com.apple.TextEncoding` extended attributes for clean Walkman FAT32/exFAT indexing.
* **Embedded Lyrics Tagging:** Preserved and written into MP3 (`USLT` UTF-16 with BOM), FLAC (Vorbis `LYRICS`), and M4A (`lyrics` atom).

### Native SensMe 12-Tone Analysis (No External Engine Required)
* **Pure Swift Acoustic Fallback:** Constructs Sony-compliant 3,270-byte `SMFM` payloads natively without needing external Python, NumPy, or SciPy installations.
* **Direct Hardware Tag Injection:** Injects SensMe 12-Tone metadata blocks directly into MP3 ID3v2.3 `GEOB` & `PRIV` frames and FLAC `APPLICATION` block type 2.

### Playlist & Metadata Fixes
* **Playlist Addition Fix:** Resolved an issue where adding music tracks to playlists did not persist properly to the connected Walkman storage.
* **Explicit Tag Sanitation:** Fixed title parsing bug where tracks with explicit markers or bracketed suffixes were incorrectly renamed to "Unknown".
* **Preset Hardening:** Constrained the `alac_16` preset strictly to 16-bit PCM frames (`-sample_fmt s16p`).
* **UI Modularity & Stability:** Modularized queue sheets from `TransferQueueView` to improve SwiftUI rendering performance and responsiveness.

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-2.1.1-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-2.1.1-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-2.1.1-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 13.0+) |

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v2.1.1</h1>

<p>Walkman Studio v2.1.1 resolves reported playback, metadata, and synchronization issues for Sony Walkman DAPs, introducing pure Swift SensMe 12-Tone acoustic analysis, automated companion <code>.lrc</code> timestamp synthesis, and conversion preset hardening across both Apple Silicon (<code>arm64</code>) and Intel-based Macs (<code>x86_64</code>).</p>

<hr>

<h2>What's New in v2.1.1</h2>

<h3>Walkman Companion Lyrics Display Fix</h3>
<ul>
  <li><strong>Automated Chronological Timestamping:</strong> Plain-text and unsynced lyrics are now synthesized with sequential <code>[mm:ss.xx]</code> timestamps, enabling the Walkman firmware "Lyrics" display button instead of leaving it greyed out.</li>
  <li><strong>Universal Audio Format Support:</strong> Companion <code>.lrc</code> files are generated for all supported audio formats (<code>FLAC</code>, <code>MP3</code>, <code>M4A</code>, <code>AAC</code>, <code>ALAC</code>, <code>WAV</code>, <code>AIFF</code>, <code>DSD</code>).</li>
  <li><strong>DOS CRLF Line Endings:</strong> Enforced strict <code>\r\n</code> line endings and stripped macOS metadata shadow files (<code>._*</code>) and <code>com.apple.TextEncoding</code> extended attributes for clean Walkman FAT32/exFAT indexing.</li>
  <li><strong>Embedded Lyrics Tagging:</strong> Preserved and written into MP3 (<code>USLT</code> UTF-16 with BOM), FLAC (Vorbis <code>LYRICS</code>), and M4A (<code>lyrics</code> atom).</li>
</ul>

<h3>Native SensMe 12-Tone Analysis (No External Engine Required)</h3>
<ul>
  <li><strong>Pure Swift Acoustic Fallback:</strong> Constructs Sony-compliant 3,270-byte <code>SMFM</code> payloads natively without needing external Python, NumPy, or SciPy installations.</li>
  <li><strong>Direct Hardware Tag Injection:</strong> Injects SensMe 12-Tone metadata blocks directly into MP3 ID3v2.3 <code>GEOB</code> &amp; <code>PRIV</code> frames and FLAC <code>APPLICATION</code> block type 2.</li>
</ul>

<h3>Playlist &amp; Metadata Fixes</h3>
<ul>
  <li><strong>Playlist Addition Fix:</strong> Resolved an issue where adding music tracks to playlists did not persist properly to the connected Walkman storage.</li>
  <li><strong>Explicit Tag Sanitation:</strong> Fixed title parsing bug where tracks with explicit markers or bracketed suffixes were incorrectly renamed to "Unknown".</li>
  <li><strong>Preset Hardening:</strong> Constrained the <code>alac_16</code> preset strictly to 16-bit PCM frames (<code>-sample_fmt s16p</code>).</li>
  <li><strong>UI Modularity &amp; Stability:</strong> Modularized queue sheets from <code>TransferQueueView</code> to improve SwiftUI rendering performance and responsiveness.</li>
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
      <td><strong><code>Walkman-Studio-2.1.1-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-2.1.1-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-2.1.1-universal.dmg</code></strong></td>
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
