#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="3.1.2"
BUILD_NUM="312"
export WALKMAN_VERSION="$VERSION"
export WALKMAN_BUILD_NUM="$BUILD_NUM"
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
    echo "Packaging $DMG_NAME with custom background artwork and layout..."
    if command -v dmgbuild &>/dev/null; then
        dmgbuild -s "$DIR/scripts/dmg_settings.py" -D app_path="$APP_BUNDLE" -D project_dir="$DIR" "Walkman Studio" "$DIST_DIR/$DMG_NAME"
    elif python3 -m dmgbuild --help &>/dev/null; then
        python3 -m dmgbuild -s "$DIR/scripts/dmg_settings.py" -D app_path="$APP_BUNDLE" -D project_dir="$DIR" "Walkman Studio" "$DIST_DIR/$DMG_NAME"
    elif [ -x "$HOME/Library/Python/3.9/bin/dmgbuild" ]; then
        "$HOME/Library/Python/3.9/bin/dmgbuild" -s "$DIR/scripts/dmg_settings.py" -D app_path="$APP_BUNDLE" -D project_dir="$DIR" "Walkman Studio" "$DIST_DIR/$DMG_NAME"
    else
        echo "Warning: dmgbuild not found, creating fallback DMG with hdiutil..."
        local DMG_TEMP_DIR="$(mktemp -d /tmp/walkman-dmg-XXXXXX)"
        cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"
        ln -s /Applications "$DMG_TEMP_DIR/Applications"
        hdiutil create -volname "Walkman Studio" -srcfolder "$DMG_TEMP_DIR" -ov -format UDZO "$DIST_DIR/$DMG_NAME"
        rm -rf "$DMG_TEMP_DIR"
    fi
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
# Walkman Studio v3.1.2

Walkman Studio v3.1.2 brings resizable side panels, enhanced metadata workflows, state preservation across navigation views, and UI responsiveness optimizations across Apple Silicon (`arm64`) and Intel-based Macs (`x86_64`).

---

## What's New in v3.1.2

### Artists Tab: Tactile Resizable Master Panel & Stutter-Free Resizing
* **Adjustable Splitter with Min/Max Bounds:** Added a smooth, interactive resize divider between the left artist master list and right discography console with bounded limits (`160pt` – `400pt`) and persistent width storage. Double-click the splitter to instantly snap back to the default width (`205pt`).
* **Zero-Stutter 60/120 FPS Resizing:** Eliminated drag lag and frame drops by decoupling `@AppStorage` disk synchronization to drag completion, suppressing implicit animation transactions during continuous drag, removing redundant layout passes, and isolating detail width tier transitions.

### Album Metadata Editor: Batch Lyrics & SenseMe Acoustic Analysis
* **Integrated Lyrics Fetching:** Easily fetch synchronized lyrics (`.lrc`) for either all tracks or specifically selected tracks in an album directly from within the Album Metadata Editor.
* **Refined, Intuitive UI:** Polished lyrics fetching interface with direct row-level status indicators and selection actions.
* **SenseMe Acoustic Analysis Reliability:** Fixed SenseMe analysis pipeline inside the Album Metadata Editor to correctly compute 12-Tone channels and energy ratings across album tracks.

### Albums Tab Navigation & App Start State
* **Exact Scroll Position Retention:** Returning from an album detail view back to the *Albums* grid now accurately retains your previous scroll position instead of jumping back to the top.
* **Default Inspector Panel State:** The track details inspector panel now defaults to closed on initial launch, providing a full-width library view.

### In-App Updater in About Walkman Studio
* **One-Click In-App Updates:** Added an interactive **Updates** tab in *About Walkman Studio* that queries the latest GitHub Releases and Google Drive mirrors directly within the app.
* **Architecture-Aware Downloads & Staging:** Automatically matches your Mac's running architecture (Apple Silicon `arm64`, Intel `x86_64`, or Universal 2), downloads the update with live progress indicators, verifies bundle signatures, and smoothly installs and relaunches with a single click.
* **Update Notification Badges:** Displays a non-intrusive status pill in the toolbar and sidebar when a new release is available, linking directly to the update screen.

---

## Downloads

| Installer | Architecture | Target System |
| :--- | :--- | :--- |
| **`Walkman-Studio-3.1.2-arm64.dmg`** | Apple Silicon (`arm64`) | MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4) |
| **`Walkman-Studio-3.1.2-intel.dmg`** | Intel (`x86_64`) | Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro |
| **`Walkman-Studio-3.1.2-universal.dmg`** | Universal 2 (`arm64` + `x86_64`) | Universal package running natively on all Macs (macOS 13.0+) |

### Alternative Mirror
* **Google Drive:** [Download v3.1.2 Release Files on Google Drive](https://drive.google.com/drive/folders/1K_lnoAEbpX_2zY9xL1PG3zv0KOFlonR-?usp=share_link)

---

## Installation

1. Download the `.dmg` corresponding to your Mac architecture above.
2. Open the disk image and drag **Walkman Studio** into your **Applications** folder.
3. Connect your Sony Walkman in USB Mass Storage mode and launch Walkman Studio.
EOF

cat << 'EOF' > "$DIST_DIR/RELEASE_NOTES.html"
<h1>Walkman Studio v3.1.2</h1>

<p>Walkman Studio v3.1.2 brings resizable side panels, enhanced metadata workflows, state preservation across navigation views, and UI responsiveness optimizations across Apple Silicon (<code>arm64</code>) and Intel-based Macs (<code>x86_64</code>).</p>

<hr>

<h2>What's New in v3.1.2</h2>

<h3>Artists Tab: Tactile Resizable Master Panel &amp; Stutter-Free Resizing</h3>
<ul>
  <li><strong>Adjustable Splitter with Min/Max Bounds:</strong> Added a smooth, interactive resize divider between the left artist master list and right discography console with bounded limits (<code>160pt</code> &ndash; <code>400pt</code>) and persistent width storage. Double-click the splitter to instantly snap back to the default width (<code>205pt</code>).</li>
  <li><strong>Zero-Stutter 60/120 FPS Resizing:</strong> Eliminated drag lag and frame drops by decoupling <code>@AppStorage</code> disk synchronization to drag completion, suppressing implicit animation transactions during continuous drag, removing redundant layout passes, and isolating detail width tier transitions.</li>
</ul>

<h3>Album Metadata Editor: Batch Lyrics &amp; SenseMe Acoustic Analysis</h3>
<ul>
  <li><strong>Integrated Lyrics Fetching:</strong> Easily fetch synchronized lyrics (<code>.lrc</code>) for either all tracks or specifically selected tracks in an album directly from within the Album Metadata Editor.</li>
  <li><strong>Refined, Intuitive UI:</strong> Polished lyrics fetching interface with direct row-level status indicators and selection actions.</li>
  <li><strong>SenseMe Acoustic Analysis Reliability:</strong> Fixed SenseMe analysis pipeline inside the Album Metadata Editor to correctly compute 12-Tone channels and energy ratings across album tracks.</li>
</ul>

<h3>Albums Tab Navigation &amp; App Start State</h3>
<ul>
  <li><strong>Exact Scroll Position Retention:</strong> Returning from an album detail view back to the <em>Albums</em> grid now accurately retains your previous scroll position instead of jumping back to the top.</li>
  <li><strong>Default Inspector Panel State:</strong> The track details inspector panel now defaults to closed on initial launch, providing a full-width library view.</li>
</ul>

<h3>In-App Updater in About Walkman Studio</h3>
<ul>
  <li><strong>One-Click In-App Updates:</strong> Added an interactive <strong>Updates</strong> tab in <em>About Walkman Studio</em> that queries the latest GitHub Releases and Google Drive mirrors directly within the app.</li>
  <li><strong>Architecture-Aware Downloads &amp; Staging:</strong> Automatically matches your Mac's running architecture (Apple Silicon <code>arm64</code>, Intel <code>x86_64</code>, or Universal 2), downloads the update with live progress indicators, verifies bundle signatures, and smoothly installs and relaunches with a single click.</li>
  <li><strong>Update Notification Badges:</strong> Displays a non-intrusive status pill in the toolbar and sidebar when a new release is available, linking directly to the update screen.</li>
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
      <td><strong><code>Walkman-Studio-3.1.2-arm64.dmg</code></strong></td>
      <td>Apple Silicon (<code>arm64</code>)</td>
      <td>MacBook Air, MacBook Pro, Mac mini, Mac Studio, iMac (M1, M2, M3, M4)</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.1.2-intel.dmg</code></strong></td>
      <td>Intel (<code>x86_64</code>)</td>
      <td>Intel-based MacBook, MacBook Pro, MacBook Air, iMac, Mac Pro</td>
    </tr>
    <tr>
      <td><strong><code>Walkman-Studio-3.1.2-universal.dmg</code></strong></td>
      <td>Universal 2 (<code>arm64</code> + <code>x86_64</code>)</td>
      <td>Universal package running natively on all Macs (macOS 13.0+)</td>
    </tr>
  </tbody>
</table>

<h3>Alternative Mirror</h3>
<p><strong>Google Drive:</strong> <a href="https://drive.google.com/drive/folders/1K_lnoAEbpX_2zY9xL1PG3zv0KOFlonR-?usp=share_link" target="_blank" rel="noopener noreferrer">Download v3.1.2 Release Files on Google Drive</a></p>

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
