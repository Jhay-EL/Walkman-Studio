"""
Sony 12 Tone Analysis DSP Mathematical Engine.
Implements the acoustic feature extraction pipeline:
1. Signal Pre-processing (mono PCM @ 22050 Hz, HPSS)
2. Pitch Class Profiling (12-Tone Chroma) & Modality
3. Rhythm, Tempo (GBPM) & Pulse Clarity
4. Spectral & Dynamic Features
5. Valence & Arousal Coordinates (-1.0 to +1.0)
6. Chorus / Highlight ("Sabi" Timestamp)
7. SenseMe Channel Classification & STMO 10-Slot Vector Mapping
"""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

import numpy as np
import scipy.ndimage
import scipy.signal

FFMPEG_PATH = "/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else (shutil.which("ffmpeg") or "ffmpeg")
SAMPLE_RATE = 22050

# Krumhansl-Schmuckler Key Profiles (12 semitones C to B)
MAJOR_PROFILE_RAW = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88], dtype=np.float32)
MINOR_PROFILE_RAW = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17], dtype=np.float32)


@dataclass
class AudioAnalysisResult:
    bpm: float
    raw_bpm: float
    valence: float
    arousal: float
    modality_score: float
    pulse_clarity: float
    dynamic_variance: float
    brightness: float
    flatness: float
    zcr: float
    bass_ratio: float
    chroma_flux: float
    highlight_sec: float
    highlight_ms: int
    mood_scores: List[int]
    channels: List[str]


def decode_audio_mono(audio_path: str | Path, sr: int = SAMPLE_RATE) -> np.ndarray:
    """
    Decodes input audio file (.flac, .mp3, .m4a) to mono float32 PCM at target sample rate.
    """
    cmd = [
        FFMPEG_PATH,
        "-i", str(audio_path),
        "-vn",
        "-ac", "1",
        "-ar", str(sr),
        "-f", "f32le",
        "pipe:1"
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
    samples = np.frombuffer(proc.stdout, dtype=np.float32)
    if len(samples) == 0:
        raise ValueError(f"Failed to decode audio or file is empty: {audio_path}")
    return samples


def perform_hpss(y: np.ndarray, sr: int = SAMPLE_RATE, n_fft: int = 2048, hop_length: int = 512) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Harmonic-Percussive Source Separation using median filtering on STFT.
    Returns (y_harmonic, y_percussive, freqs, times, mag_spectrogram).
    """
    f, t, Zxx = scipy.signal.stft(y, fs=sr, nperseg=n_fft, noverlap=n_fft - hop_length)
    mag = np.abs(Zxx)

    # Median filter: horizontal along time (axis 1) for harmonic, vertical along frequency (axis 0) for percussive
    H_filter = scipy.ndimage.median_filter(mag, size=(1, 31))
    P_filter = scipy.ndimage.median_filter(mag, size=(31, 1))

    mask_h = (H_filter ** 2) / (H_filter ** 2 + P_filter ** 2 + 1e-9)
    mask_p = (P_filter ** 2) / (H_filter ** 2 + P_filter ** 2 + 1e-9)

    Z_h = Zxx * mask_h
    Z_p = Zxx * mask_p

    _, y_h = scipy.signal.istft(Z_h, fs=sr, nperseg=n_fft, noverlap=n_fft - hop_length)
    _, y_p = scipy.signal.istft(Z_p, fs=sr, nperseg=n_fft, noverlap=n_fft - hop_length)

    min_len = min(len(y), len(y_h), len(y_p))
    return y_h[:min_len], y_p[:min_len], f, t, mag


def compute_chroma_and_modality(y_h: np.ndarray, sr: int = SAMPLE_RATE, n_fft: int = 2048, hop_length: int = 512) -> Tuple[float, float, np.ndarray]:
    """
    Computes 12-semitone chroma matrix, modality score, and chroma flux.
    """
    f, _, Z_h = scipy.signal.stft(y_h, fs=sr, nperseg=n_fft, noverlap=n_fft - hop_length)
    mag_h = np.abs(Z_h)

    # Map FFT bins to 12 semitones [C, C#, D, D#, E, F, F#, G, G#, A, A#, B]
    chroma_weights = np.zeros((12, len(f)), dtype=np.float32)
    for bin_idx, freq in enumerate(f):
        if freq < 65.4: # Below C2
            continue
        midi = 69.0 + 12.0 * np.log2(freq / 440.0)
        chroma_idx = int(round(midi)) % 12
        dist = midi - round(midi)
        weight = np.exp(-0.5 * (dist / 0.25) ** 2)
        chroma_weights[chroma_idx, bin_idx] += weight

    chroma_matrix = chroma_weights @ mag_h # (12, num_frames)
    norm = np.linalg.norm(chroma_matrix, axis=0, keepdims=True) + 1e-6
    chroma_matrix_norm = chroma_matrix / norm
    chroma_mean = np.mean(chroma_matrix_norm, axis=1)

    # Normalize K-S profiles
    maj_prof = (MAJOR_PROFILE_RAW - np.mean(MAJOR_PROFILE_RAW)) / (np.std(MAJOR_PROFILE_RAW) + 1e-6)
    min_prof = (MINOR_PROFILE_RAW - np.mean(MINOR_PROFILE_RAW)) / (np.std(MINOR_PROFILE_RAW) + 1e-6)
    chroma_norm_vec = (chroma_mean - np.mean(chroma_mean)) / (np.std(chroma_mean) + 1e-6)

    best_major_corr = max(float(np.dot(chroma_norm_vec, np.roll(maj_prof, s)) / 12.0) for s in range(12))
    best_minor_corr = max(float(np.dot(chroma_norm_vec, np.roll(min_prof, s)) / 12.0) for s in range(12))

    modality_score = float(np.clip((best_major_corr - best_minor_corr) * 2.5, -1.0, 1.0))
    chroma_diff = np.diff(chroma_matrix_norm, axis=1)
    chroma_flux = float(np.mean(chroma_diff ** 2))

    return modality_score, chroma_flux, chroma_mean


def compute_rhythm_and_tempo(y_p: np.ndarray, sr: int = SAMPLE_RATE, n_fft: int = 2048, hop_length: int = 512) -> Tuple[float, float, float]:
    """
    Computes global BPM, onset density, and pulse clarity on y_percussive.
    """
    _, _, Z_p = scipy.signal.stft(y_p, fs=sr, nperseg=n_fft, noverlap=n_fft - hop_length)
    mag_p = np.abs(Z_p)

    spec_diff = np.diff(mag_p, axis=1)
    onset_env = np.maximum(0.0, spec_diff).sum(axis=0)
    onset_env = onset_env / (np.max(onset_env) + 1e-6)
    onset_density = float(np.mean(onset_env))

    ac = np.correlate(onset_env, onset_env, mode="full")
    ac = ac[len(onset_env) - 1:]

    pulse_clarity = float(np.max(ac[1:]) / (ac[0] + 1e-6)) if len(ac) > 1 and ac[0] > 0 else 0.0

    frame_rate = sr / hop_length
    min_lag = int(round(frame_rate * 60.0 / 220.0))
    max_lag = int(round(frame_rate * 60.0 / 50.0))

    if max_lag < len(ac):
        peak_lag = min_lag + int(np.argmax(ac[min_lag : max_lag + 1]))
        bpm = float(60.0 * frame_rate / peak_lag)
    else:
        bpm = 120.0

    return bpm, onset_density, pulse_clarity


def compute_spectral_and_dynamic_features(y: np.ndarray, freqs: np.ndarray, mag: np.ndarray, sr: int = SAMPLE_RATE) -> Tuple[float, float, float, float, float, float]:
    """
    Computes rms_mean, dynamic_variance, brightness, flatness, zcr, bass_ratio.
    """
    frame_size = 2048
    hop = 512
    num_frames = (len(y) - frame_size) // hop + 1
    if num_frames > 0:
        rms_curve = np.array([np.sqrt(np.mean(y[i * hop : i * hop + frame_size] ** 2)) for i in range(num_frames)])
    else:
        rms_curve = np.array([np.sqrt(np.mean(y ** 2))])
    rms_mean = float(np.mean(rms_curve))
    dynamic_variance = float(np.std(rms_curve) / (rms_mean + 1e-6))

    spec_sum = np.sum(mag, axis=0) + 1e-9
    centroid = np.sum(freqs[:, np.newaxis] * mag, axis=0) / spec_sum
    brightness = float(np.mean(centroid) / (sr / 2.0))

    geom_mean = np.exp(np.mean(np.log(mag + 1e-9), axis=0))
    arith_mean = np.mean(mag, axis=0) + 1e-9
    flatness = float(np.mean(geom_mean / arith_mean))

    zcr = float(np.mean(np.abs(np.diff(np.sign(y)))) / 2.0)

    bass_mask = freqs <= 150.0
    bass_energy = np.sum(mag[bass_mask, :] ** 2)
    total_energy = np.sum(mag ** 2) + 1e-9
    bass_ratio = float(bass_energy / total_energy)

    return rms_mean, dynamic_variance, brightness, flatness, zcr, bass_ratio


def detect_sabi_highlight(y: np.ndarray, sr: int = SAMPLE_RATE, hop: int = 512) -> Tuple[float, int]:
    """
    Chorus / Highlight Detection ("Sabi" Timestamp).
    Convolves RMS curve with a 15-second window, skipping intro 15% and outro 20%.
    """
    frame_size = 2048
    num_frames = (len(y) - frame_size) // hop + 1
    if num_frames <= 10:
        return 0.0, 0

    rms = np.array([np.sqrt(np.mean(y[i * hop : i * hop + frame_size] ** 2)) for i in range(num_frames)])
    frame_rate = sr / hop
    window_frames = max(5, int(round(15.0 * frame_rate)))
    window = np.ones(window_frames) / window_frames
    smoothed_rms = np.convolve(rms, window, mode="same")

    intro_cut = int(round(0.15 * len(smoothed_rms)))
    outro_cut = max(intro_cut + 1, int(round(0.80 * len(smoothed_rms))))

    peak_frame = intro_cut + int(np.argmax(smoothed_rms[intro_cut:outro_cut]))
    highlight_sec = float(peak_frame * hop / sr)
    highlight_ms = int(round(highlight_sec * 1000))
    return highlight_sec, highlight_ms


def analyze_audio_track(audio_path: str | Path) -> AudioAnalysisResult:
    """
    Full DSP pipeline executing all 7 Phase 2 requirements.
    """
    y = decode_audio_mono(audio_path, SAMPLE_RATE)
    y_h, y_p, freqs, times, mag = perform_hpss(y, SAMPLE_RATE)

    modality_score, chroma_flux, chroma_mean = compute_chroma_and_modality(y_h, SAMPLE_RATE)
    bpm, onset_density, pulse_clarity = compute_rhythm_and_tempo(y_p, SAMPLE_RATE)
    rms_mean, dynamic_variance, brightness, flatness, zcr, bass_ratio = compute_spectral_and_dynamic_features(y, freqs, mag, SAMPLE_RATE)

    # 5. Valence & Arousal Coordinates (-1.0 to +1.0)
    norm_bpm = float(np.clip((bpm - 110.0) / 50.0, -1.0, 1.0))
    norm_rms = float(np.clip((rms_mean - 0.12) / 0.12, -1.0, 1.0))
    norm_onset = float(np.clip((onset_density - 1.5) / 1.5, -1.0, 1.0))
    norm_bright = float(np.clip((brightness - 0.18) / 0.12, -1.0, 1.0))

    arousal = float(np.clip(
        0.35 * norm_bpm + 0.35 * norm_rms + 0.20 * norm_onset + 0.10 * np.tanh(flatness * 15.0),
        -1.0, 1.0
    ))
    valence = float(np.clip(
        0.50 * modality_score + 0.30 * norm_bright + 0.20 * np.clip((pulse_clarity - 0.4) * 2.0, -1.0, 1.0),
        -1.0, 1.0
    ))

    # 6. Sabi Highlight
    highlight_sec, highlight_ms = detect_sabi_highlight(y, SAMPLE_RATE)

    # 7. SenseMe Channel Classification & STMO 10-Slot Vector Mapping
    channels: List[str] = []
    if arousal >= 0.45 and valence >= 0.15 and bpm >= 118:
        channels.append("Energetic")
    if arousal <= -0.25 and valence >= -0.25 and bpm <= 98:
        channels.append("Relax")
    if valence >= 0.35 and 0.05 <= arousal <= 0.65 and 100 <= bpm <= 135:
        channels.append("Upbeat")
    if -0.75 <= arousal <= -0.10 and -0.35 <= valence <= 0.40:
        channels.append("Mellow")
    if valence <= -0.10 and -0.55 <= arousal <= 0.40 and dynamic_variance >= 0.35:
        channels.append("Emotional")
    if arousal >= 0.65 and (flatness >= 0.04 or zcr >= 0.12 or bpm >= 145):
        channels.append("Extreme")
    if 108 <= bpm <= 138 and pulse_clarity >= 0.45 and bass_ratio >= 0.28 and arousal >= 0.25:
        channels.append("Dance")
    if 82 <= bpm <= 116 and -0.40 <= arousal <= 0.25 and chroma_flux >= 0.002:
        channels.append("Lounge")

    # Time-of-Day Channels
    if "Upbeat" in channels or "Acoustic" in channels or valence > 0.15:
        channels.append("Morning")
    if "Energetic" in channels or "Upbeat" in channels or valence > 0.1:
        channels.append("Daytime")
    if "Mellow" in channels or "Relax" in channels or "Lounge" in channels:
        channels.append("Evening")
    if "Relax" in channels or "Mellow" in channels or arousal <= -0.10:
        channels.append("Midnight")

    # Map to 10 STMO Mood Slots [0..9]
    # Slot 0: Energetic
    s0 = int(np.clip(50 + 35 * arousal + 15 * norm_bpm, 0, 100))
    # Slot 1: Relax
    s1 = int(np.clip(50 - 35 * arousal - 15 * norm_bpm + 10 * valence, 0, 100))
    # Slot 2: Upbeat
    s2 = int(np.clip(50 + 40 * valence + 10 * norm_bright, 0, 100))
    # Slot 3: Mellow
    s3 = int(np.clip(50 - 25 * arousal + 15 * (1.0 - min(dynamic_variance, 1.0)), 0, 100))
    # Slot 4: Emotional
    s4 = int(np.clip(30 + 40 * dynamic_variance - 25 * modality_score, 0, 100))
    # Slot 5: Lounge
    s5 = int(np.clip(50 + 30 * min(chroma_flux * 20.0, 1.0) - 20 * abs(norm_bpm), 0, 100))
    # Slot 6: Dance
    if 100 <= bpm <= 145 and pulse_clarity >= 0.4:
        s6 = int(np.clip(40 * pulse_clarity + 40 * bass_ratio + 20 * norm_rms, 0, 100))
    else:
        s6 = 0
    # Slot 7: Extreme
    s7 = int(np.clip(30 + 40 * arousal + 30 * min(flatness * 5.0, 1.0), 0, 100))
    # Slot 8: Acoustic
    s8 = int(np.clip(50 + 30 * (1.0 - min(flatness * 5.0, 1.0)) + 20 * min(dynamic_variance, 1.0), 0, 100))
    # Slot 9: Electronic
    s9 = int(np.clip(50 + 25 * pulse_clarity + 25 * (1.0 - min(dynamic_variance, 1.0)), 0, 100))

    mood_scores = [s0, s1, s2, s3, s4, s5, s6, s7, s8, s9]

    # Additional channel checks from scores
    if s8 >= 60 and "Acoustic" not in channels:
        channels.append("Acoustic")
    if s9 >= 65 and "Electronic" not in channels:
        channels.append("Electronic")

    raw_bpm = float(bpm)

    return AudioAnalysisResult(
        bpm=round(bpm, 1),
        raw_bpm=raw_bpm,
        valence=round(valence, 2),
        arousal=round(arousal, 2),
        modality_score=round(modality_score, 3),
        pulse_clarity=round(pulse_clarity, 3),
        dynamic_variance=round(dynamic_variance, 3),
        brightness=round(brightness, 3),
        flatness=round(flatness, 4),
        zcr=round(zcr, 4),
        bass_ratio=round(bass_ratio, 3),
        chroma_flux=round(chroma_flux, 5),
        highlight_sec=round(highlight_sec, 3),
        highlight_ms=highlight_ms,
        mood_scores=mood_scores,
        channels=list(dict.fromkeys(channels))
    )
