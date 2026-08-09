#!/usr/bin/env bash
# Build game data from a user-provided Pokemon Red/Blue/Yellow/Gold/Silver ROM
# and install LÖVE.
#
# Usage:
#   scripts/setup.sh --rom /path/to/pokemon-red.gb
#   scripts/setup.sh --rom /path/to/pokemon-gold.gbc
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

sha1_of() {
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 1 "$1" | cut -d' ' -f1
  else
    python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  fi
}

# Without this the extractor falls back to Red's hash and rejects every other
# cartridge ("unsupported ROM SHA-1 ...; expected ea9bcae6...").
ROM_SHA1="$(sha1_of "$ROM" | tr '[:upper:]' '[:lower:]')"
case "$ROM_SHA1" in
  ea9bcae617fdf159b045185467ae58b2e4a48b9a) ROM_VERSION=red ;;
  d7037c83e1ae5b39bde3c30787637ba1d4c48ce2) ROM_VERSION=blue ;;
  cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1) ROM_VERSION=yellow ;;
  d8b8a3600a465308c9953dfa04f0081c05bdcb94) ROM_VERSION=gold ;;
  49b163f7e57702bc939d642a18f591de55d92dae) ROM_VERSION=silver ;;
  *) fail "Unsupported ROM SHA-1 $ROM_SHA1. Expected a canonical Red/Blue/Yellow/Gold/Silver ROM." ;;
esac
say "detected ROM version: $ROM_VERSION ($ROM_SHA1)"

if [ ! -x "$VENV/bin/python3" ]; then
  say "creating Python environment"
  python3 -m venv "$VENV"
fi
say "installing Pillow"
"$VENV/bin/python3" -m pip install --quiet --upgrade pip
"$VENV/bin/python3" -m pip install --quiet pillow

say "decoding game data from $(basename "$ROM")"
cd "$ROOT"
case "$ROM_VERSION" in
  gold|silver)
    # Gen2 is imported by the engine at runtime, so its datasets go straight
    # into LÖVE's save folder rather than the repo's data/generated.
    if [ "$(uname -s)" = "Darwin" ]; then
      LOVE_SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
    else
      LOVE_SAVE="${XDG_DATA_HOME:-$HOME/.local/share}/love/pokemon-love2d"
    fi
    say "Gen2 ROM detected: extracting supported datasets into $LOVE_SAVE/$ROM_VERSION"
    "$VENV/bin/python3" tools/build_data.py --rom "$ROM" --version "$ROM_VERSION" \
      --out "$LOVE_SAVE/$ROM_VERSION/data/generated" \
      --assets "$LOVE_SAVE/$ROM_VERSION/assets/generated" \
      --clean \
      --only constants --only charmap --only moves --only items \
      --only text --only maps --only tilesets
    ;;
  *)
    "$VENV/bin/python3" tools/build_data.py --rom "$ROM" --version "$ROM_VERSION" --clean
    ;;
esac

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
