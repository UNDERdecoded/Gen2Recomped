#!/usr/bin/env bash
# Static analysis for the engine Lua (config: .luacheckrc).
#
# Complements scripts/test.sh: the tests prove behavior, luacheck catches the
# defects that never run in a green test -- undefined globals/locals (the
# class that hid a music.volume crash: a hook read a `state` that was still
# the nil global), unused values, unreachable code. The .luacheckrc mutes the
# cosmetic categories the codebase lives with, so what prints is worth a look.
#
#   scripts/lint.sh            lint src/
#   scripts/lint.sh src tools  lint specific paths
#
# Install once with:  luarocks install luacheck

set -uo pipefail
cd "$(dirname "$0")/.."

if ! command -v luacheck >/dev/null 2>&1; then
  echo "luacheck not found on PATH (install: luarocks install luacheck)" >&2
  exit 2
fi

luacheck "${@:-src}"
