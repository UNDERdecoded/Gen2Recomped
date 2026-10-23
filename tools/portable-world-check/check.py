#!/usr/bin/env python3
"""Compare the unchanged mod on both engines and Gen1's native GBA pixels."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

GEN1_REF = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"


def git(root, *args):
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True
    ).strip()


def run_lua(lua, script, engine, *args):
    result = subprocess.run(
        [lua, str(script), *map(str, args)],
        cwd=engine, text=True, capture_output=True, timeout=60,
    )
    if result.returncode:
        raise RuntimeError(f"{engine.name}/{script.name}:\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", type=Path, required=True)
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--api", type=int, choices=(2, 3), default=2)
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    gen1, gen2 = args.gen1.resolve(), args.gen2.resolve()
    if git(gen1, "rev-parse", "HEAD") != GEN1_REF or git(gen1, "status", "--porcelain"):
        parser.error("Gen1 must be clean at " + GEN1_REF)
    if not (gen2 / "src/mods/RenderData.lua").is_file():
        parser.error("compose render-data PR #136 into an isolated Gen2 checkout first")
    comparisons, native_pixels = [], []
    for version in ("firered", "emerald"):
        values = []
        for backend, engine in (("gen1", gen1), ("gen2", gen2)):
            output = run_lua(
                args.lua, gen2 / "tests/portable_world/worker.lua",
                engine, gen2, backend, version, args.api,
            )
            lines = [line[15:] for line in output.splitlines()
                     if line.startswith("PORTABLE_WORLD ")]
            if len(lines) != 1:
                raise RuntimeError(f"missing result for {backend}/{version}:\n{output}")
            values.append(json.loads(lines[0]))
        if values[0] != values[1]:
            raise RuntimeError(f"world draw mismatch for {version}")
        comparisons.append({
            "version": version,
            "checks_per_engine": values[0]["checks"],
            "draw_sha256": hashlib.sha256(
                json.dumps(values[0], sort_keys=True).encode()
            ).hexdigest(),
        })
        print(f"PASS {version}: identical world draws, cache/resize/rollback "
              f"({values[0]['checks']} checks/engine)")
        output = run_lua(
            args.lua, gen2 / "tools/portable-world-check/native_pixels.lua",
            gen1, gen2, version,
        )
        if output.strip() != "NATIVE_PIXELS 18":
            raise RuntimeError(f"unexpected native compositor result/{version}:\n{output}")
        native_pixels.append({"version": version, "layer_comparisons": 18})
        print(f"PASS {version}: 18 RGBA comparisons against native Gen1 GBA compositor")
    if git(gen1, "status", "--porcelain"):
        raise RuntimeError("reference changed during test")
    paths = [
        *sorted((gen2 / "examples/portable_oasc_world").glob("*")),
        gen2 / "src/render/PortableWorld.lua",
        gen2 / "src/render/Pipelines.lua",
        gen2 / "tools/portable-world-check/gen1_reference.lua",
    ]
    # Pin the independent pixel oracle's source as well as the new mod.
    oracle_paths = ["src/import/gba/metatile.lua", "src/import/gba/tileset.lua",
                    "src/import/gba/family.lua"]
    report = {
        "gen1_ref": GEN1_REF,
        "gen2_ref": git(gen2, "rev-parse", "HEAD"),
        "api": args.api,
        "gen1_surface": "explicit reference extension; not an upstream public Game3 render pass",
        "source_sha256": {str(p.relative_to(gen2)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in paths if p.is_file()},
        "native_oracle_sha256": {p: hashlib.sha256((gen1 / p).read_bytes()).hexdigest()
                                 for p in oracle_paths},
        "native_pixel_oracle": native_pixels,
        "comparisons": comparisons,
        "total_checks": 2 * sum(row["checks_per_engine"] for row in comparisons),
    }
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Portable world: 2 comparisons / 4 isolated loaders / "
          f"{report['total_checks']} checks passed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
