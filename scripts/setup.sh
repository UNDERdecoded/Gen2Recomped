#!/usr/bin/env bash
# Build game data from a user-provided Pokemon Red/Blue/Yellow ROM and install LÖVE.
#
# Usage:
#   scripts/setup.sh --rom /path/to/pokemon-red.gb
#   scripts/setup.sh --rom /path/to/pokemon-yellow.gbc
#   ROM_PATH=/path/to/pokemon-red.gb scripts/setup.sh
#
# With no explicit path, the first *.gb / *.gbc file in the project root is used.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/.venv"
ROM="${ROM_PATH:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rom)
      [ "$#" -ge 2 ] || { echo "error: --rom needs a path" >&2; exit 2; }
      ROM="$2"
      shift 2
      ;;
    *)
      echo "error: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 \
  || fail "Python 3 is required to decode the ROM"

if [ -z "$ROM" ]; then
  shopt -s nullglob
  for candidate in "$ROOT"/*.gb "$ROOT"/*.gbc; do
    if [ -f "$candidate" ]; then
      ROM="$candidate"
      break
    fi
  done
  shopt -u nullglob
fi
[ -n "$ROM" ] && [ -f "$ROM" ] \
  || fail "Pokemon ROM not found. Put a .gb or .gbc in $ROOT or pass --rom /path/to/file"

if [ ! -x "$VENV/bin/python3" ]; then
  say "creating Python environment"
  python3 -m venv "$VENV"
fi
say "installing Pillow"
"$VENV/bin/python3" -m pip install --quiet --upgrade pip
"$VENV/bin/python3" -m pip install --quiet pillow

say "decoding game data from $(basename "$ROM")"
cd "$ROOT"
"$VENV/bin/python3" tools/build_data.py --rom "$ROM" --clean

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

if LOVE_BIN="$(find_love)"; then
  say "LÖVE found: $LOVE_BIN"
elif [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  say "installing LÖVE via Homebrew"
  brew install --cask love
else
  fail "LÖVE 11.x is not installed; install it from https://love2d.org"
fi

say "setup complete. Start the game with: scripts/run.sh"
