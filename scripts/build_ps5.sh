#!/usr/bin/env bash
# Gen2Recomped for PS5: build the native title folder (and optionally put it
# on a console). One command:
#
#   scripts/build_ps5.sh [--deploy HOST] [--test-game] [--version X.Y.Z]
#                        [--out DIR] [--clean]
#
#   --deploy HOST   upload the folder to HOST's /data/homebrew/<TITLE_ID> over
#                   FTP (ftpsrv, port $PS5_FTP_PORT or 2121) and ask
#                   ShadowMountPlus (port 10101) to scan, which registers the
#                   title on the home screen the first time
#   --test-game     bundle ports/ps5/testgame (runtime bring-up: video,
#                   shaders, pad, audio, save dir, JIT/FFI) instead of the game
#   --version       stamp this release into the packed game.love
#                   (scripts/pack_love.sh --version)
#   --out DIR       where the title folder goes (default
#                   $G2R_PS5_WORK/out/title; the folder is DIR/<TITLE_ID>)
#   --clean         rebuild the runtime from scratch
#
# Runs on Linux or WSL (ports/ps5/BUILD.md lists the host packages). The
# runtime (LOVE 11.5 + SDL2 + ps5-opengl + LuaJIT, scripts/ps5/build_runtime.sh)
# is built once into $G2R_PS5_WORK (default ~/.cache/gen2recomp-ps5) and reused.
#
# Title folder:
#   <TITLE_ID>/eboot.bin              launcher + LOVE, development FSELF
#   <TITLE_ID>/sce_module/libc.prx    the boilerplate's clean-room loader shim
#   <TITLE_ID>/sce_sys/param.json     from ports/ps5/sce_sys
#   <TITLE_ID>/sce_sys/icon0.png      from ports/ps5/sce_sys
#   <TITLE_ID>/sce_sys/pic0.dds       ports/ps5/sce_sys/pic0.png as BC7 DDS
#   <TITLE_ID>/sce_sys/pic1.dds       ports/ps5/sce_sys/pic1.png as BC7 DDS
#   <TITLE_ID>/game.love              scripts/pack_love.sh's payload
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=ps5/deps.sh
source "$repo/scripts/ps5/deps.sh"

deploy=""
test_game=0
version=""
out=""
runtime_args=()
while [ $# -gt 0 ]; do
    case $1 in
        --deploy) [ $# -ge 2 ] || ps5_die "--deploy needs a host"; deploy=$2; shift 2 ;;
        --test-game) test_game=1; shift ;;
        --version) [ $# -ge 2 ] || ps5_die "--version needs X.Y.Z"; version=$2; shift 2 ;;
        --out) [ $# -ge 2 ] || ps5_die "--out needs a directory"; out=$2; shift 2 ;;
        --clean) runtime_args+=(--clean); shift ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) ps5_die "unknown argument: $1" ;;
    esac
done
[ "$(uname -s)" = Linux ] || ps5_die "run this on Linux or in WSL (wsl bash scripts/build_ps5.sh)"

sce_sys=$repo/ports/ps5/sce_sys
[ -f "$sce_sys/param.json" ] || ps5_die "missing $sce_sys/param.json"
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$sce_sys/param.json")
[[ $title_id =~ ^PPSA[0-9]{5}$ ]] || ps5_die "param.json titleId '$title_id' is not PPSA#####"

# ---------------------------------------------------------------- runtime
bash "$repo/scripts/ps5/build_runtime.sh" "${runtime_args[@]}"
runtime=$G2R_PS5_WORK/out/runtime

# ---------------------------------------------------------------- game.love
stage=$G2R_PS5_WORK/out
mkdir -p "$stage"
love="$stage/game.love"
rm -f "$love"
if [ $test_game = 1 ]; then
    ps5_say "packing ports/ps5/testgame"
    (cd "$repo/ports/ps5/testgame" && zip -q -r -X "$love" . -x '.*')
else
    pack=(bash "$repo/scripts/pack_love.sh" --output "$love" --listing "$stage/game.love.txt")
    [ -n "$version" ] && pack+=(--version "$version")
    "${pack[@]}"
fi

# ---------------------------------------------------------------- folder
out=${out:-$G2R_PS5_WORK/out/title}
app=$out/$title_id
rm -rf "$app"
mkdir -p "$app/sce_sys" "$app/sce_module"
cp "$runtime/eboot.bin" "$app/eboot.bin"
cp "$runtime/libc.prx" "$app/sce_module/libc.prx"
cp "$sce_sys/param.json" "$app/sce_sys/param.json"
[ -f "$sce_sys/icon0.png" ] && cp "$sce_sys/icon0.png" "$app/sce_sys/icon0.png"
cp "$love" "$app/game.love"

# pic0/pic1: the shell wants 3840x2160 BC7 DX10 DDS; sce_sys keeps PNGs.
if [ -f "$sce_sys/pic0.png" ] && [ -f "$sce_sys/pic1.png" ]; then
    tool=$G2R_PS5_WORK/build/png2dds
    src=$repo/ports/ps5/tools/png2dds.c
    stb=$G2R_PS5_WORK/build/love/src/libraries/stb
    if [ ! -x "$tool" ] || [ "$src" -nt "$tool" ]; then
        cc -O2 -w -I"$stb" -o "$tool" "$src" -lm || ps5_die "png2dds build failed"
    fi
    for pic in pic0 pic1; do
        "$tool" "$sce_sys/$pic.png" "$app/sce_sys/$pic.dds"
    done
fi

ps5_say "title folder: $app"
du -sh "$app" | sed 's/^/ps5: /'

# ---------------------------------------------------------------- deploy
if [ -n "$deploy" ]; then
    port=${PS5_FTP_PORT:-2121}
    base="ftp://$deploy:$port/data/homebrew/$title_id"
    ps5_say "uploading to $base"
    # eboot.bin and param.json last, so a half-copied folder never looks like
    # a title to ShadowMountPlus.
    (cd "$app" && find . -type f ! -name eboot.bin ! -path ./sce_sys/param.json | sort) |
    while read -r rel; do
        rel=${rel#./}
        curl -sS --ftp-create-dirs -T "$app/$rel" "$base/$rel" || ps5_die "upload failed: $rel"
    done
    for rel in eboot.bin sce_sys/param.json; do
        curl -sS --ftp-create-dirs -T "$app/$rel" "$base/$rel" || ps5_die "upload failed: $rel"
    done
    ps5_say "asking ShadowMountPlus to scan"
    curl -sS -m 10 -X POST -H 'Content-Type: application/json' -d '{"reset_attempts":true}' \
        "http://$deploy:10101/api/v1/scan" && echo ||
        ps5_say "WARNING: no answer from ShadowMountPlus on $deploy:10101; scan from its menu"
    ps5_say "deployed. ShadowMountPlus defers the scan while a homebrew title runs: close it first."
fi
