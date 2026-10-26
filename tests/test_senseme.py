import shutil
import struct
from pathlib import Path

import pytest

from backend import senseme_dsp, senseme_engine, senseme_schema

ORIG_FLAC = Path("/Users/workstation/Desktop/6. LANY - ILYSB (STRIPPED).flac")
ANALYZED_FLAC = Path("/Users/workstation/Desktop/06. ILYSB (STRIPPED) 12 tone Senseme analyzed.flac")


def test_schema_constants():
    assert senseme_schema.APP_ID == b"SMFM"
    assert senseme_schema.SMFM_TOTAL_SIZE == 3270
    assert len(senseme_schema.MOOD_SLOT_NAMES) == 10
    hdr = senseme_schema.make_chunk_header("GBPM", 4)
    assert len(hdr) == 20
    assert hdr[:4] == b"GBPM"
    assert hdr[4:8] == b"STAE"
    assert hdr[8:12] == b"MMLW"
    assert hdr[12:16] == b"\x01\x00\x80\x00"
    assert struct.unpack(">I", hdr[16:20])[0] == 4


def test_ground_truth_analyzed_file_detection():
    assert ANALYZED_FLAC.exists()
    info = senseme_engine.is_senseme_analyzed(ANALYZED_FLAC)
    assert info["isAnalyzed"] is True
    assert info["bpm"] == 84.0
    assert info["highlightSec"] == 11.572
    assert len(info["moodScores"]) == 10
    assert info["moodScores"] == [57, 50, 75, 57, 18, 60, 0, 45, 66, 52]
    assert "Acoustic" in info["channels"]
    assert "Relax" in info["channels"] or "Lounge" in info["channels"]


def test_ground_truth_unanalyzed_file_detection():
    assert ORIG_FLAC.exists()
    info = senseme_engine.is_senseme_analyzed(ORIG_FLAC)
    assert info["isAnalyzed"] is False


def test_payload_builder_exact_match():
    with open(ANALYZED_FLAC, "rb") as f:
        f.seek(0x1D171)
        ref_bytes = f.read(3270)

    synth = senseme_engine.build_smfm_payload(
        bpm=41.99850082397461 * 2.0,
        mood_scores=[57, 50, 75, 57, 18, 60, 0, 45, 66, 52],
        highlight_ms=11572,
        template_bytes=ref_bytes
    )
    assert len(synth) == 3270
    assert synth == ref_bytes


def test_dsp_analysis_and_injection(tmp_path):
    copy_path = tmp_path / "test_track.flac"
    shutil.copy2(ORIG_FLAC, copy_path)

    # Initial check: not analyzed
    pre = senseme_engine.is_senseme_analyzed(copy_path)
    assert pre["isAnalyzed"] is False

    # Run DSP and inject
    result = senseme_engine.analyze_and_inject(copy_path)
    assert result["isAnalyzed"] is True
    assert 70.0 <= result["bpm"] <= 100.0
    assert -1.0 <= result["valence"] <= 1.0
    assert -1.0 <= result["arousal"] <= 1.0
    assert result["highlightSec"] > 0
    assert len(result["moodScores"]) == 10

    # Verification reader check
    post = senseme_engine.is_senseme_analyzed(copy_path)
    assert post["isAnalyzed"] is True
    assert post["bpm"] == result["bpm"]
    assert post["highlightSec"] == result["highlightSec"]
    assert post["moodScores"] == result["moodScores"]
