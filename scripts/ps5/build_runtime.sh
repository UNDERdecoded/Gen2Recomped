#!/usr/bin/env bash
# Builds the PS5 runtime of Gen2Recomped: LOVE 11.5 and its libraries,
# statically linked with the launcher into a native PS5 title executable
# (eboot.bin, a development FSELF) plus sce_module/libc.prx.
#
#   scripts/ps5/build_runtime.sh [--clean]
#
# Linux or WSL (Ubuntu 26.04 tested) with clang-18, clang, cmake, ninja, make,
# autotools, python3, curl, git. Every input is pinned in scripts/ps5/deps.sh
# and fetched into $G2R_PS5_WORK (default ~/.cache/gen2recomp-ps5); the build
# trees are there too. Output: $G2R_PS5_WORK/out/runtime/{eboot.bin,libc.prx}.
# Each stage is skipped when its output is newer than its inputs; --clean
# rebuilds everything.
#
# The stack (ports/ps5/BUILD.md has the why):
#   ps5-opengl SDK 1.0.2       EGL + OpenGL 4.6 core / compatibility (Mesa 26.2 on AGC)
#   SDL 2.30.12 (PS5 fork)     + ps5-opengl's G19 video driver, PS5 audio + pad
#   LuaJIT 2.1                 FFI on, system malloc, JIT decided at run time
#   LOVE 11.5                  + ports/ps5/love/*.patch
#   PacBrew v0.40.2            freetype, openal-soft (SDL2 backend), vorbis,
#                              ogg, theora, modplug, mpg123, png, zlib, bzip2
#   boilerplate                CRT, libc.prx, ELF -> FSELF converter
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=deps.sh
source "$repo/scripts/ps5/deps.sh"

clean=0
for a in "$@"; do
    case $a in
        --clean) clean=1 ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) ps5_die "unknown argument: $a" ;;
    esac
done

for tool in git curl make cmake ninja python3 clang-18 autoconf patch; do
    command -v "$tool" >/dev/null || ps5_die "missing host tool: $tool"
done

ps5_fetch_all

W=$G2R_PS5_WORK
S=$W/src
B=$W/build
O=$W/out/runtime
[ $clean = 1 ] && rm -rf "$B" "$O"
mkdir -p "$B" "$O"

BP=$S/boilerplate
GLROOT=$S/ps5-opengl-sdk-1.0.2
GL=$GLROOT/sdk
G19=$GLROOT/src/ps5-opengl/integration/SDL2
NATIVE=$GLROOT/src/ps5-opengl/native-app
PB=$S/pacbrew-0.40.2/homebrew
JOBS=${JOBS:-$(nproc)}

# A private copy of the payload SDK (hard links), with ps5-opengl's AGC import
# stubs added, so the converter sees them and the boilerplate stays untouched.
SDK=$B/sdk
if [ ! -f "$SDK/.ready" ]; then
    rm -rf "$SDK"
    cp -al "$BP/.deps/native/ps5-payload-sdk" "$SDK"
    cp "$GL/lib/libSceAgc.so" "$GL/lib/libSceAgcDriver.so" "$SDK/target/lib/"
    touch "$SDK/.ready"
fi
CC=$SDK/bin/prospero-clang
CXX=$SDK/bin/prospero-clang++
AR=$SDK/bin/prospero-ar
CFLAGS_COMMON="-O2 -ffunction-sections -fdata-sections"
CXXFLAGS_COMMON="$CFLAGS_COMMON -fexceptions -fcxx-exceptions -frtti"

newer() { # newer <output> <input>...: is the output newer than every input?
    local out=$1; shift
    [ -e "$out" ] || return 1
    [ -z "$(find "$@" -newer "$out" -print -quit 2>/dev/null)" ]
}

# ---------------------------------------------------------------- LuaJIT
LJ=$B/luajit
if ! newer "$LJ/src/libluajit.a" "$repo/scripts/ps5/deps.sh" "$repo/scripts/ps5/build_runtime.sh"; then
    ps5_say "LuaJIT $LUAJIT_REV"
    rm -rf "$LJ" && mkdir -p "$LJ"
    git -C "$S/LuaJIT" archive "$LUAJIT_REV" | tar -x -C "$LJ"
    # LuaJIT knows __PROSPERO__ and then turns FFI off; the payload SDK has
    # what FFI needs (PacBrew's recipe does the same).
    sed -i 's|__PROSPERO__|__JUNK__|g' "$LJ/src/lj_arch.h"
    # The title unwinds with LLVM's libunwind, whose __register_frame takes
    # one FDE (as on macOS), not a whole .eh_frame: register the JIT's
    # machine code the macOS way, or every trace logs "bad fde: FDE is really
    # a CIE" and errors cannot unwind through JIT-compiled code.
    sed -i 's|^#if LJ_TARGET_OSX$|#if LJ_TARGET_OSX \|\| defined(LUAJIT_LLVM_LIBUNWIND)|' "$LJ/src/lj_err.c"
    grep -q 'defined(LUAJIT_LLVM_LIBUNWIND)' "$LJ/src/lj_err.c" || ps5_die "LuaJIT lj_err.c patch failed"
    # Sony's clock() counts microseconds, but the payload SDK's <time.h> says
    # CLOCKS_PER_SEC is 128 (FreeBSD's), so os.clock() ran 7812 times fast
    # (measured on 13.00: a 0.35 s loop reported 2700 s).
    sed -i 's|(1.0/(lua_Number)CLOCKS_PER_SEC)|(1.0/1000000.0)|' "$LJ/src/lib_os.c"
    grep -q '(1.0/1000000.0)' "$LJ/src/lib_os.c" || ps5_die "LuaJIT lib_os.c clock patch failed"
    make -C "$LJ" -j"$JOBS" amalg BUILDMODE=static CROSS="$SDK/bin/prospero-" \
        DEFAULT_CC=clang TARGET_LIBS=-lunwind \
        XCFLAGS="-DLUAJIT_USE_SYSMALLOC -DLUAJIT_LLVM_LIBUNWIND" Q= \
        > "$B/luajit.log" 2>&1 || {
        # The luajit executable may not link as a payload; the library is all
        # that is needed.
        [ -f "$LJ/src/libluajit.a" ] || { tail -40 "$B/luajit.log" >&2; ps5_die "LuaJIT build failed"; }
    }
fi

# ---------------------------------------------------------------- SDL2
SDLB=$B/sdl
PREFIX=$B/prefix
if ! newer "$PREFIX/lib/libSDL2.a" "$repo/ports/ps5/sdl" "$repo/scripts/ps5/deps.sh"; then
    ps5_say "SDL2 $SDL_REV + ps5-opengl G19 video driver"
    rm -rf "$SDLB" && mkdir -p "$SDLB/src" "$SDLB/g19"
    git -C "$S/SDL" archive "$SDL_REV" | tar -x -C "$SDLB/src"
    patch -d "$SDLB/src" -p1 -s < "$G19/static-ps5.patch"
    patch -d "$SDLB/src" -p1 -s < "$G19/ps5-joystick.patch"
    cp "$G19/SDL_ps5g19.c" "$G19/ps5g19_display.h" "$SDLB/g19/"
    patch -d "$SDLB/g19" -p1 -s < "$repo/ports/ps5/sdl/g19-love.patch"
    "$SDK/bin/prospero-cmake" -S "$repo/ports/ps5/sdl" -B "$SDLB/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$CFLAGS_COMMON" \
        -DSDL_SOURCE="$SDLB/src" -DG19_SOURCE="$SDLB/g19" -DPS5_OPENGL_PREFIX="$GL" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_VERBOSE_MAKEFILE=OFF > "$B/sdl.log" 2>&1 ||
        { tail -40 "$B/sdl.log" >&2; ps5_die "SDL configure failed"; }
    cmake --build "$SDLB/build" -j"$JOBS" >> "$B/sdl.log" 2>&1 ||
        { tail -40 "$B/sdl.log" >&2; ps5_die "SDL build failed"; }
    rm -rf "$PREFIX/include/SDL2"
    mkdir -p "$PREFIX/include/SDL2" "$PREFIX/lib"
    cp "$SDLB/src/include/"*.h "$PREFIX/include/SDL2/"
    cp "$SDLB/build/sdl/include/SDL2/"*.h "$PREFIX/include/SDL2/" 2>/dev/null || true
    cp "$SDLB/build/sdl/include-config-release/SDL2/"*.h "$PREFIX/include/SDL2/" 2>/dev/null || true
    cp "$(find "$SDLB/build" -name libSDL2.a | head -1)" "$PREFIX/lib/libSDL2.a"
fi

# ---------------------------------------------------------------- pkg-config
# PacBrew's .pc files name /user/homebrew (their install prefix); point them
# at the unpacked tree. SDL2 and LuaJIT come from this build.
# Their libraries are seen through a directory of .a links only: the .la files
# next to them name paths of PacBrew's build machine and break libtool.
PC=$B/pkgconfig
PBLIB=$B/pacbrew-lib
rm -rf "$PC" "$PBLIB" && mkdir -p "$PC" "$PBLIB"
ln -s "$PB"/lib/*.a "$PBLIB/"
for f in "$PB"/lib/pkgconfig/*.pc; do
    sed -e "s|/user/homebrew/lib|$PBLIB|g" -e "s|\${prefix}/lib|$PBLIB|g" \
        -e "s|\${exec_prefix}/lib|$PBLIB|g" -e "s|/user/homebrew|$PB|g" "$f" > "$PC/$(basename "$f")"
done
cat > "$PC/sdl2.pc" <<EOF
Name: sdl2
Description: SDL2 with the ps5-opengl G19 video driver
Version: 2.30.12
Libs: -L$PREFIX/lib -lSDL2
Cflags: -I$PREFIX/include/SDL2 -DSDL_MAIN_HANDLED=1
EOF
cat > "$PC/luajit.pc" <<EOF
Name: LuaJIT
Description: LuaJIT 2.1 (system malloc)
Version: 2.1
Libs: $LJ/src/libluajit.a
Cflags: -I$LJ/src
EOF
export PKG_CONFIG_LIBDIR=$PC PKG_CONFIG_PATH=

# ---------------------------------------------------------------- LOVE
LV=$B/love
if ! newer "$LV/liblove.a" "$repo/ports/ps5/love" "$PREFIX/lib/libSDL2.a" "$LJ/src/libluajit.a"; then
    ps5_say "LOVE 11.5"
    rm -rf "$LV" && mkdir -p "$LV"
    tar -xzf "$W/dl/love-11.5-linux-src.tar.gz" -C "$LV" --strip-components=1
    for p in "$repo"/ports/ps5/love/*.patch; do
        patch -d "$LV" -p1 -s < "$p"
    done
    (
        cd "$LV"
        CC=$CC CXX=$CXX AR=$AR RANLIB=$SDK/bin/prospero-ranlib \
        CFLAGS="$CFLAGS_COMMON" CXXFLAGS="$CXXFLAGS_COMMON" LDFLAGS="-L$PBLIB" \
        PKG_CONFIG="$(command -v pkg-config)" \
        ./configure --host=x86_64-pc-freebsd --prefix=/ \
            --enable-static --disable-shared --disable-exe --disable-gme \
            --with-lua=luajit --disable-dependency-tracking
    ) > "$B/love.log" 2>&1 || { tail -40 "$B/love.log" >&2; ps5_die "LOVE configure failed"; }
    make -C "$LV" -j"$JOBS" >> "$B/love.log" 2>&1 ||
        { tail -40 "$B/love.log" >&2; ps5_die "LOVE build failed"; }
    lib=$(find "$LV/src" -name 'liblove*.a' -path '*.libs*' | head -1)
    [ -n "$lib" ] || ps5_die "LOVE built no static library"
    cp "$lib" "$LV/liblove.a"
fi

# ---------------------------------------------------------------- host tool
# The boilerplate's converter, with the libc heap capped at 256 MiB the way
# ps5-opengl's native folder does (the title's heap is ours, app_heap.c).
HT=$B/hosttool
if [ ! -x "$HT/build/host/ps5-native-tool" ]; then
    ps5_say "boilerplate host tool"
    rm -rf "$HT" && mkdir -p "$HT"
    cp -a "$BP/tooling" "$BP/tools" "$HT/"
    mkdir -p "$HT/.deps" && ln -s "$BP/.deps/native" "$HT/.deps/native"
    python3 - "$HT/tooling/native/sce_module_writer.cpp" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "write_u64(result.data, result.heap_size, std::numeric_limits<std::uint64_t>::max());"
if s.count(old) != 1:
    raise SystemExit("boilerplate sce_module_writer.cpp changed; update build_runtime.sh")
open(p, "w").write(s.replace(old, "write_u64(result.data, result.heap_size, 0x10000000ULL);"))
PY
    bash "$HT/tools/build-host-tools.sh" > "$B/hosttool.log" 2>&1 ||
        { tail -20 "$B/hosttool.log" >&2; ps5_die "host tool build failed"; }
fi
TOOL=$HT/build/host/ps5-native-tool

# ---------------------------------------------------------------- launcher
L=$B/launcher
rm -rf "$L" && mkdir -p "$L"
bp_cxx() { "$CXX" -std=c++20 -O2 -fno-exceptions -fno-rtti -ffunction-sections -fdata-sections "$@"; }
bp_cxx -c "$BP/tooling/native/app_crt.cpp" -o "$L/app_crt.o"
bp_cxx -c "$BP/tooling/native/app_cpp_runtime.cpp" -o "$L/app_cpp_runtime.o"
"$CXX" -std=c++17 $CXXFLAGS_COMMON -I"$LV/src" -I"$LV/src/modules" -I"$PREFIX/include/SDL2" \
    -I"$LJ/src" -DSDL_MAIN_HANDLED=1 -c "$repo/ports/ps5/launcher/main.cpp" -o "$L/main.o"
"$CC" -std=c11 $CFLAGS_COMMON -c "$repo/ports/ps5/launcher/ffi.c" -o "$L/ffi.o"
"$CC" -std=c11 $CFLAGS_COMMON -c "$repo/ports/ps5/launcher/compat.c" -o "$L/compat.o"
"$CC" -std=c11 $CFLAGS_COMMON -c "$NATIVE/app_heap.c" -o "$L/app_heap.o"

# ffi.C's table: every PHYSFS_* function LOVE's library defines, plus the
# libc names of ports/ps5/launcher/ffi_exports.txt.
{
    "$SDK/bin/prospero-nm" -g --defined-only "$LV/liblove.a" 2>/dev/null |
        awk '$2 == "T" && $3 ~ /^PHYSFS_/ { print $3 }'
    sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$repo/ports/ps5/launcher/ffi_exports.txt"
} | sort -u > "$L/ffi_exports.list"
grep -q '^PHYSFS_mount$' "$L/ffi_exports.list" || ps5_die "no PHYSFS_mount in liblove.a"
{
    echo '/* Generated by scripts/ps5/build_runtime.sh. */'
    echo '#include <stddef.h>'
    while read -r name; do echo "extern void $name(void);"; done < "$L/ffi_exports.list"
    echo 'struct g2r_ffi_export { const char *name; void *address; };'
    echo 'const struct g2r_ffi_export g2r_ffi_exports[] = {'
    while read -r name; do echo "    {\"$name\", (void *)$name},"; done < "$L/ffi_exports.list"
    echo '};'
    echo 'const size_t g2r_ffi_export_count = sizeof(g2r_ffi_exports) / sizeof(g2r_ffi_exports[0]);'
} > "$L/ffi_exports.c"
"$CC" -std=c11 -O2 -w -fno-builtin -c "$L/ffi_exports.c" -o "$L/ffi_exports.o"

# ---------------------------------------------------------------- link
# ps5-opengl's linker layout: the boilerplate's, plus the .eh_frame bounds
# libunwind needs (C++ exceptions in LOVE, LuaJIT's error unwinding).
cat > "$L/ps5-pie.ld" <<EOF
INCLUDE "$BP/tooling/native/ps5-pie.ld"
PROVIDE(__eh_frame_start = ADDR(.eh_frame));
PROVIDE(__eh_frame_end = ADDR(.eh_frame) + SIZEOF(.eh_frame));
PROVIDE(__eh_frame_hdr_start = ADDR(.eh_frame_hdr));
PROVIDE(__eh_frame_hdr_end = ADDR(.eh_frame_hdr) + SIZEOF(.eh_frame_hdr));
EOF
# The C++ runtime must be ours, not Sony's: libSceLibcInternal exports
# __gxx_personality_v0, __cxa_get_globals, the std:: exception classes and
# more, and Sony's personality routine called by our libunwind crashes on the
# first throw. lld lets a shared library's definition satisfy a reference an
# archive could also satisfy, unless the member was extracted first; "-u X"
# before the archives, and the archives before the Sony stubs, extract it
# first ("-u foo a.a b.so will extract a.a"). The list is what LOVE, SDL and
# LuaJIT need; check_imports.py fails the build if any C++ runtime symbol is
# still imported (add it here then).
cxx_own=(
    __gxx_personality_v0 __cxa_get_globals __cxa_get_globals_fast __cxa_demangle
    __cxa_guard_acquire __cxa_guard_release __cxa_guard_abort __cxa_pure_virtual
    _ZTVN10__cxxabiv117__class_type_infoE _ZTVN10__cxxabiv120__si_class_type_infoE
    _ZTVN10__cxxabiv121__vmi_class_type_infoE
    _ZNKSt13runtime_error4whatEv _ZNSt11logic_errorD1Ev _ZNSt12length_errorD1Ev
    _ZNSt12out_of_rangeD1Ev _ZNSt13runtime_errorD1Ev _ZNSt13runtime_errorD2Ev
    _ZNSt14overflow_errorD1Ev _ZNSt16invalid_argumentD1Ev
    _ZTISt11logic_error _ZTISt12length_error _ZTISt12out_of_range _ZTISt13runtime_error
    _ZTISt14overflow_error _ZTISt16invalid_argument _ZTISt18bad_variant_access
    _ZTVSt11logic_error _ZTVSt12length_error _ZTVSt12out_of_range _ZTVSt13runtime_error
    _ZTVSt14overflow_error _ZTVSt16invalid_argument _ZTVSt18bad_variant_access
)
cxx_u=()
for sym in "${cxx_own[@]}"; do cxx_u+=(-u "$sym"); done
# The title exports nothing.
printf '{\n    local:\n        *;\n};\n' > "$L/app-symbols.map"
builtins="$(clang-18 --print-resource-dir)/lib/linux/libclang_rt.builtins-x86_64.a"
[ -f "$builtins" ] || ps5_die "clang-18 compiler-rt builtins not found: $builtins"
pb() { echo "$PB/lib/$1"; }
"$SDK/bin/prospero-lld" -T "$L/ps5-pie.ld" --eh-frame-hdr \
    --version-script "$L/app-symbols.map" -e _start -o "$L/llvm-pie.elf" \
    --gc-sections \
    --wrap=malloc --wrap=calloc --wrap=realloc --wrap=free \
    --wrap=posix_memalign --wrap=malloc_usable_size \
    --wrap=dlsym --wrap=dlopen --wrap=dlerror --wrap=dlclose --wrap=lstat \
    --wrap=opendir --wrap=readdir --wrap=closedir \
    -u ps5_agc_gate2_run "${cxx_u[@]}" -L "$SDK/target/lib" -L "$GL/lib" \
    "$L/app_crt.o" "$L/app_cpp_runtime.o" "$L/main.o" "$L/ffi.o" "$L/ffi_exports.o" \
    "$L/compat.o" "$L/app_heap.o" \
    "$SDK/target/lib/libc++abi.a" "$SDK/target/lib/libc++.a" "$SDK/target/lib/libunwind.a" \
    --as-needed "$SDK"/target/lib/*.so --no-as-needed \
    --why-extract="$B/why-extract.txt" \
    --start-group \
    "$LV/liblove.a" "$PREFIX/lib/libSDL2.a" "$LJ/src/libluajit.a" \
    "$(pb libopenal.a)" "$(pb libfreetype.a)" "$(pb libpng16.a)" "$(pb libbz2.a)" "$(pb libz.a)" \
    "$(pb libvorbisfile.a)" "$(pb libvorbis.a)" "$(pb libtheoradec.a)" "$(pb libogg.a)" \
    "$(pb libmodplug.a)" "$(pb libmpg123.a)" \
    "$GL/lib/libPS5OpenGL.a" \
    "$builtins" "$SDK/target/lib/libc.a" \
    --end-group > "$B/link.log" 2>&1 ||
    { grep -m 60 -E 'error|undefined' "$B/link.log" >&2 || tail -40 "$B/link.log" >&2; ps5_die "link failed"; }

# Imports a title cannot resolve are null calls: list what came from the
# modules PS5LM found missing in a title (libScePosixForWebKit, libkernel_sys).
python3 "$repo/scripts/ps5/check_imports.py" "$L/llvm-pie.elf" "$SDK/target/lib" "$SDK/bin/prospero-nm" \
    | tee "$B/imports.txt"

"$TOOL" link --in "$L/llvm-pie.elf" --out "$L/eboot.elf" --stub-dir "$SDK/target/lib" \
    --module-sdk 0x02000009 --companion-sdk 0x08050001 --file-name eboot.elf > "$B/convert.log" 2>&1 ||
    { tail -20 "$B/convert.log" >&2; ps5_die "ELF conversion failed"; }
"$TOOL" self --sign --in "$L/eboot.elf" --out "$O/eboot.bin" --magic 0x1D3D154F >> "$B/convert.log" 2>&1 ||
    { tail -20 "$B/convert.log" >&2; ps5_die "FSELF signing failed"; }
cp "$BP/runtime/libc.prx" "$O/libc.prx"
ps5_say "runtime ready: $O/eboot.bin ($(stat -c %s "$O/eboot.bin") bytes)"
