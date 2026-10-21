"""
Walkman Studio - FastAPI Backend Server.
Provides REST API endpoints for drive detection, library management,
batch audio conversion, metadata & baseline JPEG cover art studio,
CRLF .m3u8 playlist generation, and safe macOS eject.
"""

from __future__ import annotations

import hashlib
import io
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from backend import walkman_engine

app = FastAPI(
    title="Sony Walkman Studio API",
    description="macOS Apple Silicon manager for Sony Walkman NW-A55L",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Pydantic Request Models
# ---------------------------------------------------------------------------
class MetadataUpdateRequest(BaseModel):
    file_path: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    track_number: Optional[str] = None
    year: Optional[str] = None
    genre: Optional[str] = None


class PlaylistCreateRequest(BaseModel):
    mount_point: str
    playlist_name: str
    relative_tracks: List[str]


class PlaylistRenameRequest(BaseModel):
    mount_point: str
    old_playlist_name: str
    new_playlist_name: str


class CleanEjectRequest(BaseModel):
    mount_point: str


class TransferRequest(BaseModel):
    source_files: List[str]  # Absolute paths on host machine
    target_mount: str
    preset: str = "copy"  # copy, flac_16, flac_24, mp3_320
    custom_artist: Optional[str] = None
    custom_album: Optional[str] = None


# ---------------------------------------------------------------------------
# 1. Drive Detection Endpoints
# ---------------------------------------------------------------------------
@app.get("/api/drives")
def get_drives(allow_virtual: bool = Query(False)):
    """Returns detected physical Walkman drives (/Volumes/WALKMAN and MicroSD)."""
    drives = walkman_engine.detect_walkman_drives(allow_virtual=allow_virtual)
    return {"drives": drives}


@app.get("/api/device-info")
def get_device_info():
    """Returns detected non-Android Walkman model specifications and hardware info."""
    info = walkman_engine.detect_walkman_device_info()
    return {"device_info": info}


@app.post("/api/drives/virtual/init")
def init_virtual():
    """Initializes virtual walkman folders in ~/.walkman_virtual/."""
    walkman_engine.init_virtual_walkman()
    return {"status": "ok", "message": "Virtual Walkman initialized"}


# ---------------------------------------------------------------------------
# 2. Library & Artwork Endpoints
# ---------------------------------------------------------------------------
@app.get("/api/library")
def get_library(mount_point: str = Query(...)):
    """Scans and returns all audio tracks in /MUSIC/ of the given Walkman drive."""
    if not os.path.exists(mount_point):
        raise HTTPException(status_code=404, detail="Drive mount point not found")
    data = walkman_engine.scan_walkman_library(mount_point)
    return data


@app.get("/api/artwork")
def get_artwork(file_path: str = Query(...)):
    """Extracts and streams album cover art from a FLAC or MP3 file."""
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Audio file not found")
    art_bytes = walkman_engine.extract_cover_art(file_path)
    if not art_bytes:
        raise HTTPException(status_code=404, detail="No cover art embedded")
    return Response(content=art_bytes, media_type="image/jpeg")


@app.get("/api/audio")
def get_audio(file_path: str = Query(...)):
    """Streams audio file for preview playback."""
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Audio file not found")
    ext = os.path.splitext(file_path)[1].lower()
    media_type = "audio/flac" if ext == ".flac" else ("audio/mpeg" if ext == ".mp3" else "application/octet-stream")
    return FileResponse(file_path, media_type=media_type)


# ---------------------------------------------------------------------------
# 3. Audio Transfer & Batch Conversion Endpoint
# ---------------------------------------------------------------------------
@app.post("/api/transfer")
def transfer_audio_files(payload: TransferRequest):
    """
    Transfers local audio files to the Walkman:
    - Transcodes via FFmpeg if necessary.
    - Sanitizes Artist/Album/Title paths for FAT32/exFAT.
    - Extracts or validates Baseline RGB JPEG cover art.
    - Embeds strict ID3v2.3 UTF-16 (MP3) or Vorbis/Picture (FLAC).
    """
    target_mount = Path(payload.target_mount)
    music_dir = target_mount / "MUSIC"
    music_dir.mkdir(parents=True, exist_ok=True)

    results = []
    for src_file in payload.source_files:
        src_path = Path(src_file)
        if not src_path.exists():
            results.append({"source": src_file, "success": False, "error": "File does not exist"})
            continue

        try:
            # 1. Read existing tags or extract metadata
            mut = None
            try:
                mut = mutagen.File(str(src_path))
            except Exception:
                pass

            title = payload.custom_artist or (getattr(mut, "get", lambda k, d: [d])("title", [""])[0] if mut else "")
            artist = payload.custom_artist or (getattr(mut, "get", lambda k, d: [d])("artist", [""])[0] if mut else "")
            album = payload.custom_album or (getattr(mut, "get", lambda k, d: [d])("album", [""])[0] if mut else "")
            track_num = getattr(mut, "get", lambda k, d: [d])("tracknumber", ["01"])[0] if mut else "01"
            year = getattr(mut, "get", lambda k, d: [d])("date", [""])[0] if mut else ""
            genre = getattr(mut, "get", lambda k, d: [d])("genre", [""])[0] if mut else ""

            if not title:
                title = src_path.stem
            if not artist:
                artist = "Unknown Artist"
            if not album:
                album = "Unknown Album"

            # 2. Extract cover art from source file or directory
            cover_bytes = walkman_engine.extract_cover_art(src_path)
            if not cover_bytes:
                # Look for cover.jpg, folder.jpg in the same directory
                for cand in ["cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg"]:
                    cand_path = src_path.parent / cand
                    if cand_path.exists():
                        try:
                            cover_bytes = cand_path.read_bytes()
                            break
                        except Exception:
                            pass

            # 3. Determine target extension
            preset = payload.preset
            src_ext = src_path.suffix.lower()

            if preset == "copy":
                target_ext = src_ext
            elif preset in ("flac_16", "flac_24"):
                target_ext = ".flac"
            elif preset == "mp3_320":
                target_ext = ".mp3"
            else:
                target_ext = ".flac"

            # 4. Construct target path adhering to FAT32 / exFAT rules
            target_path = walkman_engine.get_target_track_path(
                music_root=music_dir,
                artist=artist,
                album=album,
                track_num=track_num,
                title=title,
                ext=target_ext,
            )
            target_path.parent.mkdir(parents=True, exist_ok=True)

            # 5. Perform copy or transcode
            if preset == "copy" and src_ext == target_ext:
                shutil.copy2(src_path, target_path)
            else:
                walkman_engine.convert_audio(src_path, target_path, preset=preset)

            # 6. Apply strict NW-A55L metadata and Baseline RGB JPEG cover art
            walkman_engine.write_track_metadata(
                file_path=target_path,
                title=title,
                artist=artist,
                album=album,
                track_number=track_num,
                year=year,
                genre=genre,
                cover_art_bytes=cover_bytes,
            )

            results.append({
                "source": src_file,
                "target": str(target_path),
                "relative": str(target_path.relative_to(music_dir)),
                "success": True,
            })
        except Exception as e:
            results.append({"source": src_file, "success": False, "error": str(e)})

    return {"results": results, "total": len(payload.source_files)}


# ---------------------------------------------------------------------------
# 4. Metadata & Baseline Artwork Update Endpoint
# ---------------------------------------------------------------------------
@app.put("/api/metadata")
async def update_metadata(
    file_path: str = Form(...),
    title: Optional[str] = Form(None),
    artist: Optional[str] = Form(None),
    album: Optional[str] = Form(None),
    track_number: Optional[str] = Form(None),
    year: Optional[str] = Form(None),
    genre: Optional[str] = Form(None),
    cover_file: Optional[UploadFile] = File(None),
):
    """
    Updates audio file metadata and re-encodes uploaded cover art to Baseline RGB JPEG.
    Strictly follows ID3v2.3 (MP3) or Vorbis/Picture (FLAC).
    """
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")

    cover_bytes = None
    if cover_file is not None:
        cover_bytes = await cover_file.read()

    try:
        walkman_engine.write_track_metadata(
            file_path=file_path,
            title=title,
            artist=artist,
            album=album,
            track_number=track_number,
            year=year,
            genre=genre,
            cover_art_bytes=cover_bytes,
        )
        return {"status": "ok", "message": "Metadata and Baseline JPEG updated successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/validate-artwork")
async def validate_artwork(cover_file: UploadFile = File(...)):
    """Validates whether an uploaded image conforms to Sony NW-A55L Baseline RGB JPEG rules."""
    image_bytes = await cover_file.read()
    valid, message = walkman_engine.is_baseline_rgb_jpeg(image_bytes)
    return {"valid": valid, "message": message}


# ---------------------------------------------------------------------------
# 5. Playlists Endpoints (.M3U8 with CRLF in /MUSIC/)
# ---------------------------------------------------------------------------
@app.get("/api/playlists")
def get_playlists(mount_point: str = Query(...)):
    """Scans and lists .m3u8 playlists in /MUSIC/."""
    music_dir = Path(mount_point) / "MUSIC"
    if not music_dir.exists():
        return {"playlists": []}

    playlists = []
    for f in sorted(music_dir.glob("*.m3u8")):
        tracks = walkman_engine.read_walkman_playlist(f)
        playlists.append({
            "name": f.name,
            "filename": f.name,
            "track_count": len(tracks),
            "tracks": tracks,
            "full_path": str(f),
        })
    return {"playlists": playlists}


@app.post("/api/playlists")
def create_playlist(payload: PlaylistCreateRequest):
    """Creates or updates a CRLF .m3u8 playlist inside /MUSIC/."""
    music_dir = Path(payload.mount_point) / "MUSIC"
    music_dir.mkdir(parents=True, exist_ok=True)
    try:
        playlist_path = walkman_engine.write_walkman_playlist(
            drive_music_dir=music_dir,
            playlist_name=payload.playlist_name,
            relative_tracks=payload.relative_tracks,
        )
        return {"status": "ok", "playlist_path": str(playlist_path), "tracks": len(payload.relative_tracks)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/playlists")
def delete_playlist(mount_point: str = Query(...), playlist_name: str = Query(...)):
    """Deletes an .m3u8 playlist from /MUSIC/."""
    music_dir = Path(mount_point) / "MUSIC"
    p_path = music_dir / playlist_name
    if p_path.exists():
        p_path.unlink()
        return {"status": "ok", "message": f"Deleted {playlist_name}"}
    raise HTTPException(status_code=404, detail="Playlist not found")


@app.patch("/api/playlists/rename")
@app.post("/api/playlists/rename")
def rename_playlist(payload: PlaylistRenameRequest):
    """Renames an .m3u8 playlist in /MUSIC/."""
    music_dir = Path(payload.mount_point) / "MUSIC"
    try:
        new_path = walkman_engine.rename_walkman_playlist(
            drive_music_dir=music_dir,
            old_playlist_name=payload.old_playlist_name,
            new_playlist_name=payload.new_playlist_name,
        )
        return {
            "status": "ok",
            "message": f"Renamed to {new_path.name}",
            "filename": new_path.name,
            "full_path": str(new_path)
        }
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except FileExistsError as e:
        raise HTTPException(status_code=409, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# ---------------------------------------------------------------------------
# 6. macOS Ghost File Cleanup & Safe Eject
# ---------------------------------------------------------------------------
@app.post("/api/clean-eject")
def clean_and_eject(payload: CleanEjectRequest):
    """
    Executes dot_clean -m, purges .DS_Store, ._*, .Spotlight-V100, .Trashes,
    and safely unmounts the volume.
    """
    mount = payload.mount_point
    if not os.path.exists(mount):
        raise HTTPException(status_code=404, detail="Drive mount point not found")

    clean_res = walkman_engine.clean_macos_ghost_files(mount)
    unmount_res = walkman_engine.unmount_walkman_drive(mount)

    return {
        "status": "ok",
        "clean_results": clean_res,
        "unmount_results": unmount_res,
    }


# ---------------------------------------------------------------------------
# Frontend Static Asset Mounting (for Production Desktop Mode)
# ---------------------------------------------------------------------------
frontend_dist = Path(__file__).resolve().parent.parent / "frontend" / "dist"
if frontend_dist.exists() and (frontend_dist / "index.html").exists():
    app.mount("/", StaticFiles(directory=str(frontend_dist), html=True), name="frontend")
