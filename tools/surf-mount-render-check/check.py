#!/usr/bin/env python3
"""Check one unchanged public consumer against each engine's native surf mount draws."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import zlib

GEN1 = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def pixels(sheet, box, flip_x, flip_y):
    data = bytes.fromhex(sheet["bytes"])
    width, height = struct.unpack(">II", data[16:24])
    compressed = bytearray()
    at = 8
    while at < len(data):
        size = struct.unpack(">I", data[at:at+4])[0]
        if data[at+4:at+8] == b"IDAT":
            compressed.extend(data[at+8:at+8+size])
        at += 12+size
    raw = zlib.decompress(compressed)
    assert len(raw) == height * (1+width*4)
    rows = []
    for y in range(box["y"], box["y"]+box["height"]):
        start = y*(1+width*4)
        assert raw[start] == 0, "fixture must use filter zero"
        row = raw[start+1+box["x"]*4:start+1+(box["x"]+box["width"])*4]
        cells = [row[x:x+4] for x in range(0, len(row), 4)]
        if flip_x:
            cells.reverse()
        rows.append(b"".join(cells))
    if flip_y:
        rows.reverse()
    return hashlib.sha256(b"".join(rows)).hexdigest()


def validate(rows):
    comparisons = 0
    for observation in rows:
        sheets = observation["public"]["sheets"]
        native = observation["native"]
        public = observation["public"]["scene"]["mounts"]
        assert len(native) == len(public), "visible mount count"
        for n, p in zip(native, public):
            d, source = p["draw"], p["source"]
            cx, cy = observation["camera"]["x"], observation["camera"]["y"]
            x, y = d["x"]-cx, d["y"]-cy
            if p["pixelSnap"] == "floorRelative":
                x, y = math.floor(x), math.floor(y)
            assert [n["x"], n["y"], n["source"]["width"], n["source"]["height"]] == [x, y, d["width"], d["height"]]
            assert pixels(sheets[n["sheetId"]], n["source"], n["flipX"], n["flipY"]) == pixels(sheets[p["sheetId"]], source, p["flipX"], p["flipY"])
            assert p["ownerId"] == "player"
            comparisons += 1
    return comparisons


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--gen1", type=Path, required=True)
    p.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    p.add_argument("--api", type=int, choices=[2, 3], default=2)
    p.add_argument("--report", type=Path)
    a = p.parse_args()
    gen1, gen2 = a.gen1.resolve(), a.gen2.resolve()
    if git(gen1, "rev-parse", "HEAD") != GEN1 or git(gen1, "status", "--porcelain"):
        p.error("Gen1 must be clean at " + GEN1)
    comparisons = []
    for version in ["firered", "emerald"]:
        for backend, engine in [("gen1", gen1), ("gen2", gen2)]:
            run = subprocess.run([a.lua, str(gen2/"tests/surf_mount_render/worker.lua"), str(gen2), backend, version, str(a.api)],
                                 cwd=engine, text=True, capture_output=True, timeout=60)
            lines = [x[12:] for x in run.stdout.splitlines() if x.startswith("SURF_RENDER ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            rows = json.loads(lines[0])
            count = validate(rows)
            comparisons.append({"backend": backend, "version": version, "scenarios": len(rows), "mounts_compared": count})
            print(f"PASS {backend}/{version}: {len(rows)} scenarios, {count} native geometry/RGBA comparisons")
    assert not git(gen1, "status", "--porcelain"), "reference changed"
    report = {"gen1_ref": GEN1, "gen2_ref": git(gen2, "rev-parse", "HEAD"), "api": a.api,
              "gen1_surface": "explicit test-only reference extension; not upstream public support",
              "comparison": "Each engine against its own native art/placement; native animation and layer differences preserved",
              "comparisons": comparisons,
              "native_oracle_sha256": {backend: {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in names}
                  for backend, root, names in [("gen1", gen1, ["src/core/game3/field_effects.lua", "src/core/game3/surf_bob.lua"]),
                                               ("gen2", gen2, ["src/world/Player.lua", "src/render/SpriteRenderer.lua"])]}}
    if a.report:
        a.report.write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    main()
