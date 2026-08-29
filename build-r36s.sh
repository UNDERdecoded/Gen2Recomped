#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HERE="$ROOT/.bazinga"
CACHE="$HERE/cache/r36s"
WORK="$HERE/work/r36s"
DIST="$ROOT/dist/r36s"

APP_NAME="gen2recomp"
ARTIFACT_SUFFIX="r36s-arkos"
PORT_DIR_NAME="gen2recomp"
LAUNCHER_NAME="Gen2recomp.sh"
LOVE_VERSION="11.5"
VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"

PM_RUNTIME_BASE="https://raw.githubusercontent.com/PortsMaster/PortMaster-GUI/main/PortMaster/runtimes/love_${LOVE_VERSION}"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || fail "curl is required"
command -v zip  >/dev/null || fail "zip is required"
command -v unzip >/dev/null || fail "unzip is required"

mkdir -p "$CACHE" "$WORK" "$DIST"

download() {
  local url="$1" dest="$2"
  if [ -f "$dest" ] && [ -s "$dest" ]; then
    return 0
  fi
  say "downloading $(basename "$dest")"
  curl -fL --progress-bar "$url" -o "$dest.tmp" \
    || fail "download failed: $url"
  mv "$dest.tmp" "$dest"
}

# --------------------------------------------------------------- game tree
say "staging lovegame/"
GAME_SRC="$WORK/lovegame"
rm -rf "$GAME_SRC"
mkdir -p "$GAME_SRC"

PAYLOAD="$WORK/game-payload.love"
rm -f "$PAYLOAD"
pack_args=(--output "$PAYLOAD")
if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  pack_args+=(--version "$VERSION")
fi

bash "$ROOT/scripts/pack_love.sh" "${pack_args[@]}"
bash "$ROOT/scripts/switch/verify_payload.sh" "$PAYLOAD"

unzip -q "$PAYLOAD" -d "$GAME_SRC"
rm -f "$PAYLOAD"

for required in tools/rom_manifest_gold.json tools/rom_manifest_crystal.json \
                tools/save-editor/Kit.lua main.lua; do
  [ -e "$GAME_SRC/$required" ] || fail "staged lovegame/ is missing $required"
done

: > "$GAME_SRC/portable.txt"

# --------------------------------------------------------------- love runtime
say "fetching LÖVE $LOVE_VERSION aarch64 runtime"
LOVE_BIN="$CACHE/love.aarch64"
LOVE_LIB="$CACHE/liblove-11.5.so"
LUAJIT_LIB="$CACHE/libluajit-5.1.so.2"
MODPLUG_LIB="$CACHE/libmodplug.so.1"
OGG_LIB="$CACHE/libogg.so.0"

download "$PM_RUNTIME_BASE/love.aarch64" "$LOVE_BIN"
download "$PM_RUNTIME_BASE/libs.aarch64/liblove-11.5.so" "$LOVE_LIB"
download "$PM_RUNTIME_BASE/libs.aarch64/libluajit-5.1.so.2" "$LUAJIT_LIB"
download "$PM_RUNTIME_BASE/libs.aarch64/libmodplug.so.1" "$MODPLUG_LIB"
download "$PM_RUNTIME_BASE/libs.aarch64/libogg.so.0" "$OGG_LIB"

# --------------------------------------------------------------- port tree
say "assembling port package"
PORT_ROOT="$WORK/port"
rm -rf "$PORT_ROOT"
mkdir -p "$PORT_ROOT/$PORT_DIR_NAME/bin" \
         "$PORT_ROOT/$PORT_DIR_NAME/libs.aarch64" \
         "$PORT_ROOT/$PORT_DIR_NAME/licenses" \
         "$PORT_ROOT/$PORT_DIR_NAME/conf"

cp -R "$GAME_SRC" "$PORT_ROOT/$PORT_DIR_NAME/lovegame"
cp "$LOVE_BIN" "$PORT_ROOT/$PORT_DIR_NAME/bin/love.aarch64"
chmod +x "$PORT_ROOT/$PORT_DIR_NAME/bin/love.aarch64"
cp "$LOVE_LIB" "$LUAJIT_LIB" "$MODPLUG_LIB" "$OGG_LIB" \
  "$PORT_ROOT/$PORT_DIR_NAME/libs.aarch64/"

# --------------------------------------------------------------- launcher
cat > "$PORT_ROOT/$LAUNCHER_NAME" <<'EOF'
#!/bin/bash
export HOME="${HOME:-/root}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
elif [ -d "/roms/ports/PortMaster" ]; then
  controlfolder="/roms/ports/PortMaster"
else
  controlfolder="/roms/PORTS/PortMaster"
fi

SHDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090
source "$controlfolder/control.txt"
get_controls
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

GAMEDIR="$SHDIR/gen2recomp"
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs.aarch64:${LD_LIBRARY_PATH:-}"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"
export LOVE_GRAPHICS_USE_OPENGLES="${LOVE_GRAPHICS_USE_OPENGLES:-1}"
export POKEPORT_GBCFX="${POKEPORT_GBCFX:-0}"

$ESUDO chmod a+x ./bin/love.aarch64 2>/dev/null || chmod a+x ./bin/love.aarch64
$ESUDO chmod 666 /dev/uinput 2>/dev/null || true

if [ -n "${GPTOKEYB:-}" ]; then
  $GPTOKEYB "love.aarch64" &
fi
if type pm_platform_helper >/dev/null 2>&1; then
  pm_platform_helper "$GAMEDIR/bin/love.aarch64"
fi

./bin/love.aarch64 "$GAMEDIR/lovegame"

if type pm_finish >/dev/null 2>&1; then
  pm_finish
else
  if [ -n "${ESUDO:-}" ]; then
    $ESUDO kill -9 $(pidof gptokeyb) 2>/dev/null || true
  else
    kill -9 $(pidof gptokeyb) 2>/dev/null || true
  fi
fi
EOF
chmod +x "$PORT_ROOT/$LAUNCHER_NAME"

# --------------------------------------------------------------- metadata
cat > "$PORT_ROOT/port.json" <<EOF
{
  "version": 2,
  "name": "Gen2Recomped-r36s.zip",
  "items": [
    "$LAUNCHER_NAME",
    "$PORT_DIR_NAME"
  ],
  "items_opt": null,
  "attr": {
    "title": "Gen2Recomped",
    "desc": "Native LÖVE2D recreation of Pokemon Gold, Silver and Crystal for R36S.",
    "inst": "Requires ArkOS with PortMaster. Copy a canonical .gb/.gbc cartridge dump into gen2recomp/lovegame/.",
    "genres": ["adventure", "rpg"],
    "porter": ["Alan J. Ortiz Ferrer"],
    "image": {},
    "rtr": true,
    "runtime": null,
    "reqs": [],
    "arch": ["aarch64"]
  }
}
EOF

# --------------------------------------------------------------- zip
ZIP_OUT="$DIST/Gen2Recomped-r36s.zip"
rm -f "$ZIP_OUT"
say "packing $ZIP_OUT"
(cd "$PORT_ROOT" && zip -q -9 -r "$ZIP_OUT" \
  "$LAUNCHER_NAME" "$PORT_DIR_NAME" port.json)

say "done."
say "artifact: $ZIP_OUT"
