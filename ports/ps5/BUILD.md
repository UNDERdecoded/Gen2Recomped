# Gen2Recomped on PS5 (native title)

The game runs on a jailbroken PS5 as a native **title**: an `eboot.bin` in a
folder under `/data/homebrew`, registered on the home screen by
[ShadowMountPlus](https://github.com/drakmor/ShadowMountPlus). It is not an
elfldr payload. The eboot is LOVE 11.5 plus a small launcher; the game itself
is the same `game.love` every other port ships (`scripts/pack_love.sh`).

## Build

On Linux or in WSL (Ubuntu 26.04 tested):

```sh
sudo apt install clang-18 lld-18 clang cmake ninja-build make autoconf automake libtool \
    pkg-config python3 curl git zip unzip patch
scripts/build_ps5.sh                         # title folder in ~/.cache/gen2recomp-ps5/out/title/PPSA42002
scripts/build_ps5.sh --deploy 10.0.0.101     # ... and upload it, then ask ShadowMountPlus to scan
scripts/build_ps5.sh --test-game             # the runtime bring-up game instead of Gen2Recomped
scripts/build_ps5.sh --version 1.2.3         # stamp the packed game.love (pack_love.sh --version)
```

From Windows: `wsl bash scripts/build_ps5.sh --deploy 10.0.0.101`.

The first run fetches and builds the runtime (about 5 minutes, ~1 GB in
`$G2R_PS5_WORK`, default `~/.cache/gen2recomp-ps5`); later runs only repack
`game.love` and relink. `--clean` rebuilds the runtime. Nothing large is
written into the repository.

`--deploy` uploads with FTP to `ftpsrv` on port 2121 (`PS5_FTP_PORT`),
`eboot.bin` and `param.json` last, then `POST http://<host>:10101/api/v1/scan`.
ShadowMountPlus defers that scan while any homebrew title runs or is
suspended: close it and scan again (or use its menu). It copies the icon and
backgrounds only when it first registers a title.

## Title folder

```
/data/homebrew/PPSA42002/
  eboot.bin              launcher + LOVE + SDL2 + ps5-opengl, development FSELF
  sce_module/libc.prx    the boilerplate's clean-room loader shim
  sce_sys/param.json     ports/ps5/sce_sys/param.json
  sce_sys/icon0.png      ports/ps5/sce_sys/icon0.png (512x512)
  sce_sys/pic0.dds       ports/ps5/sce_sys/pic0.png as 3840x2160 BC7 DX10 DDS
  sce_sys/pic1.dds       ports/ps5/sce_sys/pic1.png, same
  game.love              scripts/pack_love.sh
```

`sce_sys/` in the repository keeps PNGs; `ports/ps5/tools/png2dds.c` (built
on the fly, a BC7 mode-6 encoder over LOVE's stb_image) makes the DDS files,
so no texconv is needed.

## On the console

| What | Where |
|---|---|
| Game | `/app0/game.love`, mounted fused (the title folder is read-only) |
| Data root | `/data/gen2recomp` (`/download0/gen2recomp` if the title cannot write `/data`) |
| Save directory | `/data/gen2recomp/Gen2Recomp` (`love.filesystem.getSaveDirectory()`, identity `Gen2Recomp`) |
| ROM imports | `/data/gen2recomp/Gen2Recomp/imports` (the save directory's `imports`, as on Switch) |
| Log | `/data/gen2recomp/love.log` (stdout/stderr: `print`, LOVE errors), plus `[gen2recomp]` lines in the kernel log |
| JIT override | an empty `/data/gen2recomp/jit-off` or `jit-on` |
| Frame dump | an empty `/data/gen2recomp/screenshot`: every 600th frame goes to `/data/gen2recomp/screenshot.png` |

`love.system.getOS()` and `love._os` are `"PS5"` (from the start: `conf.lua`
already sees it). `love.system.openURL` returns false and does nothing.

Leaving the game (`love.event.quit()`) closes the title through
`sceSystemServiceLoadExec("exit")`; a title must never `exit()`. The PS
button/"Close application" works as for any title.

## Verified on the console

PS5 firmware 13.00, etaHEN, ShadowMountPlus 1.7beta7 (title registered as
`PPSA42002` "Gen2Recomped", icon and backgrounds shown), 2026-11-14:

- **Video**: `OpenGL 4.6 (Core Profile) Mesa 26.2.0 | PS5 AGC` (LOVE asks for
  3.3 core and gets 4.6 core), 1920x1080, max texture 16384, MSAA 4, shaders
  and canvases work, steady 60 FPS (vsync) in the bring-up game.
- **Pad**: the DualSense of the signed-in user appears as a gamepad
  (`joystickadded`, GUID above); every mapped button was checked (Cross a,
  Circle b, Square x, Triangle y, Options start, touchpad back, L1/R1, D-pad,
  L3). Analog sticks and L2/R2 axes were not exercised.
- **Audio**: LOVE's OpenAL source plays; the system log shows the title's
  process opening a shared AudioOut port. Nobody listened to it.
- **JIT**: the probe succeeds, LuaJIT runs with the JIT on (a 20M-iteration
  loop: 0.19 s); `jit-off` was not needed.
- **FFI**: `ffi.C.PHYSFS_getSearchPath`, `ffi.C.getpid` work; `ffi.load`
  fails with a clean error.
- **C++ exceptions** become Lua errors; `love.thread` workers run.
- **Save directory** `/data/gen2recomp/<identity>` is created and written.
- **Gen2Recomped** boots to its hub (News page, "0 of 18 games ready") without
  ROMs, with no Lua errors.

Not checked: leaving through `love.event.quit()` (the title was always closed
from the system), suspend/resume, a second user's pad, HDR, sound output by ear.

Console captures of a running title (the screenshot API this was tested with)
were often black even while the title rendered at 60 FPS; the frame dump
above reads the frame back through LOVE instead.

## The stack

| Part | Version / pin | Role |
|---|---|---|
| [ps5-native-app-boilerplate](https://github.com/drakmor/ps5-native-app-boilerplate) | `dd44bbd` | title CRT, `libc.prx`, ELF to FSELF converter, payload SDK v0.42 (sha256-pinned by its setup script) |
| [ps5-opengl SDK](https://github.com/darkxex/ps5-opengl/releases/tag/v1.0.2) | 1.0.2, sha256 `30d8e51d…` | EGL + OpenGL 4.6 core / compatibility: Mesa 26.2 on the PS5's AGC, the GL stack EglantinePS5 ships |
| [SDL (ps5-payload-dev fork)](https://github.com/ps5-payload-dev/SDL) | `8c56053` (2.30.12) | events, threads, PS5 pad (ScePad) and audio (SceAudioOut) backends; its OSMesa video driver is replaced by ps5-opengl's SDL2 "G19" driver (`integration/SDL2` in the SDK's sources) with `ports/ps5/sdl/g19-love.patch` |
| [LuaJIT](https://github.com/LuaJIT/LuaJIT) | `f9140a6` (PacBrew's) | FFI on (`__PROSPERO__` hidden, as PacBrew does), `LUAJIT_USE_SYSMALLOC` |
| [LOVE](https://github.com/love2d/love/releases/tag/11.5) | 11.5, sha256 `066e0843…` | autotools, static, `ports/ps5/love/0001-love-11.5-ps5.patch` |
| [PacBrew](https://github.com/ps5-payload-dev/pacbrew-repo/releases/tag/v0.40.2) | v0.40.2, sha256 `a85f65de…` | prebuilt freetype, openal-soft 1.24.3 (SDL2 backend), vorbis, ogg, theora, modplug, mpg123, libpng, zlib, bzip2 |

All pins live in `scripts/ps5/deps.sh`.

Why this stack: ps5-opengl is what the user's other titles (PS5SD, PS5LM via
ps5-homebrew-ui, EglantinePS5) draw with, and it is a real hardware GL inside
a title. PacBrew's own SDL2/LOVE packages use Mesa through zink or OSMesa
loaded with dlopen, which is a payload design.

### What the runtime changes

- **LOVE** (`ports/ps5/love/0001-love-11.5-ps5.patch`): `getOS()` and
  `love._os` are `"PS5"`; `openURL` is a no-op; `getExecutablePath()` is
  `/app0/game.love` (or `$LOVE_PS5_GAME`), which makes `boot.lua` mount the
  game fused, so the save directory is `<XDG_DATA_HOME>/<identity>` with no
  `love/` folder; LuaJIT luasocket compat fix (PacBrew's).
- **SDL** (`ports/ps5/sdl/`): the G19 driver gives LOVE one EGL window/context
  at the fixed 1920x1080 scanout size, whatever size `conf.lua` asks for
  (patched; upstream rejects other sizes and resizable windows). LOVE gets an
  OpenGL 3.3 core context first, like on desktop. SDL audio and the game
  controller layer are on; the launcher adds a controller mapping for the PS5
  backend's GUID (`0300d0424c050000e60c000011810000`): Cross=a, Circle=b,
  Square=x, Triangle=y, Options=start, **touchpad click=back**, L1/R1
  shoulders, L2/R2 triggers (analog), L3/R3, D-pad as buttons, both sticks.
  Only pads of signed-in users are seen (ScePad per user).
- **Launcher** (`ports/ps5/launcher/main.cpp`): data root, log, environment,
  JIT decision, splash, frame dump hook, LOVE's own run loop (with
  restart), title exit.
- **Memory**: `malloc` and friends are wrapped (`--wrap`) into ps5-opengl's
  `native-app/app_heap.c`, a 3 GiB heap in the title's direct memory. LuaJIT
  uses `malloc` (`LUAJIT_USE_SYSMALLOC`): its own allocator would map flexible
  memory, of which a title has only a few hundred MiB.
- **JIT**: LuaJIT exits the process if `mprotect(PROT_EXEC)` fails, so the
  launcher tries the same mapping first (and runs a 6-byte test function); if
  it fails the JIT engine is turned off before any Lua runs and LuaJIT
  interprets. FFI works either way.
- **FFI symbols**: `ffi.C.X` is `dlsym(RTLD_DEFAULT, "X")`. The title exports
  nothing, so `dlsym`/`dlopen`/`dlerror`/`dlclose` are wrapped
  (`ports/ps5/launcher/ffi.c`) and answer from a generated table: every
  `PHYSFS_*` function LOVE contains plus the libc names in
  `ports/ps5/launcher/ffi_exports.txt`. `ffi.load()` fails with an error
  (no dynamic libraries), which the game already `pcall`s.
- **C++ runtime**: `libSceLibcInternal` exports `__gxx_personality_v0`,
  `__cxa_get_globals`, the `std::` exception classes and more. Bound there,
  Sony's personality routine runs under the static libunwind and the first
  `throw` crashes. The link extracts libc++abi, libc++ and libunwind first
  (`-u` for each such symbol, archives before the Sony stubs), and
  `check_imports.py` fails the build if any C++ runtime symbol is imported.
- **lstat**: fails with `EPERM` for every path in a title (`stat` works);
  PhysFS uses it to create the save directory. `lstat` is wrapped
  (`--wrap=lstat`, `compat.c`) to fall back to `stat`.
- **LuaJIT unwinding**: LLVM libunwind's `__register_frame` takes one FDE, as
  on macOS; LuaJIT registers its JIT code that way here (`lj_err.c` patched
  by `build_runtime.sh`), otherwise each trace logs "bad fde" and errors
  cannot unwind through compiled code.
- **Imports**: a title has no `libScePosixForWebKit` or `libkernel_sys`; an
  import bound there would be a null call. `scripts/ps5/check_imports.py`
  runs after every link and fails the build if any import binds to them.
  `ports/ps5/launcher/compat.c` supplies the few libc functions no Sony
  module has (`getentropy`, `__cxa_thread_atexit_impl`, `isatty`, the
  `lstat` wrapper); the rest
  come from the payload SDK's `libc.a` (linked after the Sony stubs, so a
  stub always wins).

## Files

| File | |
|---|---|
| `scripts/build_ps5.sh` | the one command |
| `scripts/ps5/deps.sh` | pins and fetchers |
| `scripts/ps5/build_runtime.sh` | LuaJIT, SDL2, LOVE, link, FSELF |
| `scripts/ps5/check_imports.py` | import check after linking |
| `ports/ps5/launcher/` | launcher, FFI table, libc compat |
| `ports/ps5/sdl/` | SDL2 CMake wrapper and the G19 patch |
| `ports/ps5/love/` | LOVE patch |
| `ports/ps5/tools/png2dds.c` | PNG to BC7 DDS for `pic0`/`pic1` |
| `ports/ps5/testgame/` | bring-up game (`--test-game`) |
| `ports/ps5/sce_sys/` | param.json and artwork (title ID `PPSA42002`) |

## Licences

ps5-opengl (and its SDL2 driver), the boilerplate's tooling and libc.prx are
GPL-3.0-or-later; ps5-opengl's Mesa is MIT; SDL, LOVE, LuaJIT are zlib/MIT;
openal-soft is LGPL. The eboot links ps5-opengl statically, so `eboot.bin` is
a GPL-3.0 work; `game.love` is a separate file under the game's own licence.
Distributing the eboot means offering the corresponding source (the pinned
inputs above plus this directory).
