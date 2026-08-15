#!/usr/bin/env bash
# Build the Xbox Dev Mode UWP package with the shared game.love payload.
#
# Usage:
#   scripts/build_xbox_uwp.sh [--release|--relwithdebinfo]
#                             [--version X.Y.Z] [--game-love PATH]
#                             [--publisher SUBJECT]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=xbox-uwp/common.sh
. "$SCRIPT_DIR/xbox-uwp/common.sh"

CONFIGURATION="Release"
PRESET="uwp-release"
GAME_LOVE=""
VERSION="0.0.0"
VERSION_EXPLICIT=0
PUBLISHER="${GEN2RECOMPED_UWP_PUBLISHER:-CN=Gen2Recomped}"

while [ $# -gt 0 ]; do
  case "$1" in
    --release)
      CONFIGURATION="Release"
      PRESET="uwp-release"
      shift
      ;;
    --relwithdebinfo)
      CONFIGURATION="RelWithDebInfo"
      PRESET="uwp-relwithdebinfo"
      shift
      ;;
    --game-love)
      [ $# -ge 2 ] || fail "--game-love requires a path"
      GAME_LOVE="$2"
      shift 2
      ;;
    --version)
      [ $# -ge 2 ] || fail "--version requires X.Y.Z"
      VERSION="$2"
      VERSION_EXPLICIT=1
      shift 2
      ;;
    --publisher)
      [ $# -ge 2 ] || fail "--publisher requires a certificate subject"
      PUBLISHER="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) fail "Xbox UWP packages must be built from Git Bash on Windows" ;;
esac

require_command cmake
require_command cygpath
require_command powershell.exe
require_command unzip
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "invalid version '$VERSION' (expected X.Y.Z)"

if [ -z "$GAME_LOVE" ]; then
  require_command zip
  mkdir -p "$WORK"
  GAME_LOVE="$WORK/game.love"
  pack_args=(
    --output "$GAME_LOVE" \
    --listing "$WORK/love-listing.txt"
  )
  if [ "$VERSION_EXPLICIT" -eq 1 ]; then
    pack_args+=(--version "$VERSION")
  fi
  "$ROOT/scripts/pack_love.sh" "${pack_args[@]}"
else
  GAME_LOVE="$(cd "$(dirname "$GAME_LOVE")" && pwd)/$(basename "$GAME_LOVE")"
  [ -f "$GAME_LOVE" ] || fail "missing game.love: $GAME_LOVE"
  "$ROOT/scripts/switch/verify_payload.sh" "$GAME_LOVE"
  if [ "$VERSION_EXPLICIT" -eq 1 ]; then
    version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
    unzip -p "$GAME_LOVE" src/core/Version.lua \
      | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
      || fail "game.love does not report engine $VERSION"
  fi
fi

say "configuring Xbox UWP ($CONFIGURATION)"
cmake --preset "$PRESET" -S "$(windows_path "$UWP_ROOT")" \
  "-DGEN2RECOMPED_LOVE:FILEPATH=$(windows_path "$GAME_LOVE")" \
  "-DGEN2RECOMPED_VERSION:STRING=$VERSION" \
  "-DGEN2RECOMPED_UWP_PUBLISHER:STRING=$PUBLISHER"

say "building Xbox UWP ($CONFIGURATION)"
(cd "$UWP_ROOT" && cmake --build --preset "$PRESET")

build_info="$WORK/xbox-uwp-build-info.json"
bash "$SCRIPT_DIR/xbox-uwp/write_build_info.sh" \
  "$build_info" "$VERSION" "$CONFIGURATION"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
  "$(windows_path "$SCRIPT_DIR/xbox-uwp/stage_release.ps1")" \
  -Version "$VERSION" \
  -Configuration "$CONFIGURATION" \
  -BuildInfo "$(windows_path "$build_info")"

say "done. See dist/xbox-uwp/"
