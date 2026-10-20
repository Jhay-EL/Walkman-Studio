<p align="center">
  <img src="assets/icon.png" width="160" height="160" alt="Walkman Studio Icon" style="border-radius: 36px; box-shadow: 0 10px 30px rgba(0,0,0,0.5);" />
</p>

# <p align="center">Walkman Studio</p>

<p align="center">
  <strong>Native macOS Manager for the Sony Walkman NW-A55L & A50 Series</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B%20(Apple%20Silicon)-black?style=for-the-badge&logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B%20%2F%20SwiftUI-orange?style=for-the-badge&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Hardware-Sony%20Walkman%20NW--A55%20%2F%20A55L-gold?style=for-the-badge&logo=sony" alt="Sony Walkman" />
  <img src="https://img.shields.io/badge/Design-Apple%20Liquid%20Glass%20(HIG)-blue?style=for-the-badge" alt="Apple HIG" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License" />
</p>

A first-class, 100% native macOS application engineered specifically for managing the **Sony Walkman NW-A55 / NW-A55L** (and NW-A50 series) on Apple Silicon Macs.

Designed according to Apple's **Human Interface Guidelines (HIG)** and the **Liquid Glass** aesthetic (`.ultraThinMaterial`), Walkman Studio bridges the gap between modern macOS and Sony's dedicated digital audio players—eliminating the need for Windows virtual machines, slow transfer utilities, or terminal scripts.

---

## The Problem Walkman Studio Solves

Sony Walkman digital audio players are beloved for their dedicated **S-Master HX** hardware DAC/amps and long battery life. However, managing them on modern Apple Silicon Macs is notoriously frustrating:

1. **Cover Art Compatibility:** The NW-A55 firmware cannot decode Progressive JPEGs or CMYK color profiles. Progressive artwork results in blank/black squares or corrupted cover displays on the player.
2. **Metadata Freezes:** Standard macOS tagging tools often write `ID3v2.4`. The NW-A55 requires strict `ID3v2.3` with `UTF-16` encoding; ID3v2.4 tags cause the Walkman database builder to hang or freeze.
3. **macOS Ghost Files:** macOS automatically litters USB FAT32/exFAT drives with hidden `._*` AppleDouble resource forks and `.DS_Store` files. These appear as unplayable corrupted tracks on the Walkman screen.
4. **Slow Transfer / Inaccurate Tools:** Generic music managers don't respect Walkman folder hierarchy (`/MUSIC/Artist/Album/`) or Walkman One custom firmware settings.

**Walkman Studio enforces all of these hardware constraints automatically.**

---

## Core Features

### 🎧 Multi-Layout Music Browser
* **All Songs (Table View):** Native macOS `Table` with multi-column sorting (Track #, Title, Artist, Album, Format, Duration, Bitrate) and right-click context actions.
* **Albums (Artwork Grid):** High-resolution square album tiles with real-time cover caching, year/track indicators, and an Apple Music-style Album Detail drill-down view with 1-click playback.
* **Artists (Master-Detail Discography):** Split-view discography browser grouped by album with initial avatars and discography stats.
* **Hi-Res Audio (Studio Masters):** Audiophile dashboard filtered exclusively for **24-bit / 96kHz+** studio master FLAC tracks calibrated for the S-Master HX DAC.

### 🏷️ Metadata & Baseline RGB Artwork Inspector (`Cmd+I`)
* **Baseline RGB JPEG Encoder:** Built-in Apple ImageIO/CoreGraphics pipeline automatically converts any dropped image to non-progressive RGB Baseline JPEG ($\le 800\times 800$ px).
* **Strict ID3v2.3 UTF-16 Writer:** Pure-Swift binary tagger that writes compliant `TIT2`, `TPE1`, `TALB`, `TRCK`, `TYER`, `TCON`, and `APIC` front-cover frames.
* **Lyrics Section:** Reads companion **`.lrc`** files (the Sony NW-A55 native hardware standard) and embedded ID3 `USLT` tags, with an integrated editor to paste and save `.lrc` files directly alongside your tracks.

### 💽 Dual-Drive Detection & Overview
* Automatically detects both the **Internal Flash** (`/Volumes/WALKMAN`) and **MicroSD Card** (`/Volumes/SD_CARD`).
* Uses Darwin kernel `statvfs` calls to calculate real-time free and used storage blocks accurately.
* Finder / Apple Devices style Hardware Overview dashboard with live compliance checklist.

### 🧹 Clean macOS Junk & Safe Eject
* Executes `/usr/bin/dot_clean -m` to merge AppleDouble resource forks before ejecting.
* Recursively cleans hidden `._*`, `.DS_Store`, `.Spotlight-V100`, `.Trashes`, and `.fseventsd` files.
* Unmounts all connected Walkman volumes cleanly via `diskutil`.

### ⚡ Walkman One Custom Firmware (CFW) Tuning
* Direct reader and writer for `/CFW/settings.txt`.
* Toggle hardware sound emulation profiles:
  * **WM1Z:** Warm, rich, analog flagship sound signature.
  * **DMP-Z1:** Ultimate transparency, holographic soundstage, dynamic range.
  * **ZX300:** Energetic, punchy mid-bass with forward vocal presence.
  * **Neutral:** Studio reference flat monitoring.
* Configure **DAC Gain** (Normal for IEMs vs High Gain for demanding headphones), **Walkman Plus v2**, and **Vinyl Processor**.

### 🔄 Transfer & Batch Transcoder Queue
* Drag-and-drop audio files directly from Finder.
* Native FFmpeg integration with presets:
  * `Bit-Perfect Copy` (transfers without re-encoding)
  * `FLAC 16-bit / 44.1kHz` (CD Quality)
  * `FLAC 24-bit / 96kHz` (Hi-Res Studio Master)
  * `MP3 320kbps` (High Quality MP3)
* Automatically sanitizes illegal FAT32 characters (`< > : " / \ | ? *`) and organizes files into `/MUSIC/Artist/Album/NN - Title.ext`.

---

## Strict Hardware Rules Enforced

| Rule | NW-A55 Hardware Requirement | Walkman Studio Implementation |
| :--- | :--- | :--- |
| **Cover Art** | Baseline RGB JPEG only ($\le 800\times 800$) | Apple ImageIO pipeline forces `kCGColorSpaceDeviceRGB` & `kCGImagePropertyJFIFIsProgressive: false`. |
| **MP3 Tags** | ID3v2.3 with UTF-16 encoding | Pure-Swift binary frame writer (`v2_version=3`, `encoding=1` with BOM). |
| **FLAC Tags** | Vorbis comments + Picture block type 3 | Replaces existing picture blocks with compliant Baseline JPEG Front Cover. |
| **Filesystem** | FAT32 / exFAT safe names | Strips `< > : " / \ | ? *` and trailing dots/spaces from folder and file paths. |
| **Playlists** | CRLF relative POSIX `.m3u8` | Stored in `/MUSIC/` using `\r\n` line endings and relative forward-slash paths. |
| **Ghost Files** | Zero `._*` AppleDouble files | Automates `dot_clean -m` and purges macOS hidden directories before unmounting. |

---

## Requirements

* **Mac:** Apple Silicon Mac (M1, M2, M3, M4 or newer).
* **OS:** macOS 14.0 (Sonoma) or newer (macOS 15 Sequoia recommended).
* **Hardware:** Sony Walkman NW-A55, NW-A55L, NW-A56, NW-A57 (or NW-A30 / NW-A40 series).
* **Cable:** Standard Sony WM-PORT to USB-A/USB-C cable.
* **Optional:** Homebrew FFmpeg (`brew install ffmpeg`) for audio format transcoding.

---

## Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/walkman-studio.git
cd walkman-studio
```

### 2. Launch the Application
Run the startup script:
```bash
./start.sh
```
*This script automatically builds the release binary and packages `Walkman Studio.app` using the Swift Package Manager.*

### 3. Build & Package Manually
To build the standalone release app bundle:
```bash
./build_app.sh
open "Walkman Studio.app"
```

---

## Project Structure

```
walkman-studio/
├── Package.swift                    # Swift Package Manager manifest (macOS 14+)
├── build_app.sh                     # Release packager for Walkman Studio.app
├── start.sh                         # Unified one-click launcher
├── Sources/
│   └── WalkmanStudio/
│       ├── WalkmanStudioApp.swift   # App entry point with unified toolbar
│       ├── Models.swift             # Track, Album, Artist, Drive data models
│       ├── Theme.swift              # Obsidian & Gold Liquid Glass materials
│       ├── WalkmanEngine.swift      # Hardware rules, statvfs, ImageIO Baseline JPEG
│       ├── AudioTagger.swift        # ID3v2.3 binary writer, lyrics & artwork parser
│       ├── AudioPlayerService.swift # Background streaming audio preview engine
│       ├── CoverArtCache.swift      # Asynchronous image & thumbnail cache
│       ├── LibraryScanner.swift     # High-speed USB 2.0 async directory enumerator
│       └── Views/
│           ├── ContentView.swift        # NavigationSplitView coordinator & toolbar
│           ├── SidebarView.swift        # Apple HIG Source List sidebar
│           ├── DeviceOverviewView.swift # Finder/Apple Devices hardware dashboard
│           ├── LibraryView.swift        # Native macOS multi-column Table view
│           ├── AlbumsView.swift         # Apple Music style Album Grid & Detail view
│           ├── ArtistsView.swift        # Master-Detail Artist discography browser
│           ├── HiResAudioView.swift     # 24-bit Studio Master audiophile view
│           ├── MetadataStudioView.swift # Trailing Inspector pane (Tags, Art, Lyrics)
│           ├── TrackPreviewBar.swift    # Persistent bottom playback bar
│           ├── TransferQueueView.swift  # Drag & Drop queue with FFmpeg transcoding
│           ├── PlaylistsView.swift      # CRLF .M3U8 playlist editor
│           ├── WalkmanOneDspView.swift  # Walkman One CFW registers & sound signatures
│           └── CleanEjectSheet.swift    # dot_clean & safe unmount sheet
```

---

## Contributing

Contributions, bug reports, and hardware testing feedback are welcome!
1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## License

Distributed under the **MIT License**. See `LICENSE` for details.

---

## Acknowledgments

* Dedicated to the **Sony Walkman** audiophile community and the creators of the **Walkman One Custom Firmware**.
* Built with ❤️ for Apple Silicon and macOS.
