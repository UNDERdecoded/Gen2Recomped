#!/usr/bin/env python3
"""Build and qualify stock/extended LuaJIT without changing the input checkout."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PIN = "a4c064539ea931274d407e1249b4bb575424a0f4"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luajit-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="new disposable candidate directory; never an installation")
    parser.add_argument("--engine-tests", action="store_true")
    args = parser.parse_args()
    source, output = args.luajit_source.resolve(), args.output.resolve()
    engine_paths = ("main.lua", "conf.lua", "src", "assets", "data", "tests")
    engine_status = git(ROOT, "status", "--porcelain", "--untracked-files=no", "--", *engine_paths)
    if engine_status:
        parser.error("engine runtime and test inputs must be committed before qualification")
    if git(source, "rev-parse", "HEAD") != PIN:
        parser.error("LuaJIT source must be pinned to " + PIN)
    original_status = git(source, "status", "--porcelain", "--untracked-files=normal")
    if original_status:
        parser.error("LuaJIT input checkout must be clean")
    if output.exists():
        parser.error("output already exists; select a new disposable directory")
    if output == ROOT or output.is_relative_to(source) or source.is_relative_to(output):
        parser.error("output must be separate from source checkouts")
    run = subprocess.run
    if os.name != "nt" and not os.getenv("GITHUB_ACTIONS") and (ROOT / "tools/qa_storage.py").is_file():
        sys.path.insert(0, str(ROOT / "tools"))
        from qa_storage import qa_source, qa_copy, qa_cache, qa_run
        for path in (ROOT, source, HERE, Path(sys.executable)):
            qa_source(path)
        qa_cache(output.parent)
        qa_copy(output)
        run = qa_run
    patch = HERE / "luajit-upvalues.patch"
    # Check pinned Git blobs and normalize the patch itself: Windows checkout
    # conversion otherwise turns the patch's final empty context line into CRLF.
    subprocess.run(["git", "-C", str(source), "apply", "--check", "--cached", "-"],
                   input=patch.read_bytes().replace(b"\r\n", b"\n"), check=True)
    archive = subprocess.check_output(["git", "-C", str(source), "archive", PIN])
    output.mkdir(parents=True, exist_ok=False)
    artifacts = output / "artifacts"
    artifacts.mkdir()
    report = {"experimental": True, "luaJitSource": PIN,
              "engineSource": git(ROOT, "rev-parse", "HEAD"),
              "engineTree": {name: git(ROOT, "rev-parse", "HEAD:" + name)
                             for name in ("main.lua", "conf.lua", "src", "assets", "data")},
              "platform": platform.system(), "machine": platform.machine(),
              "toolsSha256": {p.name: digest(p) for p in sorted(HERE.iterdir()) if p.is_file()},
              "variants": []}

    def command(label, argv, cwd, env=None, timeout=180):
        result = run([str(value) for value in argv], cwd=cwd, env=env,
                     capture_output=True, text=True, timeout=timeout)
        (output / (label + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
        if result.returncode:
            print((result.stdout + result.stderr)[-6000:], flush=True)
        result.check_returncode()
        return result.stdout

    for label, capacity in (("stock", 60), ("extended", 120)):
        build = output / label
        build.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as files:
            files.extractall(build, filter="data")
        header = build / "src/lj_def.h"
        before = header.read_text()
        needle = "#define LJ_MAX_UPVAL\t60"
        if before.count(needle) != 1:
            raise RuntimeError("pinned upvalue declaration changed")
        if capacity != 60:
            header.write_text(before.replace(needle, "#define LJ_MAX_UPVAL\t120"))
        env = dict(os.environ)
        if platform.system() == "Darwin":
            env.setdefault("MACOSX_DEPLOYMENT_TARGET", "11.0")
        if os.name == "nt":
            # Git Bash prepends its Unix utilities to PATH, including a `link`
            # command unrelated to MSVC. The vendor batch file invokes `link`
            # by name, so keep the selected compiler's tools first in that child.
            compiler = shutil.which("cl.exe", path=env.get("PATH"))
            if not compiler or not Path(compiler).with_name("link.exe").is_file():
                raise RuntimeError("an MSVC developer environment is required")
            env["PATH"] = str(Path(compiler).parent) + os.pathsep + env["PATH"]
            build_log = command(label + "-build", ["cmd", "/d", "/c", "msvcbuild.bat", "lua52compat"],
                                build / "src", env, timeout=300)
            # msvcbuild.bat can reach its failure label with exit status zero.
            if "=== Successfully built LuaJIT for Windows/x64 ===" not in build_log:
                print(build_log[-6000:], flush=True)
                raise RuntimeError("MSVC runtime build did not complete; see build log")
            interpreter = build / "src/luajit.exe"
            library = build / "src/lua51.dll"
            c_program = build / "src/c-api-upvalues.exe"
            command(label + "-c-build", ["cl", "/nologo", "/MD", "/I" + str(build / "src"),
                    HERE / "c_api.c", build / "src/lua51.lib", "/Fe" + str(c_program)], build, env)
        else:
            command(label + "-build", ["make", "-j4", "XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT"], build, env, 300)
            interpreter = build / "src/luajit"
            library = build / "src/libluajit.so"
            c_program = build / "c-api-upvalues"
            links = ["-lm"] + (["-ldl"] if platform.system() == "Linux" else [])
            command(label + "-c-build", ["cc", "-I" + str(build / "src"), HERE / "c_api.c",
                    build / "src/libluajit.a", *links, "-o", c_program], build, env)
        text = command(label + "-closures", [interpreter, HERE / "check.lua", capacity], ROOT, env, 60)
        closure = json.loads(next(line.removeprefix("RUNTIME_UPVALUES ") for line in text.splitlines()
                                 if line.startswith("RUNTIME_UPVALUES ")))
        if not closure.get("passed") or closure["minimum"] != capacity:
            raise RuntimeError("closure qualification did not complete")
        counts = [60] if capacity == 60 else [60, 61, 64, 96, 120]
        for count in counts:
            c_result = command(label + "-c-api-" + str(count), [c_program, count], ROOT, env, 30)
            if "C_API_UPVALUES " + str(count) + " PASS" not in c_result:
                raise RuntimeError("C API qualification marker absent")
        variant = {"name": label, "capacity": capacity, "closure": closure,
                   "cApiCounts": counts, "librarySha256": digest(library),
                   "headerSha256": digest(header)}
        if args.engine_tests:
            engine_env = {k: v for k, v in env.items() if not k.startswith("POKEPORT_")}
            engine_env["LUA"] = interpreter.as_posix()
            shell = "bash"
            if os.name == "nt":
                # System32/bash.exe is a WSL launcher on Windows runners.
                # Use the Bash belonging to the already selected Git install.
                shell = Path(git(source, "--exec-path")).parents[2] / "bin/bash.exe"
                if not shell.is_file():
                    raise RuntimeError("Git for Windows Bash is required for engine tiers")
            text = command(label + "-engine", [shell, "scripts/test.sh", "--quick"], ROOT, engine_env, 900)
            match = re.search(r"engine: (\d+)/(\d+) suites passed", text)
            if not match or match[1] != match[2] or "ALL TIERS PASSED" not in text:
                raise RuntimeError("engine quick tiers did not all pass")
            variant["engineSuites"] = int(match[1])
        staged = artifacts / label
        staged.mkdir()
        for path in (interpreter, library, c_program):
            shutil.copy2(path, staged / path.name)
        shutil.copy2(build / "COPYRIGHT", staged / "COPYRIGHT-LuaJIT")
        report["variants"].append(variant)
        print("QUALIFIED", label, capacity, flush=True)
    if git(source, "status", "--porcelain", "--untracked-files=normal") != original_status:
        raise RuntimeError("input dependency checkout changed")
    if git(ROOT, "status", "--porcelain", "--untracked-files=no", "--", *engine_paths) != engine_status:
        raise RuntimeError("engine runtime/test inputs changed during qualification")
    report["sourceUnchanged"] = True
    report["passed"] = True
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
