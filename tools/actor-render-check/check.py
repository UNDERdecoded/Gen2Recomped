#!/usr/bin/env python3
"""Compare public actor observations and resolved sprite pixels on both engines."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import zlib

GEN1 = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def pixels(sheet, actor):
    # Synthetic fixtures use RGBA8/filter-zero PNGs. No external PNG decoder
    # or expected-copy of either engine's pose logic is needed.
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
    box = actor["source"]
    for y in range(box["y"], box["y"]+box["height"]):
        start = y*(1+width*4)
        assert raw[start] == 0
        row = raw[start+1:start+1+width*4]
        cells = [row[x:x+4] for x in range(0, len(row), 4)]
        if actor["flipX"]:
            cells.reverse()
        rows.append(b"".join(cells))
    return hashlib.sha256(b"".join(rows)).hexdigest()


def normalize(observations):
    result = []
    for observation in observations:
        actors = []
        for actor in observation["scene"]["actors"]:
            sheet = observation["sheets"][actor["sheetId"]]
            rgba = pixels(sheet, actor)
            actor = dict(actor)
            # Native sprite-row orders differ. Compare the public consumer's
            # resolved picture and geometry, not private numeric frame slots.
            actor.pop("frame")
            actor.pop("source")
            actor["rgba_sha256"] = rgba
            actors.append(actor)
        result.append(actors)
    return result


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
        results = []
        for backend, engine in [("gen1", gen1), ("gen2", gen2)]:
            run = subprocess.run([a.lua, str(gen2/"tests/actor_render/worker.lua"),
                                  str(gen2), backend, version, str(a.api)],
                                 cwd=engine, text=True, capture_output=True, timeout=60)
            lines = [x[13:] for x in run.stdout.splitlines() if x.startswith("ACTOR_RENDER ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            results.append(normalize(json.loads(lines[0])))
        if results[0] != results[1]:
            if a.report:
                a.report.with_suffix(".mismatch.json").write_text(json.dumps(results, indent=2))
            raise RuntimeError("actor pixel/geometry mismatch: " + version)
        comparisons.append({"version": version, "scenarios": len(results[0]),
                            "actors_compared": sum(map(len, results[0])),
                            "sha256": hashlib.sha256(json.dumps(results[0], sort_keys=True).encode()).hexdigest()})
        print(f"PASS {version}: {len(results[0])} scenarios, identical public actor geometry and resolved RGBA")
    assert not git(gen1, "status", "--porcelain"), "reference changed"
    paths = [gen2/"src/mods/ActorRenderData.lua", gen2/"src/mods/Loader.lua",
             *sorted((gen2/"examples/portable_oasc_actors").glob("*")),
             *sorted((gen2/"tools/actor-render-check").glob("*.lua"))]
    report = {"gen1_ref": GEN1, "gen2_ref": git(gen2, "rev-parse", "HEAD"), "api": a.api,
              "gen1_surface": "explicit test reference extension, not upstream public support",
              "source_sha256": {str(x.relative_to(gen2)): hashlib.sha256(x.read_bytes()).hexdigest()
                                for x in paths if x.is_file()},
              "native_oracle_sha256": {
                  name: hashlib.sha256((gen1 / name).read_bytes()).hexdigest()
                  for name in ["src/core/game3/ow_sprites.lua", "src/core/game3/player.lua",
                               "src/core/game3/objects.lua"]},
              "comparisons": comparisons}
    if a.report:
        a.report.write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    main()
