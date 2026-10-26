#!/usr/bin/env python3
"""Profile independent optimization switches in a fresh native Emerald game."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import argparse
import atexit
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import time

BOOTSTRAP = r'''
local identity=assert(os.getenv("POKEPORT_IDENTITY"))
assert(identity:match("^oasc%-gen2recomp%-qa%-perf%-"),"owned test identity required")
assert(love.filesystem.getIdentity()==identity,"isolated identity mismatch")
assert(love.filesystem.write("migrated-from-pokemon-love2d.txt","Isolated performance QA; migration bypassed.\n"))
local setIdentity=love.filesystem.setIdentity
love.filesystem.setIdentity=function(value,...)
 assert(value==identity,"test rejected identity switch")
 return setIdentity(value,...)
end
assert(require("src.core.SaveData").portableBaseDir()==nil,"portable saves forbidden")
assert(require("src.import.CacheFs").root()==nil,"external imports forbidden")
io.stdout:setvbuf("no")
love.errorhandler=function(err)
 print(debug.traceback(tostring(err),2))
 return function()return 1 end
end
assert(loadfile("engine_main.lua"))()
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--love", type=Path, required=True)
    parser.add_argument("--emerald", type=Path, required=True)
    parser.add_argument("--backend", choices=("opengl", "metal"), required=True)
    parser.add_argument("--out", type=Path, required=True,
                        help="New directory under this checkout's .local/qa")
    parser.add_argument("--qa-tools", type=Path, help="Shared qa_storage.py directory")
    parser.add_argument("--map", default="MAP_G00_N15")
    parser.add_argument("--x", type=int, default=10)
    parser.add_argument("--y", type=int, default=10)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(args.qa_tools or root / "tools"))
    from qa_storage import Storage
    storage = Storage(root)
    atexit.register(storage.close)
    binary, rom = args.love.resolve(strict=True), args.emerald.resolve(strict=True)
    driver = root / "tools/full_game_performance_driver.lua"
    for path in (root, binary, rom, driver):
        storage.source(path)
    digest = hashlib.sha1(rom.read_bytes()).hexdigest()
    expected = json.loads((root / "tools/rom_manifest_emerald.json").read_text())["romSha1"]
    if digest != expected:
        parser.error("Unsupported Emerald ROM revision")
    run = args.out.resolve()
    storage.cache(run)
    source = run / "source"
    storage.copy(source)
    run.mkdir(parents=True, exist_ok=False)
    source.mkdir()
    identity = "oasc-gen2recomp-qa-perf-" + str(time.time_ns())
    storage.identity(identity)
    head = storage.run(["git", "rev-parse", "HEAD"], cwd=root, check=True,
                       capture_output=True, text=True).stdout.strip()
    assert not storage.run(["git", "status", "--porcelain"], cwd=root, check=True,
                           capture_output=True, text=True).stdout.strip(), "Commit the candidate first"
    files = [p for folder in ("src", "mods/DRAMATIC_SHAPE") for p in (root / folder).rglob("*")
             if p.is_file() and p.suffix in (".lua", ".json")]
    hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    archive = storage.run(["git", "archive", head, "main.lua", "conf.lua", "src",
                           "assets", "data", "tests", "tools", "mods/DRAMATIC_SHAPE"],
                          cwd=root, check=True, capture_output=True).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for entry in tar.getmembers():
            assert not entry.name.startswith("/") and ".." not in Path(entry.name).parts
            assert not entry.issym() and not entry.islnk(), "Frozen inputs must not alias player data"
        tar.extractall(source)
    (source / "main.lua").rename(source / "engine_main.lua")
    # Scripted runs normally bypass software pacing. Enable its existing native
    # body in this frozen test copy so P1 and P2 are actually exercised.
    entry = source / "engine_main.lua"
    text = entry.read_text()
    marker = 'if os.getenv("POKEPORT_DRIVER") then return false end'
    assert text.count(marker) == 1, "Unknown native pacing admission gate"
    entry.write_text(text.replace(marker,
        'if os.getenv("POKEPORT_DRIVER") and os.getenv("PERF_NATIVE_PACING") ~= "1" then return false end'))
    (source / "main.lua").write_text(BOOTSTRAP)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("POKEPORT_", "PERF_", "PALETTE_GPU_"))}
    env.update(POKEPORT_IDENTITY=identity, POKEPORT_VERSION="emerald",
               POKEPORT_GRAPHICS_BACKEND=args.backend, PERF_BACKEND=args.backend,
               POKEPORT_NO_BOOT_REPORT="1", POKEPORT_NO_DISCORD="1",
               POKEPORT_NOTIFY_ONLY_UPDATES="1", POKEPORT_TOUCH="0",
               PERF_NATIVE_PACING="1",
               PERF_MAP=args.map, PERF_X=str(args.x), PERF_Y=str(args.y))
    print("Fresh owned performance run:", run, flush=True)

    def child(label, extra, timeout=900):
        with (run / (label + ".log")).open("w") as log:
            storage.run([str(binary), str(source)], cwd=source, env=dict(env, **extra),
                        stdout=log, stderr=log, timeout=timeout, check=True)

    child("import", dict(POKEPORT_IMPORT_ROM=str(rom), POKEPORT_IMPORT_ONLY="1",
                         POKEPORT_NO_MODS="1", PERF_OUT=str(run)))
    print("Fresh import passed", flush=True)
    report = dict(schema=1, sourceCommit=head, romSha1=digest, backend=args.backend,
                  sourceSha256=hashes, driverSha256=hashlib.sha256(driver.read_bytes()).hexdigest(),
                  minimumFreeGiB=20, games={}, freshIdentity=True, legacyMigrationBypassed=True,
                  testAdaptations=["Enable existing native pacing for the driver in the frozen copy",
                                   "Quarter-pixel camera pan during P7; native update and draw remain active"])
    for mode, count in (("native", 14), ("voxel", 4)):
        out = run / mode
        out.mkdir()
        child(mode, dict(POKEPORT_DRIVER=str(source / "tools/full_game_performance_driver.lua"),
                         PERF_MODE=mode, PERF_OUT=str(out),
                         **({"POKEPORT_NO_MODS": "1"} if mode == "native" else {})))
        data = json.loads((out / "report.json").read_text())
        assert data["passed"] and len(data["phases"]) == count
        assert all(p["windows"] == 2 and p["present"]["samples"] == 240 for p in data["phases"])
        report["games"][mode] = data
        print(mode, "passed:", count, "measured switch phases", flush=True)
    assert all(hashlib.sha256((root / path).read_bytes()).hexdigest() == value
               for path, value in hashes.items())
    assert digest == hashlib.sha1(rom.read_bytes()).hexdigest()
    assert head == storage.run(["git", "rev-parse", "HEAD"], cwd=root, check=True,
                               capture_output=True, text=True).stdout.strip()
    assert not storage.run(["git", "status", "--porcelain"], cwd=root, check=True,
                           capture_output=True, text=True).stdout.strip()
    report["passed"] = True
    (run / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print("FULL_GAME_PERFORMANCE_PASS", run / "result.json", flush=True)


if __name__ == "__main__":
    main()
