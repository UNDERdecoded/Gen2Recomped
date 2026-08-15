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
CONTENT=(
  main.lua
  conf.lua
  src
  data
  assets
  mods
)

say "staging payload from $ROOT"
for entry in "${CONTENT[@]}"; do
  if [ -e "$ROOT/$entry" ]; then
    cp -R "$ROOT/$entry" "$STAGE/"
  else
    say "skipping absent $entry"
  fi
done

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
find "$STAGE" -type d -name '.git' -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGE" -type f \( \
     -iname '*.gb' -o -iname '*.gbc' -o -iname '*.sav' -o -iname '*.bak' \
  -o -iname '*.love' -o -iname '*.exe' -o -iname '*.zip' \
  -o -name 'rom-cache.complete' -o -name '.DS_Store' \
  \) -delete

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
