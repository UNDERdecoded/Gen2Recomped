#!/usr/bin/env bash
# PS5 title build: pinned inputs and their fetchers. Sourced by
# scripts/ps5/build_runtime.sh and scripts/build_ps5.sh; never run on its own.
#
# Everything lands in $G2R_PS5_WORK (default ~/.cache/gen2recomp-ps5), outside
# the repository. Archives are checked against their sha256 before they are
# unpacked, git sources are checked out at an exact commit. A directory that
# is already there with its ".pinned" stamp matching the pin is reused as is.

G2R_PS5_WORK=${G2R_PS5_WORK:-$HOME/.cache/gen2recomp-ps5}

# ps5-native-app-boilerplate: the title CRT, the clean-room sce_module/libc.prx,
# the ELF -> FSELF converter, and (through its own pinned setup script) the
# public PS5 payload SDK v0.42. Same commit EglantinePS5 pins.
BOILERPLATE_URL=https://github.com/drakmor/ps5-native-app-boilerplate.git
BOILERPLATE_REV=dd44bbdc75437332ed22e3ba95126733419ef25a

# ps5-opengl SDK 1.0.2: Mesa 26.2 + the PS5 AGC winsys as static EGL/GL 4.6,
# the GL stack EglantinePS5 ships. The tarball also carries the sources of
# ps5-opengl itself, including integration/SDL2 (the SDL2 video driver and
# the two SDL patches this build applies).
GLSDK_URL=https://github.com/darkxex/ps5-opengl/releases/download/v1.0.2/ps5-opengl-sdk-1.0.2.tar.gz
GLSDK_SHA256=30d8e51dd062739b629346102be5932728ba714bc50b1bdcdf08306c8843d9a4

# PacBrew v0.40.2 prebuilt ports (built with the payload SDK): LuaJIT (FFI on),
# FreeType, OpenAL Soft 1.24.3, libogg/vorbis, libtheora, libmodplug, mpg123,
# zlib, libpng, bzip2. Only target/user/homebrew is unpacked.
PACBREW_URL=https://github.com/ps5-payload-dev/pacbrew-repo/releases/download/v0.40.2/ps5-payload-dev.tar.gz
PACBREW_SHA256=a85f65de418a8e6a898c6c3e3c870d50fff7618a200e4dd59ea9692af6ecec4d

# ps5-payload-dev's SDL fork at the commit ps5-opengl's SDL2 bridge was
# qualified against (SDL 2.30.12): PS5 joystick (ScePad) and audio
# (SceAudioOut) backends; its OSMesa video driver is replaced by the bridge.
SDL_URL=https://github.com/ps5-payload-dev/SDL.git
SDL_REV=8c56053f13ca13a0c050de613706ff69eb615836

# LuaJIT 2.1 at PacBrew's commit, rebuilt here (not PacBrew's archive) with
# LUAJIT_USE_SYSMALLOC: LuaJIT's own allocator maps flexible memory, of which a
# title has only a few hundred MiB; through malloc it lands in the title's
# direct-memory heap (ports/ps5/launcher/heap.c).
LUAJIT_URL=https://github.com/LuaJIT/LuaJIT.git
LUAJIT_REV=f9140a622a0c44a99efb391cc1c2358bc8098ab7

# LOVE 11.5, the release the game targets (same tarball and hash as PacBrew's
# love recipe).
LOVE_URL=https://github.com/love2d/love/releases/download/11.5/love-11.5-linux-src.tar.gz
LOVE_SHA256=066e0843f71aa9fd28b8eaf27d41abb74bfaef7556153ac2e3cf08eafc874c39

ps5_say() { printf 'ps5: %s\n' "$*"; }
ps5_die() { printf 'ps5: error: %s\n' "$*" >&2; exit 1; }

# ps5_fetch_archive <url> <sha256> <file>
ps5_fetch_archive() {
    local url=$1 sha=$2 file=$3
    mkdir -p "$(dirname "$file")"
    if [ -f "$file" ] && printf '%s  %s\n' "$sha" "$file" | sha256sum --check --strict --status; then
        return 0
    fi
    ps5_say "downloading $url"
    rm -f "$file.part"
    curl -fsSL --retry 3 -o "$file.part" "$url" || ps5_die "download failed: $url"
    printf '%s  %s\n' "$sha" "$file.part" | sha256sum --check --strict --status ||
        ps5_die "sha256 mismatch for $url (expected $sha)"
    mv "$file.part" "$file"
}

# ps5_fetch_git <url> <rev> <dir>
ps5_fetch_git() {
    local url=$1 rev=$2 dir=$3
    if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$rev" ]; then
        return 0
    fi
    if [ ! -d "$dir/.git" ]; then
        ps5_say "cloning $url"
        rm -rf "$dir"
        git clone -q "$url" "$dir" || ps5_die "clone failed: $url"
    fi
    # By sha: a pinned commit need not be on the default branch (the
    # boilerplate's is not).
    git -C "$dir" cat-file -e "$rev^{commit}" 2>/dev/null || git -C "$dir" fetch -q origin "$rev" ||
        ps5_die "fetch failed: $url $rev"
    git -C "$dir" -c advice.detachedHead=false checkout -q --force "$rev" ||
        ps5_die "$url has no commit $rev"
}

# ps5_stamp_ok <dir> <pin>: is <dir> already unpacked from <pin>?
ps5_stamp_ok() { [ -f "$1/.pinned" ] && [ "$(cat "$1/.pinned")" = "$2" ]; }

ps5_fetch_all() {
    local dl=$G2R_PS5_WORK/dl src=$G2R_PS5_WORK/src
    mkdir -p "$dl" "$src"

    # ---- boilerplate + payload SDK + libc.prx
    ps5_fetch_git "$BOILERPLATE_URL" "$BOILERPLATE_REV" "$src/boilerplate"
    if [ ! -x "$src/boilerplate/.deps/native/ps5-payload-sdk/bin/prospero-lld" ]; then
        ps5_say "setting up the payload SDK (boilerplate's pinned v0.42)"
        bash "$src/boilerplate/tools/setup-native-dependencies.sh" >/dev/null
    fi
    # sce_module/libc.prx is generated from the boilerplate's own source and
    # must reproduce the checksum the boilerplate commits.
    if [ ! -f "$src/boilerplate/runtime/libc.prx" ]; then
        ps5_say "generating the boilerplate's clean-room libc.prx"
        bash "$src/boilerplate/tools/rebuild-libc.sh" >/dev/null
    fi
    (cd "$src/boilerplate/runtime" && sha256sum --check --strict --status libc.prx.sha256) ||
        ps5_die "boilerplate runtime/libc.prx does not match its checksum"

    # ---- ps5-opengl SDK
    ps5_fetch_archive "$GLSDK_URL" "$GLSDK_SHA256" "$dl/ps5-opengl-sdk-1.0.2.tar.gz"
    if ! ps5_stamp_ok "$src/ps5-opengl-sdk-1.0.2" "$GLSDK_SHA256"; then
        rm -rf "$src/ps5-opengl-sdk-1.0.2"
        tar -xzf "$dl/ps5-opengl-sdk-1.0.2.tar.gz" -C "$src"
        [ -f "$src/ps5-opengl-sdk-1.0.2/sdk/lib/libPS5OpenGL.a" ] || ps5_die "ps5-opengl SDK layout changed"
        mkdir -p "$src/ps5-opengl-sdk-1.0.2/src"
        tar -xf "$src/ps5-opengl-sdk-1.0.2/sources/ps5-opengl.tar" -C "$src/ps5-opengl-sdk-1.0.2/src" \
            ps5-opengl/integration/SDL2 ps5-opengl/native-app
        echo "$GLSDK_SHA256" > "$src/ps5-opengl-sdk-1.0.2/.pinned"
    fi

    # ---- PacBrew ports
    ps5_fetch_archive "$PACBREW_URL" "$PACBREW_SHA256" "$dl/pacbrew-0.40.2.tar.gz"
    if ! ps5_stamp_ok "$src/pacbrew-0.40.2" "$PACBREW_SHA256"; then
        rm -rf "$src/pacbrew-0.40.2"
        mkdir -p "$src/pacbrew-0.40.2"
        tar -xzf "$dl/pacbrew-0.40.2.tar.gz" -C "$src/pacbrew-0.40.2" \
            --wildcards '*target/user/homebrew/*'
        local hb
        hb=$(find "$src/pacbrew-0.40.2" -type d -path '*target/user/homebrew' | head -1)
        [ -f "$hb/lib/libluajit-5.1.a" ] || ps5_die "PacBrew archive layout changed"
        ln -sfn "$hb" "$src/pacbrew-0.40.2/homebrew"
        echo "$PACBREW_SHA256" > "$src/pacbrew-0.40.2/.pinned"
    fi

    # ---- SDL fork
    ps5_fetch_git "$SDL_URL" "$SDL_REV" "$src/SDL"
    ps5_fetch_git "$LUAJIT_URL" "$LUAJIT_REV" "$src/LuaJIT"

    # ---- LOVE
    ps5_fetch_archive "$LOVE_URL" "$LOVE_SHA256" "$dl/love-11.5-linux-src.tar.gz"
}
