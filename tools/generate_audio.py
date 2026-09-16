#!/usr/bin/env python3
"""Generate the original mono placeholder sounds for Echo Escape (stdlib only)."""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def sound(kind: str, duration: float) -> None:
    rng = random.Random(1907 + sum(map(ord, kind)))
    samples: list[float] = []
    previous_noise = 0.0
    for n in range(int(RATE * duration)):
        t = n / RATE
        noise = rng.uniform(-1.0, 1.0)
        previous_noise = previous_noise * 0.63 + noise * 0.37
        if kind in ("walk", "run"):
            decay = math.exp(-t * (32 if kind == "walk" else 23))
            value = (math.sin(2 * math.pi * (100 - t * 160) * t) * 0.5
                     + previous_noise * 0.85) * decay
        elif kind == "clap":
            value = noise * math.exp(-t * 24) * 0.8
            # The little slapback is synthetic, not a physical world echo.
            if t > 0.045:
                value += noise * math.exp(-(t - 0.045) * 45) * 0.25
        elif kind == "probe":
            value = 0.0
            for pulse in (0.0, 0.18, 0.36):
                local = t - pulse
                if local >= 0:
                    frequency = 158 - local * 42
                    value += (math.sin(2 * math.pi * frequency * local)
                              + math.sin(2 * math.pi * frequency * 1.49 * local) * 0.3
                              + previous_noise * 0.18) * math.exp(-local * 10) * 0.65
        elif kind == "windup":
            envelope = min(t / 0.025, 1) * min((duration - t) / 0.035, 1)
            tremolo = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 15)
            value = (math.sin(2 * math.pi * (105 * t + 155 * t * t)) * 0.48
                     + noise * 0.25) * envelope * tremolo
        elif kind == "pickup":
            value = 0.0
            for i, frequency in enumerate((440.0, 659.25, 880.0)):
                local = t - i * 0.12
                if local >= 0:
                    value += math.sin(2 * math.pi * frequency * local) * math.exp(-local * 6) * 0.3
        elif kind == "victory":
            value = 0.0
            for i, frequency in enumerate((329.63, 440.0, 554.37, 659.25)):
                local = t - i * 0.15
                if local >= 0:
                    value += math.sin(2 * math.pi * frequency * local) * math.exp(-local * 3.5) * 0.24
        else:  # defeat: falling, soft dissonant tone
            envelope = min(t / 0.035, 1) * math.exp(-t * 3.2)
            value = (math.sin(2 * math.pi * (210 * t - 65 * t * t)) * 0.6
                     + math.sin(2 * math.pi * 87 * t) * 0.3) * envelope
        # A tiny fade prevents endpoint clicks, preserving intentional attacks.
        fade = min(1.0, (duration - t) / 0.012)
        samples.append(max(-0.95, min(0.95, value * fade)))
    with wave.open(str(OUT / f"{kind}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", round(value * 32767)) for value in samples))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, length in {"walk": 0.22, "run": 0.26, "clap": 0.30,
                         "probe": 0.90, "windup": 0.65, "pickup": 0.80,
                         "victory": 1.50, "defeat": 1.20}.items():
        sound(name, length)
    print(f"Generated 8 original WAV cues in {OUT}")
