#!/usr/bin/env python3
"""
Walkman Mock Filesystem Manager (macOS Apple Silicon).
Manages virtual Sony Walkman NW-A55L filesystems (Internal + MicroSD)
in either native macOS DMG mode (hdiutil FAT32) or folder fallback mode.
"""

from __future__ import annotations

import argparse
import io
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

import mutagen
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3, TALB, TCON, TIT2, TPE1, TRCK, TYER
from PIL import Image

INTERNAL_DMG = Path("/tmp/walkman_mock_internal.dmg")
SDCARD_DMG = Path("/tmp/walkman_mock_sdcard.dmg")
FFMPEG_BIN = "/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else (shutil.which("ffmpeg") or "ffmpeg")

CAPABILITY_XML = """<?xml version="1.0" encoding="utf-8"?>
<DeviceInfo>
  <ModelName>NW-A55</ModelName>
  <DeviceClass>MassStorage</DeviceClass>
  <Manufacturer>Sony</Manufacturer>
  <FirmwareVersion>1.02</FirmwareVersion>
  <WalkmanOneSupported>true</WalkmanOneSupported>
</DeviceInfo>
"""

CFW_SETTINGS_TXT = """# Walkman One Custom Firmware Settings
# NW-A50 / NW-WM1 / NW-ZX300
sound_signature = WM1Z
dac_gain = 0
plus_v2 = 1
vinyl_processor = 0
hardware_tuning = Neutral
"""


# ---------------------------------------------------------------------------
# Virtual DMG Mode (Native macOS FAT32 Mount)
# ---------------------------------------------------------------------------
def mount_dmg_drives() -> Dict[str, str]:
    """Creates and mounts two 64MB FAT32 disk images at /Volumes/WALKMAN and /Volumes/SD_CARD."""
    print("[*] Mounting native macOS FAT32 disk images...")
    mounted = {}

    drives = [
        ("WALKMAN", INTERNAL_DMG, "/Volumes/WALKMAN"),
        ("SD_CARD", SDCARD_DMG, "/Volumes/SD_CARD"),
    ]

    for vol_name, dmg_path, mount_path in drives:
        # Check if already mounted
        if os.path.ismount(mount_path) or Path(mount_path).exists():
            print(f"    - {vol_name} already mounted at {mount_path}")
            mounted[vol_name] = mount_path
            continue

        # Create 64MB FAT32 disk image
        if dmg_path.exists():
            dmg_path.unlink()

        print(f"    - Creating 64MB FAT32 disk image for {vol_name} at {dmg_path} ...")
        cmd_create = ["hdiutil", "create", "-size", "64m", "-fs", "MS-DOS", "-volname", vol_name, str(dmg_path), "-ov"]
        res_create = subprocess.run(cmd_create, capture_output=True, text=True, check=False)
        if res_create.returncode != 0:
            print(f"[!] Error creating {dmg_path}: {res_create.stderr}")
            continue

        # Attach image
        print(f"    - Attaching {dmg_path} ...")
        cmd_attach = ["hdiutil", "attach", str(dmg_path)]
        res_attach = subprocess.run(cmd_attach, capture_output=True, text=True, check=False)
        if res_attach.returncode != 0:
            print(f"[!] Error attaching {dmg_path}: {res_attach.stderr}")
            continue

        if Path(mount_path).exists():
            mounted[vol_name] = mount_path
            print(f"[+] Successfully mounted {vol_name} at {mount_path}")

    return mounted


def unmount_dmg_drives() -> None:
    """Detaches mounted DMG volumes and removes temporary image files."""
    print("[*] Unmounting mock DMG drives...")
    targets = [
        ("/Volumes/WALKMAN", INTERNAL_DMG),
        ("/Volumes/SD_CARD", SDCARD_DMG),
    ]

    for mount_path, dmg_path in targets:
        if Path(mount_path).exists():
            print(f"    - Detaching {mount_path} ...")
            # Try hdiutil detach then diskutil eject
            subprocess.run(["hdiutil", "detach", mount_path, "-force"], capture_output=True, check=False)
            if Path(mount_path).exists():
                subprocess.run(["diskutil", "unmountDisk", "force", mount_path], capture_output=True, check=False)

        if dmg_path.exists():
            print(f"    - Removing {dmg_path} ...")
            try:
                dmg_path.unlink()
            except Exception as e:
                print(f"[!] Could not remove {dmg_path}: {e}")

    print("[+] DMG unmount complete.")


# ---------------------------------------------------------------------------
# Folder Fallback Mode
# ---------------------------------------------------------------------------
def mount_folder_drives(mock_root: Path) -> Dict[str, str]:
    """Creates mock folder structure in mock_root/WALKMAN and mock_root/SD_CARD."""
    print(f"[*] Setting up folder fallback drives in {mock_root} ...")
    mock_root.mkdir(parents=True, exist_ok=True)
    mounted = {}

    for vol_name in ["WALKMAN", "SD_CARD"]:
        vol_dir = mock_root / vol_name
        vol_dir.mkdir(parents=True, exist_ok=True)
        mounted[vol_name] = str(vol_dir)
        print(f"[+] Mock folder ready: {vol_dir}")

    return mounted


def unmount_folder_drives(mock_root: Path) -> None:
    """Removes mock folder drives."""
    print(f"[*] Cleaning up mock folder drives in {mock_root} ...")
    for vol_name in ["WALKMAN", "SD_CARD"]:
        vol_dir = mock_root / vol_name
        if vol_dir.exists():
            shutil.rmtree(vol_dir, ignore_errors=True)
    print("[+] Folder cleanup complete.")


# ---------------------------------------------------------------------------
# Data Seeder (Audio, Baseline / Progressive Art, Playlists, macOS Ghost Files)
# ---------------------------------------------------------------------------
def seed_drives(volumes: Dict[str, str]) -> None:
    """Seeds Walkman signature files, test audio, cover art, playlists, and junk files."""
    print("[*] Seeding mock Walkman drives...")

    # 1. Seed Internal WALKMAN
    if "WALKMAN" in volumes:
        internal_root = Path(volumes["WALKMAN"])
        print(f"[*] Seeding Internal WALKMAN at {internal_root} ...")

        # Sony Device Signature
        (internal_root / "capability.xml").write_text(CAPABILITY_XML, encoding="utf-8")

        # Walkman One CFW Settings
        cfw_dir = internal_root / "CFW"
        cfw_dir.mkdir(parents=True, exist_ok=True)
        (cfw_dir / "settings.txt").write_text(CFW_SETTINGS_TXT, encoding="utf-8")

        # Music Folder Structure
        music_dir = internal_root / "MUSIC"
        album_dir = music_dir / "Test Artist" / "Test Album"
        album_dir.mkdir(parents=True, exist_ok=True)

        # Baseline RGB JPEG Cover Art (800x800, non-progressive)
        baseline_img = Image.new("RGB", (600, 600), color=(35, 120, 200))
        baseline_bytes_io = io.BytesIO()
        baseline_img.save(baseline_bytes_io, format="JPEG", quality=90, progressive=False, subsampling=0)
        baseline_art = baseline_bytes_io.getvalue()
        (album_dir / "folder.jpg").write_bytes(baseline_art)

        # Progressive JPEG Cover Art (Deliberately Progressive for rule testing)
        prog_img = Image.new("RGB", (600, 600), color=(220, 50, 50))
        prog_bytes_io = io.BytesIO()
        prog_img.save(prog_bytes_io, format="JPEG", quality=90, progressive=True)
        prog_art = prog_bytes_io.getvalue()
        (album_dir / "progressive_test_cover.jpg").write_bytes(prog_art)

        # Test FLAC track (2-second 440Hz Sine Wave)
        flac_track = album_dir / "01 - Sine Wave 440Hz.flac"
        _generate_sine_audio(flac_track, freq=440, duration=2, fmt="flac")
        _tag_flac(flac_track, "Sine Wave 440Hz", "Test Artist", "Test Album", 1, 2026, baseline_art)

        # Test MP3 track (2-second 880Hz Sine Wave)
        mp3_track = album_dir / "02 - Sine Wave 880Hz.mp3"
        _generate_sine_audio(mp3_track, freq=880, duration=2, fmt="mp3")
        _tag_mp3_id3v23(mp3_track, "Sine Wave 880Hz", "Test Artist", "Test Album", 2, 2026, baseline_art)

        # Deliberately Uncompliant MP3 (embedded with Progressive JPEG to verify validation & auto-fix)
        uncompliant_dir = music_dir / "Test Artist" / "Uncompliant Album"
        uncompliant_dir.mkdir(parents=True, exist_ok=True)
        uncompliant_mp3 = uncompliant_dir / "01 - Progressive Art Track.mp3"
        _generate_sine_audio(uncompliant_mp3, freq=550, duration=2, fmt="mp3")
        _tag_mp3_id3v23(uncompliant_mp3, "Progressive Art Track", "Test Artist", "Uncompliant Album", 1, 2026, prog_art)

        # Playlist (.m3u8 with CRLF line endings)
        playlist_lines = [
            "#EXTM3U",
            "Test Artist/Test Album/01 - Sine Wave 440Hz.flac",
            "Test Artist/Test Album/02 - Sine Wave 880Hz.mp3",
        ]
        playlist_content = "\r\n".join(playlist_lines) + "\r\n"
        (music_dir / "Test Heavy Rotation.m3u8").write_bytes(playlist_content.encode("utf-8"))

        # Seed macOS Ghost Files (To test dotfile cleaner)
        try:
            (music_dir / ".DS_Store").write_bytes(b"\x00\x00\x00\x01Bud1\x00")
        except Exception as e:
            print(f"    [!] Notice: could not write .DS_Store: {e}")

        try:
            (album_dir / "._01 - Sine Wave 440Hz.flac").write_bytes(b"\x00\x05\x16\x07Mac OS X")
        except Exception as e:
            print(f"    [!] Notice: could not write AppleDouble file: {e}")

        try:
            spotlight_dir = internal_root / ".Spotlight-V100"
            spotlight_dir.mkdir(parents=True, exist_ok=True)
            (spotlight_dir / "VolumeConfiguration.plist").write_text("<dict/>", encoding="utf-8")
        except Exception:
            # Fallback to subdirectory if root is restricted by macOS SIP/TCC
            try:
                (music_dir / ".Spotlight-V100").mkdir(parents=True, exist_ok=True)
            except Exception:
                pass

        try:
            trashes_dir = internal_root / ".Trashes" / "501"
            trashes_dir.mkdir(parents=True, exist_ok=True)
            (trashes_dir / "orphaned.tmp").write_text("trash", encoding="utf-8")
        except Exception:
            try:
                (music_dir / ".Trashes").mkdir(parents=True, exist_ok=True)
            except Exception:
                pass

        print("[+] Internal WALKMAN seeded with audio, cover art, playlist, and macOS junk files.")

    # 2. Seed MicroSD Card
    if "SD_CARD" in volumes:
        sd_root = Path(volumes["SD_CARD"])
        print(f"[*] Seeding MicroSD at {sd_root} ...")

        # MicroSD Sony Card Index Marker
        (sd_root / "Sony_Card.IND").write_bytes(b"\x00\x01SONY_NW_CARD\x00")

        # Music Folder Structure
        sd_music = sd_root / "MUSIC"
        sd_album = sd_music / "MicroSD Artist" / "Live Session"
        sd_album.mkdir(parents=True, exist_ok=True)

        sd_flac = sd_album / "01 - Ambient Track.flac"
        _generate_sine_audio(sd_flac, freq=330, duration=2, fmt="flac")
        _tag_flac(sd_flac, "Ambient Track", "MicroSD Artist", "Live Session", 1, 2026, None)

        (sd_album / ".DS_Store").write_bytes(b"\x00\x00\x00\x01Bud1\x00")
        (sd_album / "._01 - Ambient Track.flac").write_bytes(b"\x00\x05\x16\x07Mac OS X")

        print("[+] MicroSD seeded successfully.")


# ---------------------------------------------------------------------------
# Audio & Metadata Helpers
# ---------------------------------------------------------------------------
def _generate_sine_audio(output_path: Path, freq: int, duration: int, fmt: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        FFMPEG_BIN,
        "-y",
        "-f", "lavfi",
        "-i", f"sine=frequency={freq}:duration={duration}",
    ]
    if fmt == "flac":
        cmd.extend(["-c:a", "flac"])
    elif fmt == "mp3":
        cmd.extend(["-c:a", "libmp3lame", "-b:a", "320k"])
    else:
        cmd.extend(["-c:a", "flac"])

    cmd.append(str(output_path))
    res = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        raise RuntimeError(f"FFmpeg error: {res.stderr}")


def _tag_flac(path: Path, title: str, artist: str, album: str, track_num: int, year: int, art_bytes: Optional[bytes]) -> None:
    audio = FLAC(str(path))
    audio["title"] = [title]
    audio["artist"] = [artist]
    audio["album"] = [album]
    audio["tracknumber"] = [str(track_num)]
    audio["date"] = [str(year)]
    if art_bytes:
        audio.clear_pictures()
        pic = Picture()
        pic.type = 3
        pic.mime = "image/jpeg"
        pic.desc = "Front Cover"
        pic.data = art_bytes
        with Image.open(io.BytesIO(art_bytes)) as im:
            pic.width, pic.height = im.size
            pic.depth = 24
        audio.add_picture(pic)
    audio.save()


def _tag_mp3_id3v23(path: Path, title: str, artist: str, album: str, track_num: int, year: int, art_bytes: Optional[bytes]) -> None:
    tags = ID3()
    tags.setall("TIT2", [TIT2(encoding=1, text=title)])
    tags.setall("TPE1", [TPE1(encoding=1, text=artist)])
    tags.setall("TALB", [TALB(encoding=1, text=album)])
    tags.setall("TRCK", [TRCK(encoding=1, text=str(track_num))])
    tags.setall("TYER", [TYER(encoding=1, text=str(year))])
    if art_bytes:
        tags.setall("APIC", [APIC(encoding=1, mime="image/jpeg", type=3, desc="Front Cover", data=art_bytes)])
    tags.save(str(path), v2_version=3)


# ---------------------------------------------------------------------------
# CLI Entrypoint
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Walkman Mock Drive Manager")
    parser.add_argument("--mount", action="store_true", help="Mount mock Walkman drives")
    parser.add_argument("--unmount", action="store_true", help="Unmount and clean up mock Walkman drives")
    parser.add_argument("--seed", action="store_true", help="Seed mock drives with audio, artwork, playlists, and ghost files")
    parser.add_argument("--status", action="store_true", help="Check mock drives status")
    parser.add_argument("--mode", choices=["dmg", "folder"], default="dmg", help="Drive mode (dmg=native macOS FAT32, folder=directory fallback)")
    parser.add_argument("--mock-dir", type=Path, default=Path("/tmp/walkman_volumes"), help="Directory for folder fallback mode")

    args = parser.parse_args()

    # Determine volumes root
    if args.mode == "folder":
        mock_root = args.mock_dir
    else:
        mock_root = Path("/Volumes")

    if args.unmount:
        if args.mode == "dmg":
            unmount_dmg_drives()
        else:
            unmount_folder_drives(args.mock_dir)
        return

    mounted = {}
    if args.mount or args.seed or args.status:
        if args.mode == "dmg":
            mounted = mount_dmg_drives() if args.mount else {
                "WALKMAN": "/Volumes/WALKMAN" if Path("/Volumes/WALKMAN").exists() else None,
                "SD_CARD": "/Volumes/SD_CARD" if Path("/Volumes/SD_CARD").exists() else None,
            }
        else:
            mounted = mount_folder_drives(args.mock_dir) if args.mount else {
                "WALKMAN": str(args.mock_dir / "WALKMAN") if (args.mock_dir / "WALKMAN").exists() else None,
                "SD_CARD": str(args.mock_dir / "SD_CARD") if (args.mock_dir / "SD_CARD").exists() else None,
            }
        mounted = {k: v for k, v in mounted.items() if v and Path(v).exists()}

    if args.seed:
        if not mounted:
            print("[!] No mounted drives found to seed. Auto-mounting first...")
            if args.mode == "dmg":
                mounted = mount_dmg_drives()
            else:
                mounted = mount_folder_drives(args.mock_dir)
        seed_drives(mounted)

    if args.status or not (args.mount or args.unmount or args.seed):
        print("\n=== Walkman Mock Drives Status ===")
        print(f"Mode: {args.mode.upper()}")
        for vol_name in ["WALKMAN", "SD_CARD"]:
            p = Path("/Volumes" if args.mode == "dmg" else args.mock_dir) / vol_name
            status = "MOUNTED" if p.exists() else "UNMOUNTED"
            print(f"  • {vol_name:10}: {status} ({p})")


if __name__ == "__main__":
    main()
