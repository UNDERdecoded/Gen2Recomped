#!/usr/bin/env python3
"""Bake assets/logo/logo.png into a pre-scaled RGBA blob for the Switch OTA UI.

Output format (little-endian):
  uint32 width, uint32 height, then width*height RGBA8888 pixels.

Regenerate after editing the source PNG:
  python3 scripts/switch/bake_ota_logo.py

Uses Pillow when available (see scripts/setup.sh). On macOS without Pillow,
falls back to sips + BMP export.
"""

from __future__ import annotations

import math
import platform
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SRC = ROOT / "assets/logo/logo.png"
DEFAULT_OUT = ROOT / "ports/switch/assets/logo.rgba"
DEFAULT_MAX_W = 320
DEFAULT_MAX_H = 90


def fit_size(src_w: int, src_h: int, max_w: int, max_h: int) -> tuple[int, int]:
    scale = min(max_w / src_w, max_h / src_h, 1.0)
    w = max(1, int(math.floor(src_w * scale + 0.5)))
    h = max(1, int(math.floor(src_h * scale + 0.5)))
    return w, h


def read_png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as fp:
        sig = fp.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"not a PNG: {path}")
        while True:
            raw = fp.read(8)
            if len(raw) < 8:
                raise SystemExit(f"truncated PNG: {path}")
            length, ctype = struct.unpack(">I4s", raw)
            data = fp.read(length)
            fp.read(4)
            if ctype == b"IHDR":
                return struct.unpack(">II", data[:8])
            if ctype == b"IEND":
                break
    raise SystemExit(f"missing IHDR in PNG: {path}")


def read_bmp_rgba(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if len(data) < 54 or data[:2] != b"BM":
        raise SystemExit(f"not a BMP: {path}")
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    width = struct.unpack_from("<i", data, 18)[0]
    height_raw = struct.unpack_from("<i", data, 22)[0]
    bpp = struct.unpack_from("<H", data, 28)[0]
    height = abs(height_raw)
    top_down = height_raw < 0
    if bpp != 32 or width <= 0 or height <= 0:
        raise SystemExit(f"unsupported BMP {width}x{height_raw} @{bpp}bpp: {path}")

    row_bytes = ((width * 4 + 3) // 4) * 4
    pixels = bytearray(width * height * 4)
    for row in range(height):
        src_row = row if top_down else height - 1 - row
        row_off = pixel_offset + src_row * row_bytes
        for col in range(width):
            b, g, r, a = data[row_off + col * 4 : row_off + col * 4 + 4]
            dst = (row * width + col) * 4
            pixels[dst : dst + 4] = bytes((r, g, b, a))
    return width, height, bytes(pixels)


def bake_with_sips(src: Path, out_w: int, out_h: int) -> tuple[int, int, bytes]:
    if platform.system() != "Darwin":
        raise SystemExit(
            "Pillow is required to bake the OTA logo on this platform. "
            "Run scripts/setup.sh or: pip install pillow"
        )

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        scaled_png = tmp_dir / "scaled.png"
        scaled_bmp = tmp_dir / "scaled.bmp"
        subprocess.run(
            ["sips", "-z", str(out_h), str(out_w), str(src), "--out", str(scaled_png)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            ["sips", "-s", "format", "bmp", str(scaled_png), "--out", str(scaled_bmp)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        return read_bmp_rgba(scaled_bmp)


def bake_with_pillow(src: Path, out_w: int, out_h: int) -> tuple[int, int, bytes]:
    from PIL import Image

    with Image.open(src) as image:
        image = image.convert("RGBA")
        if image.size != (out_w, out_h):
            image = image.resize((out_w, out_h), Image.LANCZOS)
        w, h = image.size
        return w, h, image.tobytes()


def bake(src: Path, out: Path, max_w: int, max_h: int) -> tuple[int, int]:
    if not src.is_file():
        raise SystemExit(f"missing source PNG: {src}")

    src_w, src_h = read_png_size(src)
    out_w, out_h = fit_size(src_w, src_h, max_w, max_h)

    try:
        from PIL import Image  # noqa: F401

        w, h, pixels = bake_with_pillow(src, out_w, out_h)
    except ImportError:
        w, h, pixels = bake_with_sips(src, out_w, out_h)

    if len(pixels) != w * h * 4:
        raise SystemExit(f"unexpected pixel buffer size for {w}x{h}")

    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as fp:
        fp.write(struct.pack("<II", w, h))
        fp.write(pixels)

    return w, h


def main(argv: list[str]) -> int:
    src = Path(argv[1]) if len(argv) > 1 else DEFAULT_SRC
    out = Path(argv[2]) if len(argv) > 2 else DEFAULT_OUT
    max_w = int(argv[3]) if len(argv) > 3 else DEFAULT_MAX_W
    max_h = int(argv[4]) if len(argv) > 4 else DEFAULT_MAX_H

    w, h = bake(src, out, max_w, max_h)
    print(f"wrote {out} ({w}x{h}, {8 + w * h * 4} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
