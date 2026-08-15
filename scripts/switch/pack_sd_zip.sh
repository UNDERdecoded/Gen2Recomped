#!/usr/bin/env bash
# Pack a Switch SD-ready zip: extract at microSD root (merge-safe update).
#
# Usage:
#   scripts/switch/pack_sd_zip.sh GAME_NRO VERSION OUT_ZIP [LAUNCHER_NRO]
#
# Layout inside the zip (SD root):
#   switch/gen2recomp/gen2recomp.nro            (launcher if LAUNCHER_NRO set, else game)
#   switch/gen2recomp/Gen2Recomped-game.nro       (only when LAUNCHER_NRO set)
#   switch/gen2recomp/version.txt
#   switch/gen2recomp/INSTALL.txt
#   switch/gen2recomp/Gen2Recomp/imports/{,mods/}README.txt
#   switch/gen2recomp/Gen2Recomp/exports/.../README.txt
#
# Does not ship ROMs, saves, or mods. Re-extracting merges over an existing
# install and only overwrites the NRO(s) + these text placeholders — keep
# Gen2Recomp/ to preserve progress.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

NRO_PATH="${1:-}"
VERSION="${2:-}"
OUT_ZIP="${3:-}"
LAUNCHER_NRO="${4:-}"

[ -n "$NRO_PATH" ] && [ -n "$VERSION" ] && [ -n "$OUT_ZIP" ] \
  || fail "usage: scripts/switch/pack_sd_zip.sh GAME_NRO VERSION OUT_ZIP [LAUNCHER_NRO]"

[ -f "$NRO_PATH" ] || fail "missing game NRO at $NRO_PATH"
if [ -n "$LAUNCHER_NRO" ]; then
  [ -f "$LAUNCHER_NRO" ] || fail "missing launcher NRO at $LAUNCHER_NRO"
fi

command -v zip >/dev/null 2>&1 || fail "need zip on PATH"

# Absolutize before any cd — relative OUT_ZIP would otherwise land inside the
# staging dir and vanish when the EXIT trap cleans up.
NRO_PATH="$(cd "$(dirname "$NRO_PATH")" && pwd)/$(basename "$NRO_PATH")"
OUT_DIR="$(dirname "$OUT_ZIP")"
mkdir -p "$OUT_DIR"
OUT_ZIP="$(cd "$OUT_DIR" && pwd)/$(basename "$OUT_ZIP")"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/Gen2Recomped-sd-zip.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

APP_DIR="$STAGE/switch/gen2recomp"
# MUST equal conf.lua's t.identity: love.filesystem's save directory is
# <NRO folder>/<identity>, so an inbox under any other name is a folder the
# game never reads.  conf.lua sets "Gen2Recomp" for every non-mobile build;
# "pokemon-love2d" is the Gen 1 port's identity and was left behind by the
# rebrand, which is why a correctly-placed ROM imported nowhere.
SAVE_IDENTITY="Gen2Recomp"
SAVE_ROOT="$APP_DIR/$SAVE_IDENTITY"
mkdir -p "$APP_DIR"

if [ -n "$LAUNCHER_NRO" ]; then
  LAUNCHER_NRO="$(cd "$(dirname "$LAUNCHER_NRO")" && pwd)/$(basename "$LAUNCHER_NRO")"
  cp "$LAUNCHER_NRO" "$APP_DIR/gen2recomp.nro"
  cp "$NRO_PATH" "$APP_DIR/Gen2Recomped-game.nro"
else
  cp "$NRO_PATH" "$APP_DIR/gen2recomp.nro"
fi
printf '%s\n' "$VERSION" > "$APP_DIR/version.txt"

cat > "$APP_DIR/INSTALL.txt" <<EOF
Gen2Recomped Switch (v${VERSION})
=================================

First install or update (same steps):
  1. Extract this zip at the root of your microSD (merge folders if asked).
  2. Do NOT delete switch/gen2recomp/${SAVE_IDENTITY}/ — that folder holds
     your saves, imported ROMs, mods, and options. Re-extracting only
     replaces the NRO(s) and these help files.
  3. Launch with title override (hold R on HOME, open any title → hbmenu).
  4. Copy a legal cartridge dump (.gb / .gbc) into:
       switch/gen2recomp/${SAVE_IDENTITY}/imports/
     then press Choose ROM in the launcher — it scans that folder.

Controls in the launcher:
  Left stick / D-pad   move the pointer
  A                    click
  L / R                switch tabs
  + / -                Play, or Choose ROM on the current tab

Inboxes (drop files here via MTP / SD / FTP):
  imports/             — cartridge dumps (.gb / .gbc)
  imports/mods/        — community mod .zip files
  exports/<game>/      — pull a .sav out after Export save

Supported dumps, matched by SHA-1 (the filename does not matter):
  Gold, Silver, Crystal (Rev 0 and Rev 1), Red, Blue, Yellow

Full guide: https://github.com/UNDERdecoded/Gen2Recomped/blob/main/docs/switch-install.md
EOF

write_readme() {
  local path="$1"
  local body="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$body" > "$path"
}

write_readme "$SAVE_ROOT/imports/README.txt" \
  "Put a legal Gold / Silver / Crystal / Red / Blue / Yellow .gb or .gbc here,
then press Import in the launcher. Dumps are matched by SHA-1, so the
filename does not matter. Files stay here after import."

# Mods get their own inbox: a .zip in imports/ next to the cartridges is
# ambiguous, and the launcher scans the two folders for different things.
write_readme "$SAVE_ROOT/imports/mods/README.txt" \
  "Put community mod .zip files here, then MODS tab -> Import in the launcher."

# One exports/ folder per game the launcher can export a battery save from.
# GameVersion.VERSIONS is the source of truth for that list; keep them in step.
for game in gold silver crystal red blue yellow; do
  write_readme "$SAVE_ROOT/exports/$game/README.txt" \
    "After Export save ($game), copy the .sav out of this folder via MTP / SD / FTP."
done

rm -f "$OUT_ZIP"
(
  cd "$STAGE"
  zip -q -r "$OUT_ZIP" switch
)

[ -f "$OUT_ZIP" ] || fail "zip was not created at $OUT_ZIP"
[ -s "$OUT_ZIP" ] || fail "zip is empty: $OUT_ZIP"

LISTING="$(unzip -Z1 "$OUT_ZIP" 2>/dev/null || unzip -l "$OUT_ZIP")"
printf '%s\n' "$LISTING" | grep -q 'switch/gen2recomp/gen2recomp.nro' \
  || fail "zip missing switch/gen2recomp/gen2recomp.nro"
printf '%s\n' "$LISTING" | grep -Fq 'switch/gen2recomp/version.txt' \
  || fail "zip missing switch/gen2recomp/version.txt"
if [ -n "$LAUNCHER_NRO" ]; then
  printf '%s\n' "$LISTING" | grep -Fq 'switch/gen2recomp/Gen2Recomped-game.nro' \
    || fail "zip missing switch/gen2recomp/Gen2Recomped-game.nro (OTA dual-NRO layout)"
fi

REQUIRED=(
  "switch/gen2recomp/INSTALL.txt"
  "switch/gen2recomp/version.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/imports/README.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/imports/mods/README.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/exports/gold/README.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/exports/silver/README.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/exports/crystal/README.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/exports/red/README.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/exports/blue/README.txt"
  "switch/gen2recomp/$SAVE_IDENTITY/exports/yellow/README.txt"
)
for rel in "${REQUIRED[@]}"; do
  printf '%s\n' "$LISTING" | grep -Fq "$rel" || fail "zip missing $rel"
done

ZIP_SHA="$(sha256_file "$OUT_ZIP")"
printf '%s  %s\n' "$ZIP_SHA" "$OUT_ZIP" > "${OUT_ZIP}.sha256"
say "SD-ready zip: $OUT_ZIP"
printf '%s  %s\n' "$ZIP_SHA" "$OUT_ZIP"
