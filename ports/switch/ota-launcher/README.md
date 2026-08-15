# Native Switch OTA launcher

In-console updates for Gen2Recomped on Nintendo Switch. This NRO is the **hbmenu
entry** (`gen2recomp.nro`). It checks GitHub Releases quietly (no UI when you
are already up to date or offline). Only if a newer release exists does it show
a **launcher-style screen** (black + RGB rail + project logo + flat A/B
buttons), download the same `Gen2Recomped-*-switch.zip` used for install, verify
SHA-256 from `sha256sums.txt`, replace **both** `Gen2Recomped-game.nro` and
`gen2recomp.nro` (matching NACP version for hbmenu/Sphaira), then load the game
with `envSetNextLoad`.

The LÖVE self-updater (`src/update/Check.lua`) stays **disabled** on NX.
Wire format (also in Lua): `src/update/SwitchOta.lua`.
NACP icon: `ports/switch/assets/icon.jpg`.

## Layout on microSD

```text
sdmc:/switch/gen2recomp/gen2recomp.nro        <- this launcher
sdmc:/switch/gen2recomp/Gen2Recomped-game.nro   <- fused LÖVE game
sdmc:/switch/gen2recomp/version.txt          <- installed X.Y.Z
sdmc:/switch/gen2recomp/pokemon-love2d/      <- saves (never touched by OTA)
```

## Host tests (no DEVKITPRO)

```bash
cd ports/switch/ota-launcher
make host-test
```

## Switch build (DEVKITPRO)

Needs `DEVKITPRO` with packages roughly:

```bash
(dkp-)pacman -S --needed switch-curl switch-mbedtls switch-zlib switch-zziplib
# or: bash scripts/switch/install_devkitpro_deps.sh
```

```bash
export DEVKITPRO=/opt/devkitpro   # typical
cd ports/switch/ota-launcher
make
# -> gen2recomp.nro
```

Or from repo root (as part of `--fused`):

```bash
scripts/build_switch.sh --fetch --fused --version X.Y.Z
```

Standalone launcher build:

```bash
scripts/switch/build_ota_launcher.sh
```

Docker fallback uses the same pin as fused builds (`scripts/switch/dkp-docker.image`).

## OTA logo asset

The launcher draws a pre-scaled logo from `romfs:/logo.rgba` (no PNG decoder in
the NRO). The baked blob lives at `../assets/logo.rgba` and is copied into romfs at
build time. After changing `assets/logo/logo.png`, regenerate:

```bash
python3 scripts/switch/bake_ota_logo.py
```

Requires Pillow, or on macOS uses `sips` when Pillow is not installed.

## Packaging

`scripts/switch/pack_sd_zip.sh GAME_NRO VERSION OUT_ZIP LAUNCHER_NRO` writes both
NROs into the SD zip. That zip is also what OTA downloads.
Manifest: `scripts/switch/ota_launcher.manifest`.

## Status / known gaps

- Zip extraction uses `switch-zziplib` (`ota_unzip.c`) on device.
- OTA replaces game + launcher from the install zip (NACP versions stay aligned).
  The running launcher cannot overwrite its own NRO on sdmc/FAT; a tiny
  `ota-bootstrap.nro` (embedded in romfs) chainloads once to swap the staged
  launcher, then loads the game.
- HTTPS uses Mozilla CA bundle in romfs (`cacert.pem`, fetched at build time). `ota_net_init()` mounts romfs before the quiet release check.
- Sphaira HOME forwarders cache metadata until reinstalled (see docs/switch-install.md).
- Release runner: `switch-dev` + (`install_devkitpro_deps.sh` **or** Docker)
