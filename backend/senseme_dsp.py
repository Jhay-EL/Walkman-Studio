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
    effective_bpm: float = 0.0
    quartile_mood_scores: Optional[List[List[int]]] = None


def decode_audio_mono(audio_path: str | Path, sr: int = SAMPLE_RATE) -> np.ndarray:
    """
    Decodes input audio file (.flac, .mp3, .m4a) to mono float32 PCM at target sample rate.
    Includes a 360-second limit and non-blocking timeout protection against hanging on long/corrupt files.
    """
    cmd = [
        FFMPEG_PATH,
        "-nostdin",
        "-t", "360",
        "-i", str(audio_path),
        "-vn",
        "-ac", "1",
        "-ar", str(sr),
        "-f", "f32le",
        "pipe:1"
    ]
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        timeout=40,
        check=True
    )
    samples = np.frombuffer(proc.stdout, dtype=np.float32)
    if len(samples) == 0:
        raise ValueError(f"Failed to decode audio or file is empty: {audio_path}")
    return samples


def perform_hpss(y: np.ndarray, sr: int = SAMPLE_RATE, n_fft: int = 2048, hop_length: int = 512) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Harmonic-Percussive Source Separation using 2D median filtering on STFT.
    Optimized: directly outputs harmonic and percussive magnitude spectrograms (mag_h, mag_p)
    without redundant ISTFT-STFT cycles.
    Returns (mag_h, mag_p, freqs, times, mag).
    """
    f, t, Zxx = scipy.signal.stft(y, fs=sr, nperseg=n_fft, noverlap=n_fft - hop_length)
    mag = np.abs(Zxx)

    # Median filter: horizontal along time (axis 1) for harmonic, vertical along frequency (axis 0) for percussive
    H_filter = scipy.ndimage.median_filter(mag, size=(1, 21))
    P_filter = scipy.ndimage.median_filter(mag, size=(21, 1))

    mask_h = (H_filter ** 2) / (H_filter ** 2 + P_filter ** 2 + 1e-9)
    mask_p = (P_filter ** 2) / (H_filter ** 2 + P_filter ** 2 + 1e-9)

    mag_h = mag * mask_h
    mag_p = mag * mask_p

    return mag_h, mag_p, f, t, mag


def compute_chroma_and_modality(mag_h: np.ndarray, f: np.ndarray) -> Tuple[float, float, np.ndarray, np.ndarray]:
    """
    Computes 12-semitone chroma matrix, modality score, chroma flux, and normalized chroma matrix
    from harmonic magnitude spectrogram. Restricts FFT bins strictly to 65.41 Hz (C2) <= f <= 4186.01 Hz (C8).
    """
    # Map FFT bins to 12 semitones [C, C#, D, D#, E, F, F#, G, G#, A, A#, B]
    chroma_weights = np.zeros((12, len(f)), dtype=np.float32)
    for bin_idx, freq in enumerate(f):
        # 1. 12-Tone Chroma Frequency Bound: 65.41 Hz (C2) <= f <= 4186.01 Hz (C8)
        if freq < 65.41 or freq > 4186.01:
            continue
        midi = 69.0 + 12.0 * np.log2(freq / 440.0)
        chroma_idx = int(round(midi)) % 12
        dist = midi - round(midi)
        weight = np.exp(-0.5 * (dist / 0.25) ** 2)
        chroma_weights[chroma_idx, bin_idx] += weight

    chroma_matrix = chroma_weights @ mag_h  # (12, num_frames)
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

    return modality_score, chroma_flux, chroma_mean, chroma_matrix_norm


def compute_rhythm_and_tempo(mag_p: np.ndarray, sr: int = SAMPLE_RATE, hop_length: int = 512) -> Tuple[float, float, float]:
    """
    Computes global BPM, scale-invariant onset density, and bounded pulse clarity with
    Log-Gaussian perceptual tempo prior from percussive magnitude spectrogram.
    """
    spec_diff = np.diff(mag_p, axis=1)
    onset_env_raw = np.maximum(0.0, spec_diff).sum(axis=0)

    # 3. Scale-Invariant & Dimensionally Consistent Onset Density:
    # Ratio of temporal mean onset novelty to temporal mean frame percussive magnitude scaled by 6.0
    mean_frame_mag = float(np.mean(np.sum(mag_p, axis=0))) + 1e-6
    onset_density = float(np.mean(onset_env_raw) / mean_frame_mag) * 6.0

    # Normalized onset envelope for autocorrelation
    onset_env = onset_env_raw / (np.max(onset_env_raw) + 1e-6)

    ac = np.correlate(onset_env, onset_env, mode="full")
    ac = ac[len(onset_env) - 1:]

    frame_rate = sr / hop_length
    min_lag = int(round(frame_rate * 60.0 / 220.0))
    max_lag = int(round(frame_rate * 60.0 / 50.0))

    # 2. Autocorrelation Lag Window [tau_min, tau_max] & Perceptual Tempo Prior centered at 110 BPM
    if max_lag < len(ac) and ac[0] > 0:
        search_window = ac[min_lag : max_lag + 1]
        pulse_clarity = float(np.max(search_window) / (ac[0] + 1e-6))

        lags = np.arange(min_lag, max_lag + 1)
        bpms = 60.0 * frame_rate / lags
        prior = np.exp(-0.5 * (np.log2(bpms / 110.0) / 0.5) ** 2)
        weighted_window = search_window * prior
        peak_lag = min_lag + int(np.argmax(weighted_window))
        bpm = float(60.0 * frame_rate / peak_lag)
    else:
        pulse_clarity = 0.0
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


def detect_sabi_highlight(
    y: np.ndarray,
    chroma_matrix_norm: Optional[np.ndarray] = None,
    sr: int = SAMPLE_RATE,
    hop: int = 512
) -> Tuple[float, int]:
    """
    6. Sabi (STSA) Melodic + RMS Hook Detection.
    Combines the 15-second moving average of RMS (weight 0.65) with the 15-second moving
    average of chroma frame-to-global cosine similarity (weight 0.35) inside [0.15T, 0.80T].
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
    norm_rms_profile = smoothed_rms / (np.max(smoothed_rms) + 1e-6)

    if chroma_matrix_norm is not None and chroma_matrix_norm.shape[1] > 10:
        c_global = np.mean(chroma_matrix_norm, axis=1, keepdims=True)
        c_global_norm = c_global / (np.linalg.norm(c_global) + 1e-6)
        t_len = min(len(norm_rms_profile), chroma_matrix_norm.shape[1])
        sim = np.sum(chroma_matrix_norm[:, :t_len] * c_global_norm, axis=0)
        smoothed_sim = np.convolve(sim, window, mode="same")
        ptp_sim = float(np.ptp(smoothed_sim))
        norm_sim_profile = (smoothed_sim - np.min(smoothed_sim)) / (ptp_sim + 1e-6) if ptp_sim > 0 else np.zeros_like(smoothed_sim)
        combined = 0.65 * norm_rms_profile[:t_len] + 0.35 * norm_sim_profile[:t_len]
    else:
        combined = norm_rms_profile
        t_len = len(combined)

    intro_cut = int(round(0.15 * t_len))
    outro_cut = max(intro_cut + 1, int(round(0.80 * t_len)))

    peak_frame = intro_cut + int(np.argmax(combined[intro_cut:outro_cut]))
    highlight_sec = float(peak_frame * hop / sr)
    highlight_ms = int(round(highlight_sec * 1000))
    return highlight_sec, highlight_ms


def analyze_audio_track(audio_path: str | Path) -> AudioAnalysisResult:
    """
    Full DSP pipeline executing all 7 Sony 12 Tone & SensMe refinement requirements.
    """
    y = decode_audio_mono(audio_path, SAMPLE_RATE)
    mag_h, mag_p, freqs, times, mag = perform_hpss(y, SAMPLE_RATE)

    # 1. 12-Tone Chroma (C2 to C8 restricted)
    modality_score, chroma_flux, chroma_mean, chroma_matrix_norm = compute_chroma_and_modality(mag_h, freqs)

    # 2 & 3. Rhythm, Onset Density & Autocorrelation with Perceptual Prior
    bpm, onset_density, pulse_clarity = compute_rhythm_and_tempo(mag_p, SAMPLE_RATE)
    effective_bpm = bpm * 2.0 if bpm < 62.0 else (bpm * 0.5 if bpm > 180.0 else bpm)

    # 4. Spectral & Dynamic Measures
    rms_mean, dynamic_variance, brightness, flatness, zcr, bass_ratio = compute_spectral_and_dynamic_features(y, freqs, mag, SAMPLE_RATE)

    # Global Valence & Arousal Coordinates (-1.0 to +1.0)
    norm_bpm = float(np.clip((effective_bpm - 110.0) / 50.0, -1.0, 1.0))
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

    # 6. Sabi Highlight with 0.65 RMS + 0.35 Melodic Hook Combination
    highlight_sec, highlight_ms = detect_sabi_highlight(y, chroma_matrix_norm, SAMPLE_RATE)

    # 5. Per-Quartile STMO Computation (Q0..Q3)
    total_frames = mag.shape[1]
    q_bounds = [
        int(round(0.0 * total_frames)),
        int(round(0.25 * total_frames)),
        int(round(0.50 * total_frames)),
        int(round(0.75 * total_frames)),
        total_frames
    ]

    def compute_slot_scores_for_slice(
        q_arousal: float,
        q_valence: float,
        q_norm_bpm: float,
        q_norm_bright: float,
        q_norm_rms: float,
        q_pulse_clarity: float,
        q_dynamic_variance: float,
        q_modality_score: float,
        q_chroma_flux: float,
        q_bass_ratio: float,
        q_flatness: float,
        q_effective_bpm: float
    ) -> List[int]:
        s0 = int(np.clip(50 + 35 * q_arousal + 15 * q_norm_bpm, 0, 100))
        s1 = int(np.clip(50 - 35 * q_arousal - 15 * q_norm_bpm + 10 * q_valence, 0, 100))
        s2 = int(np.clip(50 + 40 * q_valence + 10 * q_norm_bright, 0, 100))
        s3 = int(np.clip(50 - 25 * q_arousal + 15 * (1.0 - min(q_dynamic_variance, 1.0)), 0, 100))
        s4 = int(np.clip(30 + 40 * q_dynamic_variance - 25 * q_modality_score, 0, 100))
        s5 = int(np.clip(50 + 30 * min(q_chroma_flux * 20.0, 1.0) - 20 * abs(q_norm_bpm), 0, 100))
        # 4. Re-calibrated s6 (Dance)
        s6 = int(np.clip(
            35 * min(q_pulse_clarity / 0.65, 1.0)
            + 30 * min(q_bass_ratio / 0.35, 1.0)
            + 15 * ((q_norm_rms + 1.0) / 2.0)
            + 20 * max(0.0, 1.0 - abs(q_effective_bpm - 122.0) / 35.0),
            0, 100
        ))
        s7 = int(np.clip(30 + 40 * q_arousal + 30 * min(q_flatness * 5.0, 1.0), 0, 100))
        # 4. Re-calibrated s8 (Acoustic)
        s8 = int(np.clip(
            35 + 25 * (1.0 - min(5.0 * q_flatness, 1.0))
            + 25 * min(q_dynamic_variance, 1.0)
            - 30 * min(q_bass_ratio / 0.30, 1.0)
            - 15 * max(0.0, q_norm_rms),
            0, 100
        ))
        # 4. Re-calibrated s9 (Electronic)
        s9 = int(np.clip(
            20 + 30 * min(q_pulse_clarity / 0.60, 1.0)
            + 30 * min(q_bass_ratio / 0.35, 1.0)
            + 20 * (1.0 - min(q_dynamic_variance, 1.0)),
            0, 100
        ))
        return [s0, s1, s2, s3, s4, s5, s6, s7, s8, s9]

    quartile_scores_by_q: List[List[int]] = []
    hop = 512
    frame_size = 2048

    for q in range(4):
        sf_start = q_bounds[q]
        sf_end = max(sf_start + 1, q_bounds[q + 1])
        mag_slice = mag[:, sf_start:sf_end]

        # Slice dynamic features
        samp_start = sf_start * hop
        samp_end = min(len(y), sf_end * hop + frame_size)
        y_slice = y[samp_start:samp_end] if samp_end > samp_start else y

        n_slice_frames = max(1, (len(y_slice) - frame_size) // hop + 1)
        if len(y_slice) >= frame_size:
            rms_slice_curve = np.array([np.sqrt(np.mean(y_slice[i * hop : i * hop + frame_size] ** 2)) for i in range(n_slice_frames)])
        else:
            rms_slice_curve = np.array([rms_mean])
        rms_slice_mean = float(np.mean(rms_slice_curve))
        dynamic_var_slice = float(np.std(rms_slice_curve) / (rms_slice_mean + 1e-6))

        spec_sum_slice = np.sum(mag_slice, axis=0) + 1e-9
        centroid_slice = np.sum(freqs[:, np.newaxis] * mag_slice, axis=0) / spec_sum_slice
        bright_slice = float(np.mean(centroid_slice) / (SAMPLE_RATE / 2.0))

        geom_mean_slice = np.exp(np.mean(np.log(mag_slice + 1e-9), axis=0))
        arith_mean_slice = np.mean(mag_slice, axis=0) + 1e-9
        flatness_slice = float(np.mean(geom_mean_slice / arith_mean_slice))

        bass_mask = freqs <= 150.0
        bass_ratio_slice = float(np.sum(mag_slice[bass_mask, :] ** 2) / (np.sum(mag_slice ** 2) + 1e-9))

        if chroma_matrix_norm.shape[1] > sf_end and sf_end > sf_start + 1:
            c_diff_slice = np.diff(chroma_matrix_norm[:, sf_start:sf_end], axis=1)
            chroma_flux_slice = float(np.mean(c_diff_slice ** 2))
        else:
            chroma_flux_slice = chroma_flux

        norm_rms_q = float(np.clip((rms_slice_mean - 0.12) / 0.12, -1.0, 1.0))
        norm_bright_q = float(np.clip((bright_slice - 0.18) / 0.12, -1.0, 1.0))

        arousal_q = float(np.clip(
            0.35 * norm_bpm + 0.35 * norm_rms_q + 0.20 * norm_onset + 0.10 * np.tanh(flatness_slice * 15.0),
            -1.0, 1.0
        ))
        valence_q = float(np.clip(
            0.50 * modality_score + 0.30 * norm_bright_q + 0.20 * np.clip((pulse_clarity - 0.4) * 2.0, -1.0, 1.0),
            -1.0, 1.0
        ))

        q_scores = compute_slot_scores_for_slice(
            q_arousal=arousal_q,
            q_valence=valence_q,
            q_norm_bpm=norm_bpm,
            q_norm_bright=norm_bright_q,
            q_norm_rms=norm_rms_q,
            q_pulse_clarity=pulse_clarity,
            q_dynamic_variance=dynamic_var_slice,
            q_modality_score=modality_score,
            q_chroma_flux=chroma_flux_slice,
            q_bass_ratio=bass_ratio_slice,
            q_flatness=flatness_slice,
            q_effective_bpm=effective_bpm
        )
        quartile_scores_by_q.append(q_scores)

    # 10 moods x 4 quartiles for binary STMO packing
    quartile_mood_scores: List[List[int]] = [
        [quartile_scores_by_q[q][m] for q in range(4)]
        for m in range(10)
    ]

    # Mean across quartiles used for channel assignment
    mood_scores = [
        int(np.clip(round(float(np.mean([quartile_scores_by_q[q][m] for q in range(4)]))), 0, 100))
        for m in range(10)
    ]

    s0, s1, s2, s3, s4, s5, s6, s7, s8, s9 = mood_scores

    # 7. Strict 14 Official Sony Walkman Channels & Time-of-Day Guardrails
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
    if s7 >= 60 or arousal >= 0.65 or (flatness >= 0.04 or zcr >= 0.12 or effective_bpm >= 145):
        mood_candidates.append("Extreme")
    if s6 >= 45 or (105 <= effective_bpm <= 140 and arousal >= 0.20):
        mood_candidates.append("Dance")
    if s5 >= 45 or (80 <= effective_bpm <= 120 and -0.40 <= arousal <= 0.30):
        mood_candidates.append("Lounge")

    # Fallback: if 0 mood channels qualified, assign top STMO score from slots 0..7
    if not mood_candidates:
        mood_names_8 = ["Energetic", "Relax", "Upbeat", "Mellow", "Emotional", "Lounge", "Dance", "Extreme"]
        best_mood_idx = int(np.argmax(mood_scores[:8]))
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

    # Circadian Fallback: guarantees at least 1 Time-of-Day channel
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
        channels=list(dict.fromkeys(channels)),
        effective_bpm=round(effective_bpm, 1),
        quartile_mood_scores=quartile_mood_scores
    )
