---
name: walkman-mock-fs
description: Mounts and seeds mock Sony Walkman NW-A55L internal and MicroSD filesystems, generates test audio/artwork, and verifies NW-A55L hardware compliance.
---

# Walkman Mock Filesystem Skill (`walkman-mock-fs`)

This skill enables Antigravity agents to simulate and rigorously test the **Sony Walkman NW-A55L** management workflow on macOS without requiring a physical device to be plugged in via USB.

It provisions dual mock storage volumes (`WALKMAN` Internal + `SD_CARD` MicroSD), seeds Sony device markers, creates sample audio and artwork, injects macOS ghost files, and executes strict hardware compliance audits against the non-negotiable rules in `GEMINI.md`.

---

## Architecture & Modes

The mock manager supports two modes:

| Mode | Mechanism | Target Path | Best For |
| :--- | :--- | :--- | :--- |
| **Virtual DMG Mode** *(Default)* | Native macOS `hdiutil` FAT32 disk images | `/Volumes/WALKMAN`<br>`/Volumes/SD_CARD` | Realistic testing with true FAT32 filesystem semantics, real `psutil` block devices, and `diskutil` unmounting. |
| **Folder Fallback Mode** | Plain directories with `WALKMAN_VOLUMES_ROOT` | `/tmp/walkman_volumes/WALKMAN`<br>`/tmp/walkman_volumes/SD_CARD` | Lightweight, unprivileged testing or CI environments without disk image mounting. |

---

## Helper Scripts

All scripts are located in:
`.agents/skills/walkman-mock-fs/scripts/`

- **`mock_drive_manager.py`**: Mounts, unmounts, and seeds mock Walkman storage volumes.
- **`verify_walkman_compliance.py`**: Audits tracks, artwork, playlists, and ghost files for strict NW-A55L compliance.

---

## Step-by-Step Agent Workflow

### 1. Spin Up and Seed Mock Drives

#### Virtual DMG Mode (Default)
To create 64MB FAT32 disk images, attach them to `/Volumes/`, and seed all test assets:
```bash
./venv/bin/python .agents/skills/walkman-mock-fs/scripts/mock_drive_manager.py --mount --seed
```

#### Folder Fallback Mode
If DMG mounting is unavailable or folder simulation is preferred:
```bash
./venv/bin/python .agents/skills/walkman-mock-fs/scripts/mock_drive_manager.py --mode folder --mock-dir /tmp/walkman_volumes --mount --seed
export WALKMAN_VOLUMES_ROOT=/tmp/walkman_volumes
```

---

### 2. Check Drive Status
Verify that the volumes are mounted and visible:
```bash
./venv/bin/python .agents/skills/walkman-mock-fs/scripts/mock_drive_manager.py --status
```

---

### 3. What Gets Seeded

When `--seed` is executed, the following structure is populated:

```
/Volumes/WALKMAN/
├── capability.xml                     # Sony NW-A55 mass storage device descriptor
├── CFW/
│   └── settings.txt                  # Walkman One CFW parameters (sound_signature = WM1Z, dac_gain = 0)
├── MUSIC/
│   ├── .DS_Store                     # Injected macOS junk file
│   ├── Test Heavy Rotation.m3u8      # CRLF playlist with relative POSIX paths
│   ├── Test Artist/
│   │   ├── Test Album/
│   │   │   ├── 01 - Sine Wave 440Hz.flac    # 2s FLAC with Baseline RGB JPEG (800x800)
│   │   │   ├── 02 - Sine Wave 880Hz.mp3     # 2s MP3 with strict ID3v2.3 (UTF-16)
│   │   │   ├── folder.jpg                   # Compliant Baseline RGB JPEG
│   │   │   ├── progressive_test_cover.jpg   # Deliberate Progressive JPEG (test control)
│   │   │   └── ._01 - Sine Wave 440Hz.flac  # Injected AppleDouble resource fork
│   │   └── Uncompliant Album/
│   │       └── 01 - Progressive Art Track.mp3 # Injected Progressive art track (test control)
├── .Spotlight-V100/                  # Injected macOS search index
└── .Trashes/                         # Injected macOS trash folder

/Volumes/SD_CARD/
├── Sony_Card.IND                     # Sony Walkman MicroSD identification file
└── MUSIC/
    └── MicroSD Artist/
        └── Live Session/
            ├── 01 - Ambient Track.flac
            ├── .DS_Store
            └── ._01 - Ambient Track.flac
```

---

### 4. Run Hardware Compliance Verification

After performing transfers, metadata edits, or cleaning routines in Walkman Studio, run the compliance audit tool:

```bash
./venv/bin/python .agents/skills/walkman-mock-fs/scripts/verify_walkman_compliance.py
```

#### Available Flags:
- `--assert-clean`: Asserts that **zero** macOS ghost files (`.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`) exist on the drive.
- `--include-controls`: Includes deliberate negative test controls (e.g. `Uncompliant Album`) to verify that the auditor flags them.
- `--json`: Outputs structured JSON for automated test pipelines.
- `--drive <path>`: Scans a specific drive mount point.

Example for asserting post-eject clean state:
```bash
./venv/bin/python .agents/skills/walkman-mock-fs/scripts/verify_walkman_compliance.py --assert-clean
```

---

### 5. Tear Down and Unmount Mock Drives

When testing is complete:

#### Virtual DMG Mode:
```bash
./venv/bin/python .agents/skills/walkman-mock-fs/scripts/mock_drive_manager.py --unmount
```
This detaches `/Volumes/WALKMAN` and `/Volumes/SD_CARD` and cleans up temporary disk images from `/tmp/`.

#### Folder Fallback Mode:
```bash
./venv/bin/python .agents/skills/walkman-mock-fs/scripts/mock_drive_manager.py --mode folder --mock-dir /tmp/walkman_volumes --unmount
```
