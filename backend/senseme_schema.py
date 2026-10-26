"""
Sony 12 Tone Analysis & SensMe Binary Schema & Specification.

This specification was reverse-engineered from ground-truth Sony Music Center
12 Tone / SensMe analyzed audio files (e.g. NW-A55 / NW-WM1 / NW-ZX Walkman players).

1. Container Overview:
   - In FLAC: Embedded in an APPLICATION metadata block (FLAC block type 2) with
     Application ID 'SMFM' (0x53 0x4D 0x46 0x4D).
   - In MP3 (ID3v2.3): Encapsulated inside a GEOB (General Encapsulated Object) frame
     with description 'SMFM' and/or a PRIV (Private) frame with owner 'SMFM'.
   - In M4A (MP4): Stored in the '----' freeform metadata atom with
     mean 'com.sony.walkman' / 'com.apple.iTunes' and name 'SMFM'.

2. Payload Structure (Total standard size = 3270 bytes):
   - Offset 0x0000: Application Magic: 'SMFM' (4 bytes ASCII: 0x53 0x4D 0x46 0x4D)
   - Followed by 6 sequentially packed chunks, each prefixed by a 20-byte envelope header:
     - Tag:      4 bytes ASCII (e.g. 'GBPM', 'STBF', 'STSA', 'STMO', 'STHF', 'STMM')
     - Magic1:   4 bytes ASCII 'STAE' (0x53 0x54 0x41 0x45)
     - Magic2:   4 bytes ASCII 'MMLW' (0x4D 0x4D 0x4C 0x57)
     - Flags:    4 bytes Big-Endian: 0x01 0x00 0x80 0x00 (Version 1.0, Flag 0x8000)
     - Length:   4 bytes Big-Endian unsigned integer: payload length L
     - Data:     L bytes chunk payload

3. Detailed Chunks:
   a. 'GBPM' (Global BPM, Length = 4 bytes):
      - Offset in payload: 0x0004
      - Data: 4 bytes IEEE 754 Big-Endian float.
      - Representation: Sony stores the tempo (or half-tempo for tracks > 75 BPM,
        e.g., 84 BPM is represented as 42.0f = 0x4227fe77).
   
   b. 'STBF' (Sony Track Beat Features, Length = 36 bytes):
      - Offset in payload: 0x001C
      - Data: 36 unsigned bytes representing rhythmic complexity and beat profile.

   c. 'STSA' (Sony Track Sabi / Chorus Timestamp, Length = 8 bytes):
      - Offset in payload: 0x0054
      - Data: Two 32-bit Big-Endian unsigned integers [sabi_start_ms, sabi_end_ms].
      - Sabi ("サビ" in Japanese) is the chorus / highlight hook timestamp used by
        Sony Walkman's ZAPPIN and channel preview playback.

   d. 'STMO' (Sony Track Mood Scores, Length = 160 bytes):
      - Offset in payload: 0x0070
      - Data: 40 entries of 4 bytes each = 160 bytes.
      - Structure per 4-byte entry:
        [Byte 0: 0x01 (version)]
        [Byte 1: Mood Slot Index (0 to 9)]
        [Byte 2: Time Quartile Index (0 to 3 for 0%, 25%, 50%, 75%)]
        [Byte 3: Mood Score (0 to 100 integer)]
      - 10 Mood Slots:
        Slot 0: Energetic
        Slot 1: Relax
        Slot 2: Upbeat
        Slot 3: Mellow
        Slot 4: Emotional
        Slot 5: Lounge
        Slot 6: Dance
        Slot 7: Extreme
        Slot 8: Acoustic
        Slot 9: Electronic

   e. 'STHF' (Sony Track Harmonic Features, Length = 160 bytes):
      - Offset in payload: 0x0124
      - Data: 40 entries of 4 bytes each:
        [Byte 0: 0x08]
        [Byte 1: Profile Bin Index (0 to 39)]
        [Byte 2: Intensity Value]
        [Byte 3: 0x00]

   f. 'STMM' (Sony Track Measure / Melody Timeline Map, Length = 2778 bytes):
      - Offset in payload: 0x01D8
      - Data: Sequential timeline measure descriptors, with GBPM float embedded
        at offsets 32 and 90.
"""

from __future__ import annotations

import struct
from typing import Dict, List, Optional, Tuple

APP_ID = b"SMFM"
MAGIC_STAE = b"STAE"
MAGIC_MMLW = b"MMLW"
FLAGS_DEFAULT = b"\x01\x00\x80\x00"

HEADER_SIZE = 20 # 4 tag + 4 stae + 4 mmlw + 4 flags + 4 len
SMFM_TOTAL_SIZE = 3270

MOOD_SLOT_NAMES = [
    "Energetic",
    "Relax",
    "Upbeat",
    "Mellow",
    "Emotional",
    "Lounge",
    "Dance",
    "Extreme",
    "Acoustic",
    "Electronic",
]

def make_chunk_header(tag: str | bytes, length: int) -> bytes:
    if isinstance(tag, str):
        tag_bytes = tag.encode("ascii")
    else:
        tag_bytes = tag
    assert len(tag_bytes) == 4, f"Tag must be 4 bytes, got {tag_bytes}"
    return tag_bytes + MAGIC_STAE + MAGIC_MMLW + FLAGS_DEFAULT + struct.pack(">I", length)
