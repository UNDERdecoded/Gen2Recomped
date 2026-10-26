#!/usr/bin/env python3
"""Validate and copy a release payload without repacking or restamping it."""
import argparse
import json
import re
import shutil
import zipfile
from pathlib import Path, PurePosixPath


def stage(source, destination, version=""):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    with zipfile.ZipFile(source) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("duplicate payload entries")
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or "\\" in name:
                raise ValueError("unsafe payload path: " + name)
            if path.suffix.lower() in (".gb", ".gbc", ".gba", ".nds", ".sav", ".srm", ".bak"):
                raise ValueError("private cartridge/save content: " + name)
            if "generated" in path.parts or "baseroms" in path.parts or path.name == "rom-cache.complete":
                raise ValueError("generated cartridge content: " + name)
        for name in ("main.lua", "conf.lua", "src/core/Version.lua", "src/core/GameVersion.lua"):
            if name not in names:
                raise ValueError("missing payload entry: " + name)
        declaration = archive.read("src/core/GameVersion.lua").decode("utf-8")
        for manifest in set(re.findall(r'manifest\s*=\s*"([^"]+)"', declaration)):
            data = json.loads(archive.read(manifest))
            if not re.fullmatch(r"[0-9a-fA-F]{40}", data.get("romSha1", "")):
                raise ValueError("invalid import manifest: " + manifest)
        if version:
            if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
                raise ValueError("version must be X.Y.Z")
            stamp = re.search(r'engine\s*=\s*"([^"]+)"', archive.read("src/core/Version.lua").decode("utf-8"))
            if not stamp or stamp.group(1) != version:
                raise ValueError("payload engine version does not match app version")
        bad = archive.testzip()
        if bad:
            raise ValueError("corrupt payload entry: " + bad)
    if source != destination:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--version", default="")
    args = parser.parse_args()
    stage(args.source, args.destination, args.version)


if __name__ == "__main__":
    main()
