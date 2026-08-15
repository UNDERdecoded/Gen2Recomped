#!/usr/bin/env bash
# Shared helpers for Switch packaging scripts.
# Source from other scripts:  . "$(dirname "$0")/common.sh"  (or similar)

# shellcheck disable=SC2034
if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export ROOT

# Progress on stderr so command-substitution (e.g. pack_game_love) stays a bare path.
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Print SHA-256 hex digest of PATH. Prefers shasum, falls back to sha256sum.
sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    fail "need shasum or sha256sum (install coreutils / Xcode CLT)"
  fi
}

# If nacptool is missing but $DEVKITPRO/tools/bin exists, prepend it to PATH.
ensure_dkp_tools_path() {
  if command -v nacptool >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "${DEVKITPRO:-}" ] && [ -d "$DEVKITPRO/tools/bin" ]; then
    export PATH="$DEVKITPRO/tools/bin:$PATH"
  fi
}

# Missing love-nx pin — tell user to run --fetch.
fail_need_fetch() {
  fail "${1:-missing pinned love-nx} — run: scripts/build_switch.sh --fetch"
}

# OTA launcher native build packages (shared with install_devkitpro_deps.sh).
OTA_LAUNCHER_PKGS=(switch-curl switch-mbedtls switch-zlib switch-zziplib)

ota_launcher_deps_ready() {
  command -v dkp-pacman >/dev/null 2>&1 || return 1
  local pkg
  for pkg in "${OTA_LAUNCHER_PKGS[@]}"; do
    dkp-pacman -Q "$pkg" >/dev/null 2>&1 || return 1
  done
}

# Space-separated list of missing OTA launcher packages (empty when all installed).
ota_launcher_missing_pkgs() {
  command -v dkp-pacman >/dev/null 2>&1 || return 0
  local pkg missing=""
  for pkg in "${OTA_LAUNCHER_PKGS[@]}"; do
    if ! dkp-pacman -Q "$pkg" >/dev/null 2>&1; then
      missing="${missing} ${pkg}"
    fi
  done
  printf '%s' "$missing"
}

devkitpro_ready() {
  [ -n "${DEVKITPRO:-}" ] && [ -f "$DEVKITPRO/libnx/switch_rules" ]
}

fail_missing_devkitpro() {
  fail "$(cat <<'EOF'
--fused requires DEVKITPRO (release builds ship the OTA launcher for in-console updates).

One-time setup on the Mac self-hosted runner (or your dev machine):

  1. Install devkitPro pacman: https://devkitpro.org/wiki/devkitPro_pacman
  2. Install Switch tools:     sudo dkp-pacman -S switch-dev
  3. Export DEVKITPRO (typical macOS):
       export DEVKITPRO=/opt/devkitpro
       export PATH="$DEVKITPRO/tools/bin:$PATH"
  4. OTA launcher toolchain (native or Docker — pick one):
       bash scripts/switch/install_devkitpro_deps.sh
     or install Docker (same pin as fused builds)

Then re-run: scripts/build_switch.sh --fetch --fused

See docs/switch-build.md (Runner provisioning).
EOF
)"
}

fail_missing_ota_deps() {
  local missing
  missing="$(ota_launcher_missing_pkgs)"
  fail "$(cat <<EOF
--fused needs a way to build the OTA launcher: native dkp packages or Docker.

Missing dkp packages:${missing:- (dkp-pacman not on PATH)}

Pick one:
  bash scripts/switch/install_devkitpro_deps.sh
  or install Docker (build_ota_launcher.sh uses the pinned devkitPro image)

Then re-run: scripts/build_switch.sh --fetch --fused

See docs/switch-build.md and ports/switch/ota-launcher/README.md.
EOF
)"
}

fail_ota_launcher_toolchain() {
  if ! devkitpro_ready; then
    fail_missing_devkitpro
  fi
  if ota_launcher_deps_ready; then
    fail "$(cat <<'EOF'
OTA launcher native build failed after host-test passed.

Re-run with a clean tree:
  scripts/switch/build_ota_launcher.sh

If packages look wrong, reinstall:
  bash scripts/switch/install_devkitpro_deps.sh

See ports/switch/ota-launcher/README.md.
EOF
)"
  fi
  fail_missing_ota_deps
}

# Fail fast before packing when --fused is requested.
preflight_fused_build() {
  if ! devkitpro_ready; then
    fail_missing_devkitpro
  fi
  ensure_dkp_tools_path

  local game_ok=0
  if command -v nacptool >/dev/null 2>&1 && command -v elf2nro >/dev/null 2>&1; then
    game_ok=1
  elif command -v docker >/dev/null 2>&1; then
    game_ok=1
  fi
  if [ "$game_ok" -eq 0 ]; then
    fail_fused_toolchain
  fi

  if ota_launcher_deps_ready; then
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi
  fail_missing_ota_deps
}

# Fused mode needs nacptool/elf2nro (native or Docker). Rich multi-OS hint.
fail_fused_toolchain() {
  fail "$(cat <<'EOF'
fused packaging needs DEVKITPRO, nacptool, and elf2nro (devkitPro switch-dev).

Install options:
  macOS:    https://devkitpro.org/wiki/devkitPro_pacman
            sudo dkp-pacman -S switch-dev
  OTA launcher (native or Docker):
            bash scripts/switch/install_devkitpro_deps.sh
            or install Docker
  Linux:    https://devkitpro.org/wiki/devkitPro_pacman
  Windows:  Git Bash / MSYS2 / WSL with devkitPro tools on PATH
  Docker:   install Docker; fused game and OTA launcher can build in-container

Export DEVKITPRO (typical): export DEVKITPRO=/opt/devkitpro

See docs/switch-build.md for details.
EOF
)"
}
