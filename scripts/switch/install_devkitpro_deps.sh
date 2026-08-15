#!/usr/bin/env bash
# Install DEVKITPRO Switch packages needed for the native OTA launcher.
# Run this in Terminal.app / iTerm (needs your macOS admin password):
#
#   bash scripts/switch/install_devkitpro_deps.sh
#
# Optional: speeds up local native OTA launcher builds. CI/release can fall back
# to Docker when these packages are not installed.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "==> re-running with sudo…"
  exec sudo -E bash "$0" "$@"
fi

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
export PATH="/usr/local/bin:$DEVKITPRO/pacman/bin:$DEVKITPRO/tools/bin:$PATH"

if [ -f /etc/profile.d/devkit-env.sh ]; then
  # shellcheck disable=SC1091
  . /etc/profile.d/devkit-env.sh
fi

if ! command -v dkp-pacman >/dev/null 2>&1; then
  echo "error: dkp-pacman not found. Install the pkg from:" >&2
  echo "  https://github.com/devkitPro/pacman/releases/latest" >&2
  exit 1
fi

if ! dkp-pacman -Q switch-dev >/dev/null 2>&1; then
  echo "error: switch-dev is not installed (needed for nacptool/elf2nro)." >&2
  echo "  sudo dkp-pacman -S switch-dev" >&2
  echo "Then re-run: bash scripts/switch/install_devkitpro_deps.sh" >&2
  exit 1
fi

echo "==> DEVKITPRO=$DEVKITPRO"
# Named packages only (avoid interactive switch-dev group member prompt).
# ZIP reading uses switch-zziplib (dkp has no minizip port for Switch).
dkp-pacman -Sy --noconfirm --needed "${OTA_LAUNCHER_PKGS[@]}"

echo "==> installed packages:"
dkp-pacman -Q | grep -E 'switch-(curl|mbedtls|zlib|zziplib|tools)|libnx|devkitA64' || true

# Ensure zsh/bash sessions see DEVKITPRO
MARKER="# gen1recomp-devkitpro"
for rc in /Users/*/.zshrc /Users/*/.bash_profile; do
  [ -f "$rc" ] || continue
  if ! grep -q "$MARKER" "$rc" 2>/dev/null; then
    {
      echo ""
      echo "$MARKER"
      echo "export DEVKITPRO=/opt/devkitpro"
      echo 'export PATH="$DEVKITPRO/tools/bin:$DEVKITPRO/devkitA64/bin:$PATH"'
    } >> "$rc"
    echo "==> appended DEVKITPRO exports to $rc"
  fi
done

echo "==> done. Open a new shell, then:"
echo "    export DEVKITPRO=/opt/devkitpro"
echo "    scripts/switch/build_ota_launcher.sh"
