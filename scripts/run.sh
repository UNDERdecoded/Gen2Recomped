#!/usr/bin/env bash
# Run the LÖVE2D Pokémon recomp port (macOS-friendly).
#
# Assumes scripts/setup.sh has been run once (LÖVE installed).  Extra
# arguments are passed through to LÖVE.
#
# Link play is peer-to-peer (lua-enet, bundled with LÖVE): one player
# picks HOST A GAME in START > LINK and reads out the address shown;
# the other picks JOIN A GAME and types it in.  UDP port 7777 by
# default (override with POKEPORT_LINK_PORT on both sides).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Gen1 setup writes into the project's data/generated, but Gen2 writes into
# LÖVE's save folder under gold/ or silver/, and the in-app launcher can
# import a ROM at runtime -- so a missing local cache is a warning, not fatal.
if [ "$(uname -s)" = "Darwin" ]; then
  LOVE_SAVE="$HOME/Library/Application Support/LOVE/${POKEPORT_IDENTITY:-pokemon-love2d}"
else
  LOVE_SAVE="${XDG_DATA_HOME:-$HOME/.local/share}/love/${POKEPORT_IDENTITY:-pokemon-love2d}"
fi

have_generated_data() {
  if [ -f "$ROOT/data/generated/maps.lua" ]; then return 0; fi
  for d in "$LOVE_SAVE"/*/data/generated; do
    if [ -f "$d/maps.lua" ]; then return 0; fi
  done
  return 1
}

if ! have_generated_data; then
  printf '\033[1;33m==>\033[0m %s\n' \
    "generated data not found; the in-app launcher will import a ROM at startup"
fi

find_love() {
  command -v love >/dev/null 2>&1 && { echo "love"; return; }
  for app in "/Applications/love.app" "$HOME/Applications/love.app"; do
    if [ -x "$app/Contents/MacOS/love" ]; then
      echo "$app/Contents/MacOS/love"
      return
    fi
  done
  return 1
}

LOVE_BIN="$(find_love)" \
  || fail "LÖVE not found,  run scripts/setup.sh (or install from https://love2d.org)"

exec "$LOVE_BIN" "$ROOT" "$@"
