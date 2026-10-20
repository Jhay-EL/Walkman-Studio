"""
Unit tests for walkman_engine following strict Sony Walkman NW-A55L hardware rules.
"""

import io
import os
import shutil
import tempfile
from pathlib import Path
from PIL import Image
import mutagen
from mutagen.flac import FLAC
from mutagen.id3 import ID3, APIC

from backend import walkman_engine


def test_sanitize_filename():
    """Rule 4: Strip illegal characters and trailing dots."""
    # Test illegal chars < > : " / \ | ? *
    raw = 'Artist: <The Best> / "Album"? *Track* | 2024.'
    sanitized = walkman_engine.sanitize_filename(raw)
    assert ":" not in sanitized
    assert "<" not in sanitized
    assert ">" not in sanitized
    assert "/" not in sanitized
    assert '"' not in sanitized
    assert "?" not in sanitized
    assert "*" not in sanitized
    assert "|" not in sanitized
    assert not sanitized.endswith(".")
    assert sanitized == "Artist The Best  Album Track  2024"

    # Test trailing dot and spaces
    assert walkman_engine.sanitize_filename("The Beatles...") == "The Beatles"
    assert walkman_engine.sanitize_filename("   Pink Floyd   ") == "Pink Floyd"
    assert walkman_engine.sanitize_filename("") == "Unknown"


def test_target_track_path():
    """Rule 4: Canonical path /MUSIC/Artist/Album/01 - Track.ext"""
    root = "/Volumes/WALKMAN/MUSIC"
    path = walkman_engine.get_target_track_path(
        music_root=root,
        artist="David Bowie: Legacy",
        album="Heroes / 1977?",
        track_num="3",
        title='Heroes "Single Edit"',
        ext=".flac",
    )
    expected = Path(root) / "David Bowie Legacy" / "Heroes  1977" / "03 - Heroes Single Edit.flac"
    assert path == expected


def test_encode_baseline_jpeg():
    """Rule 1: Baseline RGB JPEG Only, max 800x800, subsampling=0, non-progressive."""
    # Create a 1200x1600 RGBA (with alpha transparency) image
    rgba_img = Image.new("RGBA", (1200, 1600), color=(255, 100, 50, 200))
    rgba_bytes = io.BytesIO()
    rgba_img.save(rgba_bytes, format="PNG")
    
    # Encode with walkman_engine
    encoded_bytes = walkman_engine.encode_baseline_jpeg(rgba_bytes.getvalue(), max_dimension=800)
    
    # Verify image properties
    with Image.open(io.BytesIO(encoded_bytes)) as result_img:
        assert result_img.format == "JPEG"
        assert result_img.mode == "RGB"  # Alpha channel stripped
        assert result_img.width <= 800
        assert result_img.height <= 800
        # Preserved aspect ratio 1200:1600 (3:4) -> 600:800
        assert result_img.width == 600
        assert result_img.height == 800
        # Progressive flag must be False
        assert not result_img.info.get("progressive", False)

    valid, msg = walkman_engine.is_baseline_rgb_jpeg(encoded_bytes)
    assert valid is True
    assert "Valid NW-A55L Baseline RGB JPEG" in msg


def test_cmyk_image_conversion():
    """Rule 1: Convert CMYK to RGB."""
    cmyk_img = Image.new("CMYK", (500, 500), color=(100, 50, 0, 10))
    buf = io.BytesIO()
    cmyk_img.save(buf, format="JPEG")

    encoded = walkman_engine.encode_baseline_jpeg(buf.getvalue())
    with Image.open(io.BytesIO(encoded)) as im:
        assert im.mode == "RGB"
        assert not im.info.get("progressive", False)


def test_playlist_crlf_format():
    """Rule 5: .M3U8 playlists must use CRLF (\\r\\n) line endings and relative POSIX paths."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        music_dir = Path(tmp_dir) / "MUSIC"
        music_dir.mkdir()

        tracks = [
            "Pink Floyd/The Wall/01 - In the Flesh.flac",
            "Pink Floyd/The Wall/02 - The Thin Ice.flac",
            "Queen/A Night at the Opera/04 - You're My Best Friend.flac",
        ]
        p_path = walkman_engine.write_walkman_playlist(music_dir, "Rock Classics", tracks)
        assert p_path.exists()
        assert p_path.name == "Rock Classics.m3u8"

        raw_bytes = p_path.read_bytes()
        assert b"\r\n" in raw_bytes
        # Every line ending must be \r\n, not just bare \n
        lines = raw_bytes.split(b"\r\n")
        assert lines[0] == b"#EXTM3U"
        assert lines[1] == b"Pink Floyd/The Wall/01 - In the Flesh.flac"
        assert lines[2] == b"Pink Floyd/The Wall/02 - The Thin Ice.flac"

        # Verify reading
        read_back = walkman_engine.read_walkman_playlist(p_path)
        assert read_back == tracks


def test_macos_ghost_file_cleanup():
    """Rule 6: Purge .DS_Store, ._*, .Spotlight-V100, .Trashes."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        mount = Path(tmp_dir)
        sub = mount / "MUSIC" / "Artist"
        sub.mkdir(parents=True)

        # Create dummy ghost files
        ds_store = mount / ".DS_Store"
        ds_store.write_text("junk")
        apple_double = sub / "._01 - Track.flac"
        apple_double.write_text("resource fork")
        spotlight = mount / ".Spotlight-V100"
        spotlight.mkdir()
        (spotlight / "Store.db").write_text("index")
        trashes = mount / ".Trashes"
        trashes.mkdir()

        # Run cleanup
        res = walkman_engine.clean_macos_ghost_files(mount)
        assert res["success"] is True
        assert not ds_store.exists()
        assert not apple_double.exists()
        assert not spotlight.exists()
        assert not trashes.exists()


def test_flac_and_mp3_tagging_and_artwork():
    """Rules 2 & 3: Test ID3v2.3 UTF-16 on MP3 and Vorbis/Picture type=3 on FLAC."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp = Path(tmp_dir)
        flac_path = tmp / "test.flac"
        mp3_path = tmp / "test.mp3"

        # Generate 0.5s silent FLAC and MP3 via ffmpeg
        import subprocess
        subprocess.run(
            ["/opt/homebrew/bin/ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "0.5", str(flac_path)],
            check=True, capture_output=True
        )
        subprocess.run(
            ["/opt/homebrew/bin/ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "0.5", str(mp3_path)],
            check=True, capture_output=True
        )

        # Create a sample RGBA cover art (to test conversion to Baseline RGB JPEG)
        cover_img = Image.new("RGBA", (600, 600), color=(30, 90, 150, 255))
        cover_buf = io.BytesIO()
        cover_img.save(cover_buf, format="PNG")
        raw_art_bytes = cover_buf.getvalue()

        # 1. Test FLAC metadata
        walkman_engine.write_track_metadata(
            file_path=flac_path,
            title="Time",
            artist="Pink Floyd",
            album="The Dark Side of the Moon",
            track_number=4,
            year=1973,
            genre="Progressive Rock",
            cover_art_bytes=raw_art_bytes,
        )

        flac_file = FLAC(str(flac_path))
        assert flac_file["title"] == ["Time"]
        assert flac_file["artist"] == ["Pink Floyd"]
        assert flac_file["album"] == ["The Dark Side of the Moon"]
        assert flac_file["tracknumber"] == ["4"]
        assert len(flac_file.pictures) == 1
        pic = flac_file.pictures[0]
        assert pic.type == 3  # Front Cover
        assert pic.mime == "image/jpeg"
        # Verify embedded picture is valid Baseline RGB JPEG
        valid, _ = walkman_engine.is_baseline_rgb_jpeg(pic.data)
        assert valid is True

        # Test extracted artwork
        extracted = walkman_engine.extract_cover_art(flac_path)
        assert extracted is not None
        assert extracted == pic.data

        # 2. Test MP3 metadata strictly ID3v2.3 UTF-16
        walkman_engine.write_track_metadata(
            file_path=mp3_path,
            title="Money",
            artist="Pink Floyd",
            album="The Dark Side of the Moon",
            track_number=6,
            year=1973,
            genre="Progressive Rock",
            cover_art_bytes=raw_art_bytes,
        )

        id3 = ID3(str(mp3_path))
        # Rule 2: strictly ID3v2.3
        assert id3.version == (2, 3, 0)
        assert str(id3.get("TIT2")) == "Money"
        assert str(id3.get("TPE1")) == "Pink Floyd"
        assert str(id3.get("TALB")) == "The Dark Side of the Moon"
        assert str(id3.get("TRCK")) == "6"
        assert str(id3.get("TDRC", id3.get("TYER"))) == "1973"
        
        # Check APIC frame
        apic_frames = id3.getall("APIC")
        assert len(apic_frames) == 1
        apic = apic_frames[0]
        assert apic.type == 3  # Front Cover
        assert apic.mime == "image/jpeg"
        assert apic.encoding == 1  # UTF-16
        valid, _ = walkman_engine.is_baseline_rgb_jpeg(apic.data)
        assert valid is True

        # Test MP3 extracted artwork
        mp3_extracted = walkman_engine.extract_cover_art(mp3_path)
        assert mp3_extracted is not None
        assert mp3_extracted == apic.data


def test_detect_walkman_device_info():
    """Verify accurate detection of non-Android Walkman model from default-capability.xml."""
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        xml_content = """<?xml version="1.0" encoding="ISO-8859-1"?>
<devices xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <device>
    <identification>
      <class>WALKMAN/Standard/AudioOnly</class>
      <model>NW-A50Series</model>
      <marketingname>WALKMAN NW-A50Series</marketingname>
      <vendor>Sony Corporation</vendor>
      <firmwareversion>1.02</firmwareversion>
    </identification>
    <display index="0">
      <width unit="pixels">800</width>
      <height unit="pixels">480</height>
    </display>
  </device>
</devices>"""
        (tmp_path / "default-capability.xml").write_text(xml_content, encoding="latin-1")
        (tmp_path / "MUSIC").mkdir()

        mock_drive = [{
            "id": "WALKMAN",
            "name": "WALKMAN",
            "mount_point": str(tmp_path),
            "type": "internal",
            "total_bytes": 13164281856,  # 13.2 GB formatted (NW-A55L 16GB)
            "used_bytes": 1000000,
            "free_bytes": 13163281856,
            "percent_used": 0.1,
            "has_cfw": False,
            "music_dir": str(tmp_path / "MUSIC"),
        }]

        info = walkman_engine.detect_walkman_device_info(mock_drive)
        assert info is not None
        assert info["model_raw"] == "NW-A50Series"
        assert info["specific_model"] == "NW-A55L"
        assert "Sony Walkman NW-A55L" in info["display_name"]
        assert info["is_non_android"] is True
        assert info["firmware_version"] == "1.02"
        assert info["display_resolution"] == "800x480"

