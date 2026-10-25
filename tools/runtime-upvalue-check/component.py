#!/usr/bin/env python3
"""Stage a checked desktop Lua component from passing native qualification artifacts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PIN = "a4c064539ea931274d407e1249b4bb575424a0f4"
LOVE = "937eb3b21f973607ab080aa26b7ef2a6b3b2b663"
ENGINE_PATHS = ("main.lua", "conf.lua", "src", "assets", "data")
ARCHES = {"windows": {"x86_64"}, "macos": {"x86_64", "arm64"}}
CPU = {0x01000007: "x86_64", 0x0100000C: "arm64"}
HOST_ARCHIVES = {
    "windows": "1f4c6997bd93502f986f5187d877da84247617eede89d8140bcbf570bd07ea22",
    "macos": "f70f60d162eda6931b0b28e2b094b83b741986f0feac08d33a10be7c57e724f8",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def engine_tree(ref, root=ROOT):
    return {name: subprocess.check_output(
        ["git", "rev-parse", "--verify", ref + ":" + name], cwd=root, text=True).strip()
        for name in ENGINE_PATHS}


def child(root, relative):
    value = Path(relative)
    path = (root / value).resolve()
    if (value.is_absolute() or ".." in value.parts or "\\" in str(relative)
            or ":" in str(relative) or not path.is_relative_to(root.resolve()) or path == root.resolve()):
        raise ValueError("component path escapes its directory")
    return path


def slices(data, platform):
    """Return exact thin-library bytes, so lipo cannot silently change a slice."""
    if platform == "windows":
        if data[:2] != b"MZ" or len(data) < 64:
            raise ValueError("candidate is not a Windows PE library")
        offset = struct.unpack_from("<I", data, 60)[0]
        if offset + 6 > len(data) or data[offset:offset + 4] != b"PE\0\0":
            raise ValueError("invalid PE header")
        if struct.unpack_from("<H", data, offset + 4)[0] != 0x8664:
            raise ValueError("Windows runtime must be AMD64")
        return {"x86_64": data}
    if data[:4] in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        if len(data) < 32:
            raise ValueError("truncated Mach-O library")
        endian = "<" if data[:4] == b"\xcf\xfa\xed\xfe" else ">"
        arch = CPU.get(struct.unpack_from(endian + "I", data, 4)[0])
        if not arch:
            raise ValueError("unsupported Mac architecture")
        return {arch: data}
    formats = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
               b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    if data[:4] not in formats or len(data) < 8:
        raise ValueError("candidate is not a Mach-O library")
    endian, wide = formats[data[:4]]
    count = struct.unpack_from(endian + "I", data, 4)[0]
    size = 32 if wide else 20
    if count != 2 or 8 + count * size > len(data):
        raise ValueError("universal Mac runtime must have exactly two slices")
    result = {}
    for index in range(count):
        at = 8 + index * size
        cpu = struct.unpack_from(endian + "I", data, at)[0]
        offset, length = struct.unpack_from(endian + ("QQ" if wide else "II"), data, at + 8)
        if offset < 8 + count * size or not length or offset + length > len(data):
            raise ValueError("invalid universal library slice")
        body = data[offset:offset + length]
        thin = slices(body, "macos")
        arch = CPU.get(cpu)
        if arch in result or set(thin) != {arch}:
            raise ValueError("universal architecture headers disagree")
        result.update(thin)
    return result


def qualify(capacity_bytes, host_bytes, library_bytes, platform):
    capacity, host = json.loads(capacity_bytes), json.loads(host_bytes)
    system = "Windows" if platform == "windows" else "Darwin"
    variants = {row["name"]: row for row in capacity.get("variants", [])}
    tree = capacity.get("engineTree", {})
    if not (capacity.get("passed") is True and capacity.get("sourceUnchanged") is True
            and capacity.get("luaJitSource") == PIN and capacity.get("platform") == system
            and set(variants) == {"stock", "extended"} and set(tree) == set(ENGINE_PATHS)
            and all(isinstance(v, str) and len(v) == 40 for v in tree.values())):
        raise ValueError("passing pinned engine qualification with source-tree binding required")
    for name, limit in (("stock", 60), ("extended", 120)):
        row = variants[name]
        expected = [60] if name == "stock" else [60, 61, 64, 96, 120]
        if not (row.get("capacity") == limit and row.get("engineSuites", 0) > 0
                and row.get("closure", {}).get("passed") is True
                and row["closure"].get("minimum") == limit and row.get("cApiCounts") == expected):
            raise ValueError("closure, C API and engine gates must pass for both variants")
    if variants["stock"]["engineSuites"] != variants["extended"]["engineSuites"]:
        raise ValueError("stock and extended engine suite coverage differs")
    library_hash = sha(library_bytes)
    host_variants = {row["variant"]: row for row in host.get("variants", [])}
    if not (host.get("passed") is True and host.get("platform") == system
            and host.get("machine") == capacity.get("machine") and host.get("baseLoveCommit") == LOVE
            and host.get("originalArchiveSha256") == HOST_ARCHIVES[platform]
            and host.get("qualificationSha256") == sha(capacity_bytes)
            and host.get("inputCandidateLibrarySha256") == library_hash
            and variants["extended"].get("librarySha256") == library_hash
            and set(host_variants) == {"stock", "extended"}
            and host_variants["stock"].get("capacity") == 60
            and host_variants["extended"].get("capacity") == 120
            and all(row.get("checks", 0) > 0 for row in host_variants.values())):
        raise ValueError("matching actual LOVE host/thread/FFI acceptance required")
    arch = {"AMD64": "x86_64", "x86_64": "x86_64", "arm64": "arm64"}.get(capacity.get("machine"))
    if set(slices(library_bytes, platform)) != {arch} or arch not in ARCHES[platform]:
        raise ValueError("qualified machine and library architecture differ")
    return arch, tree


def macos_minimum(bodies):
    versions = []
    for data in bodies.values():
        endian = "<" if data[:4] == b"\xcf\xfa\xed\xfe" else ">"
        commands, total = struct.unpack_from(endian + "II", data, 16)
        at, end = 32, 32 + total
        found = []
        if end > len(data):
            raise ValueError("truncated Mach-O load commands")
        for _ in range(commands):
            if at + 8 > end:
                raise ValueError("truncated Mach-O load command")
            cmd, size = struct.unpack_from(endian + "II", data, at)
            if size < 8 or at + size > end:
                raise ValueError("invalid Mach-O load command")
            if cmd == 0x32 and size >= 24:  # LC_BUILD_VERSION
                target, version = struct.unpack_from(endian + "II", data, at + 8)
                if target != 1:
                    raise ValueError("runtime library targets a different Apple platform")
                found.append(version)
            elif cmd == 0x24 and size >= 16:  # LC_VERSION_MIN_MACOSX
                found.append(struct.unpack_from(endian + "I", data, at + 8)[0])
            at += size
        if not found:
            raise ValueError("Mac runtime has no deployment-version command")
        versions.extend(found)
    version = max(versions)
    return "%d.%d.%d" % (version >> 16, (version >> 8) & 255, version & 255)


def verify(manifest_path, platform, expected_tree):
    manifest_path = manifest_path.resolve()
    root = manifest_path.parent
    manifest = json.loads(manifest_path.read_text())
    if not (manifest.get("schema") == 1 and manifest.get("platform") == platform
            and manifest.get("experimental") is True and manifest.get("capacity") == 120
            and manifest.get("luaJitSource") == PIN and manifest.get("baseLoveCommit") == LOVE):
        raise ValueError("unsupported qualified runtime component")
    library = child(root, manifest["library"])
    data = library.read_bytes()
    if sha(data) != manifest["librarySha256"]:
        raise ValueError("component library checksum mismatch")
    bodies = slices(data, platform)
    if set(bodies) != ARCHES[platform]:
        raise ValueError("component is missing a required desktop architecture")
    if platform == "macos":
        minimum = macos_minimum(bodies)
        if manifest.get("minimumMacOS", minimum) != minimum:
            raise ValueError("component deployment version disagrees with its library")
        manifest["minimumMacOS"] = minimum
    seen = set()
    for row in manifest["qualifications"]:
        capacity = child(root, row["capacityReport"]).read_bytes()
        host = child(root, row["hostReport"]).read_bytes()
        if sha(capacity) != row["capacitySha256"] or sha(host) != row["hostSha256"]:
            raise ValueError("qualification receipt checksum mismatch")
        arch, tree = qualify(capacity, host, bodies[row["architecture"]], platform)
        if arch in seen or arch != row["architecture"] or tree != expected_tree:
            raise ValueError("component qualification does not cover this engine/architecture")
        seen.add(arch)
    if seen != ARCHES[platform]:
        raise ValueError("component receipts do not cover all required architectures")
    notice = child(root, manifest["notice"])
    if sha(notice.read_bytes()) != manifest["noticeSha256"]:
        raise ValueError("LuaJIT license notice checksum mismatch")
    return library, notice, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=ARCHES, required=True)
    parser.add_argument("--candidate", type=Path, action="append", required=True,
                        help="extracted qualification artifact directory; one per native architecture")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    candidates = [p.resolve() for p in args.candidate]
    if output.exists() or any(output.is_relative_to(p) or p.is_relative_to(output) for p in candidates):
        parser.error("output must be a new directory separate from all inputs")
    run = subprocess.run
    if os.name != "nt" and not os.getenv("GITHUB_ACTIONS") and (ROOT / "tools/qa_storage.py").is_file():
        sys.path.insert(0, str(ROOT / "tools"))
        from qa_storage import qa_source, qa_copy, qa_cache, qa_run
        for path in (ROOT, *candidates, Path(sys.executable)):
            qa_source(path)
        qa_cache(output.parent)
        qa_copy(output)
        run = qa_run
    checked = []
    for candidate in candidates:
        reports = [(p, json.loads(p.read_bytes())) for p in candidate.rglob("report.json")]
        capacity = [p for p, row in reports if "luaJitSource" in row]
        host = [p for p, row in reports if "baseLoveCommit" in row]
        if len(capacity) != 1 or len(host) != 1:
            parser.error("each artifact must contain exactly one capacity and one host report")
        lib = capacity[0].parent / "artifacts/extended" / ("lua51.dll" if args.platform == "windows" else "libluajit.so")
        arch, tree = qualify(capacity[0].read_bytes(), host[0].read_bytes(), lib.read_bytes(), args.platform)
        checked.append((arch, tree, capacity[0], host[0], lib))
    if {row[0] for row in checked} != ARCHES[args.platform] or len(checked) != len(ARCHES[args.platform]):
        parser.error("provide exactly the native architectures required by the platform")
    tree = checked[0][1]
    if any(row[1] != tree for row in checked):
        parser.error("candidate engine source trees differ")
    output.mkdir(parents=True)
    (output / "reports").mkdir()
    target = output / ("Lua" if args.platform == "macos" else "lua51.dll")
    if args.platform == "macos":
        run(["lipo", "-create", *[str(row[4]) for row in checked], "-output", str(target)], check=True)
    else:
        shutil.copy2(checked[0][4], target)
    notice = output / "COPYRIGHT-LuaJIT"
    shutil.copy2(checked[0][4].with_name("COPYRIGHT-LuaJIT"), notice)
    records = []
    for arch, _, capacity, host, _ in checked:
        cp, hp = "reports/" + arch + "-capacity.json", "reports/" + arch + "-host.json"
        shutil.copy2(capacity, output / cp)
        shutil.copy2(host, output / hp)
        records.append(dict(architecture=arch, capacityReport=cp, hostReport=hp,
                            capacitySha256=sha(capacity.read_bytes()), hostSha256=sha(host.read_bytes())))
    manifest = dict(schema=1, experimental=True, platform=args.platform, capacity=120,
                    luaJitSource=PIN, baseLoveCommit=LOVE, library=target.name,
                    librarySha256=sha(target.read_bytes()), notice=notice.name,
                    noticeSha256=sha(notice.read_bytes()), qualifications=records)
    if args.platform == "macos":
        manifest["minimumMacOS"] = macos_minimum(slices(target.read_bytes(), "macos"))
    path = output / "component.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    verify(path, args.platform, tree)
    print("QUALIFIED_COMPONENT", path, flush=True)


if __name__ == "__main__":
    main()
