"""Create FantasySiege's original star-lantern cues and looping ambience.

Only Python's standard library is used. There are no samples, external audio,
network services, or third-party synthesizers. The output is reproducible PCM.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050
TAU = math.tau
SEED = 20261118
DURATIONS = {
    "click": 0.085,
    "summon": 0.42,
    "hit": 0.13,
    "heal": 0.62,
    "pulse": 0.78,
    "warning": 0.64,
    "victory": 1.6,
    "defeat": 1.4,
    "train": 0.82,
    "ambient": 24.0,
}


def smooth(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def envelope(age: float, length: float, decay: float, attack: float = 0.008) -> float:
    if not 0.0 <= age < length:
        return 0.0
    return smooth(age / attack) * math.exp(-age / decay) * smooth((length - age) / 0.045)


def bell(t: float, start: float, frequency: float, length: float, decay: float = 0.22) -> float:
    age = t - start
    if age < 0:
        return 0.0
    phase = TAU * frequency * age
    return envelope(age, length, decay) * (
        math.sin(phase) + 0.22 * math.sin(phase * 2.0) + 0.07 * math.sin(phase * 3.0)
    )


def arpeggio(t: float, notes: list[float], spacing: float, length: float) -> float:
    return sum(bell(t, i * spacing, frequency, length - i * spacing, 0.34) for i, frequency in enumerate(notes))


def ambient(t: float, length: float) -> float:
    # Integer carrier and modulation cycles over 24 seconds make the waveform
    # continuous across the WAV loop boundary, without an audible fade to silence.
    notes = [73.416, 146.832, 220.0, 261.626, 329.628, 349.228, 440.0, 587.330]
    amplitudes = [0.11, 0.16, 0.11, 0.09, 0.07, 0.09, 0.05, 0.028]
    result = 0.0
    for i, (note, amplitude) in enumerate(zip(notes, amplitudes)):
        frequency = round(note * length) / length
        phase = i * 0.73
        drift = 0.55 + 0.45 * math.cos(TAU * t / length + i * 1.17)
        shimmer = 0.94 + 0.06 * math.sin(TAU * 3.0 * t / length + phase)
        tone = math.sin(TAU * frequency * t + phase)
        tone += 0.10 * math.sin(TAU * frequency * 2.0 * t + phase * 2.0)
        result += amplitude * drift * shimmer * tone
    return result


def render(name: str) -> list[float]:
    length = DURATIONS[name]
    sample_count = round(length * RATE)
    noise = random.Random(SEED + sum(ord(char) for char in name))
    filtered = 0.0
    samples: list[float] = []
    for index in range(sample_count):
        t = index / RATE
        if name == "ambient":
            value = ambient(t, length)
        elif name == "click":
            value = bell(t, 0.0, 1108.73, length, 0.017)
            value += 0.38 * bell(t, 0.0, 554.365, length, 0.024)
        elif name == "summon":
            phase = TAU * (293.665 * t + 360.0 * t * t)
            value = 0.4 * math.sin(phase) * envelope(t, length, 0.16, 0.016)
            value += 0.55 * bell(t, 0.035, 440.0, length - 0.035, 0.14)
            value += 0.32 * bell(t, 0.105, 587.330, length - 0.105, 0.18)
        elif name == "hit":
            filtered = 0.74 * filtered + 0.26 * noise.uniform(-1.0, 1.0)
            phase = TAU * (130.0 * t - 220.0 * t * t)
            value = (0.65 * math.sin(phase) + filtered) * envelope(t, length, 0.034, 0.002)
        elif name == "heal":
            value = arpeggio(t, [523.251, 659.255, 783.991], 0.09, length)
        elif name == "pulse":
            phase = TAU * (165.0 * t + 540.0 * t * t)
            filtered = 0.86 * filtered + 0.14 * noise.uniform(-1.0, 1.0)
            value = (math.sin(phase) + 0.20 * filtered) * envelope(t, length, 0.19, 0.025)
            value += 0.48 * bell(t, 0.09, 880.0, length - 0.09, 0.25)
        elif name == "warning":
            # Two warm low bells are distinct from the bright summon/heal cues.
            value = bell(t, 0.0, 220.0, 0.25, 0.11)
            value += 0.70 * bell(t, 0.0, 233.082, 0.25, 0.11)
            value += bell(t, 0.30, 220.0, length - 0.30, 0.11)
            value += 0.70 * bell(t, 0.30, 233.082, length - 0.30, 0.11)
        elif name == "victory":
            value = arpeggio(t, [293.665, 369.994, 440.0, 587.330, 739.989], 0.16, length)
        elif name == "defeat":
            value = arpeggio(t, [293.665, 261.626, 220.0, 146.832], 0.19, length)
        elif name == "train":
            value = arpeggio(t, [440.0, 587.330, 698.456], 0.13, length)
        else:
            raise ValueError(name)
        samples.append(value)
    peak = max(abs(sample) for sample in samples) or 1.0
    target_peak = 0.24 if name == "ambient" else (0.48 if name == "warning" else 0.58)
    return [sample * target_peak / peak for sample in samples]


def write_wav(path: Path, samples: list[float]) -> dict:
    quantized = [max(-32767, min(32767, round(sample * 32767))) for sample in samples]
    pcm = struct.pack(f"<{len(quantized)}h", *quantized)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)
    return {
        "file": path.name,
        "samples": len(quantized),
        "duration_seconds": len(quantized) / RATE,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "peak": max(abs(sample) for sample in quantized) / 32767,
        "rms": math.sqrt(sum(sample * sample for sample in quantized) / len(quantized)) / 32767,
        "loop_boundary_step": abs(quantized[-1] - quantized[0]) / 32767,
        "largest_sample_step": max(abs(b - a) for a, b in zip(quantized, quantized[1:])) / 32767,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "assets" / "audio")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records = [write_wav(args.output / f"{name}.wav", render(name)) for name in DURATIONS]
    manifest = {
        "schema": 1,
        "original_work": "FantasySiege / 星灯远征",
        "generator": "tools/generate_audio.py",
        "seed": SEED,
        "third_party_audio": [],
        "format": {"encoding": "PCM signed 16-bit little-endian", "channels": 1, "sample_rate": RATE},
        "files": records,
    }
    (args.output / "generated_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(records)} original WAV files in {args.output}")
    print("Ambient: 24 second continuous periodic loop; other cues: 0.085–1.6 seconds.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
