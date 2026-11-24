#!/usr/bin/env python3
"""Show which PS5 module each import of the title binds to, and fail on the
ones a title cannot resolve.

    check_imports.py <linked pie elf> <sdk target/lib> <prospero-nm>

The boilerplate's converter binds every undefined symbol to the first
DT_NEEDED stub module that exports it, in DT_NEEDED order. PS5LM found
(docs/CONSOLE.md, "Imports that resolve to nothing") that functions bound to
libScePosixForWebKit or libkernel_sys are null in a title: a call jumps to
address 0. Such a symbol has to be defined by the title itself
(ports/ps5/launcher/compat.c). Exit status 1 when any is left, so the build
stops before it produces a title that crashes.

Also fails when a piece of the C++ runtime is imported (libSceLibcInternal
exports __gxx_personality_v0, __cxa_get_globals, std:: exception classes...):
mixing Sony's C++ ABI library with the static libc++abi/libunwind crashes on
the first throw, so all of it must come from the static libraries.
"""
import collections
import pathlib
import re
import subprocess
import sys

RISKY = {"libScePosixForWebKit.so", "libScePosixForWebKit.sprx", "libScePosixForWebKit.prx",
         "libkernel_sys.so", "libkernel_sys.sprx", "libkernel_sys.prx"}


# The C++ runtime: must never be imported. __cxa_atexit/__cxa_finalize are
# the C library's (the title CRT registers destructors through Sony's libc).
CXX_RUNTIME = re.compile(r"^(__gxx_personality|__cxa_|_Unwind_|_ZSt|_ZNSt|_ZNKSt|_ZTISt|_ZTVSt|_ZTSSt"
                         r"|_ZTVN10__cxxabiv|_Znw|_Zna|_Zdl|_Zda)")
CXX_ALLOWED = {"__cxa_atexit", "__cxa_finalize"}


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def main():
    elf, libdir, nm = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
    needed = re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", run("readelf", "-d", elf))
    by_soname = {}
    for stub in sorted(libdir.glob("*.so")):
        found = re.findall(r"\(SONAME\)\s+Library soname: \[([^\]]+)\]", run("readelf", "-d", str(stub)))
        by_soname.setdefault(found[0] if found else stub.name, stub)
    exports = {}
    for name in needed:
        syms = set()
        for line in run(nm, "-D", "--defined-only", str(by_soname[name])).splitlines():
            parts = line.split()
            if len(parts) >= 3:
                syms.add(parts[2].split("@")[0])
        exports[name] = syms
    undefined = sorted({line.split()[-1].split("@")[0]
                        for line in run(nm, "-D", "--undefined-only", elf).splitlines() if line.split()})
    bound = collections.defaultdict(list)
    missing = []
    for sym in undefined:
        module = next((m for m in needed if sym in exports[m]), None)
        if module is None:
            missing.append(sym)
        else:
            bound[module].append(sym)
    print(f"imports: {len(undefined)} symbols from {len(needed)} modules")
    for module in needed:
        print(f"imports: {module}: {len(bound[module])}")
    bad = False
    for module in needed:
        if module in RISKY and bound[module]:
            bad = True
            print(f"imports: UNRESOLVABLE IN A TITLE ({module}): {' '.join(bound[module])}")
    cxx = [s for s in undefined if CXX_RUNTIME.match(s) and s not in CXX_ALLOWED]
    if cxx:
        bad = True
        print(f"imports: C++ RUNTIME IMPORTED (link libc++abi/libc++/libunwind first): {' '.join(cxx)}")
    for sym in missing:
        bad = True
        print(f"imports: no stub module exports {sym}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
