<p align="center">
  <img src="assets/icon.png" width="160" height="160" alt="Walkman Studio Icon" style="border-radius: 36px; box-shadow: 0 10px 30px rgba(0,0,0,0.5);" />
</p>

# <p align="center">Walkman Studio</p>

<p align="center">
  <strong>Native macOS Music Manager & Audio Conversion Utility for Non-Android Sony Walkman DAPs</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B%20(Apple%20Silicon)-black?style=for-the-badge&logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Language-Swift%205.9%2B-orange?style=for-the-badge&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Architecture-Non--Android%20Sony%20OS-blue?style=for-the-badge" alt="Non-Android Sony OS" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License" />
</p>

A dedicated native macOS desktop application built specifically for managing non-Android Sony Walkman digital audio players. It automates dual-drive library management, strict hardware-compliant metadata tagging, Baseline RGB JPEG artwork conversion, `.LRC` synchronized lyrics syncing, batch FFmpeg audio transcoding, `.M3U8` CRLF playlist creation, and macOS dotfile purging.

Walkman Studio focuses strictly on safe, non-destructive music library management and conversion.

<p align="center">
  <img src="assets/sc/01_device_overview.png" alt="Walkman Studio Interface" width="100%" />
</p>

---

## The Problem Walkman Studio Solves

Sony Walkman non-Android digital audio players deliver exceptional audio fidelity via their hardware **S-Master HX** DAC/amplifier, but connecting them to modern Apple Silicon Macs presents major challenges:

1. **Cover Art Rejections:** The Walkman display engine cannot decode Progressive JPEGs or CMYK color spaces. Embedded progressive album covers result in blank/black tiles or corrupted artwork on the device screen.
2. **Database Builder Freezes:** Modern tagging software defaults to `ID3v2.4`. The Walkman requires strict `ID3v2.3` with `UTF-16` encoding; newer ID3v2.4 tags cause the Walkman's library database scan to hang or freeze indefinitely.
3. **Ghost Files / Duplicate Corrupted Tracks:** macOS automatically writes hidden `._*` AppleDouble resource forks, `.DS_Store`, and `.Spotlight-V100` files to FAT32 and exFAT volumes. On the Walkman, these shadow files appear as duplicate, unplayable, greyed-out tracks.
4. **Dual Storage Routing:** Walkman players operate with two distinct storage partitions (Internal Flash + MicroSD Expansion), requiring proper file path routing and relative CRLF playlist formatting.

**Walkman Studio automatically eliminates all of these issues.**

---

## Core Features

### Automated Baseline RGB JPEG Artwork Engine
* Automatically inspects and converts album artwork to strict **Baseline RGB JPEG** format ($\le 800\times 800$ resolution).
* Strips progressive scan passes, alpha channels, and CMYK color spaces that crash or freeze the Walkman display engine.
* Instant drag-and-drop cover art validator with real-time hardware compliance status.

### Strict ID3v2.3 (UTF-16) & FLAC Metadata Tagger
* Enforces pure binary `ID3v2.3` tagging with `UTF-16` Little Endian encoding and BOM (`encoding=1`) on all MP3 files—preventing database corruption on the Walkman.
* Standard Vorbis comments and Front Cover `Picture` block (`type=3`, `image/jpeg`) embedding for FLAC files.
* Direct editing of Title, Artist, Album, Track Number, Year, and Genre with one-click atomic saving.

### Synchronized Lyrics Manager (.LRC & Embedded USLT)
* Detects and displays companion **`.lrc`** synchronized lyrics files—the native lyrics standard supported by Sony Walkman players.
* **Automated Online Lyrics Fetching (LRCLIB API):** Queries the open-source **[LRCLIB](https://lrclib.net)** API (`/api/get` and `/api/search`) to automatically retrieve and generate timestamp-accurate synchronized `.lrc` companion files matched by track title, artist, album, and duration (with fallback to **[Lyrics.ovh](https://lyrics.ovh)**).
* Reads embedded ID3 `USLT` (Unsynchronized lyrics) frames.
* Built-in lyrics editor: paste, edit, or fetch lyrics and save them directly as `.lrc` companion files alongside your tracks for instant on-screen display during Walkman playback.

### Batch Audio Transcoding & Transfer Queue (FFmpeg)
* Drag-and-drop batch transfer queue supporting multiple audio formats.
* Integrated FFmpeg conversion presets:
  * `Bit-Perfect Copy` (direct transfer without re-encoding)
  * `FLAC 16-bit / 44.1kHz` (CD Quality lossless)
  * `FLAC 24-bit / 96kHz` (Hi-Res Studio Master)
  * `MP3 320kbps` (High-bitrate MP3)
* Automatically sanitizes illegal FAT32/exFAT filesystem characters (`< > : " / \ | ? *`) and organizes files into `/MUSIC/Artist/Album/NN - Title.ext`.

### CRLF Relative POSIX .M3U8 Playlist Engine
* Creates and edits playlists stored in `/MUSIC/`.
* Enforces relative POSIX paths (`Artist/Album/Track.flac`) and strict **CRLF** (`\r\n`) line endings required by Sony Walkman firmware for playlist recognition.

### Dual-Drive Detection & Storage Manager
* Automatically detects both the **Internal Flash** (`/Volumes/WALKMAN`) and **MicroSD Card** (`/Volumes/SD_CARD`).
* Direct Darwin kernel `statvfs` integration providing exact byte counts, used storage, and remaining capacity.
* Quick-switch selector directly in the sidebar navigation to seamlessly manage or browse either storage drive.

### macOS Dotfile Purge & Safe Eject
* Automatically runs `/usr/bin/dot_clean -m` to merge AppleDouble resource forks before unmounting.
* Recursively searches for and removes hidden `._*`, `.DS_Store`, `.Spotlight-V100`, `.Trashes`, and `.fseventsd` ghost files.
* Cleanly unmounts both Internal Flash and MicroSD volumes via `diskutil` to prevent filesystem corruption.

### High-Performance Library Browser
* **All Songs (Table View):** Multi-column sortable table (`#`, `Title`, `Artist`, `Album`, `Format`, `Duration`, `Bitrate`) with search filtering and instant playback.
* **Albums (Artwork Grid):** Visual album browser with cover art caching, year indicators, track counts, and an Album Detail drill-down view.
* **Artists (Discography Browser):** Master-detail view grouping tracks by artist and album.
* **Hi-Res Audio (Studio Masters):** Filtered view exclusively displaying **24-bit / 96kHz+** lossless FLAC tracks calibrated for the S-Master HX DAC.
* Sub-second library indexing: scans 7,000+ tracks over USB 2.0 in ~0.25 seconds without UI lag.

### Modern macOS Design UI Language
* Fully adopts macOS Sonoma / Sequoia design guidelines with a unified transparent title bar and seamless split dividers.
* Brushed silver and matte dark obsidian palette inspired by the Sony Walkman Signature Series aluminum chassis, with zero glow or artificial visual clutter.
* Aligned inspector pane with matching mid-page navigation dividers.

---

## Screenshots

<p align="center">
  <img src="assets/sc/01_device_overview.png" alt="Device Overview Dashboard" width="100%" />
</p>
<p align="center"><em><strong>Device Overview & Storage Dashboard:</strong> Real-time dual-drive gauges (Internal Flash & MicroSD), storage partition health, library statistics, dotfile clean & safe unmount, and atomic tag & synced lyrics inspector.</em></p>

<br />

<p align="center">
  <img src="assets/sc/02_library_browser.png" alt="Library Browser" width="100%" />
</p>
<p align="center"><em><strong>All Songs Library Browser:</strong> High-performance multi-column sortable table, instant search, audio format filter chips (FLAC, MP3, Hi-Res), and synchronized audio playback preview bar.</em></p>

<br />

<p align="center">
  <img src="assets/sc/03_hires_audio.png" alt="Hi-Res Studio Masters" width="100%" />
</p>
<p align="center"><em><strong>Hi-Res Audio Studio Master Library:</strong> Audiophile view filtering exclusively for 24-bit/96kHz+ lossless streams calibrated for the Sony S-Master HX DAC.</em></p>

<br />

<p align="center">
  <img src="assets/sc/04_playlists.png" alt="Playlists Engine" width="100%" />
</p>
<p align="center"><em><strong>CRLF Relative POSIX .M3U8 Playlists:</strong> Hardware-compliant playlist editor enforcing CRLF line breaks and relative POSIX paths required by Sony Walkman firmware.</em></p>

<br />

<p align="center">
  <img src="assets/sc/05_transfer_queue.png" alt="Batch Transfer Queue" width="100%" />
</p>
<p align="center"><em><strong>Batch Audio Transcoding & Transfer Queue:</strong> Drag-and-drop batch queue with integrated FFmpeg presets (Bit-perfect copy, FLAC 16/24-bit, MP3) and automatic FAT32/exFAT character sanitization.</em></p>

---

## Supported Sony Walkman Devices

Walkman Studio is designed **exclusively for non-Android Sony Walkman DAPs** running Sony OS / Linux architecture. Android-based Walkmans (such as NW-A105, NW-A306, NW-ZX507) use MTP and do not have these FAT32/ID3v2.3 constraints.

| Series | Supported Models | Storage Architecture |
| :--- | :--- | :--- |
| **NW-A50 Series** | NW-A55, NW-A55L, NW-A56, NW-A57 | Internal Flash + MicroSD |
| **NW-A40 Series** | NW-A45, NW-A46, NW-A47 | Internal Flash + MicroSD |
| **NW-A30 Series** | NW-A35, NW-A36, NW-A37 | Internal Flash + MicroSD |
| **NW-A20 / NW-A10 Series** | NW-A25, NW-A27, NW-A15, NW-A17 | Internal Flash + MicroSD |
| **NW-ZX Series** | NW-ZX300, NW-ZX100 | Internal Flash + MicroSD |
| **NW-WM1 Series** | NW-WM1A, NW-WM1Z | Internal Flash + MicroSD |
| **NW-WS Series** | NW-WS620, NW-WS410 | Internal Flash (Wearable) |

---

## Strict Hardware Rules Summary

| Rule | Walkman Hardware Constraint | Walkman Studio Automated Handling |
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
* **Hardware:** Any non-Android Sony Walkman DAP (NW-A, NW-ZX, NW-WM1, NW-WS series).
* **Cable:** Sony WM-PORT to USB cable (or model-specific USB cable).
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
├── Package.swift                         # Swift Package Manager manifest
├── build_app.sh                          # Release packager for Walkman Studio.app
├── start.sh                              # Unified startup script
├── assets/
│   ├── icon.png                          # High-resolution application icon
│   ├── AppIcon.icns                      # macOS icon bundle (16x16 to 1024x1024)
│   ├── walkman_device.png                # Sony Walkman hardware artwork
│   ├── walkman_device_cropped.png        # Cropped device preview icon
│   └── sc/                               # High-resolution application screenshots
├── Sources/
│   └── WalkmanStudio/
│       ├── WalkmanStudioApp.swift        # Main app entry point & transparent titlebar
│       ├── Models.swift                  # Track, Album, Artist, Drive data models
│       ├── Theme.swift                   # Brushed Silver & Dark Obsidian palette
│       ├── WalkmanEngine.swift           # Hardware rules, statvfs, ImageIO Baseline JPEG
│       ├── WalkmanDeviceDetector.swift   # XML hardware capability inspector
│       ├── LyricsService.swift           # LRCLIB & Lyrics.ovh synchronized lyrics engine
│       ├── AudioTagger.swift             # ID3v2.3 binary writer, lyrics & artwork parser
│       ├── AudioPlayerService.swift      # Streaming audio preview engine
│       ├── CoverArtCache.swift           # Asynchronous image & thumbnail cache
│       ├── LibraryScanner.swift          # High-speed USB 2.0 async directory enumerator
│       └── Views/
│           ├── ContentView.swift         # Main coordinator & unified toolbar
│           ├── SidebarView.swift         # Source list sidebar navigation
│           ├── DeviceOverviewView.swift  # Hardware dashboard with dual storage gauges
│           ├── WalkmanDeviceIconView.swift # Authentic Sony Walkman hardware device icon
│           ├── AboutWalkmanStudioView.swift # Supported devices & system architecture modal
│           ├── LibraryView.swift         # Multi-column sortable track table
│           ├── AlbumsView.swift          # Album Grid & Album Detail drill-down
│           ├── ArtistsView.swift         # Master-detail artist discography browser
│           ├── HiResAudioView.swift      # 24-bit Studio Master audiophile view
│           ├── MetadataStudioView.swift  # Inspector pane (Tags, Art, Lyrics editor)
│           ├── TrackPreviewBar.swift     # Persistent bottom playback bar
│           ├── TransferQueueView.swift   # Drag & drop queue with FFmpeg transcoding
│           ├── PlaylistsView.swift       # CRLF .M3U8 playlist generator
│           └── CleanEjectSheet.swift     # dot_clean & safe unmount modal
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

* Dedicated to the **Sony Walkman** audiophile community.
* Synchronized `.lrc` lyrics fetching powered by the community-driven **[LRCLIB](https://lrclib.net)** API.

---

## Support & Contact

* **Email:** [jl.temporary@outlook.it](mailto:jl.temporary@outlook.it)
* **Buy Me a Coffee:** [buymeacoffee.com/jhayel](https://www.buymeacoffee.com/jhayel)

<a href="https://www.buymeacoffee.com/jhayel" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="42" style="border-radius: 8px;" />
</a>
