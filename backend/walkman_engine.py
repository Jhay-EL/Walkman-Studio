"""
Walkman Studio Engine for Sony Walkman NW-A55L (macOS Apple Silicon).
Implements all strict hardware rules for non-Android Sony Walkman DAPs:
1. Baseline RGB JPEG Only (max 800x800, non-progressive, subsampling=0).
2. ID3v2.3 Enforcement (v2_version=3, UTF-16 encoding=1, never ID3v2.4).
3. FLAC Artwork & Vorbis Tags (mutagen.flac.Picture type=3 Front Cover, image/jpeg).
4. FAT32 / exFAT Path Sanitization (strip <>:"/\\|?* and trailing dots/spaces).
5. Playlist Format (.M3U8 in /MUSIC/, relative POSIX paths, CRLF \\r\\n).
6. macOS Ghost File Cleanup (dot_clean -m, remove .DS_Store, ._*, .Spotlight-V100, .Trashes).
7. Safe macOS Ejection.
"""

from __future__ import annotations

import io
import os
import re
import shutil
import sqlite3
import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import mutagen
import psutil
from mutagen.flac import FLAC, Picture
from mutagen.id3 import (
    APIC,
    ID3,
    TALB,
    TCON,
    TIT2,
    TPE1,
    TRCK,
    TYER,
    ID3NoHeaderError,
)
from PIL import Image

FFMPEG_PATH = "/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else (shutil.which("ffmpeg") or "ffmpeg")


# ---------------------------------------------------------------------------
# Hardware Constraint 4: FAT32 / exFAT Path Sanitization
# ---------------------------------------------------------------------------
def sanitize_filename(name: str, max_length: int = 120) -> str:
    """
    Sanitize artist, album, and track names for FAT32 / exFAT filesystems.
    Strips illegal characters: < > : " / \\ | ? * and control chars (0x00-0x1F).
    Strips trailing dots and spaces which corrupt FAT32 directory tables.
    """
    if not name:
        return "Unknown"
    # Replace illegal characters with underscore or remove them
    sanitized = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "", str(name))
    # Strip leading and trailing periods and spaces
    sanitized = sanitized.strip(". ")
    if not sanitized:
        return "Unknown"
    return sanitized[:max_length].strip(". ")


def get_target_track_path(music_root: str | Path, artist: str, album: str, track_num: int | str, title: str, ext: str) -> Path:
    """
    Constructs the canonical NW-A55L target file path:
    /MUSIC/<Sanitized Artist>/<Sanitized Album>/<TrackNumber> - <Sanitized Title>.<ext>
    """
    clean_artist = sanitize_filename(artist) or "Unknown Artist"
    clean_album = sanitize_filename(album) or "Unknown Album"
    clean_title = sanitize_filename(title) or "Unknown Track"
    
    try:
        t_int = int(str(track_num).split("/")[0])
        track_prefix = f"{t_int:02d}"
    except (ValueError, IndexError):
        track_prefix = "01"

    clean_ext = ext.lstrip(".").lower()
    filename = f"{track_prefix} - {clean_title}.{clean_ext}"
    return Path(music_root) / clean_artist / clean_album / filename


# ---------------------------------------------------------------------------
# Hardware Constraint 1: Baseline RGB JPEG Encoding
# ---------------------------------------------------------------------------
def encode_baseline_jpeg(image_data: bytes | io.BytesIO | str | Path, max_dimension: int = 800, quality: int = 92) -> bytes:
    """
    Converts image data to strict Baseline RGB JPEG for the NW-A55L:
    - Mode converted strictly to RGB (rejecting CMYK, RGBA, Palette).
    - Resized to fit max_dimension (max 800x800) preserving aspect ratio.
    - Saved with progressive=False and subsampling=0 (4:4:4).
    """
    if isinstance(image_data, (str, Path)):
        img = Image.open(image_data)
    elif isinstance(image_data, bytes):
        img = Image.open(io.BytesIO(image_data))
    else:
        img = Image.open(image_data)

    # 1. Convert mode to RGB
    if img.mode != "RGB":
        img = img.convert("RGB")

    # 2. Resize within max_dimension
    if img.width > max_dimension or img.height > max_dimension:
        img.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)

    # 3. Save as Baseline JPEG (non-progressive, subsampling=0)
    output = io.BytesIO()
    img.save(
        output,
        format="JPEG",
        quality=quality,
        progressive=False,
        subsampling=0,
    )
    return output.getvalue()


def is_baseline_rgb_jpeg(image_bytes: bytes, max_dim: int = 800) -> Tuple[bool, str]:
    """Checks whether an image conforms strictly to the NW-A55L Baseline RGB JPEG rule."""
    try:
        with Image.open(io.BytesIO(image_bytes)) as img:
            if img.format != "JPEG":
                return False, f"Format is {img.format}, not JPEG"
            if img.mode != "RGB":
                return False, f"Mode is {img.mode}, must be RGB (no CMYK or RGBA)"
            if img.info.get("progressive", False):
                return False, "Image is Progressive JPEG (must be Baseline)"
            if img.width > max_dim or img.height > max_dim:
                return False, f"Dimensions {img.width}x{img.height} exceed {max_dim}x{max_dim}"
            return True, "Valid NW-A55L Baseline RGB JPEG"
    except Exception as e:
        return False, f"Invalid image: {e}"


# ---------------------------------------------------------------------------
# Hardware Constraint 2 & 3: Metadata Tagging (ID3v2.3 UTF-16 & FLAC Vorbis)
# ---------------------------------------------------------------------------
def write_track_metadata(
    file_path: str | Path,
    title: Optional[str] = None,
    artist: Optional[str] = None,
    album: Optional[str] = None,
    track_number: Optional[int | str] = None,
    year: Optional[int | str] = None,
    genre: Optional[str] = None,
    cover_art_bytes: Optional[bytes] = None,
) -> None:
    """
    Applies tags and cover art strictly conforming to Sony NW-A55L rules:
    - MP3: Strictly ID3v2.3 (v2_version=3) with UTF-16 (encoding=1).
    - FLAC: Vorbis comments and Picture block type=3 with image/jpeg.
    """
    path = Path(file_path)
    ext = path.suffix.lower()

    baseline_art = None
    if cover_art_bytes:
        baseline_art = encode_baseline_jpeg(cover_art_bytes)

    if ext == ".flac":
        _write_flac_tags(path, title, artist, album, track_number, year, genre, baseline_art)
    elif ext == ".mp3":
        _write_mp3_id3v23(path, title, artist, album, track_number, year, genre, baseline_art)
    else:
        raise ValueError(f"Unsupported file format for Walkman metadata: {ext}")


def _write_flac_tags(
    path: Path,
    title: Optional[str],
    artist: Optional[str],
    album: Optional[str],
    track_number: Optional[int | str],
    year: Optional[int | str],
    genre: Optional[str],
    baseline_art: Optional[bytes],
) -> None:
    audio = FLAC(str(path))

    if title is not None:
        audio["title"] = [str(title)]
    if artist is not None:
        audio["artist"] = [str(artist)]
    if album is not None:
        audio["album"] = [str(album)]
    if track_number is not None:
        audio["tracknumber"] = [str(track_number)]
    if year is not None:
        audio["date"] = [str(year)]
    if genre is not None:
        audio["genre"] = [str(genre)]

    if baseline_art:
        audio.clear_pictures()
        pic = Picture()
        pic.type = 3  # Front Cover
        pic.mime = "image/jpeg"
        pic.desc = "Front Cover"
        pic.data = baseline_art
        with Image.open(io.BytesIO(baseline_art)) as img:
            pic.width, pic.height = img.size
            pic.depth = 24
        audio.add_picture(pic)

    audio.save()


def _write_mp3_id3v23(
    path: Path,
    title: Optional[str],
    artist: Optional[str],
    album: Optional[str],
    track_number: Optional[int | str],
    year: Optional[int | str],
    genre: Optional[str],
    baseline_art: Optional[bytes],
) -> None:
    try:
        tags = ID3(str(path))
    except ID3NoHeaderError:
        tags = ID3()

    # Clear existing tags if needed or update directly with encoding=1 (UTF-16)
    if title is not None:
        tags.setall("TIT2", [TIT2(encoding=1, text=str(title))])
    if artist is not None:
        tags.setall("TPE1", [TPE1(encoding=1, text=str(artist))])
    if album is not None:
        tags.setall("TALB", [TALB(encoding=1, text=str(album))])
    if track_number is not None:
        tags.setall("TRCK", [TRCK(encoding=1, text=str(track_number))])
    if year is not None:
        tags.setall("TYER", [TYER(encoding=1, text=str(year))])
    if genre is not None:
        tags.setall("TCON", [TCON(encoding=1, text=str(genre))])

    if baseline_art:
        tags.setall(
            "APIC",
            [
                APIC(
                    encoding=1,
                    mime="image/jpeg",
                    type=3,  # Front cover
                    desc="Front Cover",
                    data=baseline_art,
                )
            ],
        )

    # Strictly enforce ID3v2.3
    tags.save(str(path), v2_version=3)


def extract_cover_art(file_path: str | Path) -> Optional[bytes]:
    """Extracts front cover art from FLAC or MP3, returning raw bytes or None."""
    path = Path(file_path)
    ext = path.suffix.lower()

    if ext == ".flac":
        try:
            audio = FLAC(str(path))
            for pic in audio.pictures:
                if pic.type == 3 or len(audio.pictures) == 1:
                    return pic.data
        except Exception:
            pass
    elif ext == ".mp3":
        try:
            tags = ID3(str(path))
            for frame in tags.getall("APIC"):
                if frame.type == 3 or len(tags.getall("APIC")) == 1:
                    return frame.data
        except Exception:
            pass

    # Fallback to album folder image (folder.jpg, cover.jpg, etc.)
    parent = path.parent
    for cand in ["folder.jpg", "cover.jpg", "front.jpg", "folder.png", "cover.png"]:
        cand_path = parent / cand
        if cand_path.exists():
            try:
                return cand_path.read_bytes()
            except Exception:
                pass
    return None


# ---------------------------------------------------------------------------
# Hardware Constraint 5: Playlist Format (.M3U8 with CRLF in /MUSIC/)
# ---------------------------------------------------------------------------
def write_walkman_playlist(drive_music_dir: str | Path, playlist_name: str, relative_tracks: List[str]) -> Path:
    """
    Creates an .m3u8 playlist inside /MUSIC/:
    - Uses relative POSIX paths (e.g. Artist/Album/01 - Track.flac).
    - Enforces CRLF (\\r\\n) line endings required by Sony NW-A55L hardware.
    """
    clean_name = sanitize_filename(playlist_name)
    if not clean_name.lower().endswith(".m3u8"):
        clean_name += ".m3u8"

    playlist_path = Path(drive_music_dir) / clean_name
    
    lines = ["#EXTM3U"]
    for track in relative_tracks:
        # Normalize to POSIX path
        posix_rel = track.replace("\\", "/").lstrip("/")
        lines.append(posix_rel)

    # Join strictly with CRLF
    content = "\r\n".join(lines) + "\r\n"
    playlist_path.write_bytes(content.encode("utf-8"))
    return playlist_path


def read_walkman_playlist(playlist_path: str | Path) -> List[str]:
    """Reads a walkman .m3u8 playlist and returns the list of track paths."""
    path = Path(playlist_path)
    if not path.exists():
        return []
    content = path.read_bytes().decode("utf-8", errors="replace")
    tracks = []
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            tracks.append(line)
    return tracks


def rename_walkman_playlist(drive_music_dir: str | Path, old_playlist_name: str, new_playlist_name: str) -> Path:
    """
    Renames an .m3u8 playlist inside /MUSIC/ on the Walkman drive.
    Cleans up old and new companion AppleDouble ._ files.
    """
    music_dir = Path(drive_music_dir)
    old_clean = sanitize_filename(old_playlist_name)
    if not old_clean.lower().endswith((".m3u8", ".m3u")):
        old_clean += ".m3u8"

    old_path = music_dir / old_clean
    if not old_path.exists():
        old_path = music_dir / old_playlist_name
        if not old_path.exists():
            raise FileNotFoundError(f"Playlist '{old_playlist_name}' not found")

    new_clean = sanitize_filename(new_playlist_name)
    if not new_clean or new_clean == "Unknown":
        raise ValueError("Playlist name cannot be empty")
    if not new_clean.lower().endswith((".m3u8", ".m3u")):
        new_clean += ".m3u8"

    new_path = music_dir / new_clean
    if new_path == old_path:
        return new_path

    if new_path.exists() and new_path.name.lower() != old_path.name.lower():
        raise FileExistsError(f"A playlist named '{new_clean}' already exists")

    if new_path.name.lower() == old_path.name.lower():
        temp_path = music_dir / f".tmp_rename_{old_clean}"
        old_path.rename(temp_path)
        temp_path.rename(new_path)
    else:
        old_path.rename(new_path)

    # Clean companion dotfiles
    old_dot = music_dir / f"._{old_path.name}"
    if old_dot.exists():
        try:
            old_dot.unlink()
        except OSError:
            pass

    new_dot = music_dir / f"._{new_path.name}"
    if new_dot.exists():
        try:
            new_dot.unlink()
        except OSError:
            pass

    return new_path


# ---------------------------------------------------------------------------
# Hardware Constraint 6: macOS Ghost File Cleanup & Unmount
# ---------------------------------------------------------------------------
def clean_macos_ghost_files(mount_point: str | Path) -> Dict[str, Any]:
    """
    Purges macOS metadata pollution from FAT32 / exFAT Walkman storage:
    1. Runs `dot_clean -m` to merge AppleDouble metadata.
    2. Deletes .DS_Store, ._* AppleDouble files, .Spotlight-V100, .Trashes, .fseventsd.
    """
    mount = Path(mount_point)
    if not mount.exists():
        return {"success": False, "error": f"Path not found: {mount}"}

    results = {
        "dot_clean_run": False,
        "deleted_files": [],
        "deleted_dirs": [],
        "errors": [],
    }

    # 1. Run dot_clean -m
    try:
        proc = subprocess.run(["dot_clean", "-m", str(mount)], capture_output=True, text=True, check=False)
        results["dot_clean_run"] = (proc.returncode == 0)
        if proc.returncode != 0 and proc.stderr:
            results["errors"].append(f"dot_clean: {proc.stderr.strip()}")
    except Exception as e:
        results["errors"].append(f"dot_clean error: {e}")

    # 2. Recursively delete macOS ghost files and directories
    target_names = {".ds_store"}
    target_prefixes = ("._",)
    target_dir_names = {".spotlight-v100", ".trashes", ".fseventsd"}

    for root, dirs, files in os.walk(str(mount), topdown=False):
        for f in files:
            f_lower = f.lower()
            if f_lower in target_names or f.startswith(target_prefixes):
                full_path = os.path.join(root, f)
                try:
                    os.unlink(full_path)
                    results["deleted_files"].append(full_path)
                except Exception as e:
                    results["errors"].append(f"Failed deleting {full_path}: {e}")

        for d in dirs:
            if d.lower() in target_dir_names:
                full_path = os.path.join(root, d)
                try:
                    shutil.rmtree(full_path, ignore_errors=True)
                    results["deleted_dirs"].append(full_path)
                except Exception as e:
                    results["errors"].append(f"Failed removing dir {full_path}: {e}")

    results["success"] = len(results["errors"]) == 0
    return results


def unmount_walkman_drive(mount_point: str | Path) -> Dict[str, Any]:
    """Safely ejects / unmounts the Walkman volume using macOS diskutil."""
    try:
        proc = subprocess.run(["diskutil", "unmount", str(mount_point)], capture_output=True, text=True, check=False)
        if proc.returncode == 0:
            return {"success": True, "message": proc.stdout.strip()}
        else:
            # Try diskutil unmountDisk if partition unmount failed
            proc2 = subprocess.run(["diskutil", "unmountDisk", str(mount_point)], capture_output=True, text=True, check=False)
            return {
                "success": proc2.returncode == 0,
                "message": proc2.stdout.strip() if proc2.returncode == 0 else proc2.stderr.strip(),
            }
    except Exception as e:
        return {"success": False, "error": str(e)}


# ---------------------------------------------------------------------------
# Audio Conversion via FFmpeg
# ---------------------------------------------------------------------------
def convert_audio(
    source_path: str | Path,
    dest_path: str | Path,
    preset: str = "flac_16",
    bitrate: str = "320k",
) -> None:
    """
    Transcodes audio to target destination using native FFmpeg:
    - preset 'flac_16': 16-bit FLAC (standard lossless)
    - preset 'flac_24': 24-bit FLAC (high-resolution lossless)
    - preset 'mp3_320': 320kbps CBR MP3
    - preset 'copy': direct stream copy if format matches
    """
    src = Path(source_path)
    dst = Path(dest_path)
    dst.parent.mkdir(parents=True, exist_ok=True)

    cmd = [FFMPEG_PATH, "-y", "-i", str(src)]

    if preset == "copy":
        cmd.extend(["-c:a", "copy"])
    elif preset == "flac_16":
        cmd.extend(["-c:a", "flac", "-sample_fmt", "s16"])
    elif preset == "flac_24":
        cmd.extend(["-c:a", "flac", "-sample_fmt", "s32"])
    elif preset == "mp3_320":
        cmd.extend(["-c:a", "libmp3lame", "-b:a", bitrate])
    else:
        # Default fallback
        cmd.extend(["-c:a", "flac"])

    # Suppress video/album art streams during ffmpeg transcode so we can cleanly
    # embed the strict NW-A55L Baseline JPEG using Mutagen
    cmd.extend(["-vn", str(dst)])

    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"FFmpeg error: {proc.stderr}")


# ---------------------------------------------------------------------------
# Drive Detection & Virtual Walkman Simulation
# ---------------------------------------------------------------------------
VIRTUAL_DIR = Path.home() / ".walkman_virtual"

@dataclass
class WalkmanDrive:
    id: str
    name: str
    mount_point: str
    type: str  # 'internal' | 'microsd' | 'virtual'
    total_bytes: int
    used_bytes: int
    free_bytes: int
    percent_used: float
    has_cfw: bool
    music_dir: str


def detect_walkman_drives(allow_virtual: bool = False) -> List[Dict[str, Any]]:
    """
    Detects real mounted Sony Walkman volumes (/Volumes/WALKMAN and MicroSD).
    Virtual simulation drives are only loaded if explicitly requested with allow_virtual=True.
    """
    drives = []
    volumes_dir = Path(os.getenv("WALKMAN_VOLUMES_ROOT", "/Volumes"))

    system_volumes = {"MACINTOSH HD", "RECOVERY", "PREBOOT", "VM", "UPDATE"}

    if volumes_dir.exists():
        candidates = []
        for vol in volumes_dir.iterdir():
            if not vol.is_dir() or vol.is_symlink():
                continue
            vol_name = vol.name.upper()
            if vol_name in system_volumes or vol.name.endswith(".dmg"):
                continue
            candidates.append(vol)

        # 1. First pass: look for internal WALKMAN
        has_internal = any(
            ("WALKMAN" in v.name.upper() or v.name.upper().startswith("NW-"))
            and "SD" not in v.name.upper()
            and "MICROSD" not in v.name.upper()
            for v in candidates
        )

        for vol in candidates:
            vol_name = vol.name.upper()

            is_internal = ("WALKMAN" in vol_name or vol_name.startswith("NW-")) and ("SD" not in vol_name and "MICROSD" not in vol_name)
            
            # Capability XML validation
            xml_file = vol / "default-capability.xml"
            xml_upper = vol / "DEFAULT-CAPABILITY.XML"
            xml_target = xml_file if xml_file.is_file() else (xml_upper if xml_upper.is_file() else None)
            xml_exists = False
            if xml_target:
                try:
                    c = xml_target.read_text(encoding="latin-1").lower()
                    if "sony" in c or "walkman" in c or "nw-" in c:
                        xml_exists = True
                except Exception:
                    pass

            devicon_exists = (vol / "DevIcon.fil").exists() or (vol / "DEVICON.FIL").exists()
            sony_card_exists = (
                (vol / "Sony_Card.IND").exists()
                or (vol / "SONY_CARD.IND").exists()
                or (vol / "sony_card.ind").exists()
            )
            music_exists = (vol / "MUSIC").is_dir() or (vol / "Music").is_dir()
            cfw_exists = (vol / "CFW").is_dir()

            # Authentic Sony Walkman Android package markers
            sony_android_pkg_exists = (
                (vol / "Android" / "data" / "com.sony.walkman").is_dir()
                or (vol / "Android" / "data" / "com.sony.snei.walkman").is_dir()
                or (vol / "Android" / "media" / "com.sony.walkman").is_dir()
                or (vol / "Android" / "data" / "com.sony.walkman.soundsettings").is_dir()
            )

            # Secondary companion SD card only when an authentic internal Walkman is mounted simultaneously
            is_companion_sd = has_internal and not is_internal and (
                "SD" in vol_name or "CARD" in vol_name or sony_card_exists or music_exists
            )

            # Strict authentic Walkman verification
            is_authentic_walkman = (
                xml_exists
                or (is_internal and (music_exists or devicon_exists))
                or sony_card_exists
                or (devicon_exists and music_exists)
                or (sony_android_pkg_exists and music_exists)
                or (vol_name.startswith("NW-") and music_exists)
                or is_companion_sd
            )

            if is_authentic_walkman:
                try:
                    usage = psutil.disk_usage(str(vol))
                    d_type = "internal" if is_internal else "microsd"
                    resolved_music = (vol / "Music") if (vol / "Music").is_dir() else (vol / "MUSIC")
                    drives.append({
                        "id": vol.name,
                        "name": vol.name if is_internal else f"{vol.name} (MicroSD)",
                        "mount_point": str(vol),
                        "type": d_type,
                        "total_bytes": usage.total,
                        "used_bytes": usage.used,
                        "free_bytes": usage.free,
                        "percent_used": usage.percent,
                        "has_cfw": cfw_exists,
                        "music_dir": str(resolved_music),
                    })
                except Exception:
                    continue

    # Fallback to Virtual Walkman if no physical drive detected
    if not drives and allow_virtual:
        init_virtual_walkman()
        for v_name in ["WALKMAN", "MICROSD"]:
            v_path = VIRTUAL_DIR / v_name
            if v_path.exists():
                try:
                    usage = psutil.disk_usage(str(v_path))
                    drives.append({
                        "id": f"virtual_{v_name.lower()}",
                        "name": f"Virtual {v_name} (Simulation)",
                        "mount_point": str(v_path),
                        "type": "internal" if v_name == "WALKMAN" else "microsd",
                        "total_bytes": 16 * 1024 * 1024 * 1024 if v_name == "WALKMAN" else 128 * 1024 * 1024 * 1024,
                        "used_bytes": usage.used,
                        "free_bytes": usage.free,
                        "percent_used": usage.percent,
                        "has_cfw": True,
                        "music_dir": str(v_path / "MUSIC"),
                    })
                except Exception:
                    continue

    return drives


def detect_walkman_device_info(drives: Optional[List[Dict[str, Any]]] = None) -> Optional[Dict[str, Any]]:
    """
    Accurately detects the connected non-Android Sony Walkman model from default-capability.xml.
    Resolves specific series, models (NW-A55L, NW-A55, NW-ZX300, etc.), firmware, and specs.
    """
    if drives is None:
        drives = detect_walkman_drives(allow_virtual=True)

    if not drives:
        return None

    internal = next((d for d in drives if d.get("type") == "internal"), drives[0])
    mount_point = Path(internal["mount_point"])
    xml_path = mount_point / "default-capability.xml"

    xml_content = None
    if xml_path.exists():
        try:
            xml_content = xml_path.read_text(encoding="latin-1")
        except Exception:
            pass

    if not xml_content:
        # Check other drives
        for d in drives:
            p = Path(d["mount_point"]) / "default-capability.xml"
            if p.exists():
                try:
                    xml_content = p.read_text(encoding="latin-1")
                    break
                except Exception:
                    pass

    has_cfw = any(d.get("has_cfw") for d in drives)
    capacity_gb = internal.get("total_bytes", 0) / (1024 ** 3)

    if xml_content:
        import re
        def get_tag(tag: str, default: str = "") -> str:
            m = re.search(rf"<{tag}>(.*?)</{tag}>", xml_content, re.DOTALL)
            return m.group(1).strip() if m else default

        model_raw = get_tag("model", "NW-A50Series")
        marketing_name = get_tag("marketingname", f"WALKMAN {model_raw}")
        vendor = get_tag("vendor", "Sony Corporation")
        firmware_ver = get_tag("firmwareversion", "1.02")
        width = get_tag("width", "800")
        height = get_tag("height", "480")

        upper = model_raw.upper()
        is_android = any(k in upper for k in ["A100", "A105", "A106", "A107", "A300", "A306", "A307", "ZX500", "ZX505", "ZX507", "ZX700", "ZX706", "ZX707", "WM1AM2", "WM1ZM2"])

        if "A300" in upper or "A306" in upper or "A307" in upper:
            specific = "NW-A306" if capacity_gb < 45 else "NW-A307"
            series = "NW-A300 Series"
            width, height = "1280", "720"
        elif "A100" in upper or "A105" in upper or "A106" in upper:
            specific = "NW-A105" if capacity_gb < 25 else ("NW-A106" if capacity_gb < 45 else "NW-A107")
            series = "NW-A100 Series"
            width, height = "1280", "720"
        elif "ZX700" in upper or "ZX706" in upper or "ZX707" in upper:
            specific = "NW-ZX706" if capacity_gb < 45 else "NW-ZX707"
            series = "NW-ZX700 Series"
            width, height = "1280", "720"
        elif "ZX500" in upper or "ZX505" in upper or "ZX507" in upper:
            specific = "NW-ZX505" if capacity_gb < 25 else "NW-ZX507"
            series = "NW-ZX500 Series"
            width, height = "1280", "720"
        elif "WM1AM2" in upper:
            specific = "NW-WM1AM2"
            series = "NW-WM1 Series M2"
            width, height = "1280", "720"
        elif "WM1ZM2" in upper:
            specific = "NW-WM1ZM2"
            series = "NW-WM1 Series M2"
            width, height = "1280", "720"
        elif "A50" in upper:
            specific = "NW-A55L" if capacity_gb < 20 else ("NW-A56" if capacity_gb < 45 else "NW-A57")
            series = "NW-A50 Series"
        elif "A40" in upper:
            specific = "NW-A45" if capacity_gb < 20 else ("NW-A46" if capacity_gb < 45 else "NW-A47")
            series = "NW-A40 Series"
        elif "A30" in upper:
            specific = "NW-A35" if capacity_gb < 20 else ("NW-A36" if capacity_gb < 45 else "NW-A37")
            series = "NW-A30 Series"
        elif "ZX300" in upper:
            specific = "NW-ZX300A" if capacity_gb < 25 else "NW-ZX300"
            series = "NW-ZX300 Series"
        elif "WM1" in upper:
            specific = "NW-WM1A" if capacity_gb < 180 else "NW-WM1Z"
            series = "NW-WM1 Signature Series"
        else:
            specific = model_raw
            series = model_raw

        display_name = f"Sony Walkman {specific}" + (" (Walkman One CFW)" if has_cfw else "")

        return {
            "model_raw": model_raw,
            "marketing_name": marketing_name,
            "display_name": display_name,
            "series_name": series,
            "specific_model": specific,
            "vendor": vendor,
            "firmware_version": firmware_ver,
            "is_non_android": not is_android,
            "has_cfw": has_cfw,
            "display_resolution": f"{width}x{height}",
            "internal_capacity_gb": round(capacity_gb, 1),
        }

    # If no capability XML is found, verify authentic Sony hardware indicators
    is_virtual = any("virtual" in d.get("id", "").lower() or ".walkman_virtual" in d.get("mount_point", "") for d in drives)
    if is_virtual:
        return {
            "model_raw": "NW-A50Series",
            "marketing_name": "WALKMAN NW-A50Series",
            "display_name": "Sony Walkman NW-A55L" + (" (Walkman One CFW)" if has_cfw else ""),
            "series_name": "NW-A50 Series",
            "specific_model": "NW-A55L",
            "vendor": "Sony Corporation",
            "firmware_version": "1.02",
            "is_non_android": True,
            "has_cfw": has_cfw,
            "display_resolution": "800x480",
            "internal_capacity_gb": round(capacity_gb, 1),
        }

    # 1. Check for Sony Android Walkman packages (com.sony.walkman / com.sony.snei.walkman)
    for d in drives:
        mp = Path(d["mount_point"])
        has_sony_pkg = (
            (mp / "Android" / "data" / "com.sony.walkman").is_dir()
            or (mp / "Android" / "data" / "com.sony.snei.walkman").is_dir()
            or (mp / "Android" / "media" / "com.sony.walkman").is_dir()
            or (mp / "Android" / "data" / "com.sony.walkman.soundsettings").is_dir()
        )
        if has_sony_pkg:
            return {
                "model_raw": "NW-A300Series",
                "marketing_name": "WALKMAN NW-A300Series",
                "display_name": "Sony Walkman NW-A306",
                "series_name": "NW-A300 Series",
                "specific_model": "NW-A306",
                "vendor": "Sony Corporation",
                "firmware_version": "Android Walkman OS",
                "is_non_android": False,
                "has_cfw": False,
                "display_resolution": "1280x720",
                "internal_capacity_gb": round(capacity_gb, 1),
            }

    # 2. Check for authentic Sony non-Android markers (Sony_Card.IND, DevIcon.fil, or WALKMAN / NW- volume)
    for d in drives:
        mp = Path(d["mount_point"])
        has_sony_ind = (mp / "Sony_Card.IND").exists() or (mp / "SONY_CARD.IND").exists() or (mp / "sony_card.ind").exists()
        has_devicon = (mp / "DevIcon.fil").exists() or (mp / "DEVICON.FIL").exists()
        vol_name = mp.name.upper()
        if has_sony_ind or has_devicon or "WALKMAN" in vol_name or vol_name.startswith("NW-"):
            return {
                "model_raw": "NW-A50Series",
                "marketing_name": "WALKMAN NW-A50Series",
                "display_name": "Sony Walkman NW-A55L" + (" (Walkman One CFW)" if has_cfw else ""),
                "series_name": "NW-A50 Series",
                "specific_model": "NW-A55L",
                "vendor": "Sony Corporation",
                "firmware_version": "1.02",
                "is_non_android": True,
                "has_cfw": has_cfw,
                "display_resolution": "800x480",
                "internal_capacity_gb": round(capacity_gb, 1),
            }

    # Non-Sony drive / unsupported device: strictly reject to prevent false positives
    return None


def init_virtual_walkman() -> None:
    """Initializes simulated Walkman internal and microSD directories for testing."""
    for v_name in ["WALKMAN", "MICROSD"]:
        v_path = VIRTUAL_DIR / v_name
        (v_path / "MUSIC").mkdir(parents=True, exist_ok=True)
        cfw_dir = v_path / "CFW"
        cfw_dir.mkdir(parents=True, exist_ok=True)
        settings_file = cfw_dir / "settings.txt"
        if not settings_file.exists():
            settings_file.write_text(DEFAULT_CFW_SETTINGS, encoding="utf-8")


# ---------------------------------------------------------------------------
# Library Scanner (High-Performance SQLite Cached)
# ---------------------------------------------------------------------------
DB_CACHE_PATH = Path.home() / ".walkman_library_cache.db"

def _get_cache_conn():
    conn = sqlite3.connect(str(DB_CACHE_PATH))
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tracks_cache (
            full_path TEXT PRIMARY KEY,
            mtime REAL,
            size INTEGER,
            format TEXT,
            title TEXT,
            artist TEXT,
            album TEXT,
            track_num TEXT,
            year TEXT,
            genre TEXT,
            duration_seconds REAL,
            bitrate_kbps INTEGER,
            sample_rate INTEGER,
            bits_per_sample INTEGER,
            has_artwork INTEGER,
            relative_path TEXT
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_cache_path ON tracks_cache(full_path)")
    for col in [
        ("date_added", "REAL DEFAULT 0"),
        ("is_senseme", "INTEGER DEFAULT 0"),
        ("senseme_bpm", "REAL DEFAULT 0"),
        ("senseme_valence", "REAL DEFAULT 0"),
        ("senseme_arousal", "REAL DEFAULT 0"),
        ("senseme_channels", "TEXT DEFAULT ''"),
        ("senseme_highlight_sec", "REAL DEFAULT 0"),
    ]:
        try:
            conn.execute(f"ALTER TABLE tracks_cache ADD COLUMN {col[0]} {col[1]}")
        except sqlite3.OperationalError:
            pass
    conn.commit()
    return conn


def _enrich_library_worker(pending_paths: List[str]):
    """Background thread worker that sequentially enriches tracks with exact mutagen duration/bitrate."""
    if not pending_paths:
        return
    try:
        conn = _get_cache_conn()
        updates = []
        for full_path in pending_paths:
            if not os.path.exists(full_path):
                continue
            ext = os.path.splitext(full_path)[1].lower()
            try:
                duration = 0.0
                bitrate = 0
                sample_rate = 44100
                bits_per_sample = 16
                has_art = False

                if ext == ".flac":
                    flac = FLAC(full_path)
                    duration = getattr(flac.info, "length", 0.0)
                    bitrate = getattr(flac.info, "bitrate", 0)
                    sample_rate = getattr(flac.info, "sample_rate", 44100)
                    bits_per_sample = getattr(flac.info, "bits_per_sample", 16)
                    has_art = len(flac.pictures) > 0
                elif ext == ".mp3":
                    id3 = ID3(full_path)
                    has_art = len(id3.getall("APIC")) > 0
                    mut = mutagen.File(full_path)
                    if mut and hasattr(mut, "info"):
                        duration = getattr(mut.info, "length", 0.0)
                        bitrate = getattr(mut.info, "bitrate", 0)
                        sample_rate = getattr(mut.info, "sample_rate", 44100)

                is_sm = 0
                sm_bpm = 0.0
                sm_val = 0.0
                sm_aro = 0.0
                sm_ch = ""
                sm_hl = 0.0
                try:
                    from backend import senseme_engine
                    sm_res = senseme_engine.is_senseme_analyzed(full_path)
                    if sm_res.get("is_analyzed"):
                        is_sm = 1
                        sm_bpm = sm_res.get("bpm", 0.0)
                        sm_val = sm_res.get("valence", 0.0)
                        sm_aro = sm_res.get("arousal", 0.0)
                        sm_ch = ",".join(sm_res.get("channels", []))
                        sm_hl = sm_res.get("highlight_sec", 0.0)
                except Exception:
                    pass

                updates.append((
                    round(duration, 2),
                    round(bitrate / 1000) if bitrate else 0,
                    sample_rate,
                    bits_per_sample,
                    1 if has_art else 0,
                    is_sm,
                    sm_bpm,
                    sm_val,
                    sm_aro,
                    sm_ch,
                    sm_hl,
                    full_path,
                ))
                if len(updates) >= 50:
                    conn.executemany("""
                        UPDATE tracks_cache SET
                            duration_seconds = ?,
                            bitrate_kbps = ?,
                            sample_rate = ?,
                            bits_per_sample = ?,
                            has_artwork = CASE WHEN has_artwork = 1 THEN 1 ELSE ? END,
                            is_senseme = ?,
                            senseme_bpm = ?,
                            senseme_valence = ?,
                            senseme_arousal = ?,
                            senseme_channels = ?,
                            senseme_highlight_sec = ?
                        WHERE full_path = ?
                    """, updates)
                    conn.commit()
                    updates = []
            except Exception:
                continue

        if updates:
            conn.executemany("""
                UPDATE tracks_cache SET
                    duration_seconds = ?,
                    bitrate_kbps = ?,
                    sample_rate = ?,
                    bits_per_sample = ?,
                    has_artwork = CASE WHEN has_artwork = 1 THEN 1 ELSE ? END,
                    is_senseme = ?,
                    senseme_bpm = ?,
                    senseme_valence = ?,
                    senseme_arousal = ?,
                    senseme_channels = ?,
                    senseme_highlight_sec = ?
                WHERE full_path = ?
            """, updates)
            conn.commit()
        conn.close()
    except Exception:
        pass


def scan_walkman_library(drive_mount: str | Path) -> Dict[str, Any]:
    """
    High-performance library scanner for Sony Walkman storage.
    Uses fast directory hierarchy parsing, SQLite caching, and background tag enrichment
    to handle 10,000+ tracks in sub-second time over USB.
    """
    music_dir = Path(drive_mount) / "MUSIC"
    if not music_dir.exists():
        alt_music = Path(drive_mount) / "Music"
        if alt_music.exists():
            music_dir = alt_music
        else:
            return {"tracks": [], "albums": [], "artists": [], "total_tracks": 0}

    conn = _get_cache_conn()
    cursor = conn.cursor()

    # Read existing cache into memory for instant lookup
    cursor.execute(
        "SELECT full_path, mtime, size, format, title, artist, album, track_num, year, genre, duration_seconds, bitrate_kbps, sample_rate, bits_per_sample, has_artwork, relative_path, is_senseme, senseme_bpm, senseme_valence, senseme_arousal, senseme_channels, senseme_highlight_sec FROM tracks_cache"
    )
    cached_map = {row[0]: row for row in cursor.fetchall()}

    tracks = []
    albums_set = set()
    artists_set = set()
    new_cache_rows = []
    enrich_queue = []

    supported_exts = {".flac", ".mp3", ".m4a", ".alac", ".wav", ".aif", ".aiff", ".dsf", ".dff", ".ape", ".wma"}
    track_num_regex = re.compile(r"^(\d+)[\.\s\-_]+(.*)$")

    for root, _, files in os.walk(str(music_dir)):
        has_folder_art = None

        for f in sorted(files):
            if f.startswith("._") or f.startswith("."):
                continue

            ext = os.path.splitext(f)[1].lower()
            if ext not in supported_exts:
                continue

            full_path = os.path.join(root, f)

            # 1. Fast Cache Hit Check
            cached = cached_map.get(full_path)
            if cached:
                (_, mtime, size, fmt, title, artist, album, track_num, year, genre, duration, bitrate, sample_rate, bits_per_sample, has_art, rel_path) = cached[:16]
                is_sm = cached[16] if len(cached) > 16 else 0
                sm_bpm = cached[17] if len(cached) > 17 else 0.0
                sm_val = cached[18] if len(cached) > 18 else 0.0
                sm_aro = cached[19] if len(cached) > 19 else 0.0
                sm_ch = [c for c in (cached[20] or "").split(",") if c] if len(cached) > 20 else []
                sm_hl = cached[21] if len(cached) > 21 else 0.0

                artists_set.add(artist)
                albums_set.add(f"{artist} - {album}")
                tracks.append({
                    "filename": f,
                    "relative_path": rel_path,
                    "full_path": full_path,
                    "format": fmt,
                    "title": title,
                    "artist": artist,
                    "album": album,
                    "track_num": track_num,
                    "year": year,
                    "genre": genre,
                    "duration_seconds": duration,
                    "bitrate_kbps": bitrate,
                    "sample_rate": sample_rate,
                    "bits_per_sample": bits_per_sample,
                    "has_artwork": bool(has_art),
                    "size_bytes": size,
                    "is_senseme": bool(is_sm),
                    "senseme_bpm": sm_bpm,
                    "senseme_valence": sm_val,
                    "senseme_arousal": sm_aro,
                    "senseme_channels": sm_ch,
                    "senseme_highlight_sec": sm_hl,
                })
                if duration == 0.0:
                    enrich_queue.append(full_path)
                continue

            # 2. Cache Miss: Fast path derivation (<0.5ms per track)
            try:
                st = os.stat(full_path)
                mtime = st.st_mtime
                size = st.st_size
            except Exception:
                mtime = 0.0
                size = 0

            rel_path = os.path.relpath(full_path, str(music_dir))
            parts = Path(rel_path).parts

            if len(parts) >= 3:
                artist = parts[0]
                album = parts[1]
            elif len(parts) == 2:
                artist = "Unknown Artist"
                album = parts[0]
            else:
                artist = "Unknown Artist"
                album = "Unknown Album"

            stem = Path(f).stem
            match = track_num_regex.match(stem)
            if match:
                track_num = match.group(1).lstrip("0") or "1"
                title = match.group(2).strip()
            else:
                track_num = ""
                title = stem

            # Check folder artwork once per directory
            if has_folder_art is None:
                has_folder_art = any(
                    os.path.exists(os.path.join(root, cand))
                    for cand in ["folder.jpg", "cover.jpg", "front.jpg", "Folder.jpg", "Cover.jpg"]
                )

            fmt = ext.lstrip(".").upper()
            artists_set.add(artist)
            albums_set.add(f"{artist} - {album}")

            new_row = (
                full_path,
                mtime,
                size,
                fmt,
                title,
                artist,
                album,
                track_num,
                "",
                "",
                0.0,
                0,
                44100,
                16,
                1 if has_folder_art else 0,
                rel_path,
            )
            new_cache_rows.append(new_row)
            enrich_queue.append(full_path)

            tracks.append({
                "filename": f,
                "relative_path": rel_path,
                "full_path": full_path,
                "format": fmt,
                "title": title,
                "artist": artist,
                "album": album,
                "track_num": track_num,
                "year": "",
                "genre": "",
                "duration_seconds": 0.0,
                "bitrate_kbps": 0,
                "sample_rate": 44100,
                "bits_per_sample": 16,
                "has_artwork": has_folder_art or (ext in (".flac", ".mp3")),
                "size_bytes": size,
            })

    # Batch insert newly discovered tracks into cache
    if new_cache_rows:
        cursor.executemany("""
            INSERT OR REPLACE INTO tracks_cache (
                full_path, mtime, size, format, title, artist, album, track_num,
                year, genre, duration_seconds, bitrate_kbps, sample_rate, bits_per_sample,
                has_artwork, relative_path
            ) VALUES
            (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, new_cache_rows)
        conn.commit()

    conn.close()

    # Trigger background enrichment thread if any tracks need duration/bitrate
    if enrich_queue:
        t = threading.Thread(
            target=_enrich_library_worker,
            args=(enrich_queue,),
            daemon=True,
        )
        t.start()

    return {
        "tracks": tracks,
        "albums": sorted(list(albums_set)),
        "artists": sorted(list(artists_set)),
        "total_tracks": len(tracks),
    }
