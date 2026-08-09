# gen2recomp

<p align="center"><img src="./assets/logo/gen2logo.png"></p>

<p align="center"><img src="./assets/logo/UD.png" width="220"></p>

<p align="center"><b>by UNDERdecodedHD</b><br>
a fork of <a href="https://github.com/bryanthaboi/gen1recomp">Gen1Recomp</a> by
<a href="https://github.com/bryanthaboi">bryanthaboi</a> and
<a href="https://boisclub.games">BOIS CLUB GAMES</a></p>

A native LÖVE2D recreation of Poke Gold and Silver, built on Gen1Recomp's
Red/Blue/Yellow engine. The engine, script VM, and map behavior are
hand-written Lua; game data and graphics are decoded from a ROM supplied by the
player.

gen2recomp keeps everything the upstream project does for Generation I and adds
the Generation II half: the Gen2 script VM and its command table, the Johto and
Kanto world, day/night, breeding and the Day-Care, the Pokegear, shinies, held
items, and the Gold/Silver title sequence.

> [!CAUTION]
> **Neither this project nor Gen1Recomp is affiliated with the website
> `gen1recomp[.]com`.** That site is not run by either project and was not
> authorized by anyone involved. Do not download anything from it, and treat
> anything it hosts or claims as untrustworthy. Even if it links back to a real
> repository, the people behind it can change its content at any time. This
> GitHub repository is the only official source for gen2recomp.

This project does not include a ROM, emulate the Game Boy, transpile assembly,
or download a disassembly. A canonical US Poke Gold, Silver, Red, Blue, or
Yellow ROM is the only game content input.

The ROM is verified, used during import, and then released from memory. It is
not copied into the cache. Later launches load the private generated cache and
do not ask for the ROM again. Every version can be imported and played side by
side.

## Quick Start

Open the desktop app. On first boot, choose your legally obtained `.gb` /
`.gbc` file or drop it onto the window. Import takes a few seconds for Gen 1
and a couple of minutes for Gen 2, then the game starts automatically.

Only the canonical US ROMs are accepted. The importer verifies SHA-1 before
creating any game data:

| Version | Size  | SHA-1                                      |
| ------- | ----- | ------------------------------------------ |
| Gold    | 2 MiB | `d8b8a3600a465308c9953dfa04f0081c05bdcb94` |
| Silver  | 2 MiB | `49b163f7e57702bc939d642a18f591de55d92dae` |
| Red     | 1 MiB | `ea9bcae617fdf159b045185467ae58b2e4a48b9a` |
| Blue    | 1 MiB | `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2` |
| Yellow  | 1 MiB | `cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1` |

The packaged app contains neither a ROM nor pre-extracted game data. Music,
sound effects, and cries are synthesized while the game runs from compact
audio channel programs copied out of the verified ROM.

### A note on Windows Defender warnings

Windows Defender sometimes flags LÖVE builds with a generic machine-learning
detection such as `Trojan:Win32/Wacatac!ml`. This is a known false positive:
the exe is the official LÖVE runtime with the game archive appended (the
standard way LÖVE games ship), and Defender's heuristics distrust unsigned
executables with appended data. Releases publish SHA-256 checksums
(`sha256sums.txt`) so you can verify your download, and you can confirm a
flagged file yourself on [VirusTotal](https://www.virustotal.com), where these
builds come back clean on every engine except Defender's heuristic.

## Controls


| Action | Keyboard          | Controller         |
| ------ | ----------------- | ------------------ |
| Move   | Arrow keys / WASD | D-pad / left stick |
| A      | Z / Enter / Space | A                  |
| B      | X / Backspace     | B                  |
| Start  | Escape            | Start              |
| Select | Tab / Shift       | Back / Select      |


Rebind any of these in-game under **OPTIONS → CONTROLS**. Controllers are
supported out of the box.

### Hotkeys


| Key       | What it does                                         |
| --------- | ---------------------------------------------------- |
| `-` / `=` | Zoom out / in (overworld; also mouse wheel)          |
| `2`       | Cycle COLORS                                         |
| `3`       | Cycle TILT (free-roam overworld)                     |
| `4`       | Cycle ZOOM through every level (free-roam overworld) |
| `5`       | Cycle GBC FX                                         |
| `F1`      | Save                                                 |
| `F2`      | Load                                                 |
| `F10`     | Open / close the mod manager                         |


COLORS, TILT, ZOOM, GBC FX, and VOID FILL are also in the Options menu
and persist in `options.lua`.

### Low-end devices

**OPTIONS → PERFORMANCE** scales the port's optional extras for weaker
hardware: **HIGH** (everything on), **BALANCED** (no 3D tilt or GBC FX),
**LOW** (also no survey zoom, FPS capped), or **AUTO** — the default, which
picks a tier from your device (ARM handhelds → LOW, phones → BALANCED,
normal desktops → HIGH, unchanged). It only scales presentation; the
fixed-step game logic is identical on every tier, and a lower tier hides
your tilt/zoom/GBC-FX preferences without forgetting them. Details in
[docs/new-features.md](docs/new-features.md#performance-tier-low-end-devices).

### Rulesets

**OPTIONS → RULESET** picks which set of Generation I battle behaviors to run.
Both rulesets share the same damage formulas; they differ only in whether
the original's quirks are kept. The setting persists in `options.lua`, and
mods can register their own. Gold and Silver always run their own Gen 2 rules.

`gen1_faithful` is the default and reproduces the original cartridge,
famous bugs included:

| Rule                        | Behavior                                              |
| --------------------------- | ----------------------------------------------------- |
| `oneIn256Miss`              | A 100%-accurate move still misses on a roll of 255     |
| `critUsesBaseSpeed`         | Crit rate reads base speed, not the current stat       |
| `critIgnoresStages`         | Crit rate ignores stat stages                          |
| `focusEnergyBug`            | FOCUS ENERGY quarters the crit rate instead of x4      |
| `enemyUnlimitedPP`          | Enemies never spend PP, so they never Struggle         |
| `hyperBeamSkipRechargeOnKO` | HYPER BEAM skips its recharge when the target faints   |
| `randMin` / `randMax`       | Damage random factor 217-255                           |

`modern_clean` keeps the formulas but removes the notorious quirks:

| Rule                        | Behavior                                              |
| --------------------------- | ----------------------------------------------------- |
| `oneIn256Miss`              | Off: a 100%-accurate move always hits                  |
| `critUsesBaseSpeed`         | Unchanged: crit rate still reads base speed            |
| `critIgnoresStages`         | Off: stat stages count toward the crit rate            |
| `focusEnergyBug`            | Off: FOCUS ENERGY raises the crit rate as intended     |
| `enemyUnlimitedPP`          | Off: enemies deplete PP and Struggle when empty        |
| `hyperBeamSkipRechargeOnKO` | Off: HYPER BEAM always recharges, like Gen 2+          |
| `randMin` / `randMax`       | Damage random factor 217-255, same as faithful         |

## Running From Source

Requires LÖVE 11.x. Place a Gold or Silver ROM in the project folder and
double-click `Play-Mac.command` or `Play-Windows.bat`, or run:

```sh
scripts/setup.sh --rom "/path/to/Poke Gold.gbc"   # or Silver.gbc / Red.gb / ...
scripts/run.sh
```

On Windows, `scripts/setup.ps1` and `scripts/run.ps1` do the same thing. After
the first import, `love .` is enough.

### Linux

`scripts/setup.sh` and `scripts/run.sh` are the Linux path too. They need
LÖVE 11.x and Python 3 (with `venv`) on `PATH`; the setup script only
auto-installs LÖVE on macOS, so install it first with your package manager:

```sh
# Debian / Ubuntu
sudo apt install love python3 python3-venv

# Fedora
sudo dnf install love python3

# Arch
sudo pacman -S love python

# Any distro (Flatpak)
flatpak install flathub org.love2d.love2d
```

Then, from the project folder:

```sh
chmod +x scripts/*.sh                              # first time only
scripts/setup.sh --rom "/path/to/Poke Gold.gbc"
scripts/run.sh
```

`scripts/play.sh` does both steps in one go. After the first import, `love .`
is enough — or `flatpak run org.love2d.love2d .` if you installed the Flatpak.
If you use the official AppImage from [love2d.org](https://love2d.org), make it
executable (`chmod +x love-11.5-x86_64.AppImage`) and either put it on `PATH`
as `love` or run `./love-11.5-x86_64.AppImage .` directly.

Saves, options, and the generated data cache live in
`~/.local/share/love/pokemon-love2d/` (Gold and Silver keep theirs in the
`gold/` and `silver/` subfolders) unless you enable
[Portable Mode](#portable-mode). Controllers work through SDL2; if yours is not
detected, check that your user is in the `input` group or that `udev` rules for
the pad are installed. On Wayland with older LÖVE builds, launching with
`SDL_VIDEODRIVER=x11` through XWayland avoids most window and input quirks.

The Gen 2 importer reads the symbol files under `tools/vendor/symbols/`
(`pokegold.sym` / `pokesilver.sym`); `scripts/setup_gen2_symbols.ps1` fetches
them. The regression suite lives in `tests/drivers/`; each driver runs with
`POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/<name>.lua love .`.

## Portable Mode

By default the game keeps your save, options, and the private ROM-derived
data cache in your OS's normal per-user app data folder. To keep everything
next to the game instead (handy for a USB stick or portable drive you carry
between computers), drop an empty file named `portable.txt` next to the app
(next to the `.app`/`.exe`, or next to `main.lua`/`conf.lua` when
running from source), then launch the game. Portable mode is desktop-only
(Windows, Linux, macOS); it has no effect on Android or iOS, where the app
runs from a read-only package.

With `portable.txt` present:

- `save.lua`, `save.lua.bak`, and `options.lua` are read from and written to
that same folder instead of the OS save directory.
- A ROM import writes the generated `data/generated` and `assets/generated`
cache straight into that folder too (nothing is left in the OS save
directory), so a later launch reuses it without asking for the ROM again
even on a different computer, as long as the same folder comes along.
- Deleting `portable.txt` switches back to the normal OS save directory; nothing
already written to either location is touched automatically, so copy files
over yourself if you want to carry existing progress across the switch.

## iOS

Sideload the `.ipa` with AltStore (Windows or Mac) — see
[docs/ios-sideload.md](docs/ios-sideload.md). To build and install from source
on a Mac instead, see [docs/ios-install.md](docs/ios-install.md).

## Android

The build steps and packaging layout live in
[mobile/ANDROID.md](mobile/ANDROID.md); `scripts/build_android.ps1` and
`scripts/build_android.sh` drive the build.

## Handhelds

A PortMaster-style port for the **Anbernic RG34XXSP** on Stock OS 64-bit MOD
builds from `build-rg34xxsp.sh`. Install steps, controls, and troubleshooting
live in [docs/anbernic-rg34xxsp.md](docs/anbernic-rg34xxsp.md).

## Modding

The game ships a native mod platform: content registries, events and hooks,
per-mod saves and options, and an in-game manager. Start with
[docs/modding.md](docs/modding.md) and
[CONTRIBUTING-mods.md](CONTRIBUTING-mods.md).

Shipped example mods, one per kind of author, live in [mods/](mods/) —
including `DRAMATIC_SHAPE`, the voxel renderer, extended by UNDERdecodedHD for
Generation II support.

Maps can be edited in [Tiled](https://www.mapeditor.org) and exported back out
as a mod; see [docs/tiled-map-editing.md](docs/tiled-map-editing.md).

## Bugs and Ideas

Found a bug? A warp dropping you somewhere it shouldn't, a battle doing math
that looks wrong, text in the wrong box, anything that does not match the
original game — open an issue and attach a screenshot if you can. It saves a
lot of back and forth, and if you can't get one, describe what you saw instead.

Same for features: say what you want, why it is worth doing, and how you
picture it working. A request with real detail is one that can actually get
built.

## Docs

- [docs/architecture.md](docs/architecture.md) — runtime details
- [docs/gen2-migration-roadmap.md](docs/gen2-migration-roadmap.md) — what is
done and what is left in the Gen 2 port
- [docs/gen2-script-engine.md](docs/gen2-script-engine.md) — the Gen 2 script VM
- [docs/behavior-porting-notes.md](docs/behavior-porting-notes.md) — formula
provenance
- [docs/known-differences.md](docs/known-differences.md) — where the port still
diverges from the cartridge
- START > LINK connects two copies directly over UDP.

## Credits

gen2recomp is by **UNDERdecodedHD**, forked from **Gen1Recomp** by
**bryanthaboi** and **BOIS CLUB GAMES, LLC**. The Generation I engine, mod
platform, renderer, and tooling are theirs; the Generation II import, script
VM, world, and battle work are this fork's. See [LICENSE.MD](LICENSE.MD) for
the full copyright split.

## Special Thanks

This project would not be possible without [pret](https://github.com/pret) —
the pret band of decompiling maniacs — and their
[pokered](https://github.com/pret/pokered),
[pokegold](https://github.com/pret/pokegold), and
[pokecrystal](https://github.com/pret/pokecrystal) disassemblies.

<p align="center"><a href="https://boisclub.games"><img src="./assets/logo/bcg.png"></a></p>
