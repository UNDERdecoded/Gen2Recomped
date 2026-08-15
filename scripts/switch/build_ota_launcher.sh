#!/usr/bin/env bash
# Build the native Switch OTA launcher NRO (DEVKITPRO or Docker).
#
# Usage: scripts/switch/build_ota_launcher.sh [OUT_NRO] [VERSION]
#
# Default OUT_NRO: dist/switch/Gen2Recomped-launcher.nro
# VERSION (optional X.Y.Z) is written into the NACP so hbmenu shows the
# same release as the fused game; defaults to 0.0.0 when omitted.
# Host-only protocol check: always runs `make host-test` first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

LAUNCHER_DIR="$ROOT/ports/switch/ota-launcher"
OUT_NRO="${1:-$ROOT/dist/switch/Gen2Recomped-launcher.nro}"
APP_VERSION="${2:-${GEN2_LAUNCHER_VERSION:-0.0.0}}"
DKP_IMAGE_FILE="$ROOT/scripts/switch/dkp-docker.image"

[ -d "$LAUNCHER_DIR" ] || fail "missing $LAUNCHER_DIR"
[ -f "$LAUNCHER_DIR/Makefile" ] || fail "missing Makefile"

# The header advertises "DEVKITPRO or Docker" and the Docker branch is right
# there further down -- but this precondition bailed before anything could
# reach it, so the Docker path was dead code and a runner without a native
# devkitPro install could never build the launcher (only the FUSED NRO, which
# build_fused.sh containerises properly).  Fail only when NEITHER is available.
if ! devkitpro_ready && ! command -v docker >/dev/null 2>&1; then
  fail_missing_devkitpro
fi

say "host-test ota_protocol (no DEVKITPRO required)"
make -C "$LAUNCHER_DIR" host-test

mkdir -p "$(dirname "$OUT_NRO")"

if ota_launcher_deps_ready; then
  say "building launcher NRO with native DEVKITPRO (NACP $APP_VERSION)"
  make -C "$LAUNCHER_DIR" clean || true
  if ! make -C "$LAUNCHER_DIR" all APP_VERSION="$APP_VERSION"; then
    fail_ota_launcher_toolchain
  fi
  cp "$LAUNCHER_DIR/gen2recomp.nro" "$OUT_NRO"
  say "wrote $OUT_NRO"
  exit 0
fi

resolve_dkp_image() {
  if [ -n "${GEN2_DKP_IMAGE:-}" ]; then
    printf '%s' "$GEN2_DKP_IMAGE"
    return 0
  fi
  [ -f "$DKP_IMAGE_FILE" ] || fail "missing Docker image pin: $DKP_IMAGE_FILE"
  local line
  line="$(grep -v '^[[:space:]]*#' "$DKP_IMAGE_FILE" | grep -v '^[[:space:]]*$' | head -1 || true)"
  [ -n "$line" ] || fail "empty Docker image pin: $DKP_IMAGE_FILE"
  printf '%s' "$line"
}

if command -v docker >/dev/null 2>&1; then
  image="$(resolve_dkp_image)"
  say "building launcher NRO via Docker ($image, NACP $APP_VERSION)"
  if ! docker run --rm \
    -v "$ROOT:/work" \
    -w /work/ports/switch/ota-launcher \
    -e "APP_VERSION=$APP_VERSION" \
    "$image" \
    bash -lc 'pacman -Sy --noconfirm switch-curl switch-mbedtls switch-zlib switch-zziplib >/dev/null 2>&1 || true; make clean; make all APP_VERSION="$APP_VERSION"'; then
    fail_ota_launcher_toolchain
  fi
  cp "$LAUNCHER_DIR/gen2recomp.nro" "$OUT_NRO"
  say "wrote $OUT_NRO"
  exit 0
fi

fail_missing_ota_deps
