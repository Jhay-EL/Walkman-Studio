<p align="center">
  <img src="assets/icon.png" width="160" height="160" alt="Walkman Studio Icon" style="border-radius: 36px; box-shadow: 0 10px 30px rgba(0,0,0,0.5);" />
</p>

# <p align="center">Walkman Studio</p>

<p align="center">
  <strong>Complete Management Utility for the Sony Walkman NW-A55 / NW-A50 Series on macOS</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B%20(Apple%20Silicon)-black?style=for-the-badge&logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Language-Swift%205.9%2B-orange?style=for-the-badge&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Hardware-Sony%20Walkman%20NW--A55%20%2F%20A55L-gold?style=for-the-badge&logo=sony" alt="Sony Walkman" />
  <img src="https://img.shields.io/badge/Firmware-Walkman%20One%20CFW%20Ready-blue?style=for-the-badge" alt="Walkman One" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License" />
</p>

A dedicated macOS desktop application and hardware management utility built specifically for the **Sony Walkman NW-A55 / NW-A55L** (and NW-A50 series). It automates dual-drive library management, strict hardware-compliant metadata tagging, Baseline JPEG artwork conversion, `.LRC` synchronized lyrics syncing, batch audio transcoding, Walkman One custom firmware tuning, and macOS dotfile purging.

---

## The Problem Walkman Studio Solves

Sony Walkman digital audio players deliver exceptional audio fidelity via their hardware **S-Master HX** DAC/amplifier, but connecting them to modern Apple Silicon Macs presents major challenges:

1. **Cover Art Rejections:** The NW-A55 firmware cannot decode Progressive JPEGs or CMYK color spaces. Embedded progressive album covers result in blank/black tiles or corrupted artwork on the device screen.
2. **Database Builder Freezes:** Modern tagging software often defaults to `ID3v2.4`. The NW-A55 requires strict `ID3v2.3` with `UTF-16` encoding; newer ID3v2.4 tags cause the Walkman's library database scan to hang or freeze indefinitely.
3. **Ghost Files / Corrupted Tracks:** macOS automatically writes hidden `._*` AppleDouble resource forks, `.DS_Store`, and `.Spotlight-V100` files to FAT32 and exFAT volumes. On the Walkman, these shadow files appear as duplicate, unplayable, greyed-out tracks.
4. **Volume Management:** The Walkman NW-A55 operates with two separate volumes (Internal Flash + MicroSD Expansion), requiring proper file path routing and CRLF playlist formatting.

**Walkman Studio automatically eliminates all of these issues.**

---

## Core Features

### 🖼️ Automated Baseline RGB JPEG Artwork Engine
* Automatically inspects and converts album artwork to strict **Baseline RGB JPEG** format ($\le 800\times 800$ resolution).
* Strips progressive scan passes, alpha channels, and CMYK color spaces that crash or freeze the Walkman NW-A55 display engine.
* Instant drag-and-drop cover art validator with real-time hardware compliance status.

### 🏷️ Strict ID3v2.3 (UTF-16) & FLAC Metadata Tagger
* Enforces pure binary `ID3v2.3` tagging with `UTF-16` Little Endian encoding and BOM (`encoding=1`) on all MP3 files—preventing database corruption on the Walkman.
* Standard Vorbis comments and Front Cover `Picture` block (`type=3`, `image/jpeg`) embedding for FLAC files.
* Direct editing of Title, Artist, Album, Track Number, Year, and Genre with one-click atomic saving.

### 📝 Synchronized Lyrics Manager (.LRC & Embedded USLT)
* Detects and displays companion **`.lrc`** synchronized lyrics files—the native lyrics standard supported by the Sony NW-A55.
* Reads embedded ID3 `USLT` (Unsynchronized lyrics) frames.
* Built-in lyrics editor: paste or write lyrics and save them directly as `.lrc` companion files alongside your tracks for instant on-screen display during Walkman playback.

### ⚡ Walkman One Custom Firmware (CFW) DSP Tuning
* Direct reader and writer for `/CFW/settings.txt` on the Walkman root directory.
* Switch between hardware sound emulation profiles:
  * **WM1Z:** Warm, lush, analog sound signature with deep bass authority.
  * **DMP-Z1:** Reference transparency, holographic soundstage, and analytical dynamics.
  * **ZX300:** Energetic, punchy mid-bass slam with forward vocal presence.
  * **Neutral:** Bit-perfect studio reference frequency response.
* Toggle **DAC Gain** (Normal for sensitive IEMs vs High Gain for demanding headphones), **Vinyl Processor**, and **Walkman Plus v2** audio driver pipeline.

### 🧹 macOS Dotfile Purge & Safe Eject
* Automatically runs `/usr/bin/dot_clean -m` to merge AppleDouble resource forks before unmounting.
* Recursively searches for and removes hidden `._*`, `.DS_Store`, `.Spotlight-V100`, `.Trashes`, and `.fseventsd` ghost files.
* Cleanly unmounts both Internal Flash and MicroSD volumes via `diskutil` to prevent filesystem corruption.

### 💽 Dual-Drive Detection & Storage Manager
* Automatically detects both the **Internal Flash** (`/Volumes/WALKMAN`) and **MicroSD Card** (`/Volumes/SD_CARD`).
* Direct Darwin kernel `statvfs` integration providing exact byte counts, used storage, and remaining capacity.
* Quick-switch selector to seamlessly manage or browse either storage drive.

### 🎵 High-Performance Library Browser
* **All Songs (Table View):** Multi-column sortable table (`#`, `Title`, `Artist`, `Album`, `Format`, `Duration`, `Bitrate`) with search filtering and instant playback.
* **Albums (Artwork Grid):** Visual album browser with cover art caching, year indicators, track counts, and an Album Detail drill-down view.
* **Artists (Discography Browser):** Master-detail view grouping tracks by artist and album.
* **Hi-Res Audio (Studio Masters):** Filtered view exclusively displaying **24-bit / 96kHz+** lossless FLAC tracks calibrated for the S-Master HX DAC.
* Sub-second library indexing: scans 7,000+ tracks over USB 2.0 in ~0.25 seconds without UI lag.

### 🔄 Batch Audio Transcoding & Transfer Queue (FFmpeg)
* Drag-and-drop batch transfer queue supporting multiple audio formats.
* Integrated FFmpeg conversion presets:
  * `Bit-Perfect Copy` (direct transfer without re-encoding)
  * `FLAC 16-bit / 44.1kHz` (CD Quality lossless)
  * `FLAC 24-bit / 96kHz` (Hi-Res Studio Master)
  * `MP3 320kbps` (High-bitrate MP3)
* Automatically sanitizes illegal FAT32/exFAT filesystem characters (`< > : " / \ | ? *`) and organizes files into `/MUSIC/Artist/Album/NN - Title.ext`.

### 📋 CRLF Relative POSIX .M3U8 Playlist Engine
* Creates and edits playlists stored in `/MUSIC/`.
* Enforces relative POSIX paths (`Artist/Album/Track.flac`) and strict **CRLF** (`\r\n`) line endings required by Sony Walkman firmware for playlist recognition.

---

## Strict Hardware Rules Summary

| Rule | NW-A55 Hardware Constraint | Walkman Studio Automated Handling |
| :--- | :--- | :--- |
| **Cover Art** | Baseline RGB JPEG only ($\le 800\times 800$) | Converts progressive/CMYK images to Baseline RGB with zero progressive scans. |
| **MP3 Tags** | ID3v2.3 with UTF-16 encoding | Binary tagger writes `ID3v2.3` with `encoding=1` (UTF-16 with BOM). |
| **FLAC Tags** | Vorbis comments + Picture block type 3 | Clears corrupted blocks and embeds compliant Front Cover JPEG blocks. |
| **Filesystem** | FAT32 / exFAT character limits | Strips illegal characters (`< > : " / \ | ? *`) and trailing dots/spaces. |
| **Playlists** | CRLF relative POSIX `.m3u8` | Generates playlists inside `/MUSIC/` using `\r\n` line breaks and POSIX paths. |
| **Ghost Files** | Zero `._*` AppleDouble files | Automates `dot_clean -m` and purges macOS hidden metadata files before ejecting. |

---

## Requirements

* **Mac:** Apple Silicon Mac (M1, M2, M3, M4 or newer).
* **OS:** macOS 14.0 (Sonoma) or newer.
* **Hardware:** Sony Walkman NW-A55, NW-A55L, NW-A56, NW-A57 (also compatible with NW-A30 / NW-A40 series).
* **Cable:** Sony WM-PORT to USB cable.
* **Optional:** Homebrew FFmpeg (`brew install ffmpeg`) for audio format transcoding.

---

## Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/Jhay-EL/Walkman-Studio.git
cd Walkman-Studio
```

### 2. Launch the Application
Run the startup script:
```bash
./start.sh
```
*This script automatically builds the release binary and packages `Walkman Studio.app` using the Swift Package Manager.*

### 3. Build & Package Manually
To compile the standalone release app bundle:
```bash
./build_app.sh
open "Walkman Studio.app"
```

---

## Project Structure

```
Walkman-Studio/
├── Package.swift                    # Swift Package Manager manifest
├── build_app.sh                     # Release packager for Walkman Studio.app
├── start.sh                         # Unified startup script
├── assets/
│   ├── icon.png                     # High-resolution application icon
│   └── AppIcon.icns                 # macOS icon bundle (16x16 to 1024x1024)
├── Sources/
│   └── WalkmanStudio/
│       ├── WalkmanStudioApp.swift   # Main application entry point
│       ├── Models.swift             # Track, Album, Artist, Drive data models
│       ├── Theme.swift              # Obsidian & Gold color palette
│       ├── WalkmanEngine.swift      # Hardware rules, statvfs, ImageIO Baseline JPEG encoder
│       ├── AudioTagger.swift        # ID3v2.3 binary writer, lyrics & artwork parser
│       ├── AudioPlayerService.swift # Streaming audio preview engine
│       ├── CoverArtCache.swift      # Asynchronous image & thumbnail cache
│       ├── LibraryScanner.swift     # High-speed USB 2.0 async directory enumerator
│       └── Views/
│           ├── ContentView.swift        # Main coordinator & unified toolbar
│           ├── SidebarView.swift        # Source list sidebar navigation
│           ├── DeviceOverviewView.swift # Hardware dashboard with dual storage gauges
│           ├── LibraryView.swift        # Multi-column sortable track table
│           ├── AlbumsView.swift         # Album Grid & Album Detail drill-down
│           ├── ArtistsView.swift        # Master-detail artist discography browser
│           ├── HiResAudioView.swift     # 24-bit Studio Master audiophile view
│           ├── MetadataStudioView.swift # Inspector pane (Tags, Art, Lyrics editor)
│           ├── TrackPreviewBar.swift    # Persistent bottom playback bar
│           ├── TransferQueueView.swift  # Drag & drop queue with FFmpeg transcoding
│           ├── PlaylistsView.swift      # CRLF .M3U8 playlist generator
│           ├── WalkmanOneDspView.swift  # Walkman One CFW registers & sound signatures
│           └── CleanEjectSheet.swift    # dot_clean & safe unmount modal
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

* Dedicated to the **Sony Walkman** audiophile community and the developers of the **Walkman One Custom Firmware**.
