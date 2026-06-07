#!/usr/bin/env python3
"""
wav2coe.py — WAV to Xilinx COE converter for 24-bit / 48 kHz I2S transmitters
═══════════════════════════════════════════════════════════════════════════════
Converts any WAV file to a Xilinx Block RAM initialisation (.coe) file
compatible with a mono 24-bit I2S TX core running at 48 kHz.

Always extracts channel 0 (left) from the source WAV.
One COE entry per audio sample — address N → sample N.

Signal chain
────────────
  WAV in  →  extract ch0  →  polyphase resample
          →  TPDF dither  →  24-bit quantise  →  two's-complement
          →  Xilinx COE out

Word-width modes (--word-width)
────────────────────────────────
  24  Pure 24-bit words (BRAM data_width = 24, memory-efficient)
  32  MSB-justified: audio in bits [31:8], bits [7:0] = 0x00
      (matches I2S left-justified / Philips format in 32-bit frames)

Dependencies
────────────
  pip install soundfile scipy numpy
  (soundfile handles 8/16/24/32-bit WAV natively; scipy for resampling)

Usage examples
──────────────
  python wav2coe.py  audio.wav  audio.coe
  python wav2coe.py  audio.wav  audio.coe  --normalize
  python wav2coe.py  audio.wav  audio.coe  --word-width 32 --radix 16
  python wav2coe.py  audio.wav  audio.coe  --no-dither
  python wav2coe.py  audio.wav  audio.coe  --sample-rate 44100
"""

import argparse
import math
import os
import sys
from pathlib import Path

import numpy as np
from scipy import signal as sp_signal


# ─────────────────────────────────────────────────────────────────
# Audio I/O
# ─────────────────────────────────────────────────────────────────

def read_wav(filepath: str) -> tuple[np.ndarray, int]:
    """
    Read a WAV file and return float64 samples in [-1, 1] and sample rate.
    Returns samples as shape (n_frames, n_channels).
    Prefers soundfile (handles 24-bit natively); falls back to wave module.
    """
    try:
        import soundfile as sf
        samples, sr = sf.read(filepath, always_2d=True, dtype="float64")
        return samples, sr
    except ImportError:
        pass

    # ── wave-module fallback ──────────────────────────────────────
    import wave

    with wave.open(filepath, "rb") as w:
        n_ch     = w.getnchannels()
        sw       = w.getsampwidth()   # bytes per sample
        sr       = w.getframerate()
        n_frames = w.getnframes()
        raw      = w.readframes(n_frames)

    bits = sw * 8

    if bits == 8:                          # unsigned 8-bit PCM
        data = np.frombuffer(raw, dtype=np.uint8).astype(np.float64)
        data = (data - 128.0) / 128.0

    elif bits == 16:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32_768.0

    elif bits == 24:                       # no native np dtype for 24-bit
        raw_arr = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        # Little-endian: byte[0]=LSB … byte[2]=MSB
        ints = (raw_arr[:, 2].astype(np.int32) << 16 |
                raw_arr[:, 1].astype(np.int32) <<  8 |
                raw_arr[:, 0].astype(np.int32))
        # Sign-extend from 24 bits
        ints = np.where(ints >= 0x80_0000, ints - 0x100_0000, ints)
        data = ints.astype(np.float64) / 8_388_608.0

    elif bits == 32:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2_147_483_648.0

    else:
        raise ValueError(f"Unsupported WAV bit depth: {bits}")

    samples = data.reshape(-1, n_ch)
    return samples, sr


# ─────────────────────────────────────────────────────────────────
# Resampling
# ─────────────────────────────────────────────────────────────────

def resample_audio(samples: np.ndarray, src_sr: int, dst_sr: int) -> np.ndarray:
    """
    Polyphase resampling via scipy.signal.resample_poly.
    Uses a Kaiser-windowed anti-aliasing FIR designed automatically by scipy.
    samples is a 1-D float64 array (single channel).
    """
    if src_sr == dst_sr:
        return samples

    gcd  = math.gcd(src_sr, dst_sr)
    up   = dst_sr // gcd
    down = src_sr // gcd

    print(f"    Polyphase resample {src_sr} Hz → {dst_sr} Hz  "
          f"(up={up}, down={down})")

    return sp_signal.resample_poly(
        samples,
        up,
        down,
        padtype="line",   # edge-padding reduces Gibbs at boundaries
    )


# ─────────────────────────────────────────────────────────────────
# Dithering
# ─────────────────────────────────────────────────────────────────

def apply_tpdf_dither(samples: np.ndarray, bit_depth: int) -> np.ndarray:
    """
    Triangular Probability Density Function (TPDF) dither.

    When truncating from higher precision to bit_depth, plain rounding
    introduces correlated quantisation error (harmonic distortion).
    TPDF dither converts that into spectrally flat, uncorrelated noise
    at a level below the last bit — preserving perceived dynamic range.

    TPDF = sum of two independent uniform distributions of ±0.5 LSB,
    giving a triangular PDF of ±1 LSB amplitude. This is the minimum
    dither that achieves noise modulation suppression.
    """
    lsb = 1.0 / (1 << (bit_depth - 1))    # amplitude of 1 LSB
    noise = (np.random.uniform(-0.5, 0.5, samples.shape) +
             np.random.uniform(-0.5, 0.5, samples.shape)) * lsb
    return samples + noise


# ─────────────────────────────────────────────────────────────────
# Quantisation
# ─────────────────────────────────────────────────────────────────

def quantise(samples: np.ndarray, bit_depth: int) -> np.ndarray:
    """
    Round float64 samples in [-1, 1] to signed integers for bit_depth.
    Returns np.int32 array (safe for up to 32-bit audio).
    """
    max_pos =  (1 << (bit_depth - 1)) - 1   #  8_388_607 for 24-bit
    max_neg = -(1 << (bit_depth - 1))        # -8_388_608 for 24-bit

    ints = np.round(samples * max_pos).astype(np.int32)
    return np.clip(ints, max_neg, max_pos)


# ─────────────────────────────────────────────────────────────────
# COE formatting helpers
# ─────────────────────────────────────────────────────────────────

_MASK = {n: (1 << n) - 1 for n in (16, 24, 32)}   # two's-complement masks

def to_unsigned(value: int, bit_depth: int) -> int:
    """Signed integer → unsigned two's-complement at bit_depth."""
    return int(value) & _MASK[bit_depth]


def format_value(v: int, radix: int, width_bits: int) -> str:
    """Format an unsigned integer according to COE radix."""
    if radix == 16:
        hex_digits = (width_bits + 3) // 4
        return f"{v:0{hex_digits}X}"
    if radix == 2:
        return f"{v:0{width_bits}b}"
    return str(v)    # decimal


def write_coe(
    filepath: str,
    values: list[int],
    radix: int,
    word_width: int,
    meta: dict,
) -> None:
    """Write a Xilinx-compatible .coe initialisation file."""
    items_per_line = 8   # readability; no semantic meaning

    with open(filepath, "w") as f:
        # ── header ──────────────────────────────────────────────
        f.write("; Xilinx COE — I2S audio ROM initialisation\n")
        f.write("; Generated by wav2coe.py\n")
        for k, v in meta.items():
            f.write(f"; {k:<18}: {v}\n")
        f.write(";\n")
        f.write(f"memory_initialization_radix={radix};\n")
        f.write("memory_initialization_vector=\n")

        # ── vector ──────────────────────────────────────────────
        formatted = [format_value(v, radix, word_width) for v in values]
        n = len(formatted)

        for i in range(0, n, items_per_line):
            chunk = formatted[i : i + items_per_line]
            is_last_chunk = (i + items_per_line >= n)

            if is_last_chunk:
                # Last item gets semicolon, not comma
                body = ", ".join(chunk[:-1])
                if body:
                    f.write(body + ",\n")
                f.write(chunk[-1] + ";\n")
            else:
                f.write(", ".join(chunk) + ",\n")


# ─────────────────────────────────────────────────────────────────
# Main conversion
# ─────────────────────────────────────────────────────────────────

def convert(
    input_path:   str,
    output_path:  str,
    target_sr:    int  = 48_000,
    bit_depth:    int  = 24,
    word_width:   int  = 24,
    radix:        int  = 16,
    normalize:    bool = False,
    dither:       bool = True,
) -> None:
    bar = "═" * 54
    print(f"\n{bar}")
    print(f"  wav2coe — WAV → COE  ({bit_depth}-bit / {target_sr // 1000} kHz I2S)")
    print(f"{bar}")
    print(f"  Input  : {input_path}")
    print(f"  Output : {output_path}\n")

    # ── Step 1: Read ────────────────────────────────────────────
    print("[1/4] Reading WAV …")
    raw_samples, src_sr = read_wav(input_path)
    n_frames, n_ch = raw_samples.shape
    print(f"    {n_ch} ch  ·  {src_sr} Hz  ·  {n_frames} frames  "
          f"({n_frames / src_sr:.3f} s)")

    # ── Step 2: Extract channel 0 (left) ────────────────────────
    samples = raw_samples[:, 0]          # 1-D from here on
    if n_ch > 1:
        print(f"[2/4] Extracted channel 0 (left) from {n_ch}-channel source")
    else:
        print("[2/4] Source is mono — using as-is")

    # ── Step 3: Normalise (optional) ────────────────────────────
    peak_dbfs = 20 * np.log10(np.max(np.abs(samples)) + 1e-300)
    if normalize:
        peak = np.max(np.abs(samples))
        if peak > 0:
            gain = 0.99997 / peak
            samples = samples * gain
            print(f"    Normalised: {peak_dbfs:.2f} dBFS → −0.0 dBFS (gain {gain:.4f})")
    else:
        print(f"    Peak: {peak_dbfs:.2f} dBFS  (normalisation off)")
        if peak_dbfs > 0:
            print("    ⚠  Clipping detected in source — consider --normalize")

    # ── Step 3: Resample ────────────────────────────────────────
    print("[3/4] Resample …")
    samples = resample_audio(samples, src_sr, target_sr)
    n_out = len(samples)

    # ── Step 4: Dither + quantise ────────────────────────────────
    print("[4/4] Dither + quantise …")
    if dither:
        samples = apply_tpdf_dither(samples, bit_depth)
        print(f"    TPDF dither applied (±1 LSB @ {bit_depth}-bit)")
    else:
        print("    Dithering disabled")

    samples = np.clip(samples, -1.0, 1.0)
    samples_int = quantise(samples, bit_depth)

    # ── Build COE vector ─────────────────────────────────────────
    print("\nBuilding COE vector …")
    shift = word_width - bit_depth       # 0 for 24→24, 8 for 24→32

    coe_values = [
        (to_unsigned(int(s), bit_depth) << shift)
        for s in samples_int
    ]

    # ── Write COE ───────────────────────────────────────────────
    meta = {
        "Source file"   : os.path.basename(input_path),
        "Source SR"     : f"{src_sr} Hz",
        "Target SR"     : f"{target_sr} Hz",
        "Bit depth"     : f"{bit_depth}-bit",
        "Word width"    : f"{word_width}-bit",
        "Channel"       : "0 (left / mono)",
        "Dither"        : "TPDF" if dither else "none",
        "Normalized"    : str(normalize),
        "COE entries"   : n_out,
        "Duration"      : f"{n_out / target_sr:.3f} s",
        "BRAM depth"    : f"{n_out}  (next pow2: {2**math.ceil(math.log2(n_out))})",
    }

    write_coe(output_path, coe_values, radix, word_width, meta)

    size_kb = os.path.getsize(output_path) / 1024
    print(f"\n✓ Done!")
    print(f"  COE entries : {n_out}")
    print(f"  BRAM depth  : ≥ {n_out}  "
          f"(next power-of-2: {2**math.ceil(math.log2(n_out))})")
    print(f"  Duration    : {n_out / target_sr:.3f} s")
    print(f"  File size   : {size_kb:.1f} KB")
    print(f"  Output      : {output_path}")


# ─────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(
        prog="wav2coe",
        description="Convert WAV → Xilinx COE for a 24-bit/48 kHz I2S transmitter",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    p.add_argument("input",
        help="Input WAV file (any sample rate / bit depth)")
    p.add_argument("output", nargs="?",
        help="Output .coe file (default: same name as input)")

    p.add_argument("--sample-rate", "-r", type=int, default=48_000,
        metavar="HZ",
        help="Target sample rate in Hz (default: 48000)")
    p.add_argument("--bit-depth", "-b", type=int, default=24,
        choices=[16, 24, 32],
        help="Audio bit depth written to COE (default: 24)")
    p.add_argument("--word-width", "-w", type=int, default=24,
        choices=[16, 24, 32],
        help=(
            "COE memory word width (default: 24).\n"
            "  24 = pure 24-bit words (BRAM data_width=24)\n"
            "  32 = audio MSB-justified in 32-bit frame, bits[7:0]=0x00"
        ))
    p.add_argument("--radix", type=int, default=16, choices=[2, 10, 16],
        help="Number base for COE values: 2=binary, 10=decimal, 16=hex (default)")
    p.add_argument("--normalize", "-n", action="store_true",
        help="Normalize peak to −0.0 dBFS before conversion")
    p.add_argument("--no-dither", action="store_true",
        help="Disable TPDF dithering (not recommended for down-conversion)")

    args = p.parse_args()

    output = args.output or str(Path(args.input).with_suffix(".coe"))

    # Sanity checks
    if args.bit_depth > args.word_width:
        p.error(
            f"--bit-depth ({args.bit_depth}) cannot exceed "
            f"--word-width ({args.word_width})"
        )

    convert(
        input_path   = args.input,
        output_path  = output,
        target_sr    = args.sample_rate,
        bit_depth    = args.bit_depth,
        word_width   = args.word_width,
        radix        = args.radix,
        normalize    = args.normalize,
        dither       = not args.no_dither,
    )


if __name__ == "__main__":
    main()