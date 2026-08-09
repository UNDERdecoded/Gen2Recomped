#!/usr/bin/env bash
# After first boot of the freshly flashed Stock OS Mod, reinsert the SD card
# and run this to install gen1recomp + Red/Blue ROMs into roms/PORTS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGE="$ROOT/.bazinga/work/rg34xxsp-install"
DECPREP="$(cd "$ROOT/../decprep" && pwd)"
ZIP="$ROOT/dist/rg34xxsp/gen1recomp-rg34xxsp.zip"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Find the Anbernic user/ROMs volume (usually "NO NAME" after first-boot expand).
find_roms_root() {
  local v candidate
  for v in /Volumes/*; do
    [ -d "$v" ] || continue
    # Prefer a volume that already has Roms/ or PORTS/
    if [ -d "$v/Roms" ] || [ -d "$v/roms" ] || [ -d "$v/PORTS" ] || [ -d "$v/ports" ]; then
      echo "$v"
      return 0
    fi
  done
  # Fallback: large FAT volume named NO NAME on disk8
  for v in "/Volumes/NO NAME" /Volumes/NO\ NAME /Volumes/ROMS /Volumes/EASYROMS; do
    if [ -d "$v" ]; then
      echo "$v"
      return 0
    fi
  done
  return 1
}

say "looking for Anbernic ROMs volume"
ROMS_ROOT="$(find_roms_root)" || fail "no ROMs volume mounted. Boot the RG34XXSP once (wait for first-boot setup), power off, reinsert the SD, then rerun."

say "using: $ROMS_ROOT"
# Resolve PORTS dir (stock uses Roms/PORTS)
if [ -d "$ROMS_ROOT/Roms/PORTS" ]; then
  PORTS="$ROMS_ROOT/Roms/PORTS"
elif [ -d "$ROMS_ROOT/roms/PORTS" ]; then
  PORTS="$ROMS_ROOT/roms/PORTS"
elif [ -d "$ROMS_ROOT/Roms/ports" ]; then
  PORTS="$ROMS_ROOT/Roms/ports"
elif [ -d "$ROMS_ROOT/PORTS" ]; then
  PORTS="$ROMS_ROOT/PORTS"
else
  mkdir -p "$ROMS_ROOT/Roms/PORTS"
  PORTS="$ROMS_ROOT/Roms/PORTS"
fi
say "PORTS: $PORTS"

# Refresh staged payload
mkdir -p "$STAGE/PORTS"
if [ -f "$ZIP" ]; then
  rm -rf "$STAGE/PORTS/Gen1recomp.sh" "$STAGE/PORTS/gen1recomp" "$STAGE/PORTS/port.json" \
    "$STAGE/PORTS/gameinfo.xml" "$STAGE/PORTS/README.md"
  unzip -q -o "$ZIP" -d "$STAGE/PORTS"
else
  fail "missing $ZIP — run ./build-rg34xxsp.sh first"
fi

# Ensure ROMs are in lovegame (Choose ROM scans this folder on stock OS)
[ -f "$DECPREP/Pokemon - Red Version.gb" ] || fail "missing Red ROM in $DECPREP"
[ -f "$DECPREP/Pokemon - Blue Version.gb" ] || fail "missing Blue ROM in $DECPREP"
cp -f "$DECPREP/Pokemon - Red Version.gb" "$STAGE/PORTS/gen1recomp/lovegame/"
cp -f "$DECPREP/Pokemon - Blue Version.gb" "$STAGE/PORTS/gen1recomp/lovegame/"

say "copying gen1recomp port"
rm -rf "$PORTS/gen1recomp" "$PORTS/Gen1recomp.sh"
cp -R "$STAGE/PORTS/gen1recomp" "$PORTS/"
cp -f "$STAGE/PORTS/Gen1recomp.sh" "$PORTS/"
cp -f "$STAGE/PORTS/port.json" "$PORTS/gen1recomp/" 2>/dev/null || true
cp -f "$STAGE/PORTS/README.md" "$PORTS/gen1recomp/" 2>/dev/null || true
chmod +x "$PORTS/Gen1recomp.sh" "$PORTS/gen1recomp/bin/love.aarch64"

# Also drop carts in the stock GB folder for the emulator library
GB_DIR=""
for candidate in "$ROMS_ROOT/Roms/GB" "$ROMS_ROOT/roms/GB" "$ROMS_ROOT/Roms/gb"; do
  if [ -d "$candidate" ]; then GB_DIR="$candidate"; break; fi
done
if [ -n "$GB_DIR" ]; then
  say "copying .gb into $GB_DIR"
  cp -f "$DECPREP/Pokemon - Red Version.gb" "$GB_DIR/"
  cp -f "$DECPREP/Pokemon - Blue Version.gb" "$GB_DIR/"
fi

sync
say "installed:"
ls -lh "$PORTS/Gen1recomp.sh"
ls -lh "$PORTS/gen1recomp/lovegame/"*.gb
say "eject the SD, insert TF1 in the RG34XXSP, open Ports → Gen1recomp, Choose ROM."
