"""
Sony 12 Tone Analysis & SensMe Metadata Engine for Walkman Studio.

Provides non-destructive binary synthesis, injection, and parsing for:
- FLAC (.flac): Native FLAC APPLICATION block type 2 (App ID 'SMFM')
- MP3 (.mp3): ID3v2.3 GEOB ('SMFM') and PRIV ('SMFM') frames
- M4A (.m4a): MP4 '----' atom ('com.sony.walkman:SMFM')
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import mutagen
from mutagen.flac import FLAC
from mutagen.id3 import GEOB, ID3, PRIV, ID3NoHeaderError
from mutagen.mp4 import MP4

from backend import senseme_dsp
from backend.senseme_schema import (
    APP_ID,
    MAGIC_MMLW,
    MAGIC_STAE,
    MOOD_SLOT_NAMES,
    SMFM_TOTAL_SIZE,
    make_chunk_header,
)

TEMPLATE_PATH = Path(__file__).resolve().parent / "resources" / "smfm_template.bin"

_CACHED_TEMPLATE: Optional[bytes] = None


def get_template_bytes() -> bytes:
    """Loads the reference 3270-byte SMFM template."""
    global _CACHED_TEMPLATE
    if _CACHED_TEMPLATE is not None:
        return _CACHED_TEMPLATE
    if TEMPLATE_PATH.exists():
        _CACHED_TEMPLATE = TEMPLATE_PATH.read_bytes()
        return _CACHED_TEMPLATE
    raise FileNotFoundError(f"SMFM template file not found at {TEMPLATE_PATH}")


def build_smfm_payload(
    bpm: float,
    mood_scores: List[int],
    highlight_ms: int,
    template_bytes: Optional[bytes] = None
) -> bytes:
    """
    Constructs a 100% hardware-compatible Sony 12 Tone / SenseMe SMFM binary block.
    Total size is exactly 3270 bytes.
    """
    if len(mood_scores) != 10:
        raise ValueError(f"STMO requires exactly 10 mood scores, got {len(mood_scores)}")
    if template_bytes is None:
        template_bytes = get_template_bytes()

    # 1. GBPM (4 bytes: packed float BE)
    bpm_float = float(bpm / 2.0 if bpm > 75.0 else bpm)
    gbpm_data = struct.pack(">f", bpm_float)
    gbpm_chunk = make_chunk_header(b"GBPM", len(gbpm_data)) + gbpm_data

    # 2. STBF (36 bytes: beat features)
    stbf_data = template_bytes[4 + 20 + 4 + 20 : 4 + 20 + 4 + 20 + 36]
    stbf_chunk = make_chunk_header(b"STBF", len(stbf_data)) + stbf_data

    # 3. STSA (8 bytes: Sabi highlight timestamp ms)
    stsa_data = struct.pack(">2I", int(highlight_ms), int(highlight_ms))
    stsa_chunk = make_chunk_header(b"STSA", len(stsa_data)) + stsa_data

    # 4. STMO (160 bytes: 10 moods x 4 quartiles)
    stmo_bytes = bytearray()
    for m in range(10):
        val = int(max(0, min(100, mood_scores[m])))
        for q in range(4):
            stmo_bytes.extend([0x01, m, q, val])
    stmo_data = bytes(stmo_bytes)
    stmo_chunk = make_chunk_header(b"STMO", len(stmo_data)) + stmo_data

    # 5. STHF (160 bytes: harmonic features)
    sthf_offset = 4 + 20 + 4 + 20 + 36 + 20 + 8 + 20 + 160 + 20
    sthf_data = template_bytes[sthf_offset : sthf_offset + 160]
    sthf_chunk = make_chunk_header(b"STHF", len(sthf_data)) + sthf_data

    # 6. STMM (2778 bytes: timeline structure with embedded BPM)
    stmm_offset = 4 + 20 + 4 + 20 + 36 + 20 + 8 + 20 + 160 + 20 + 160 + 20
    stmm_data = bytearray(template_bytes[stmm_offset : stmm_offset + 2778])
    bpm_bytes = struct.pack(">f", bpm_float)
    stmm_data[32:36] = bpm_bytes
    stmm_data[90:94] = bpm_bytes
    stmm_chunk = make_chunk_header(b"STMM", len(stmm_data)) + bytes(stmm_data)

    payload = APP_ID + gbpm_chunk + stbf_chunk + stsa_chunk + stmo_chunk + sthf_chunk + stmm_chunk
    if len(payload) != SMFM_TOTAL_SIZE:
        raise ValueError(f"Payload size mismatch: expected {SMFM_TOTAL_SIZE}, got {len(payload)}")
    return payload


def parse_smfm_payload(data: bytes) -> Optional[Dict[str, Any]]:
    """
    Parses a raw SMFM binary payload into structured 12 Tone / SenseMe metadata.
    """
    if not data or len(data) < 24:
        return None

    if data.startswith(b"SMFM"):
        payload = data[4:]
    else:
        payload = data

    chunks: Dict[str, bytes] = {}
    offset = 0
    while offset + 20 <= len(payload):
        header = payload[offset : offset + 20]
        tag = header[0:4].decode("ascii", errors="ignore")
        length = struct.unpack(">I", header[16:20])[0]
        cdata = payload[offset + 20 : offset + 20 + length]
        chunks[tag] = cdata
        offset += 20 + length

    if "GBPM" not in chunks or "STMO" not in chunks:
        return None

    # BPM
    raw_bpm = struct.unpack(">f", chunks["GBPM"])[0]
    bpm = round(raw_bpm * 2.0 if raw_bpm < 58.0 else raw_bpm, 1)

    # Highlight (STSA)
    highlight_sec = 0.0
    if "STSA" in chunks and len(chunks["STSA"]) >= 8:
        ms = struct.unpack(">I", chunks["STSA"][:4])[0]
        highlight_sec = round(ms / 1000.0, 3)

    # Mood Scores (STMO)
    stmo = chunks["STMO"]
    mood_scores = []
    for m in range(10):
        if (m + 1) * 16 <= len(stmo):
            score = stmo[m * 16 + 3]
            mood_scores.append(score)
        else:
            mood_scores.append(50)

    # Derived Valence & Arousal
    pos_arousal = (mood_scores[0] + mood_scores[6] + mood_scores[7]) / 300.0
    neg_arousal = (mood_scores[1] + mood_scores[3]) / 200.0
    arousal = round(float(min(max((pos_arousal - neg_arousal) * 2.0, -1.0), 1.0)), 2)

    pos_valence = (mood_scores[2] * 1.5 + mood_scores[1] + mood_scores[5]) / 350.0
    neg_valence = (mood_scores[4] * 1.5 + mood_scores[7] * 0.5) / 200.0
    valence = round(float(min(max((pos_valence - neg_valence) * 1.8, -1.0), 1.0)), 2)

    # Channels
    channels: List[str] = []
    if arousal >= 0.35 and valence >= 0.15 and bpm >= 115:
        channels.append("Energetic")
    if arousal <= -0.15 and valence >= -0.30 and bpm <= 105:
        channels.append("Relax")
    if valence >= 0.20 and -0.10 <= arousal <= 0.65:
        channels.append("Upbeat")
    if -0.75 <= arousal <= 0.0 and -0.35 <= valence <= 0.45:
        channels.append("Mellow")
    if mood_scores[4] >= 45 or (valence <= -0.10 and -0.55 <= arousal <= 0.40):
        channels.append("Emotional")
    if arousal >= 0.65 or mood_scores[7] >= 65:
        channels.append("Extreme")
    if mood_scores[6] >= 50 or (108 <= bpm <= 138 and arousal >= 0.25):
        channels.append("Dance")
    if mood_scores[5] >= 50 or (80 <= bpm <= 118 and -0.40 <= arousal <= 0.30):
        channels.append("Lounge")
    if mood_scores[8] >= 55:
        channels.append("Acoustic")
    if mood_scores[9] >= 60:
        channels.append("Electronic")

    if "Upbeat" in channels or "Relax" in channels or valence > 0.1:
        channels.append("Daytime")
    if "Mellow" in channels or "Relax" in channels or "Lounge" in channels:
        channels.append("Evening")
    if "Relax" in channels or "Mellow" in channels or arousal <= -0.10:
        channels.append("Midnight")
    if "Upbeat" in channels or "Acoustic" in channels or "Relax" in channels:
        channels.append("Morning")

    return {
        "isAnalyzed": True,
        "is_analyzed": True,
        "bpm": bpm,
        "rawBpm": raw_bpm,
        "raw_bpm": raw_bpm,
        "valence": valence,
        "arousal": arousal,
        "moodScores": mood_scores,
        "mood_scores": mood_scores,
        "channels": list(dict.fromkeys(channels)),
        "highlightSec": highlight_sec,
        "highlight_sec": highlight_sec,
    }


# ---------------------------------------------------------------------------
# Format-Specific Injection & Readers
# ---------------------------------------------------------------------------

def inject_flac_smfm(file_path: str | Path, smfm_payload: bytes) -> None:
    """
    Non-destructively injects the SMFM APPLICATION block (type 2) into a FLAC file.
    Replaces existing SMFM block or inserts before PADDING / at end of headers.
    Audio frames are completely untouched.
    """
    path = Path(file_path)
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic != b"fLaC":
            raise ValueError(f"Not a valid FLAC file: {path}")

        blocks: List[Tuple[int, bytes]] = []
        is_last = False
        while not is_last:
            h = f.read(4)
            if len(h) < 4:
                break
            b0 = h[0]
            is_last = bool(b0 & 0x80)
            btype = b0 & 0x7F
            blen = (h[1] << 16) | (h[2] << 8) | h[3]
            bdata = f.read(blen)
            blocks.append((btype, bdata))

        audio_frames = f.read()

    # Filter out existing SMFM application block
    new_blocks: List[Tuple[int, bytes]] = []
    inserted = False
    for btype, bdata in blocks:
        if btype == 2 and bdata.startswith(b"SMFM"):
            continue
        if btype == 1 and not inserted: # PADDING
            new_blocks.append((2, smfm_payload))
            inserted = True
        new_blocks.append((btype, bdata))

    if not inserted:
        new_blocks.append((2, smfm_payload))

    # Atomic rewrite
    tmp_path = path.with_suffix(".flac.tmp")
    with open(tmp_path, "wb") as f:
        f.write(b"fLaC")
        for i, (btype, bdata) in enumerate(new_blocks):
            last_flag = 0x80 if (i == len(new_blocks) - 1) else 0x00
            b0 = last_flag | (btype & 0x7F)
            blen = len(bdata)
            header = bytes([b0, (blen >> 16) & 0xFF, (blen >> 8) & 0xFF, blen & 0xFF])
            f.write(header)
            f.write(bdata)
        f.write(audio_frames)

    shutil.move(str(tmp_path), str(path))


def read_flac_smfm(file_path: str | Path) -> Optional[bytes]:
    """Fast inspection of FLAC headers for SMFM APPLICATION block."""
    path = Path(file_path)
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic != b"fLaC":
            return None
        is_last = False
        while not is_last:
            h = f.read(4)
            if len(h) < 4:
                break
            is_last = bool(h[0] & 0x80)
            btype = h[0] & 0x7F
            blen = (h[1] << 16) | (h[2] << 8) | h[3]
            bdata = f.read(blen)
            if btype == 2 and bdata.startswith(b"SMFM"):
                return bdata
    return None


def inject_mp3_smfm(file_path: str | Path, smfm_payload: bytes) -> None:
    """
    Injects SMFM payload into MP3 ID3v2.3 tag via GEOB and PRIV frames.
    """
    path = Path(file_path)
    try:
        audio = ID3(str(path))
    except ID3NoHeaderError:
        audio = ID3()

    # 1. GEOB frame: desc='SMFM'
    geob = GEOB(
        encoding=0, # ISO-8859-1
        mime="application/octet-stream",
        filename="",
        desc="SMFM",
        data=smfm_payload
    )
    audio.add(geob)

    # 2. PRIV frame: owner='SMFM'
    priv = PRIV(
        owner="SMFM",
        data=smfm_payload
    )
    audio.add(priv)

    # Save strictly in ID3v2.3 format
    audio.save(str(path), v2_version=3)


def read_mp3_smfm(file_path: str | Path) -> Optional[bytes]:
    """Reads SMFM payload from MP3 ID3v2.3 GEOB or PRIV frames."""
    path = Path(file_path)
    try:
        audio = ID3(str(path))
    except Exception:
        return None

    # Check GEOB frames
    for frame in audio.getall("GEOB"):
        if frame.desc == "SMFM" and frame.data and frame.data.startswith(b"SMFM"):
            return frame.data

    # Check PRIV frames
    for frame in audio.getall("PRIV"):
        if frame.owner in ("SMFM", "Sony Corporation") and frame.data and frame.data.startswith(b"SMFM"):
            return frame.data

    return None


def inject_m4a_smfm(file_path: str | Path, smfm_payload: bytes) -> None:
    """
    Injects SMFM payload into M4A / MP4 container freeform atom.
    """
    path = Path(file_path)
    audio = MP4(str(path))
    if audio.tags is None:
        audio.add_tags()
    audio.tags["----:com.sony.walkman:SMFM"] = smfm_payload
    audio.tags["----:com.apple.iTunes:SMFM"] = smfm_payload
    audio.save(str(path))


def read_m4a_smfm(file_path: str | Path) -> Optional[bytes]:
    """Reads SMFM payload from M4A container."""
    path = Path(file_path)
    try:
        audio = MP4(str(path))
        if audio.tags:
            for key in ("----:com.sony.walkman:SMFM", "----:com.apple.iTunes:SMFM", "SMFM"):
                if key in audio.tags:
                    val = audio.tags[key]
                    if isinstance(val, list) and len(val) > 0 and isinstance(val[0], bytes):
                        return val[0]
                    elif isinstance(val, bytes):
                        return val
    except Exception:
        pass
    return None


def is_senseme_analyzed(file_path: str | Path) -> Dict[str, Any]:
    """
    Fast verification reader for any audio file (.flac, .mp3, .m4a).
    Returns { isAnalyzed: bool, bpm, valence, arousal, channels, highlightSec, moodScores }.
    """
    path = Path(file_path)
    ext = path.suffix.lower()

    raw_payload: Optional[bytes] = None
    if ext == ".flac":
        raw_payload = read_flac_smfm(path)
    elif ext == ".mp3":
        raw_payload = read_mp3_smfm(path)
    elif ext in (".m4a", ".m4b", ".alac", ".aac", ".mp4"):
        raw_payload = read_m4a_smfm(path)

    if raw_payload:
        parsed = parse_smfm_payload(raw_payload)
        if parsed:
            return parsed

    return {
        "isAnalyzed": False,
        "is_analyzed": False,
        "bpm": 0.0,
        "rawBpm": 0.0,
        "raw_bpm": 0.0,
        "valence": 0.0,
        "arousal": 0.0,
        "moodScores": [0] * 10,
        "mood_scores": [0] * 10,
        "channels": [],
        "highlightSec": 0.0,
        "highlight_sec": 0.0,
    }


def analyze_and_inject(file_path: str | Path) -> Dict[str, Any]:
    """
    Executes Phase 2 DSP analysis, synthesizes 100% hardware-compatible SMFM payload,
    and non-destructively injects it into the audio file.
    """
    path = Path(file_path)
    ext = path.suffix.lower()

    # 1. Run DSP feature extraction
    dsp_result = senseme_dsp.analyze_audio_track(path)

    # 2. Synthesize SMFM binary payload
    payload = build_smfm_payload(
        bpm=dsp_result.bpm,
        mood_scores=dsp_result.mood_scores,
        highlight_ms=dsp_result.highlight_ms
    )

    # 3. Inject into file format
    if ext == ".flac":
        inject_flac_smfm(path, payload)
    elif ext == ".mp3":
        inject_mp3_smfm(path, payload)
    elif ext in (".m4a", ".m4b", ".alac", ".aac", ".mp4"):
        inject_m4a_smfm(path, payload)
    else:
        raise ValueError(f"Unsupported format for 12 Tone injection: {ext}")

    return {
        "isAnalyzed": True,
        "is_analyzed": True,
        "bpm": dsp_result.bpm,
        "rawBpm": dsp_result.raw_bpm,
        "raw_bpm": dsp_result.raw_bpm,
        "valence": dsp_result.valence,
        "arousal": dsp_result.arousal,
        "moodScores": dsp_result.mood_scores,
        "mood_scores": dsp_result.mood_scores,
        "channels": dsp_result.channels,
        "highlightSec": dsp_result.highlight_sec,
        "highlight_sec": dsp_result.highlight_sec,
    }


# ---------------------------------------------------------------------------
# CLI Entry Point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Sony 12 Tone / SenseMe Engine for Walkman Studio")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # inspect
    inspect_parser = subparsers.add_parser("inspect", help="Inspect audio file for 12 Tone metadata")
    inspect_parser.add_argument("file_path", help="Path to audio file")

    # analyze
    analyze_parser = subparsers.add_parser("analyze", help="Analyze audio file with 12 Tone DSP")
    analyze_parser.add_argument("file_path", help="Path to audio file")
    analyze_parser.add_argument("--inject", action="store_true", help="Inject analysis into file metadata")

    args = parser.parse_args()

    if args.command == "inspect":
        res = is_senseme_analyzed(args.file_path)
        print(json.dumps(res, indent=2))
    elif args.command == "analyze":
        if args.inject:
            res = analyze_and_inject(args.file_path)
        else:
            dsp_res = senseme_dsp.analyze_audio_track(args.file_path)
            res = {
                "isAnalyzed": False,
                "bpm": dsp_res.bpm,
                "valence": dsp_res.valence,
                "arousal": dsp_res.arousal,
                "moodScores": dsp_res.mood_scores,
                "channels": dsp_res.channels,
                "highlightSec": dsp_res.highlight_sec,
            }
        print(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
