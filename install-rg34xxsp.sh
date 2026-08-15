#!/usr/bin/env bash
# After first boot of the freshly flashed Stock OS Mod, reinsert the SD card
# and run this to install Gen2Recomped + your cartridge dumps into roms/PORTS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGE="$ROOT/.bazinga/work/rg34xxsp-install"
DECPREP="$(cd "$ROOT/../decprep" && pwd)"
# Matches build-rg34xxsp.sh's ARTIFACT_SUFFIX; the old path
# (gen1recomp-rg34xxsp.zip) was never the name that script produced.
ZIP="$ROOT/dist/rg34xxsp/gen2recomp-rg34xxsp-stockos64-mod.zip"

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
  rm -rf "$STAGE/PORTS/Gen2recomp.sh" "$STAGE/PORTS/gen2recomp" "$STAGE/PORTS/port.json" \
    "$STAGE/PORTS/gameinfo.xml" "$STAGE/PORTS/README.md"
  unzip -q -o "$ZIP" -d "$STAGE/PORTS"
else
  fail "missing $ZIP — run ./build-rg34xxsp.sh first"
fi

# Ensure cartridge dumps are in lovegame (Choose ROM scans this folder on
# stock OS).  Every .gb/.gbc in decprep goes across, rather than two hardcoded
# Gen 1 filenames: this repo is Gen 2 first and the import gate is the SHA-1
# in src/core/GameVersion.lua, not the filename.
roms=0
while IFS= read -r rom; do
  cp -f "$rom" "$STAGE/PORTS/gen2recomp/lovegame/"
  say "  + $(basename "$rom")"
  roms=$((roms + 1))
done < <(find "$DECPREP" -maxdepth 1 -type f \( -iname '*.gb' -o -iname '*.gbc' \) | sort)
[ "$roms" -gt 0 ] || fail "no .gb/.gbc cartridge dumps found in $DECPREP"

say "copying Gen2Recomped port"
rm -rf "$PORTS/gen2recomp" "$PORTS/Gen2recomp.sh"
cp -R "$STAGE/PORTS/gen2recomp" "$PORTS/"
cp -f "$STAGE/PORTS/Gen2recomp.sh" "$PORTS/"
cp -f "$STAGE/PORTS/port.json" "$PORTS/gen2recomp/" 2>/dev/null || true
cp -f "$STAGE/PORTS/README.md" "$PORTS/gen2recomp/" 2>/dev/null || true
chmod +x "$PORTS/Gen2recomp.sh" "$PORTS/gen2recomp/bin/love.aarch64"

# Also drop carts in the stock GB folder for the emulator library
GB_DIR=""
for candidate in "$ROMS_ROOT/Roms/GB" "$ROMS_ROOT/roms/GB" "$ROMS_ROOT/Roms/gb"; do
  if [ -d "$candidate" ]; then GB_DIR="$candidate"; break; fi
done
if [ -n "$GB_DIR" ]; then
  say "copying cartridge dumps into $GB_DIR"
  find "$DECPREP" -maxdepth 1 -type f \( -iname '*.gb' -o -iname '*.gbc' \) \
    -exec cp -f {} "$GB_DIR/" \;
fi

sync
say "installed:"
ls -lh "$PORTS/Gen2recomp.sh"
ls -lh "$PORTS/gen2recomp/lovegame/"*.gb*
say "eject the SD, insert TF1 in the RG34XXSP, open Ports → Gen2Recomped, Choose ROM."
