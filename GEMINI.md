# Walkman Studio (macOS Apple Silicon) — Workspace Rules

## Project Overview
A native-feeling macOS desktop application for managing the Sony Walkman NW-A55L on Apple Silicon Macs. It handles dual-drive detection (Internal `WALKMAN` + MicroSD), audio conversion, metadata tagging, Baseline JPEG cover art encoding, folder organization, `.M3U8` playlists, Walkman One CFW DSP settings, and macOS dotfile purging.

## Tech Stack & Architecture
- **Backend:** Python 3.11+ with `FastAPI`, `uvicorn`, `mutagen`, `Pillow`, `psutil`, and native `/opt/homebrew/bin/ffmpeg`.
- **Frontend:** React + TypeScript + Vite + Tailwind CSS (Dark Sony Walkman Signature Series gold/obsidian aesthetic).
- **Desktop Wrapper:** `pywebview` (or Tauri) to launch the app in a clean native macOS window without requiring a browser tab.

## Strict Sony Walkman NW-A55L Hardware Constraints (NON-NEGOTIABLE)
1. **Baseline RGB JPEG Only:** The NW-A55L cannot render Progressive JPEGs or CMYK images. Every album cover MUST be converted via Pillow to `RGB`, resized to max `800x800`, and saved with `progressive=False` and `subsampling=0`.
2. **ID3v2.3 Enforcement:** MP3 metadata MUST be saved strictly as `ID3v2.3` (`v2_version=3`) with `UTF-16` (`encoding=1`). Never write `ID3v2.4`.
3. **FLAC Artwork & Tags:** FLAC files must use standard Vorbis comments and `Picture` blocks (`type=3` Front Cover, `image/jpeg`), clearing existing picture blocks before embedding.
4. **FAT32 / exFAT Sanitization:** Strip illegal filesystem characters (`< > : " / \ | ? *`) and trailing dots from all Artist, Album, and Track filenames before writing to `/Volumes/<Walkman>/MUSIC/`.
5. **Playlist Format:** `.M3U8` playlists must be placed inside `/MUSIC/`, use relative POSIX paths (`Artist/Album/01 - Track.flac`), and use `CRLF` (`\r\n`) line endings.
6. **macOS Ghost File Cleanup:** Before ejecting, always execute `dot_clean -m` on the Walkman mount point and delete `.DS_Store`, `._*` AppleDouble files, `.Spotlight-V100`, and `.Trashes`.
