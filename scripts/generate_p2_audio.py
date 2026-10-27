#!/usr/bin/env python3
"""Original P2 arcade effects: deterministic synthesis, WAV encoding and offline QA.

No external sound files feed the synthesis. Existing meow.wav is read ONLY for
an unchanged-byte check and mixed-headroom analysis. Python 3 + NumPy required.
Run from any directory: python3 scripts/generate_p2_audio.py
Verify without writing: python3 scripts/generate_p2_audio.py --check
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import sys
import wave

import numpy as np

RATE = 48000
PEAK_DBFS = -10.5
MAX_PCM = math.floor(32768 * 10 ** (PEAK_DBFS / 20))
ROOT = Path(__file__).resolve().parents[1]
MEOW_SHA256 = "551cc7c8a4c90e6a120de466707ba36670f05dc8e0d96223a8a355b47cfd3eb2"
SOURCE_MEOW_SHA256 = "a3af64f8c9dd921343f076d7ed3bcfc9d0f7db49b84e6a81c84fae72d1c8b38d"
BANDS = [("sub_0_100_hz", 0, 100), ("body_100_250_hz", 100, 250),
         ("low_mid_250_1000_hz", 250, 1000), ("phone_mid_1000_4000_hz", 1000, 4000),
         ("air_4000_8000_hz", 4000, 8000), ("high_8000_24000_hz", 8000, 24001)]
# Duration, per-player recommended LINEAR gain, group, design intent.
CUES = {
    "swing_punch": (0.125, 0.12, "combat", "Compact cloth/air sweep, no contact thump."),
    "swing_kick": (0.195, 0.14, "combat", "Wider double air sweep with low-mid cloth movement."),
    "hit_light": (0.105, 0.20, "combat", "One short dry padded snap; front-hand jab."),
    "hit_straight": (0.165, 0.22, "combat", "Firm leading strike plus delayed low-mid body, not pitched jab."),
    "hit_heavy": (0.250, 0.24, "combat", "Rounded broad thump, midrange slap and damped body tail."),
    "hit_kick": (0.215, 0.23, "combat", "Wide slap followed by a separate cushioned body pulse."),
    "block": (0.115, 0.18, "combat", "Short muted glove clack with little low-end impact."),
    "guard_break": (0.270, 0.22, "combat", "Three soft staggered clacks and a broad cloth release."),
    "jump": (0.105, 0.10, "combat", "Light cloth lift and muted foot release."),
    "land": (0.120, 0.12, "combat", "Two closely spaced cushioned sole contacts."),
    "down_land": (0.245, 0.20, "combat", "Two low-mid padded contacts with short stage resonance."),
    "ko": (0.325, 0.22, "combat", "Two soft downward resolving resonances, no voice or gore."),
    "ui_confirm": (0.105, 0.12, "ui", "Soft tactile two-part wood/click confirmation."),
    "heart_emit": (0.185, 0.14, "combat", "Warm airy pop with two short upward body pulses."),
}


def db(value: float) -> float:
    return round(20 * math.log10(max(float(value), 1e-15)), 6)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def white_noise(count: int, seed: int) -> np.ndarray:
    """Own stable xorshift32 stream; independent of NumPy random versions."""
    state = seed or 1
    out = np.empty(count, dtype=np.float64)
    for index in range(count):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        state &= 0xFFFFFFFF
        out[index] = state / 2147483648.0 - 1.0
    return out


def lowpass(data: np.ndarray, cutoff: float) -> np.ndarray:
    coefficient = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    result = np.empty_like(data)
    state = 0.0
    for index, value in enumerate(data):
        state += coefficient * (float(value) - state)
        result[index] = state
    return result


def band_noise(count: int, seed: int, low: float, high: float) -> np.ndarray:
    data = white_noise(count, seed)
    data = lowpass(lowpass(data, high), high)
    data = data - lowpass(data, low)
    data = data - lowpass(data, low)
    return data / max(float(np.sqrt(np.mean(data * data))), 1e-12)


def shape(t: np.ndarray, offset: float, attack: float, decay: float) -> np.ndarray:
    age = np.maximum(t - offset, 0.0)
    return (1.0 - np.exp(-age / attack)) * np.exp(-age / decay) * (t >= offset)


def synthesize(cue: str, variant: int) -> tuple[bytes, dict]:
    duration, _, _, intent = CUES[cue]
    # Variant 2 is only slightly longer; seed, transient and modal damping vary too.
    duration += 0.004 if variant == 2 else 0.0
    count = round(duration * RATE)
    t = np.arange(count, dtype=np.float64) / RATE
    data = np.zeros(count, dtype=np.float64)
    seed = int.from_bytes(hashlib.sha256(f"livehouse-p2-v1/{cue}/{variant}".encode()).digest()[:4], "little")
    layer = 0
    v = variant - 1
    timbre = 1.0 - 0.035 * v
    descriptors = []

    def noise(gain, low, high, offset=0.0, attack=0.0008, decay=0.02):
        nonlocal data, layer
        layer += 1
        data += gain * band_noise(count, (seed + layer * 104729) & 0xFFFFFFFF, low, high) * shape(t, offset, attack, decay)
        descriptors.append({"kind": "filtered_noise", "gain": gain, "band_hz": [low, high],
                            "offset_seconds": offset, "attack_seconds": attack, "decay_seconds": decay})

    def body(gain, frequency, offset=0.0, attack=0.0012, decay=0.035, drop=0.12, ratios=(1.0, 1.67, 2.43)):
        nonlocal data
        z = np.maximum(t - offset, 0.0)
        f = frequency * timbre
        # Integrated exponential pitch settling + non-harmonic damped modes.
        phase = 2 * np.pi * (f * z + f * drop * 0.010 * (1 - np.exp(-z / 0.010)))
        modes = np.zeros(count, dtype=np.float64)
        for index, ratio in enumerate(ratios):
            modes += (0.56 ** index) * np.sin(phase * ratio + index * 0.19) * np.exp(-z * index / (decay * 1.8))
        data += gain * modes * shape(t, offset, attack, decay)
        descriptors.append({"kind": "damped_inharmonic_body", "gain": gain, "base_hz": f,
                            "ratios": list(ratios), "offset_seconds": offset,
                            "attack_seconds": attack, "decay_seconds": decay, "settling_fraction": drop})

    if cue == "swing_punch":
        noise(0.42, 650, 4300, attack=0.008, decay=0.025)
        noise(0.16, 280, 1300, offset=0.016 + v * 0.002, attack=0.009, decay=0.019)
        body(0.08, 490, offset=0.004, attack=0.006, decay=0.017, drop=-0.12)
    elif cue == "swing_kick":
        noise(0.38, 440, 3100, attack=0.012, decay=0.040)
        noise(0.20, 1000, 5500, offset=0.025 + v * 0.002, attack=0.009, decay=0.031)
        body(0.13, 360, offset=0.009, attack=0.008, decay=0.028, drop=-0.10)
    elif cue == "hit_light":
        noise(0.47, 800, 5600, attack=0.0005, decay=0.009)
        noise(0.18, 350, 1700, attack=0.001, decay=0.016)
        body(0.58, 340, attack=0.0008, decay=0.018)
        body(0.17, 710, offset=0.003, decay=0.011)
    elif cue == "hit_straight":
        noise(0.36, 800, 4600, attack=0.0006, decay=0.012)
        noise(0.20, 450, 2200, offset=0.010 + v * 0.001, decay=0.021)
        body(0.58, 285, attack=0.0011, decay=0.032)
        body(0.30, 460, offset=0.019 + v * 0.002, attack=0.0018, decay=0.023)
        body(0.13, 900, offset=0.004, decay=0.010)
    elif cue == "hit_heavy":
        noise(0.40, 650, 4600, attack=0.0009, decay=0.016)
        noise(0.25, 220, 1350, offset=0.010 + v * 0.002, attack=0.002, decay=0.040)
        body(0.59, 185, attack=0.002, decay=0.047, drop=0.20)
        body(0.42, 390, offset=0.008, decay=0.038)
        body(0.22, 720, offset=0.004, decay=0.025)
    elif cue == "hit_kick":
        noise(0.46, 650, 5100, attack=0.0008, decay=0.018)
        noise(0.20, 230, 1600, offset=0.018, attack=0.004, decay=0.034)
        body(0.56, 245, attack=0.0012, decay=0.034)
        body(0.33, 365, offset=0.026 + v * 0.002, attack=0.002, decay=0.031)
        body(0.19, 820, offset=0.004, decay=0.013)
    elif cue == "block":
        noise(0.40, 950, 5000, decay=0.009)
        noise(0.13, 350, 1700, offset=0.006, decay=0.018)
        body(0.42, 700, decay=0.014, drop=0.015, ratios=(1.0, 1.46, 2.11))
        body(0.19, 380, offset=0.003, decay=0.018)
    elif cue == "guard_break":
        for offset, level, frequency in [(0.0, 0.40, 610), (0.027, 0.30, 470), (0.059 + v * 0.002, 0.23, 355)]:
            noise(level, 650, 4200, offset=offset, decay=0.013)
            body(level, frequency, offset=offset, decay=0.022, drop=0.035)
        noise(0.19, 300, 1700, offset=0.045, attack=0.007, decay=0.043)
    elif cue == "jump":
        noise(0.32, 650, 3300, attack=0.004, decay=0.017)
        body(0.18, 450, attack=0.003, decay=0.016, drop=-0.10)
        noise(0.10, 250, 1100, decay=0.009)
    elif cue == "land":
        for offset, level in [(0.0, 0.38), (0.016 + v * 0.002, 0.22)]:
            noise(level, 420, 2800, offset=offset, decay=0.010)
            body(level * 1.3, 300, offset=offset, decay=0.019)
    elif cue == "down_land":
        noise(0.36, 350, 3300, decay=0.022)
        body(0.59, 190, attack=0.002, decay=0.044)
        body(0.32, 360, offset=0.008, decay=0.039)
        noise(0.26, 450, 2600, offset=0.036 + v * 0.002, decay=0.022)
        body(0.28, 285, offset=0.039 + v * 0.002, decay=0.033)
    elif cue == "ko":
        noise(0.24, 500, 3000, decay=0.024)
        body(0.43, 400, attack=0.002, decay=0.045, drop=0.12)
        noise(0.19, 350, 2300, offset=0.074 + v * 0.002, decay=0.027)
        body(0.52, 265, offset=0.077 + v * 0.002, attack=0.003, decay=0.048, drop=0.08)
        body(0.14, 790, offset=0.080, decay=0.025)
    elif cue == "ui_confirm":
        noise(0.22, 950, 4300, decay=0.005)
        body(0.30, 950, attack=0.0007, decay=0.012, drop=0.02, ratios=(1.0, 1.48, 2.15))
        body(0.25, 1270, offset=0.025 + v * 0.001, decay=0.013, drop=0.015, ratios=(1.0, 1.41, 2.06))
        noise(0.10, 1200, 4500, offset=0.026, decay=0.005)
    elif cue == "heart_emit":
        noise(0.27, 750, 3600, attack=0.003, decay=0.026)
        body(0.35, 540, attack=0.002, decay=0.025, drop=-0.11)
        body(0.26, 760, offset=0.029 + v * 0.002, attack=0.003, decay=0.028, drop=-0.06)
        noise(0.14, 1600, 5300, offset=0.019, attack=0.008, decay=0.026)
    else:
        raise ValueError(cue)

    # Two mild high-pass stages remove rumble without relying on sub-bass.
    data -= lowpass(data, 95)
    data -= lowpass(data, 95)
    fade = np.ones(count)
    fade_in = round(0.0012 * RATE)
    fade_out = round(min(0.018, duration * 0.14) * RATE)
    fade[:fade_in] = np.sin(np.linspace(0, np.pi / 2, fade_in)) ** 2
    fade[-fade_out:] = np.sin(np.linspace(np.pi / 2, 0, fade_out)) ** 2
    data *= fade
    data -= float(np.sum(data)) * fade / float(np.sum(fade))
    data[:2] = 0
    data[-2:] = 0
    data *= MAX_PCM / max(float(np.max(np.abs(data))), 1e-12)
    pcm = np.rint(data).astype(np.int32)
    # Exact integer DC cancellation without changing endpoint zeros or peak cap.
    residual = int(np.sum(pcm, dtype=np.int64))
    if residual:
        candidates = np.flatnonzero((pcm * (1 if residual > 0 else -1) > 32))
        if len(candidates) < abs(residual):
            raise AssertionError("Too few cancellation samples")
        indices = candidates[np.linspace(0, len(candidates) - 1, abs(residual), dtype=int)]
        pcm[indices] -= 1 if residual > 0 else -1
    assert int(np.sum(pcm, dtype=np.int64)) == 0
    assert int(np.max(np.abs(pcm))) <= MAX_PCM
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.astype("<i2").tobytes())
    return buffer.getvalue(), {"deterministic_seed": seed, "design_intent": intent, "layers": descriptors}


def decode(data: bytes) -> tuple[np.ndarray, int]:
    with wave.open(io.BytesIO(data), "rb") as source:
        assert source.getnchannels() == 1 and source.getsampwidth() == 2
        rate = source.getframerate()
        values = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64) / 32768
    return values, rate


def reconstruction_peak(values: np.ndarray, factor: int = 8) -> float:
    """FFT-interpolated peak estimate, not an ITU-certified true-peak meter."""
    spectrum = np.fft.rfft(values)
    if len(values) % 2 == 0:
        spectrum[-1] *= 0.5
    return float(np.max(np.abs(np.fft.irfft(spectrum, n=len(values) * factor) * factor)))


def analyze(data: bytes) -> dict:
    values, rate = decode(data)
    # Whole-file FFT energy: fractions add to 1 (half-open bands, Nyquist included).
    spectrum = np.abs(np.fft.rfft(values)) ** 2
    if len(values) % 2 == 0:
        spectrum[1:-1] *= 2
    else:
        spectrum[1:] *= 2
    frequencies = np.fft.rfftfreq(len(values), 1 / rate)
    total = max(float(np.sum(spectrum)), 1e-30)
    bands = {name: round(float(np.sum(spectrum[(frequencies >= lo) & (frequencies < hi)])) / total, 8)
             for name, lo, hi in BANDS}
    phone = round(sum(bands[name] for name in ["low_mid_250_1000_hz", "phone_mid_1000_4000_hz"]), 8)
    peak = float(np.max(np.abs(values)))
    reconstructed_peak = reconstruction_peak(values)
    rms = float(np.sqrt(np.mean(values * values)))
    tail_rms = float(np.sqrt(np.mean(values[-round(rate * 0.004):] ** 2)))
    peak_first4 = float(np.max(np.abs(values[:4])))
    peak_last4 = float(np.max(np.abs(values[-4:])))
    # Quantitative gates are technical checks, not an assertion of phone audibility.
    checks = {
        "mono_pcm16_48khz": rate == RATE,
        "duration_070_to_350_ms": 0.07 <= len(values) / rate <= 0.35,
        "peak_below_minus_8_dbfs": peak <= 10 ** (-8 / 20),
        "eightfold_peak_estimate_below_minus_8_dbfs": reconstructed_peak <= 10 ** (-8 / 20),
        "non_silent": rms > 0.005,
        "zero_integer_dc": abs(float(np.sum(values))) < 1e-12,
        "zero_endpoints": bool(values[0] == 0 and values[-1] == 0),
        "quiet_endpoint_neighbors": max(peak_first4, peak_last4) <= 0.005,
        "tail_last_4ms_below_minus_50_dbfs": tail_rms <= 10 ** (-50 / 20),
        "phone_band_fraction_above_55_percent": phone >= 0.55,
        "sub100_fraction_below_8_percent": bands["sub_0_100_hz"] < 0.08,
        "not_clipped": peak < 0.999,
    }
    return {"duration_seconds": round(len(values) / rate, 9), "sample_count": len(values),
            "sample_rate_hz": rate, "channels": 1, "encoding": "signed PCM 16-bit little endian",
            "bytes": len(data), "sha256": sha(data), "sample_peak_linear": round(peak, 9),
            "sample_peak_dbfs": db(peak), "eightfold_fft_peak_estimate_dbfs": db(reconstructed_peak), "rms_dbfs": db(rms), "dc_mean": float(np.mean(values)),
            "first_sample": float(values[0]), "last_sample": float(values[-1]),
            "tail_last_4ms_rms_dbfs": db(tail_rms), "band_energy_fraction": bands,
            "phone_band_250_4000_fraction": phone, "checks": checks}


def mix_checks(bank: dict[str, bytes], meow: bytes) -> dict:
    """Prove a bounded mix independently of phase; also measure real sample sums."""
    samples = {name: decode(data)[0] for name, data in bank.items()}
    cat, cat_rate = decode(meow)
    assert cat_rate == RATE
    peaks = {name: float(np.max(np.abs(data))) for name, data in samples.items()}
    cat_peak = float(np.max(np.abs(cat)))
    groups = {"combat": {"voices": 6, "gain_cap_linear": 0.24},
              "voice": {"voices": 2, "gain_cap_linear": 0.11},
              "ui": {"voices": 2, "gain_cap_linear": 0.12}}
    maxima = {group: max(peaks[f"{cue}_{variant}.wav"] for cue in CUES if CUES[cue][2] == group for variant in (1, 2))
              for group in ("combat", "ui")}
    maxima["voice"] = cat_peak
    reconstructed = {name: reconstruction_peak(data) for name, data in samples.items()}
    reconstructed_maxima = {group: max(reconstructed[f"{cue}_{variant}.wav"] for cue in CUES if CUES[cue][2] == group for variant in (1, 2))
                            for group in ("combat", "ui")}
    reconstructed_maxima["voice"] = reconstruction_peak(cat)
    reconstructed_bound = sum(config["voices"] * config["gain_cap_linear"] * reconstructed_maxima[group] for group, config in groups.items())
    bound = 0.0
    for group, config in groups.items():
        config["max_source_peak_linear"] = round(maxima[group], 9)
        contribution = config["voices"] * config["gain_cap_linear"] * maxima[group]
        config["phase_independent_peak_contribution"] = round(contribution, 9)
        bound += contribution
    # Include unattenuated file peak alignment at the allowed fixed gains.
    align_length = max(len(x) for x in samples.values()) + len(cat)
    aligned = np.zeros(align_length)
    align_at = max(np.argmax(np.abs(x)) for x in [*samples.values(), cat])
    stress_names = ["hit_heavy_1.wav", "hit_heavy_2.wav", "hit_kick_1.wav", "hit_straight_2.wav", "guard_break_1.wav", "down_land_2.wav"]
    peak_aligned_sources = [(samples[name], 0.24) for name in stress_names] + [(cat, 0.11), (cat, 0.11)] + [(samples[f"ui_confirm_{v}.wav"], 0.12) for v in (1, 2)]
    for data, gain in peak_aligned_sources:
        index = int(np.argmax(np.abs(data)))
        start = align_at - index
        polarity = 1 if data[index] >= 0 else -1
        aligned[start:start + len(data)] += data * gain * polarity
    peak_aligned = float(np.max(np.abs(aligned)))
    # Deterministic 12-second burst, preserving caps by round-robin group slots.
    total = np.zeros(12 * RATE)
    voice_ends = {group: [0] * int(config["voices"]) for group, config in groups.items()}
    event_count = 0
    for step in range(480):
        at = round(step * 0.025 * RATE)
        group = ("voice" if step % 19 == 0 else "ui" if step % 23 == 0 else "combat")
        open_slots = [i for i, end in enumerate(voice_ends[group]) if end <= at]
        if not open_slots:
            continue
        if group == "voice":
            data, gain = cat, 0.11
        else:
            names = [name for name in samples if CUES[name.rsplit("_", 1)[0]][2] == group]
            name = names[(step * 13 + 7) % len(names)]
            data = samples[name]
            gain = CUES[name.rsplit("_", 1)[0]][1]
        end = min(len(total), at + len(data))
        total[at:end] += data[:end - at] * gain
        voice_ends[group][open_slots[0]] = end
        event_count += 1
    # Distinct jab / straight shape, compared without requiring a listening claim.
    a, b = samples["hit_light_1.wav"], samples["hit_straight_1.wav"]
    n = min(len(a), len(b))
    jab_straight_correlation = float(np.corrcoef(a[:n], b[:n])[0, 1])
    result = {"schema": 1, "method": "Offline decoded PCM; no hardware or subjective listening claim.",
              "group_caps": groups, "master_gain_linear": 1.0,
              "phase_independent_sum_peak_bound_linear": round(bound, 9),
              "phase_independent_sum_peak_bound_dbfs": db(bound),
              "eightfold_fft_sum_peak_estimate_bound_dbfs": db(reconstructed_bound),
              "reconstruction_note": "Eightfold FFT interpolation is an additional conservative numerical estimate, not a certified intersample/analog peak measurement.",
              "bound_scope": "Any timing, phase and variant, only while the stated group counts and linear gains are enforced; no added music/FX/boosts.",
              "peak_aligned_10_voice_stress": {"sample_peak_linear": round(peak_aligned, 9), "sample_peak_dbfs": db(peak_aligned), "deliberately_aligns_and_inverts_polarity": True},
              "twelve_second_burst": {"events": event_count, "peak_linear": round(float(np.max(np.abs(total))), 9), "peak_dbfs": db(float(np.max(np.abs(total)))), "rms_dbfs": db(float(np.sqrt(np.mean(total * total))))},
              "jab_straight_waveform_correlation": round(jab_straight_correlation, 6),
              "checks": {"worst_bound_below_minus_3_dbfs": bound < 10 ** (-3 / 20),
                         "peak_aligned_below_bound": peak_aligned <= bound + 1e-12,
                         "eightfold_estimate_below_minus_3_dbfs": reconstructed_bound < 10 ** (-3 / 20),
                         "burst_below_bound": float(np.max(np.abs(total))) <= bound + 1e-12,
                         "jab_straight_not_same_waveform": abs(jab_straight_correlation) < 0.8}}
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Regenerate in memory; compare all exact bytes and validate without writing.")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "assets/audio/p2")
    args = parser.parse_args()
    meow_path = ROOT / "assets/audio/meow.wav"
    original_path = ROOT / "assets/audio/originals/bigsoundbank_0494_original.wav"
    assert sha(meow_path.read_bytes()) == MEOW_SHA256, "Existing meow.wav changed"
    assert sha(original_path.read_bytes()) == SOURCE_MEOW_SHA256, "Existing original cat recording changed"
    bank = {}
    entries = []
    for cue, (_, gain, group, _) in CUES.items():
        for variant in (1, 2):
            filename = f"{cue}_{variant}.wav"
            payload, synthesis = synthesize(cue, variant)
            metrics = analyze(payload)
            assert all(metrics["checks"].values()), (filename, metrics)
            bank[filename] = payload
            entries.append({"file": filename, "cue": cue, "variant": variant, "group": group,
                            "recommended_player_gain_linear": gain, "recommended_player_gain_db": db(gain),
                            **metrics, "synthesis": synthesis})
    mix = mix_checks(bank, meow_path.read_bytes())
    assert all(mix["checks"].values()), mix
    manifest = {"schema": 1, "bank": "Livehouse Duel P2 original procedural arcade effects", "created_date_utc": "2026-10-25",
                "provenance": {"authoring": "Original procedural synthesis authored by OpenAI assistant for this game project.",
                               "source": "scripts/generate_p2_audio.py", "source_sha256": sha(Path(__file__).read_bytes()),
                               "source_inputs": "Numeric synthesis parameters and deterministic xorshift32 noise only. No recordings, libraries of sound samples, commercial-game extraction, or third-party audio inputs.",
                               "third_party_audio_license": "Not applicable to generated P2 samples; existing separately licensed CC0 cat recording is untouched.",
                               "reproduction": "Python 3.12.14 + NumPy 2.3.5 reference environment; deterministic source, seeds, PCM and SHA-256 checks. Floating-point libraries can affect exact bytes on other architectures; --check detects differences.",
                               "listening": "Not subjectively auditioned. Numeric waveform, spectrum, headroom and byte checks do not certify perceptual quality or phone playback."},
                "audio": {"sample_rate_hz": RATE, "channels": 1, "sample_width_bits": 16, "peak_target_dbfs": PEAK_DBFS, "loop": False},
                "meow_preserved": {"file": "../meow.wav", "sha256": MEOW_SHA256, "source_sha256": SOURCE_MEOW_SHA256},
                "runtime_contract": {"variant_count": 2, "extra_pitch_shift": False, "import_policy": "Lossless PCM (compress/mode=0), no normalize, no trim, no loop, no forced resample; source WAV numeric budget assumes no lossy transform.", "recommended_variant_policy": "Alternate or bounded random choice; do not play both variants for one event.", "group_limits": mix["group_caps"], "maximum_master_gain_linear": 1.0,
                                     "gate_policy": "One cue per accepted event, mute/pause/background/menu stop all voices, user-input audio unlock, no BGM.", "independent_mix_bound_dbfs": mix["phase_independent_sum_peak_bound_dbfs"]},
                "band_energy_method": "Whole-file one-sided rFFT power normalized to unit energy; half-open frequency intervals, including Nyquist. Phone-band metric is a spectral proxy, not perceptual certification.",
                "files": entries}
    encoded = dict(bank)
    encoded["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    encoded["mix-checks.json"] = (json.dumps(mix, ensure_ascii=False, indent=2) + "\n").encode()
    encoded["SHA256SUMS.txt"] = "".join(f"{sha(payload)}  {name}\n" for name, payload in sorted(encoded.items())).encode()
    if args.check:
        mismatches = [name for name, data in encoded.items() if not (args.output_dir / name).is_file() or (args.output_dir / name).read_bytes() != data]
        if mismatches:
            print("FAIL: missing or non-reproducible files: " + ", ".join(mismatches), file=sys.stderr)
            return 1
    else:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for name, data in encoded.items():
            (args.output_dir / name).write_bytes(data)
    print(f"PASS: {'verified' if args.check else 'generated'} {len(bank)} mono 48 kHz PCM16 cues; {sum(len(data) for data in bank.values())} WAV bytes.")
    print(f"Source SHA-256: {manifest['provenance']['source_sha256']}")
    print(f"Peak range: {min(x['sample_peak_dbfs'] for x in entries):.3f} to {max(x['sample_peak_dbfs'] for x in entries):.3f} dBFS; minimum phone-band fraction {min(x['phone_band_250_4000_fraction'] for x in entries):.1%}.")
    print(f"10-voice phase-independent peak bound {mix['phase_independent_sum_peak_bound_dbfs']:.3f} dBFS; stress burst {mix['twelve_second_burst']['peak_dbfs']:.3f} dBFS.")
    print("Existing CC0 meow and original-source hashes unchanged. Technical-only QA; no listening claim.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
