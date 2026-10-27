import shutil
import struct
from pathlib import Path

import pytest

from backend import senseme_dsp, senseme_engine, senseme_schema

CANDIDATE_ANALYZED = [
    Path("/Users/workstation/Desktop/06. ILYSB (STRIPPED) 12 tone Senseme analyzed.flac"),
    Path("/Volumes/SD_CARD/MUSIC/LANY/Make Out/06. ILYSB (STRIPPED).flac"),
]
ANALYZED_FLAC = next((p for p in CANDIDATE_ANALYZED if p.exists()), None)

CANDIDATE_ORIG = [
    Path("/Users/workstation/Desktop/6. LANY - ILYSB (STRIPPED).flac"),
    Path("/Users/workstation/Downloads/Janine Berdin performs What if I miss you for the rest of my life LIVE on Wish 107.5 Bus.flac"),
]
ORIG_FLAC = next((p for p in CANDIDATE_ORIG if p.exists()), None)


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
    assert ANALYZED_FLAC is not None and ANALYZED_FLAC.exists()
    info = senseme_engine.is_senseme_analyzed(ANALYZED_FLAC)
    assert info["isAnalyzed"] is True
    assert info["bpm"] == 84.0
    assert info["highlightSec"] == 11.572
    assert len(info["moodScores"]) == 10
    assert info["moodScores"] == [57, 50, 75, 57, 18, 60, 0, 45, 66, 52]
    assert "Acoustic" in info["channels"]
    assert "Relax" in info["channels"] or "Lounge" in info["channels"]


def test_ground_truth_unanalyzed_file_detection(tmp_path):
    if ORIG_FLAC and ORIG_FLAC.exists() and not senseme_engine.is_senseme_analyzed(ORIG_FLAC)["isAnalyzed"]:
        info = senseme_engine.is_senseme_analyzed(ORIG_FLAC)
        assert info["isAnalyzed"] is False
    else:
        tmp_f = tmp_path / "unanalyzed.flac"
        shutil.copy2(ANALYZED_FLAC, tmp_f)
        assert senseme_engine.strip_flac_smfm(tmp_f) is True
        info = senseme_engine.is_senseme_analyzed(tmp_f)
        assert info["isAnalyzed"] is False


def test_payload_builder_exact_match():
    assert ANALYZED_FLAC is not None and ANALYZED_FLAC.exists()
    ref_bytes = senseme_engine.read_flac_smfm(ANALYZED_FLAC)
    assert ref_bytes is not None
    assert len(ref_bytes) == 3270

    synth = senseme_engine.build_smfm_payload(
        bpm=84.0,
        mood_scores=[57, 50, 75, 57, 18, 60, 0, 45, 66, 52],
        highlight_ms=11572,
        template_bytes=ref_bytes,
        raw_bpm=41.99850082397461,
    )
    assert len(synth) == 3270
    assert synth == ref_bytes


def test_dsp_analysis_and_injection(tmp_path):
    copy_path = tmp_path / "test_track.flac"
    if ORIG_FLAC and ORIG_FLAC.exists() and not senseme_engine.is_senseme_analyzed(ORIG_FLAC)["isAnalyzed"]:
        shutil.copy2(ORIG_FLAC, copy_path)
    else:
        shutil.copy2(ANALYZED_FLAC, copy_path)
        senseme_engine.strip_flac_smfm(copy_path)

    # Initial check: not analyzed
    pre = senseme_engine.is_senseme_analyzed(copy_path)
    assert pre["isAnalyzed"] is False

    # Run DSP and inject
    result = senseme_engine.analyze_and_inject(copy_path)
    assert result["isAnalyzed"] is True
    assert 50.0 <= result["bpm"] <= 220.0
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
    assert "Shuffle All Songs" in post["channels"]


def test_walkman_14_channels():
    walkman_channels = [
        "Energetic", "Emotional", "Lounge", "Dance",
        "Extreme", "Upbeat", "Relax", "Mellow",
        "Morning", "Daytime", "Evening", "Night", "Midnight",
        "Shuffle All Songs"
    ]
    # Check night condition
    night_payload = senseme_engine.build_smfm_payload(
        bpm=90.0,
        mood_scores=[40, 50, 40, 60, 40, 50, 30, 20, 50, 40],
        highlight_ms=5000,
        raw_bpm=90.0,
    )
    # Parse payload
    info = senseme_engine.parse_smfm_payload(night_payload)
    assert info is not None
    assert "Night" in info["channels"]
    assert "Shuffle All Songs" in info["channels"]
