# Native Switch OTA launcher

In-console updates for Gen2Recomped on Nintendo Switch. This NRO is the **hbmenu
entry** (`gen2recomp.nro`). It checks GitHub Releases quietly (no UI when you
are already up to date or offline). Only if a newer release exists does it show
a **launcher-style screen** (black + RGB rail + project logo + flat A/B
buttons), download the same `Gen2Recomped-*-switch.zip` used for install, verify
SHA-256 from `sha256sums.txt`, replace **both** `Gen2Recomped-game.nro` and
`gen2recomp.nro` (matching NACP version for hbmenu/Sphaira), then load the game
with `envSetNextLoad`.

The LÖVE self-updater (`src/update/Check.lua`) resolves **notify-only** on NX,
and that is a derived answer now rather than an OS list: `Platform.canHostPayload()`
says the save directory can host a payload (it can — a `.love` copied into
`pokemon-love2d/updates/` by hand still chainloads), and `HostShell.transport()`
says there is no HTTPS client reachable from Lua on this console. The launcher
banner reads "Update from the OTA launcher (gen2recomp.nro)" and draws no button,
because there is no browser for one to open. See `docs/auto-update.md`.

Wire format: `include/ota_protocol.h` with `src/ota_protocol.c`, exercised on the
host by `host/test_ota_protocol.c` (`make host-test`, 34 cases). **There is no
Lua mirror** — this line used to point at a `SwitchOta.lua` under `src/update`
which has never existed in the tree.
NACP icon: `ports/switch/assets/icon.jpg`.

## The repository slug was wrong (fixed 2026-10-04)

`OTA_RELEASES_API` and the checksum URL in `src/main.c` both read
`UNDERdecodedHD/Gen2Recomped`. Measured: that slug answers **HTTP 404** and
`UNDERdecoded/Gen2Recomped` answers **200**. `UNDERdecodedHD` is the author
name (the NACP author above, the MSIX publisher, the intro credit); the GitHub
owner is `UNDERdecoded`. So the quiet release check 404ed on every launch, the
launcher took its "up to date or offline" path and showed nothing, and the
console had no working in-app update path at all.

Both URLs derive from one `OTA_REPO_SLUG` in `include/ota_protocol.h` now, and
`tools/auto_update_check.lua` asserts it equals `Check.REPO` in
`src/update/Check.lua` — the cross-language half of this port's recurring bug.

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
build time. After changing `assets/logo/gen2logo.png`, regenerate:

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
- The releases API and the checksum URL derive from one `OTA_REPO_SLUG` and are
  cross-checked against `Check.REPO`; before 2026-10-04 both were a 404.
- OTA replaces game + launcher from the install zip (NACP versions stay aligned).
  The running launcher cannot overwrite its own NRO on sdmc/FAT; a tiny
  `ota-bootstrap.nro` (embedded in romfs) chainloads once to swap the staged
  launcher, then loads the game.
- HTTPS uses Mozilla CA bundle in romfs (`cacert.pem`, fetched at build time). `ota_net_init()` mounts romfs before the quiet release check.
- Sphaira HOME forwarders cache metadata until reinstalled (see docs/switch-install.md).
- Release runner: `switch-dev` + (`install_devkitpro_deps.sh` **or** Docker)
