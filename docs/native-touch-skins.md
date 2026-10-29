# Native custom touch skins

Upstream stack: this change is based on the offered viewport/window contract
PR #124 (and its prerequisites). Merge those first. The runtime needs their
actual game rectangle and input mapping; no viewport stub is provided here.

The shared engine now supplies the real `src.core.TouchSkin` service used by
Gen1 mods. This is engine work; mod files and their optional geometry consumers
do not need changes. The implementation is adapted from Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, with its original copyright and
[licence](../licenses/GEN1RECOMP-TOUCH-SKINS.md) retained. No proprietary Gen1
launcher code or bundled third-party skin artwork is included.

## Installed skins and options

Skins live under `skins/<id>/skin.lua`, `skins/<id>/overlay.cfg`, or in an
installed `skins/<id>.zip` / `.deltaskin` inside the engine's writable storage.
`TouchSkin.installArchive(name, bytes)` installs archive bytes through the same
persistence filesystem used by native options. `TouchSkin.list()` discovers
native, RetroArch and Delta configurations; `load` loads their artwork and
controls. A wrapped Delta archive may contain its metadata in a subdirectory.

When installed skins exist, native OPTIONS offers **TOUCH SKIN**. LEFT/RIGHT
cycles the library and DEFAULT, applies the choice immediately and saves
`options.touchControls.skin`. DEFAULT restores the existing native pad. The
position/size editor retains this selection in its save snapshot. Turning the
pad off clears the active skin and its cutout. Invalid/missing selections
restore the native presentation and expose `TouchControls.skinError`.

Mobile OPTIONS also offers **HAPTICS**: OFF, LIGHT, NORMAL and STRONG, with
Gen1's light default and legacy-name normalization. The preference is shared
across cartridges, outside position/size layout snapshots. The first owner of
a button/key/action pulses through the real `love.system.vibrate`; additional
contacts holding that same input, release and focus reset do not retrigger it.
Runtimes without a vibrator retain normal input. Unit pulse checks do not
constitute physical phone vibration acceptance.

The custom-skin studio/library editor and its launcher integration remain a
separate, open Gen1 parity requirement. This runtime PR does not claim that
the existing native position editor implements that studio.

## Input and presentation owners

* Controls support GB/GBA buttons, combinations, directional areas, sectors,
  arbitrary key bindings, held speed actions and overlay page switching.
  Multiple contacts share per-button and per-key ownership. Release, a reused
  pointer id, cancellation polling and focus reset release the correct holds.
* The real `Game.touchSkinHotkey` routes held/toggled speed, reset and OPTIONS
  through native engine owners. Existing fixed-speed state locks still apply.
* Native `GameViewport` fits the game into the active skin's screen cutout and
  maps gameplay coordinates into it. Explicit `render.viewport` mods retain
  final layout authority; the skin is their default rectangle. Unsupported
  native combined-screen layouts retain their existing owner.
* Bezel/control artwork draws in OS-window space after final composition.
  A desktop bezel survives controller use without capturing gameplay input.
  With no selected skin, the viewport stays on its existing direct path.
* The native default pad, Gen4 X/Y layout, sticks, free-camera drag and touch
  cancellation recovery are retained; the Gen1 controller file is not used
  as a replacement for those implementations.

The library retains native/RetroArch/Delta export, native editing data helpers,
image import and viewport detection. Raster JPEG data embedded in a PDF may
be recovered; vector-only PDF artwork reports that conversion is required.

## Verification scope

ROM-free suites:

```sh
luajit tests/engine/touch_skin_test.lua
luajit tests/engine/touch_skin_dpad_area.lua
luajit tests/engine/skin_format_import_test.lua
luajit tests/engine/touch_skin_native.lua
luajit tests/engine/touch_haptics.lua
luajit tests/engine/touch_orientation_bug633.lua
luajit tests/engine/game_viewport.lua
```

The first three preserve Gen1 format/input contracts, with third-party bundled
art assertions replaced by owned memory-only assets in the native suite. The
native suite also exercises the actual mod loader, normal OPTIONS input,
save-codec round trips, contact ownership, rendering calls and viewport hooks.
Archive-member fixtures model PhysFS mounts explicitly; they are not evidence
of real ZIP decoding or GPU/window acceptance. Real runtime import, both GPU
backends, rotation and packaged desktop/mobile builds still require acceptance.
