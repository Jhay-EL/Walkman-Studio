# Walkman Studio - Codebase Rules & Development Guidelines

## 1. Mandatory Application Restart Rule
> [!IMPORTANT]
> **ALWAYS restart the software after making changes to the codebase.**
> Whenever changes are made to Swift sources (`Sources/`), Python backend (`backend/`), UI components, or assets:
> 1. Compile and package the release application bundle:
>    ```bash
>    ./build_app.sh arm64
>    ```
> 2. Run automated test suites to ensure zero regressions:
>    ```bash
>    ./venv/bin/pytest
>    ```
> 3. **Immediately terminate any running instance of the app and relaunch the updated bundle:**
>    ```bash
>    killall WalkmanStudio 2>/dev/null || true
>    open "/Users/workstation/Documents/Projects/walkman-studio/Walkman Studio.app"
>    ```
> 4. Verify that the refreshed app is running:
>    ```bash
>    pgrep -il walkman
>    ```

## 2. Hardware Compliance (Sony Walkman DAPs)
- **Cover Artwork**: Strict Baseline RGB JPEG only, maximum 800x800 resolution (no Progressive JPEGs, no CMYK, no PNGs on storage).
- **ID3v2.3 UTF-16**: For MP3, always enforce strict ID3v2.3 with UTF-16 encoding (avoid ID3v2.4 which causes scrambled tags on Sony firmware).
- **FLAC Metadata**: Preserve FLAC metadata blocks; encapsulate Sony 12 Tone / SenseMe metadata strictly in FLAC `APPLICATION` block code `2` with application ID `SMFM` (3270 bytes). Never corrupt audio frames.
- **File System Sanitation**: Paths on FAT32/exFAT drives must never contain invalid characters (`\ / : * ? " < > |`), and macOS AppleDouble dot-files (`._*`) / `.DS_Store` must be cleaned.

## 3. UI & Architecture Guidelines
- **Track Detail Pane (Inspector Sidebar)**: View-only pane. Do not place analysis or destructive action buttons in this sidebar. Rich acoustic analysis (12 Tone / SenseMe) should only be displayed if the track is already analyzed.
- **Batch Operations**: Analysis, sync, and conversions belong in the Library toolbar, table context menus, and Transfer Queue.

## 4. No Screenshots / Snapshots Rule
- **Zero Screenshots / Snapshots**: Do NOT take screenshots or UI snapshots of the app to confirm changes. The user will manually inspect and confirm changes in the running application to keep interactions fast and efficient.
