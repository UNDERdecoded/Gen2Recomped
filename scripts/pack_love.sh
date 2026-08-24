#!/usr/bin/env bash
# The SHARED .love packer.  Every platform's build script calls this and only
# this, so a payload can never drift between desktop, Steam Deck, Switch and
# Xbox: scripts/build_linux_arm64.sh, scripts/build_xbox_uwp.sh,
# scripts/switch/verify_payload.sh and scripts/xbox-uwp/selftest_build_xbox_uwp.sh
# are all written against the contract below and were failing outright without
# it (the file was referenced by four scripts and did not exist).
#
# Usage:
#   scripts/pack_love.sh --output PATH [--listing PATH] [--version X.Y.Z]
#                        [--dry-run]
#
#   --output   where to write the .love (required)
#   --listing  write the archive's file listing here, one path per line, in
#              the same form `unzip -Z1` prints -- which is what
#              scripts/switch/verify_payload.sh greps
#   --version  stamp this release into src/core/Version.lua INSIDE the archive.
#              The working tree is never touched: the tree carries the version
#              it is building towards and CI restamps the packed copy.
#   --dry-run  accepted for callers that only want the archive and the listing
#              in a scratch directory; nothing outside --output / --listing is
#              written either way, so this is a no-op kept for compatibility
#              with scripts/xbox-uwp/selftest_build_xbox_uwp.sh.
#
# The exclude set below is the SAME set verify_payload.sh rejects, expressed as
# a filter rather than as a test -- pack and verify have to agree or every
# build fails its own gate.  Nothing under data/generated or assets/generated
# ships (that is the player's ROM import), no .gb/.gbc/.sav ever ships, and no
# .bak save backups.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUTPUT=""
LISTING=""
VERSION=""
DRY_RUN=0

fail() { printf 'pack_love: error: %s\n' "$*" >&2; exit 1; }
say()  { printf 'pack_love: %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || fail "--output requires a path"
      OUTPUT="$2"; shift 2 ;;
    --listing)
      [ $# -ge 2 ] || fail "--listing requires a path"
      LISTING="$2"; shift 2 ;;
    --version)
      [ $# -ge 2 ] || fail "--version requires X.Y.Z"
      VERSION="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[ -n "$OUTPUT" ] || fail "--output is required"
if [ -n "$VERSION" ]; then
  printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || fail "invalid --version '$VERSION' (expected X.Y.Z)"
fi

command -v zip   >/dev/null 2>&1 || fail "required command not found: zip"
command -v unzip >/dev/null 2>&1 || fail "required command not found: unzip"

# Absolute, because the zip runs from inside the staging directory.
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
if [ -n "$LISTING" ]; then
  mkdir -p "$(dirname "$LISTING")"
  LISTING="$(cd "$(dirname "$LISTING")" && pwd)/$(basename "$LISTING")"
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pack-love.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# ---------------------------------------------------------------- contents
# Only what the game loads at runtime.  Everything else in the repo -- the
# build scripts, the tools, the tests, the docs, the port projects -- is
# development material and has no business inside a shipped payload.
#
# tools/ is development material EXCEPT two things the game itself loads:
#   * tools/save-editor -- main.lua's own header calls it "part of the
#     shipped app, not a dev-only script"; it puts
#     tools/save-editor/?.lua and tools/save-editor/panels/?.lua on
#     love.filesystem's require path, so a payload without it boots fine and
#     then errors the moment the player presses Edit on a save row.
#     scripts/build.sh has always shipped it; leaving it out of the shared
#     packer silently regressed Switch, Xbox and ARM64.
#   * tools/rom_manifest*.json -- see MANIFEST_GLOB below.
#   * tools/map-editor -- the same argument as save-editor, and it was missed.
#     App.lua loads in "map" mode (main.lua's openMapEditor) and every panel it
#     draws, every store it writes and the mod exporter all live under
#     tools/map-editor. Shipped without it the payload boots, the launcher
#     offers MAP EDITOR, and the require fails the moment it is pressed --
#     and the failures are SILENT where they are pcall'd, which is how the
#     EXPORT button came to be a control that draws and does nothing.
CONTENT=(
  main.lua
  conf.lua
  src
  data
  assets
  mods
  tools/save-editor
  tools/map-editor
)

# The ROM symbol manifests: src/core/GameVersion.lua names one per cartridge
# (tools/rom_manifest.json, _blue, _yellow, _gold, _silver, _crystal) and the
# importer resolves every symbol through them.  Leaving them out produces a
# payload that boots and then cannot import a ROM at all -- which is what
# scripts/build_linux_arm64.sh's contract check caught as
# "game.love is missing tools/rom_manifest_gold.json".
MANIFEST_GLOB="tools/rom_manifest*.json"

say "staging payload from $ROOT"
for entry in "${CONTENT[@]}"; do
  if [ -e "$ROOT/$entry" ]; then
    # Nested entries (tools/save-editor) keep their prefix: the require path
    # the game builds is the archive path, so a flattened copy is invisible.
    mkdir -p "$STAGE/$(dirname "$entry")"
    rm -rf "${STAGE:?}/$entry"
    cp -R "$ROOT/$entry" "$STAGE/$entry"
  else
    say "skipping absent $entry"
  fi
done

# The ROM manifests, keeping their tools/ prefix so the runtime paths resolve.
manifests=0
for manifest in $ROOT/$MANIFEST_GLOB; do
  if [ -f "$manifest" ]; then
    mkdir -p "$STAGE/tools"
    cp "$manifest" "$STAGE/tools/"
    manifests=$((manifests + 1))
  fi
done
[ "$manifests" -gt 0 ] || fail "no $MANIFEST_GLOB found; the payload could not import any ROM"
say "staged $manifests ROM manifest(s)"

# LICENSE ships with the payload; the loader does not read it, but a
# redistributable archive that carries no licence is not redistributable.
for licence in LICENSE LICENSE.MD LICENSE.md; do
  [ -f "$ROOT/$licence" ] && cp "$ROOT/$licence" "$STAGE/" && break
done

# ---------------------------------------------------------------- excludes
# Pruned from the STAGE rather than passed to zip as -x patterns: the two
# forms disagree on how they anchor a leading directory, and a silent
# mismatch here ships a player's ROM.
say "pruning generated content, ROMs and backups"
rm -rf "$STAGE/data/generated" "$STAGE/assets/generated"
# ...and a MOD's generated content, for exactly the same reason.  The two
# paths above are the engine's ROM import; a mod that extracts from a
# cartridge writes its own, under its own folder, and those two rm's do not
# reach it -- STADIUM2_OVERWORLD_MODELS/assets/generated holds 500-odd sprite
# sheets pulled out of a Stadium 2 dump.  A payload is redistributable and
# that art is not, so the rule has to follow the content rather than the
# path it happens to sit at.
#
# This is a RELEASE GATE, not just hygiene. scripts/switch/verify_payload.sh
# rejects the pattern `/(data|assets)/generated/` anywhere in the archive, and
# the payload job that runs it is not continue-on-error -- so a mod folder
# carrying its own extracted art fails the whole release, and every console
# job with it. Pruning here is what keeps that from happening.
#
# No maxdepth: the rule follows the CONTENT, and a mod is free to nest its
# assets however it likes.
#
# Named rather than silent: if a mod ever ships hand-authored art under a
# folder called `generated`, this line is why it vanished, and the build log
# is where that has to be visible.
while IFS= read -r generated; do
  say "pruning mod-generated content: ${generated#$STAGE/}"
  rm -rf "$generated"
done < <(find "$STAGE/mods" -mindepth 2 -type d \
              \( -name generated -o -name baseroms \) 2>/dev/null)
find "$STAGE" -type d -name '.git' -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGE" -type f \( \
     -iname '*.gb' -o -iname '*.gbc' -o -iname '*.sav' -o -iname '*.bak' \
  -o -iname '*.love' -o -iname '*.exe' -o -iname '*.zip' \
  -o -name 'rom-cache.complete' -o -name '.DS_Store' \
  \) -delete

# ------------------------------------------------------------- contract
# The same required-entry gate scripts/build.sh applies to its game.love, so
# the shared packer cannot ship a payload the desktop packer would reject.
# tools/map-editor is on this list for the reason it was ADDED to CONTENT:
# it was missing, nothing caught it, and the way that surfaced was a button in
# the shipped editor that drew and silently did nothing (its require is
# pcall'd). A contract entry is what turns that into a failed build instead of
# a bug report.
for required in main.lua conf.lua src/core/Version.lua \
                tools/save-editor/App.lua tools/save-editor/Kit.lua \
                tools/save-editor/panels/Party.lua \
                tools/map-editor/MapEdits.lua \
                tools/map-editor/ModExport.lua \
                tools/map-editor/panels/Preview.lua; do
  [ -e "$STAGE/$required" ] || fail "payload is missing $required"
done

# ------------------------------------------------------------ version stamp
# The archive's copy only.  A build stamps the release it is producing; a
# plain `pack_love.sh --output x.love` keeps whatever the tree says.
if [ -n "$VERSION" ]; then
  [ -f "$STAGE/src/core/Version.lua" ] || fail "no src/core/Version.lua to stamp"
  say "stamping engine $VERSION"
  # Only the `engine` field, and only its value: every other number in
  # Version.lua is a contract version that a release must not move.
  perl -0pi -e "s/(engine\\s*=\\s*\")[^\"]*(\")/\${1}$VERSION\${2}/" \
    "$STAGE/src/core/Version.lua"
  grep -Eq "engine[[:space:]]*=[[:space:]]*\"${VERSION//./\\.}\"" \
    "$STAGE/src/core/Version.lua" || fail "version stamp did not apply"
fi

# ------------------------------------------------------------------- archive
rm -f "$OUTPUT"
say "writing $OUTPUT"
( cd "$STAGE" && zip -r -q -X "$OUTPUT" . -x '.*' )

[ -f "$OUTPUT" ] || fail "zip produced no archive"

if [ -n "$LISTING" ]; then
  unzip -Z1 "$OUTPUT" > "$LISTING"
  say "listing: $LISTING ($(wc -l < "$LISTING" | tr -d ' ') entries)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  say "dry run: archive left at $OUTPUT and not installed anywhere"
fi

size="$(wc -c < "$OUTPUT" | tr -d ' ')"
say "OK $(basename "$OUTPUT") ($size bytes)"
