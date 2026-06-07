#!/usr/bin/env python3
"""
coe2wav.py — Xilinx COE to WAV converter
═════════════════════════════════════════
Round-trip verification tool for wav2coe.py.
Reads a .coe file and writes a .wav you can play back directly.

If the output WAV sounds like your original sample → the Python
converter is clean and the issue is elsewhere (FPGA RTL, pitch
table, BRAM configuration, etc.).

If the output WAV sounds wrong → the converter has a bug.

Reads metadata written by wav2coe.py (sample rate, bit depth,
word width) from the COE header comments automatically.
All values can be overridden via CLI flags.

Dependencies
────────────
  pip install soundfile numpy

Usage examples
──────────────
  python coe2wav.py  snare.coe              # auto-reads header metadata
  python coe2wav.py  snare.coe  snare_rt.wav
  python coe2wav.py  snare.coe  --sample-rate 48000 --bit-depth 24
  python coe2wav.py  snare.coe  --word-width 32   # MSB-justified 32-bit words
"""

import argparse
import math
import os
import re
import sys
from pathlib import Path

import numpy as np


# ─────────────────────────────────────────────────────────────────
# COE parsing
# ─────────────────────────────────────────────────────────────────

def parse_coe(filepath: str) -> tuple[int, list[int], dict]:
    """
    Parse a Xilinx .coe file.

    Returns
    -------
    radix   : int          — 2, 10, or 16
    values  : list[int]    — unsigned integer values as written in the file
    meta    : dict         — key/value pairs extracted from header comments
    """
    with open(filepath, "r") as f:
        raw = f.read()

    # ── Extract header metadata from wav2coe comment lines ───────
    meta: dict = {}
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped.startswith(";"):
            break                              # header comments are at the top
        if ":" in stripped:
            _, rest = stripped[1:].split(":", 1)
            key_raw, val_raw = stripped[1:].split(":", 1)
            meta[key_raw.strip()] = val_raw.strip()

    # ── Strip all comment lines before parsing directives ────────
    no_comments = "\n".join(
        ln for ln in raw.splitlines() if not ln.strip().startswith(";")
    )

    # ── Radix ─────────────────────────────────────────────────────
    m = re.search(
        r"memory_initialization_radix\s*=\s*(\d+)\s*;",
        no_comments,
        re.IGNORECASE,
    )
    if not m:
        raise ValueError("memory_initialization_radix not found in COE file")
    radix = int(m.group(1))

    # ── Vector ────────────────────────────────────────────────────
    m = re.search(
        r"memory_initialization_vector\s*=\s*([\s\S]+?)\s*;",
        no_comments,
        re.IGNORECASE,
    )
    if not m:
        raise ValueError("memory_initialization_vector not found in COE file")
    vector_str = m.group(1)

    if radix == 16:
        tokens = re.findall(r"[0-9A-Fa-f]+", vector_str)
        values = [int(t, 16) for t in tokens]
    elif radix == 2:
        tokens = re.findall(r"[01]+", vector_str)
        values = [int(t, 2) for t in tokens]
    elif radix == 10:
        tokens = re.findall(r"\d+", vector_str)
        values = [int(t, 10) for t in tokens]
    else:
        raise ValueError(f"Unsupported radix: {radix}")

    return radix, values, meta


def extract_meta_int(meta: dict, *keys: str, default: int) -> int:
    """Pull the first matching numeric value from the metadata dict."""
    for k in keys:
        for mk, mv in meta.items():
            if k.lower() in mk.lower():
                nums = re.findall(r"\d+", mv)
                if nums:
                    return int(nums[0])
    return default


# ─────────────────────────────────────────────────────────────────
# Sample reconstruction
# ─────────────────────────────────────────────────────────────────

def unsigned_to_signed(values: list[int], bit_depth: int) -> np.ndarray:
    """
    Convert unsigned two's-complement integers to signed float64 in [-1, 1].
    """
    half     = 1 << (bit_depth - 1)          # 2^23 = 8_388_608
    max_pos  = half - 1                       # 8_388_607
    scale    = 1.0 / max_pos

    out = np.empty(len(values), dtype=np.float64)
    for i, v in enumerate(values):
        signed = v - (1 << bit_depth) if v >= half else v
        out[i] = signed * scale

    return np.clip(out, -1.0, 1.0)


# ─────────────────────────────────────────────────────────────────
# WAV writing
# ─────────────────────────────────────────────────────────────────

def write_wav(filepath: str, samples: np.ndarray, sample_rate: int) -> None:
    """Write float64 samples as a 24-bit mono WAV."""
    try:
        import soundfile as sf
        sf.write(filepath, samples, sample_rate, subtype="PCM_24")
        return
    except ImportError:
        pass

    # ── wave-module fallback (writes 16-bit) ─────────────────────
    import wave, struct

    print("  soundfile not available — writing 16-bit WAV as fallback")
    ints = np.round(samples * 32767).astype(np.int16)

    with wave.open(filepath, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(ints.tobytes())


# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────

def convert(
    input_path:  str,
    output_path: str,
    sample_rate: int | None = None,
    bit_depth:   int | None = None,
    word_width:  int | None = None,
) -> None:
    bar = "═" * 54
    print(f"\n{bar}")
    print(f"  coe2wav — COE → WAV  (round-trip verification)")
    print(f"{bar}")
    print(f"  Input  : {input_path}")
    print(f"  Output : {output_path}\n")

    # ── Parse COE ───────────────────────────────────────────────
    print("[1/3] Parsing COE …")
    radix, values, meta = parse_coe(input_path)
    print(f"    Radix       : {radix}")
    print(f"    Raw entries : {len(values)}")
    if meta:
        print("    Header metadata found:")
        for k, v in meta.items():
            print(f"      {k}: {v}")

    # ── Resolve parameters (CLI > header > defaults) ─────────────
    sr  = sample_rate or extract_meta_int(meta, "Target SR",  default=48_000)
    bd  = bit_depth   or extract_meta_int(meta, "Bit depth",  default=24)
    ww  = word_width  or extract_meta_int(meta, "Word width", default=24)

    print(f"\n    Using: {sr} Hz · {bd}-bit audio · {ww}-bit words")

    if bd > ww:
        raise ValueError(f"bit_depth ({bd}) cannot exceed word_width ({ww})")

    # ── Undo word-width packing ──────────────────────────────────
    # For --word-width 32: audio was MSB-justified (shifted left by 8).
    # Shift back right to recover the 24-bit audio value.
    shift = ww - bd
    if shift > 0:
        print(f"    Shifting values right by {shift} bits (word_width={ww} → bit_depth={bd})")
        values = [v >> shift for v in values]

    # ── Reconstruct float samples ────────────────────────────────
    print("\n[2/3] Reconstructing samples …")
    samples = unsigned_to_signed(values, bd)

    peak_dbfs = 20 * np.log10(np.max(np.abs(samples)) + 1e-300)
    print(f"    Samples  : {len(samples)}")
    print(f"    Duration : {len(samples) / sr:.3f} s  @ {sr} Hz")
    print(f"    Peak     : {peak_dbfs:.2f} dBFS")

    # ── Write WAV ────────────────────────────────────────────────
    print("\n[3/3] Writing WAV …")
    write_wav(output_path, samples, sr)

    size_kb = os.path.getsize(output_path) / 1024
    print(f"    Written : {output_path}  ({size_kb:.1f} KB)")
    print(f"\n✓ Done! Play {os.path.basename(output_path)} and compare with your original.")
    print( "  If it sounds identical → Python converter is clean.")
    print( "  If it sounds wrong     → bug is in wav2coe.py.")


def main() -> None:
    p = argparse.ArgumentParser(
        prog="coe2wav",
        description="Convert Xilinx COE back to WAV for round-trip verification",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    p.add_argument("input",
        help="Input .coe file")
    p.add_argument("output", nargs="?",
        help="Output .wav file (default: <input>_roundtrip.wav)")

    p.add_argument("--sample-rate", "-r", type=int, default=None,
        metavar="HZ",
        help="Sample rate in Hz (auto-read from COE header if generated by wav2coe)")
    p.add_argument("--bit-depth", "-b", type=int, default=None,
        choices=[16, 24, 32],
        help="Audio bit depth (auto-read from COE header)")
    p.add_argument("--word-width", "-w", type=int, default=None,
        choices=[16, 24, 32],
        help="COE word width — use 32 if generated with --word-width 32 (auto-read from header)")

    args = p.parse_args()

    stem   = Path(args.input).stem
    output = args.output or str(Path(args.input).parent / f"{stem}_roundtrip.wav")

    convert(
        input_path  = args.input,
        output_path = output,
        sample_rate = args.sample_rate,
        bit_depth   = args.bit_depth,
        word_width  = args.word_width,
    )


if __name__ == "__main__":
    main()