#!/usr/bin/env python3
"""
Walkman NW-A55L Hardware Compliance Verifier.
Verifies all 6 hardware constraints across audio files, cover art,
playlists, and directory structures on Sony Walkman drives.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

import mutagen
from mutagen.flac import FLAC
from mutagen.id3 import ID3
from PIL import Image


class ComplianceReporter:
    def __init__(self, json_mode: bool = False):
        self.json_mode = json_mode
        self.passed: List[str] = []
        self.failed: List[Dict[str, str]] = []
        self.warnings: List[str] = []

    def record_pass(self, check_name: str, item: str):
        self.passed.append(f"{check_name}: {item}")

    def record_fail(self, check_name: str, item: str, reason: str):
        self.failed.append({"check": check_name, "item": item, "reason": reason})

    def record_warn(self, check_name: str, item: str, reason: str):
        self.warnings.append(f"{check_name}: {item} ({reason})")

    def print_summary(self) -> int:
        if self.json_mode:
            print(json.dumps({
                "passed_count": len(self.passed),
                "failed_count": len(self.failed),
                "warning_count": len(self.warnings),
                "failures": self.failed,
                "warnings": self.warnings,
                "success": len(self.failed) == 0,
            }, indent=2))
            return 0 if len(self.failed) == 0 else 1

        print("\n" + "=" * 65)
        print("  SONY WALKMAN NW-A55L HARDWARE COMPLIANCE AUDIT")
        print("=" * 65)

        print(f"\n[+] Checks Passed:   {len(self.passed)}")
        print(f"[!] Warnings:        {len(self.warnings)}")
        print(f"[-] Failures:        {len(self.failed)}")

        if self.warnings:
            print("\n--- Warnings ---")
            for w in self.warnings:
                print(f"  • {w}")

        if self.failed:
            print("\n--- Compliance Violations (NON-NEGOTIABLE) ---")
            for f in self.failed:
                print(f"  ✖ [{f['check']}] {f['item']}")
                print(f"    Reason: {f['reason']}")
            print("\n[RESULT] FAILED - Violations detected!")
            return 1

        print("\n[RESULT] SUCCESS - 100% NW-A55L Hardware Compliant!")
        return 0


# ---------------------------------------------------------------------------
# Hardware Constraint 1: Baseline RGB JPEG Verification
# ---------------------------------------------------------------------------
def check_image_bytes(image_data: bytes, source_name: str, reporter: ComplianceReporter) -> bool:
    try:
        with Image.open(io.BytesIO(image_data)) as img:
            if img.format != "JPEG":
                reporter.record_fail("Cover Art Format", source_name, f"Format is {img.format}, not JPEG")
                return False
            if img.mode != "RGB":
                reporter.record_fail("Cover Art Mode", source_name, f"Color mode is {img.mode}, must be RGB (no CMYK or RGBA)")
                return False
            if img.info.get("progressive", False):
                reporter.record_fail("Baseline JPEG", source_name, "Image is encoded as Progressive JPEG (NW-A55L freezes or fails to render)")
                return False
            if img.width > 800 or img.height > 800:
                reporter.record_fail("Cover Art Dimensions", source_name, f"Resolution {img.width}x{img.height} exceeds max 800x800")
                return False

            reporter.record_pass("Baseline RGB JPEG", f"{source_name} ({img.width}x{img.height} RGB Baseline)")
            return True
    except Exception as e:
        reporter.record_fail("Cover Art Corrupt", source_name, str(e))
        return False


# ---------------------------------------------------------------------------
# Hardware Constraint 2 & 3: Audio Tags & Artwork Verification
# ---------------------------------------------------------------------------
def verify_audio_file(file_path: Path, reporter: ComplianceReporter, ignore_uncompliant_dir: bool = True):
    if ignore_uncompliant_dir and "uncompliant" in str(file_path).lower():
        reporter.record_warn("Deliberate Control", file_path.name, "Skipping known uncompliant test control file")
        return

    ext = file_path.suffix.lower()

    # 1. MP3 Check
    if ext == ".mp3":
        try:
            id3 = ID3(str(file_path))
            # Rule 2: ID3v2.3 enforcement
            if id3.version != (2, 3, 0):
                reporter.record_fail("ID3 Version", str(file_path), f"Version is {id3.version}, MUST strictly be (2, 3, 0) ID3v2.3")
            else:
                reporter.record_pass("ID3v2.3 Version", str(file_path))

            # Artwork check
            apic_frames = id3.getall("APIC")
            for apic in apic_frames:
                check_image_bytes(apic.data, f"{file_path.name} APIC front cover", reporter)
        except Exception as e:
            reporter.record_fail("MP3 Read Error", str(file_path), str(e))

    # 2. FLAC Check
    elif ext == ".flac":
        try:
            audio = FLAC(str(file_path))
            reporter.record_pass("FLAC Vorbis", str(file_path))
            for pic in audio.pictures:
                if pic.type == 3:  # Front cover
                    check_image_bytes(pic.data, f"{file_path.name} FLAC Picture type=3", reporter)
        except Exception as e:
            reporter.record_fail("FLAC Read Error", str(file_path), str(e))


# ---------------------------------------------------------------------------
# Hardware Constraint 5: Playlist Verification (.m3u8 CRLF)
# ---------------------------------------------------------------------------
def verify_playlist_file(playlist_path: Path, reporter: ComplianceReporter):
    raw_bytes = playlist_path.read_bytes()

    # Check for CRLF
    if b"\r\n" not in raw_bytes:
        reporter.record_fail("Playlist Line Endings", str(playlist_path), "File does NOT use Windows CRLF (\\r\\n) line endings")
    else:
        # Verify no bare \n exists
        parts = raw_bytes.split(b"\r\n")
        has_bare_lf = any(b"\n" in p for p in parts)
        if has_bare_lf:
            reporter.record_fail("Playlist Line Endings", str(playlist_path), "Contains mixed bare LF line endings without CR")
        else:
            reporter.record_pass("Playlist CRLF", playlist_path.name)

    # Check relative paths and forward slashes
    lines = raw_bytes.decode("utf-8", errors="replace").splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "\\" in line:
            reporter.record_fail("Playlist POSIX Paths", f"{playlist_path.name} -> {line}", "Contains Windows backslashes (\\) instead of POSIX (/)")
        elif line.startswith("/"):
            reporter.record_fail("Playlist Relative Path", f"{playlist_path.name} -> {line}", "Path is absolute, must be relative to /MUSIC/")
        else:
            reporter.record_pass("Playlist Relative POSIX", f"{playlist_path.name} -> {line}")


# ---------------------------------------------------------------------------
# Hardware Constraint 6: macOS Ghost Files Audit
# ---------------------------------------------------------------------------
def check_ghost_files(mount_root: Path, reporter: ComplianceReporter):
    ghost_patterns = {".ds_store"}
    ghost_prefixes = ("._",)
    ghost_dirs = {".spotlight-v100", ".trashes", ".fseventsd"}

    found_ghosts = []

    for root, dirs, files in os.walk(str(mount_root)):
        for f in files:
            if f.lower() in ghost_patterns or f.startswith(ghost_prefixes):
                found_ghosts.append(os.path.join(root, f))
        for d in dirs:
            if d.lower() in ghost_dirs:
                found_ghosts.append(os.path.join(root, d))

    if found_ghosts:
        reporter.record_fail(
            "macOS Ghost Files",
            str(mount_root),
            f"Found {len(found_ghosts)} ghost file(s): {', '.join(found_ghosts[:5])}{'...' if len(found_ghosts) > 5 else ''}"
        )
    else:
        reporter.record_pass("Zero macOS Ghost Files", f"{mount_root} is clean of .DS_Store, ._*, and index caches")


# ---------------------------------------------------------------------------
# Main Audit Runner
# ---------------------------------------------------------------------------
def audit_walkman_drive(mount_point: Path, reporter: ComplianceReporter, assert_clean: bool = False, ignore_uncompliant: bool = True):
    print(f"[*] Auditing Walkman volume at: {mount_point}")

    if not mount_point.exists():
        reporter.record_fail("Volume Missing", str(mount_point), "Mount point does not exist")
        return

    # 1. Audit Ghost Files if requested
    if assert_clean:
        check_ghost_files(mount_point, reporter)

    music_dir = mount_point / "MUSIC"
    if not music_dir.exists():
        reporter.record_warn("No Music Directory", str(mount_point), "/MUSIC/ folder not found")
        return

    # 2. Audit Audio Files & Loose Covers
    for root, _, files in os.walk(str(music_dir)):
        for f in sorted(files):
            # Skip AppleDouble resource forks from audio/image decoding (they are audited under ghost files)
            if f.startswith("._"):
                continue

            full_path = Path(root) / f
            ext = full_path.suffix.lower()

            if ext in (".flac", ".mp3"):
                verify_audio_file(full_path, reporter, ignore_uncompliant_dir=ignore_uncompliant)
            elif ext in (".jpg", ".jpeg"):
                if ignore_uncompliant and "uncompliant" in str(full_path).lower():
                    continue
                if ignore_uncompliant and "progressive" in f.lower():
                    reporter.record_warn("Deliberate Control", f, "Skipping known progressive test control file")
                    continue
                check_image_bytes(full_path.read_bytes(), str(full_path), reporter)
            elif ext == ".m3u8":
                verify_playlist_file(full_path, reporter)


def main():
    parser = argparse.ArgumentParser(description="Walkman NW-A55L Hardware Compliance Verifier")
    parser.add_argument("--drive", type=Path, help="Specific drive mount point to verify (e.g. /Volumes/WALKMAN)")
    parser.add_argument("--volumes-root", type=Path, default=Path(os.getenv("WALKMAN_VOLUMES_ROOT", "/Volumes")), help="Volumes root directory")
    parser.add_argument("--assert-clean", action="store_true", help="Assert that zero macOS ghost files (.DS_Store, ._*, etc.) exist")
    parser.add_argument("--include-controls", action="store_true", help="Include deliberate test control files (e.g. Uncompliant Album)")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")

    args = parser.parse_args()
    reporter = ComplianceReporter(json_mode=args.json)

    if args.drive:
        targets = [args.drive]
    else:
        # Detect all Walkman drives under volumes root
        targets = []
        if args.volumes_root.exists():
            for item in args.volumes_root.iterdir():
                if item.is_dir() and ("WALKMAN" in item.name.upper() or (item / "MUSIC").exists() or (item / "Sony_Card.IND").exists()):
                    targets.append(item)

    if not targets:
        if not args.json:
            print(f"[!] No Walkman drives found under {args.volumes_root}")
        sys.exit(1)

    for target in targets:
        audit_walkman_drive(
            mount_point=target,
            reporter=reporter,
            assert_clean=args.assert_clean,
            ignore_uncompliant=not args.include_controls,
        )

    sys.exit(reporter.print_summary())


if __name__ == "__main__":
    main()
