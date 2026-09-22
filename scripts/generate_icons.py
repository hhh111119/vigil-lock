#!/usr/bin/env python3
"""Generate Vigil app icons (PNG + ICNS) without extra deps."""
from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "src-tauri" / "icons"


def write_png(path: Path, size: int, rgba_at) -> bytes:
    rows = []
    for y in range(size):
        raw = bytearray([0])
        for x in range(size):
            raw.extend(rgba_at(x, y, size))
        rows.append(bytes(raw))
    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)
    return png


def rgba(x: int, y: int, size: int) -> tuple[int, int, int, int]:
    cx = cy = (size - 1) / 2.0
    d = math.hypot(x - cx, y - cy)
    r = size * 0.33
    stroke = max(1.15, size * 0.018)
    pupil = size * 0.055
    bg = (10, 10, 11, 255)
    fg = (200, 204, 212, 255)
    ring = max(0.0, 1.0 - abs(d - r) / (stroke * 0.55))
    dot = 1.0 if d <= pupil else max(0.0, 1.0 - (d - pupil) / 0.9)
    t = min(1.0, max(ring, dot))
    if t <= 0:
        return bg
    return tuple(int(bg[i] + (fg[i] - bg[i]) * t) for i in range(4))  # type: ignore[return-value]


def icns_file(entries: list[tuple[bytes, bytes]]) -> bytes:
    body = b""
    for tag, data in entries:
        body += tag + struct.pack(">I", 8 + len(data)) + data
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    pngs: dict[int, bytes] = {}
    mapping = {
        32: "32x32.png",
        128: "128x128.png",
        256: "128x128@2x.png",
        1024: "icon.png",
    }
    for size, name in mapping.items():
        pngs[size] = write_png(ROOT / name, size, rgba)
    pngs[512] = write_png(ROOT / "512x512.png", 512, rgba)
    (ROOT / "icon.icns").write_bytes(
        icns_file(
            [
                (b"ic10", pngs[1024]),
                (b"ic09", pngs[512]),
                (b"ic08", pngs[256]),
                (b"ic07", pngs[128]),
            ]
        )
    )
    print("icons ->", ROOT)


if __name__ == "__main__":
    main()
