#!/usr/bin/env bash
# Write provenance for an Xbox UWP package.
#
# Usage: scripts/xbox-uwp/write_build_info.sh OUTPUT VERSION CONFIGURATION

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

OUTPUT="${1:-}"
VERSION="${2:-}"
CONFIGURATION="${3:-}"
MANIFEST="$UWP_ROOT/third_party/manifest.json"

[ -n "$OUTPUT" ] && [ -n "$VERSION" ] && [ -n "$CONFIGURATION" ] \
  || fail "usage: $0 OUTPUT VERSION CONFIGURATION"
[ -f "$MANIFEST" ] || fail "missing dependency manifest: $MANIFEST"

mkdir -p "$(dirname "$OUTPUT")"
GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MANIFEST_SHA256="$(sha256_file "$MANIFEST")"
LOVE_COMMIT="$(awk '
  /"love"[[:space:]]*:/ { in_love=1 }
  in_love && /"commit"[[:space:]]*:/ {
    value=$0
    sub(/^.*"commit"[[:space:]]*:[[:space:]]*"/, "", value)
    sub(/".*$/, "", value)
    print value
    exit
  }
' "$MANIFEST")"
[ -n "$LOVE_COMMIT" ] || fail "LÖVE revision is missing from the dependency manifest"

cat > "$OUTPUT" <<EOF
{
  "platform": "xbox-uwp",
  "version": "$VERSION",
  "configuration": "$CONFIGURATION",
  "gitCommit": "$GIT_COMMIT",
  "loveCommit": "$LOVE_COMMIT",
  "dependencyManifestSha256": "$MANIFEST_SHA256",
  "builtAt": "$BUILT_AT"
}
EOF

say "build info: $OUTPUT"
