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

# Ensure parent directory is in sys.path so 'import backend' always works
_backend_dir = Path(__file__).resolve().parent
_project_dir = _backend_dir.parent
if str(_project_dir) not in sys.path:
    sys.path.insert(0, str(_project_dir))

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
    template_bytes: Optional[bytes] = None,
    raw_bpm: Optional[float] = None,
    quartile_mood_scores: Optional[List[List[int]]] = None,
) -> bytes:
    """
    Constructs a 100% hardware-compatible Sony 12 Tone / SenseMe SMFM binary block.
    Total size is exactly 3270 bytes. Supports per-quartile dynamic STMO values.
    """
    if len(mood_scores) != 10:
        raise ValueError(f"STMO requires exactly 10 mood scores, got {len(mood_scores)}")
    if template_bytes is None:
        template_bytes = get_template_bytes()

    # 1. GBPM (4 bytes: packed float BE)
    bpm_float = float(raw_bpm if raw_bpm is not None else bpm)
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
        for q in range(4):
            if quartile_mood_scores and len(quartile_mood_scores) > m and len(quartile_mood_scores[m]) > q:
                val = int(max(0, min(100, quartile_mood_scores[m][q])))
            else:
                val = int(max(0, min(100, mood_scores[m])))
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

    # Mood Scores (STMO: mean across 4 quartiles for each mood)
    stmo = chunks["STMO"]
    mood_scores = []
    for m in range(10):
        if (m + 1) * 16 <= len(stmo):
            q_scores = [stmo[m * 16 + q * 4 + 3] for q in range(4)]
            score = int(round(sum(q_scores) / 4.0))
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

    # 7. Strict 14 Official Sony Walkman Channels & Time-of-Day Guardrails
    effective_bpm = bpm * 2.0 if bpm < 62.0 else (bpm * 0.5 if bpm > 180.0 else bpm)
    s0, s1, s2, s3, s4, s5, s6, s7, s8, s9 = mood_scores

    channels: List[str] = []

    # A) 8 Mood Channels
    mood_candidates: List[str] = []
    if s0 >= 55 or (arousal >= 0.35 and valence >= 0.15 and effective_bpm >= 115):
        mood_candidates.append("Energetic")
    if s1 >= 55 or (arousal <= -0.15 and valence >= -0.30 and effective_bpm <= 105):
        mood_candidates.append("Relax")
    if s2 >= 55 or (valence >= 0.20 and -0.10 <= arousal <= 0.65):
        mood_candidates.append("Upbeat")
    if s3 >= 55 or (-0.75 <= arousal <= 0.05 and -0.35 <= valence <= 0.45):
        mood_candidates.append("Mellow")
    if s4 >= 50 or (valence <= -0.10 and -0.55 <= arousal <= 0.40):
        mood_candidates.append("Emotional")
    if s7 >= 60 or arousal >= 0.65 or effective_bpm >= 145:
        mood_candidates.append("Extreme")
    if s6 >= 45 or (105 <= effective_bpm <= 140 and arousal >= 0.20):
        mood_candidates.append("Dance")
    if s5 >= 45 or (80 <= effective_bpm <= 120 and -0.40 <= arousal <= 0.30):
        mood_candidates.append("Lounge")

    # Fallback: if 0 mood channels qualified, assign top STMO score from slots 0..7
    if not mood_candidates:
        mood_names_8 = ["Energetic", "Relax", "Upbeat", "Mellow", "Emotional", "Lounge", "Dance", "Extreme"]
        best_mood_idx = int(max(range(8), key=lambda i: mood_scores[i]))
        mood_candidates.append(mood_names_8[best_mood_idx])

    channels.extend(mood_candidates)

    # B) 5 Time-of-Day Channels with Bounding Guards
    time_candidates: List[str] = []
    # Morning (05:00 - 10:00)
    if (s2 >= 55 or s8 >= 60 or s1 >= 55 or valence >= 0.15) and (-0.25 <= arousal <= 0.40) and (80 <= effective_bpm <= 130):
        time_candidates.append("Morning")

    # Daytime (10:00 - 17:00)
    if (s0 >= 55 or s2 >= 55 or s6 >= 55 or valence >= 0.10) and (arousal >= 0.05) and (effective_bpm >= 95):
        time_candidates.append("Daytime")

    # Evening (17:00 - 21:00)
    if (s3 >= 55 or s1 >= 55 or s5 >= 45) and (-0.45 <= arousal <= 0.20) and (effective_bpm <= 120):
        time_candidates.append("Evening")

    # Night (21:00 - 00:00)
    if (s5 >= 45 or s4 >= 50 or s3 >= 55) and (arousal <= 0.15 and valence <= 0.25) and (effective_bpm <= 115):
        time_candidates.append("Night")

    # Midnight (00:00 - 05:00)
    if (s1 >= 55 or s3 >= 55) and (arousal <= 0.0) and (effective_bpm <= 90):
        time_candidates.append("Midnight")

    # Circadian Fallback
    if not time_candidates:
        if arousal >= 0.20 or effective_bpm >= 120:
            time_candidates.append("Daytime")
        elif arousal <= -0.20 or effective_bpm <= 85:
            time_candidates.append("Midnight")
        elif valence >= 0.15:
            time_candidates.append("Morning")
        elif arousal <= 0.05:
            time_candidates.append("Night")
        else:
            time_candidates.append("Evening")

    channels.extend(time_candidates)

    # C) Global 14th Channel
    channels.append("Shuffle All Songs")

    return {
        "isAnalyzed": True,
        "is_analyzed": True,
        "bpm": bpm,
        "rawBpm": raw_bpm,
        "raw_bpm": raw_bpm,
        "effectiveBpm": effective_bpm,
        "effective_bpm": effective_bpm,
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


def strip_flac_smfm(file_path: str | Path) -> bool:
    """Removes any existing SMFM APPLICATION block from a FLAC file."""
    path = Path(file_path)
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic != b"fLaC":
            return False
        blocks: List[Tuple[int, bytes]] = []
        is_last = False
        found_smfm = False
        while not is_last:
            h = f.read(4)
            if len(h) < 4:
                break
            is_last = bool(h[0] & 0x80)
            btype = h[0] & 0x7F
            blen = (h[1] << 16) | (h[2] << 8) | h[3]
            bdata = f.read(blen)
            if btype == 2 and bdata.startswith(b"SMFM"):
                found_smfm = True
                continue
            blocks.append((btype, bdata))
        audio_frames = f.read()

    if not found_smfm or not blocks:
        return False

    tmp_path = path.with_suffix(".flac.tmp")
    with open(tmp_path, "wb") as f:
        f.write(b"fLaC")
        for i, (btype, bdata) in enumerate(blocks):
            last_flag = 0x80 if (i == len(blocks) - 1) else 0x00
            b0 = last_flag | (btype & 0x7F)
            blen = len(bdata)
            header = bytes([b0, (blen >> 16) & 0xFF, (blen >> 8) & 0xFF, blen & 0xFF])
            f.write(header)
            f.write(bdata)
        f.write(audio_frames)

    shutil.move(str(tmp_path), str(path))
    return True


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
            if btype == 2:
                bdata = f.read(blen)
                if bdata.startswith(b"SMFM"):
                    return bdata
            else:
                f.seek(blen, 1)
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

    # Check GEOB frames (support our injector 'SMFM' and Sony Music Center 'USR_SMFMF'/'application/SMFMF')
    for frame in audio.getall("GEOB"):
        if frame.data:
            if frame.data.startswith(b"SMFM") or frame.data.startswith(b"GBPM"):
                return frame.data

    # Check PRIV frames
    for frame in audio.getall("PRIV"):
        if frame.data:
            if frame.data.startswith(b"SMFM") or frame.data.startswith(b"GBPM"):
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
        highlight_ms=dsp_result.highlight_ms,
        raw_bpm=dsp_result.raw_bpm,
        quartile_mood_scores=dsp_result.quartile_mood_scores,
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
