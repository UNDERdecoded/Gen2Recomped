# Launcher

The launcher is `src/import/RomImporter.lua`, the first-run / title screen
that runs before `Game:load`. Besides ROM import (see the file's own header)
it hosts a tabbed shell covering per-game save slots and a mod manager. This
file documents the runtime model; the visual spec lives separately.

## Android multi-ROM / mod / save import

On Android, `love.system.pickFile([kind])` opens the Storage Access Framework
picker (`GameActivity.showFilePicker`); the chosen file is copied into the app
save directory as:

| `kind` | Destination |
| --- | --- |
| nil / `"rom"` | `picked_rom.gb` (open) |
| `"mod"` | `picked_mod.zip` (open) |
| `"sav"` / `"save"` | `picked_save.sav` (open) |

Export uses a separate API: `love.system.createFile(suggestedName)` →
`GameActivity.showCreateDocument` (`ACTION_CREATE_DOCUMENT`), which copies
staged `pending_export.sav` to the user-chosen URI and writes `export_done.flag`
for the launcher to acknowledge on refocus.

`RomImporter` then imports on refocus / Choose:

- **ROMs** via `findPendingRom`: only a 1 MiB `.gb` whose SHA-1 maps to a
  version that is **not** yet ready counts as pending. A leftover
  `picked_rom.gb` from Red therefore cannot block Blue's Choose (issue #167).
- **Mods** via `findPendingMod`: Prefer `picked_mod.zip`, or (on Choose) any
  other `.zip` at the save-dir root (USB copy).
- **Saves** via `findPendingSav`: Prefer `picked_save.sav`, or (on Choose) any
  other `.sav` at the save-dir root.

After a successful import the consumed save-dir file is removed.

## Android game-data / mods folder

Android's default save identity (`Android/data/<package>/files/save/pokemon-love2d`)
is often on a small internal volume. Mods, ROM caches and imported base files
follow **GAME DATA FOLDER** in launcher Settings instead:

- `love.system.pickFolder()` → `GameActivity.showFolderPicker`: a volume dialog
  listing each `getExternalFilesDirs()` app folder (phone, SD card, with free
  space) plus optional `ACTION_OPEN_DOCUMENT_TREE`. The chosen absolute path
  is written to `picked_folder.txt`; `RomImporter:focus` / `_pollPickedFiles`
  calls `SaveData.setDataDir`.
- Direct rows for each volume (`love.system.getExternalDataDirs`) skip the
  dialog. `USE THE DEFAULT FOLDER` clears the setting.
- Writes go through `CacheFs` (`io.*`); reads need the folder on the PhysFS
  path, so Android also exposes `love.system.mountDirectory`.
- Saves and `options.lua` stay in the identity folder on purpose. After
  switching, **MOVE EXISTING DATA HERE** copies `mods/`, `modstorage/` and
  `imports/base/` into the new place.

Most shared folders (Downloads, Drive) are not writable via `io.open` on
Android 11+; the picker rejects those and asks for Phone storage or an SD
card. iOS still keeps everything in the app folder.

**Manual check (device/emulator):** import Red → switch to Blue → Choose →
system file picker must appear (not a silent Red re-extract) → pick Blue →
Blue becomes ready beside Red. On the MODS tab, Import mod .zip must open the
same system picker and install the chosen archive on return.

## Tab structure

`self.tab` is one of `"red"`, `"blue"`, `"yellow"`, `"mods"`. The tab bar
draws one chip per game plus a MODS chip and rebuilds `self.tabRects` every
frame so `mousepressed` can dispatch clicks; switching tabs mid-import is
allowed (a dropped ROM still routes by SHA-1 regardless of which tab shows).

- A game tab (`_drawGamePanel`) shows the ROM card, the SAVE FILES card, the
  Play button, and the SAVE SLOT card in a responsive two-column grid (see
  Responsiveness). The MODS tab (`_drawModsPanel`) shows the mod list instead.
- The self-updater banner (`self.Check`, see `docs/updater.md`) draws as a
  centered pill in a reserved band just above the footer, on every tab. That
  position is unchanged by this redesign, so `docs/updater.md` needed no edits.

## Save slot model

All slot I/O lives in `src/core/SaveData.lua` and goes through the same fs
abstraction (`persistFs`) every other save/options call uses, so portable
mode (an `io.*` filesystem used when `portable.txt` marks the install)
keeps working unchanged.

- **Files.** A version's playthroughs live under `saves/<version>/`, one file
  per slot: `saves/<version>/slot1.lua` plus a rolling `.bak` and staged
  `.tmp` witness (`slotNames`), mirroring the write/recovery discipline
  `SaveData.save`/`load` already use for the flat legacy file. Slot ids match
  `slot%d+`; `createSlot` allocates one past the highest existing number so a
  reused id can never collide with a lingering file.
- **Registry.** The ordered slot list and which one is active persist in
  `options.lua` (via the existing `SaveData.loadOptions`/`saveOptions`):
  `options.saveSlots = { [version] = { list = {"slot1", ...}, active = "slot1" } }`.
  Custom slot labels (#205) live alongside them in the same registry:
  `options.saveSlots[version].names = { slot1 = "Nuzlocke" }`, written by
  `SaveData.renameSlot` (trimmed; an empty label clears it) and surfaced on
  each `listSlots` row as `label` (the launcher row shows `label`, falling
  back to the player name). `deleteSlot` drops the label with the slot.
  Renaming never touches the save file, so an empty slot can be labeled.
  On desktop, right-clicking a slot row opens the inline rename modal
  (Enter commits, Esc cancels); touch has no secondary button, so the
  affordance is desktop-only.
- **Active slot resolution.** `saveNames(version)`, the function every
  existing caller (`TitleState` hasSave/load/save, recovery order) already
  goes through, now resolves the *active* slot instead of a fixed flat name.
  Resolved once per version per process (`ensureVersionSlots`, cached in
  `activeSlotCache`/`slotsChecked`): a registry entry wins; otherwise a lazy
  legacy migration may create one; otherwise the flat legacy path is used
  (`save.lua` / `save_blue.lua`), so a pre-slots install keeps working as before.
- **Legacy migration.** One-time per version, lazy on first
  `listSlots`/`load`/`saveNames` call (`tryMigrateLegacy`): if a flat legacy
  file exists and no `saves/<version>/` registry does, its main + `.bak` are
  copied into `saves/<version>/slot1.lua(.bak)`, verified readable
  (`decodeSlot`: main, then `.tmp`, then `.bak`), and only then are the
  originals removed and `slot1` registered as active. A copy that fails to
  verify leaves the originals in place; migration never loses data.

The launcher-facing API:
- `SaveData.listSlots(version)` -> array of `{id, exists, name, meta}` for
  every registered slot. `name` is the save's player name, or `nil` for an
  empty slot; `meta` is `{badges, timeText, dexCount}` (the same fields the
  title screen's `ContinueInfo` shows) or `nil`. The pure part,
  `SaveData.slotSummary(save)`, is unit-testable with no filesystem.
- `SaveData.setActiveSlot(version, slotId)` registers the id if new, persists
  it as active, and updates the process cache so the very next save/load
  lands there. The launcher calls this the moment a slot row is clicked
  (`RomImporter:_selectSlot`); pressing Play needs no signature change, since
  `Game.lua`/`main.lua` still just call `SaveData.load()`/`save()`.
- `SaveData.createSlot(version)` -> new slot id, registered but with **no
  save file written**. An empty slot means the title screen offers NEW GAME
  only, which needs no further changes.
- `SaveData.deleteSlot(version, slotId)` removes the slot's
  main/`.bak`/`.tmp` files, drops it from the registry, and if it was active
  points active at another remaining slot (or clears active when the list is
  empty). The launcher's SAVE SLOT panel Delete control calls this.

## Launcher mod manager

`src/mods/LauncherMods.lua` is a launcher-only read of the mod set. It runs
before `Game:load`, so **it never loads a mod's entry chunk**; only
`manifest.json` is read and validated (`src/mods/Manifest.validate`), the way
`Loader:_discover` finds mods without running them. The real loader
(`src/mods/Loader.lua`) still owns the actual load at boot.

- `LauncherMods.list()` scans `mods/` one level deep (first id wins on a
  duplicate) and returns one row per mod:
  `{id, name, version, badge, description, enabled, status, statusDetail}`.
  `badge` is the manifest's `category`, falling back to `profile`, then
  `"MOD"`, uppercased. `enabled` reads `options.mods[id]` (missing means
  enabled, matching the loader's own default).
- `status` is `"ok"`, `"warn"`, or `"conflict"`, computed by the pure
  `LauncherMods.deriveList`/`statusFor` against `ManagerState.resolveToggle`
  and the validated manifests: `conflict` when enabling this mod collides
  with another enabled one; `warn` for an out-of-range `game_version` or an
  absent/disabled/wrong-version hard dependency; `ok` otherwise. Having no
  `love.*` calls, this half is table-driven by the test suite on its own.
- `LauncherMods.setEnabled(id, bool)` persists `options.mods[id]` as a plain
  boolean, the exact shape `Loader:_saveState` writes, so the running game
  and the in-game `ManagerState` see the change on next boot. The mods panel
  calls this on every toggle and re-derives the list right away
  (`RomImporter:_refreshMods`) so a status change (e.g. a new conflict)
  shows without waiting for a reload.
- `LauncherMods.installZip(path)` mounts the archive with
  `love.filesystem.mount`, locates the mod root via `locateRoot` (manifest at
  the zip root, or inside one top-level folder), validates its manifest, and
  copies the tree into the save-dir `mods/<id>/` before unmounting. Rejects a
  duplicate of an already-installed mod id, and accepts either an external
  path string or a LOVE `DroppedFile`, staging a dropped file into a save-dir
  temp first (mount only reaches save-dir-relative paths), the same way
  `RomImporter` handles a dropped ROM. A failed copy rolls its partial tree
  back, and every path unmounts and clears the staged temp file.
- `LauncherMods.uninstall(id)` removes `mods/<id>/` and clears
  `options.mods[id]` so a later reinstall starts from the loader's default
  (enabled). The mods panel Delete control calls this and re-derives the list.

## Import / Export save

The SAVE FILES card wires a raw Gen1 `.sav` battery image to the save slots
through `src/import/SaveFileIO.lua`, which sits on top of
`src/save_convert/SaveConvert.lua` and the slot API in `SaveData`.

- **Import save** is live once the game's ROM is imported (playable). It opens
  a native `.sav` picker (`chooseSav` on desktop; on Android,
  `love.system.pickFile("sav")` → `picked_save.sav`, same SAF path as ROMs).
  `SaveFileIO.importToSlot` reads the bytes (an absolute path, a save-dir
  relative name, a dropped LOVE file, or raw bytes),
  guards the 32768-byte size, runs `SaveConvert.importSav` (which also rejects
  a bad main-data checksum), then registers a fresh slot (`SaveData.createSlot`),
  writes it (`SaveData.writeSlot`), and makes it active (`SaveData.setActiveSlot`).
  The meta stamp is re-stamped off `gen1_import` to the current numeric format
  so `SaveData.load`'s migration pass accepts the slot. On success the SAVE SLOT
  panel is refreshed with the new slot selected.
- **Export save** is live only when the active slot actually holds a save
  (checked against `listSlots`). `SaveFileIO.exportActiveSlot` loads the active
  slot, encodes it back with `SaveConvert.exportSav` (a slot never keeps
  `rawImport`, so this is a zero-filled template export, which is valid), and
  writes `exports/gen1recomp-<version>-<slotId>.sav` in the save directory
  (`love.filesystem.createDirectory("exports")`). On desktop it returns the
  absolute path (`love.filesystem.getSaveDirectory()`), which the notice line
  shows with an "Open folder" affordance (`love.system.openURL("file://" .. dir)`).
  On Android the bytes are also staged as `pending_export.sav` and
  `love.system.createFile(suggestedName)` opens `ACTION_CREATE_DOCUMENT` so the
  player can save to Downloads / Drive / etc.; on return `export_done.flag`
  makes focus show "Save exported."
- **Drag-drop.** `filedropped` routes a `.sav` to the import path for the
  currently active game tab; when a non-game tab (mods, or the locked yellow
  placeholder) is showing it defaults to red, the always-present first game
  (`_savedropTarget`). `.gb` (ROM) and `.zip` (mod) routing is unchanged.
- **Failure UX.** Every error path (wrong size, bad checksum, write failure,
  nothing to export, ROM not imported yet) surfaces as a red notice line on the
  card. Nothing raises and nothing silently no-ops.

`SaveFileIO` is love-free enough to unit-test through the same in-memory
filesystem stub the slot backend uses (`tests/engine/save_file_io_tests.lua`).

### Old and wrapped saves (2026-10-17)

Reported: "importing a save from an old version fails with size doesn't
match". Every file was measured against one size per generation, so anything
in a wrapper was refused. `src/save_convert/SaveVariants.lua` now runs before
the size check (`SaveFileIO.importToSlot`, and `SaveConvert.importSav` for the
CLI):

| File | What happens |
| --- | --- |
| This port's own `.lua` save from an older build (`saves/<game>/slotN.lua`, a `.bak`, `save_online.lua`, the old `save.lua`) | Recognised by its `return {` text, decoded with `SaveSerializer`, brought forward with `SaveData.runMigrations`, written as a new slot. Inline `options` are dropped (they live in `options.lua` now). A save that names another game is refused with "this is a Pokemon Red save; import it on the Pokemon Red page". |
| Gen 1 / 2, 32 KiB + 44 or 48 bytes | The MBC3 clock footer (VBA, VBA-M, BGB, mGBA, My OldBoy) is dropped. |
| Gen 1 / 2, 64 KiB | Padding (0x00 / 0xFF) or the image written twice: the first 32 KiB is used. |
| Gen 3, 128 KiB + 16 bytes | mGBA's RTC block is dropped (any footer up to 64 bytes is). |
| Gen 3, 64 KiB | An emulator left on 512 Kbit flash: padded back to 128 KiB with 0xFF. Slot A is whole in the first 64 KiB; Gen3Save's sector checks decide. |
| Gen 3, 256 KiB of padding | The first 128 KiB is used. |
| Gen 4 / 5 | Unchanged: `NdsSave.unwrap` (DeSmuME `.dsv`, no$gba, 1 MiB, trailing bytes). |

Anything else is still refused, and the notice now says why ("the 8000 bytes
after the save are not padding or an emulator footer"). The desktop pickers
list `*.lua` beside `*.sav` / `*.dsv`; Android's picker is `*/*` already and the
pick is sniffed by content, so a `.lua` copied to `picked_save.sav` works.

Checks: `python tools/run_lua_check.py tests/save_variants_test.lua` (29,
synthetic images and an old format-1 save) and `lovec tools/save_variants_check`
(33: every variant through the real codecs against the imported caches in
`DATA`, default `G:/Gen2Recomped`, plus copies of real old slot files from
`OLD`). Older port exports were never the wrong size, so there is nothing
else to convert: before b017ee1 a Gen 3 export raised instead of writing.

## Responsiveness

Every measurement derives from `love.graphics.getDimensions()` each frame
plus the existing global scale `s = clamp(height / 768, 0.7, 1.6)`; nothing
assumes a fixed window size. The game panel's two-column grid (ROM/SAVE
FILES/Play on the left, SAVE SLOT on the right) collapses to one stacked
column, slot card below Play, when the window is too narrow for both
`~300 * s`-wide columns. The save-slot list and the mod list both scroll
(wheel, or drag on touch/desktop) clamped to their own content extent,
recomputed every draw. The tab bar labels only the active chip so it stays
narrow-safe, and content caps out at `~1440 * s` wide, centered.

The desktop window has a floor of 480x360 (`conf.lua` `minwidth`/`minheight`),
under which the cards stop being readable at all. Mobile ignores it: those
windows are fullscreen.

### Page scroll

Two columns fit any window the launcher is likely to open in; one stacked
column does not. On a phone-shaped window the ROM card, SAVE FILES, Play and
SAVE SLOT together run past the bottom, and a footer pinned to the window
bottom painted over them with the overflow unreachable.

So the whole column under the tab bar -- panel, updater banner, footer --
scrolls as one page whenever it is taller than the room below the tab bar:

- The strip, logo and tab bar stay pinned, so navigation is always on screen.
  Everything else draws at `contentTop - pageScroll` inside a scissor, and the
  footer is laid out downward from `footerTop` right after the content instead
  of upward from the window bottom.
- `RomImporter.pageScrollFor(naturalH, viewportH, scroll)` is the whole
  decision, pure and pinned by `tests/engine/launcher_page_scroll.lua`. A
  window that grows back drags the offset down with it, so the page can never
  stay parked past its own end.
- The panels report their natural height as they draw (`_drawGamePanel` and
  `_drawModsPanel` return it), so the decision reads the previous frame's
  measurement -- the same one-frame settle the two lists already rely on.
- **One scroll axis at a time.** While the page scrolls, the panels draw
  `paged`: the slot and mod lists take their natural height, keep no inner
  scroll region and report a max of 0, so the wheel, the right stick and a drag
  all move the page and never fight a list for the same gesture. Two-column
  layouts do not overflow, `paged` stays false, and every one of these behaves
  exactly as it did before.
- Hit testing follows the clip: `inside` (clicks) and `_ptIn` (hover) reject a
  rect that scrolled out of the viewport, so a control that slid under the tab
  bar cannot be clicked through it. Tab chips carry `pinned = true` and are
  exempt. `pageScroll` resets on a tab change, each tab being a different
  length.
- A press on empty background pans the page, resolved in `_updateSlotDrag` like
  every other drag here.

### Dragging on Android

The launcher is handed no move events on any platform: `main.lua` forwards
neither `touchmoved` nor `mousemoved` while it is up, which is why every drag
here is resolved by polling inside `draw` instead. Desktop polls the mouse;
Android used to poll nothing at all ("no reliable pointer polling" meant its
mouse emulation), so it had no scroll gesture whatsoever -- fine while every
scroll region was an inner list with a wheel alternative, useless the moment
the page itself became the thing that scrolls, since a phone is exactly where
it overflows.

`love.touch` is pollable, so `_pointerHold` reads the first active touch there
and hands `_updateSlotDrag` the same (held, y) pair the mouse gives on desktop.
Consequences:

- Slot rows and mod toggles ARM on press and commit on release on Android too,
  matching desktop, so a swipe that starts on a card scrolls instead of
  selecting the row it started on.
- `touchPollable` (set once in `new`) gates all of it. Where `love.touch` is
  missing, every Android path is exactly what it was: act on press, never arm,
  no drag.

## Sidebar layout

The launcher opens in the sidebar layout (`src/import/LauncherSidebar.lua`,
installed over `RomImporter` as a mixin). Settings -> LAYOUT switches back to
the classic tab bar (`options.launcherClassic`).

- **Top bar**: the colour strip, with the Gen 2 logo centred across the window.
- **Rail**: News (the default), Games, Mods, Tools and Settings. The foot of
  the rail holds the TiltRips code and DONATE.
- **Games**: you pick a console, then a series (Pokemon / ROM hacks), then a
  game. A console with nothing imported is greyed out and offers an import.
  - The first page has a Continue card (the game whose save was written
    last), then Favorites and Recent rows.
  - The star on a tile marks it as a favourite (`options.launcherFavorites`;
    `launcherRecent` holds the recent list).
  - A game's page is the classic game panel. The header carries back,
    FAVORITE, MUSIC and IMPORT ROMS.
- **Mods**: search, a tag filter (taken from each mod's metadata) and a sort
  order (`options.launcherModSort`).
- **Tools**: Map Editor, Save Editor, Translate, Import / Export Save,
  Import ROMs, Touch Controls and Scrape Game Art. You pick the tool, then
  the game, then the slot where the tool needs one. The same tools are still
  on each game's page.
- **News**: `launcher_news.json` at the repo root on `main`, merged with the
  GitHub releases. The result is cached in `launcher_news.lua` for 6 hours.
  Format:
  `{ "items": [ { "title": "...", "date": "YYYY-MM-DD", "body": "...", "url": "..." } ] }`

### Background

`src/import/LauncherBackdrop.lua` runs an imported game's real title / main
menu behind the launcher. It mounts the version and calls `Game:load`, then
draws the game under a scrim.

The picture is fitted to the content area beside the rail and under the top
bar, not to the whole window. For the length of the game's draw:

- a bare `setCanvas()` binds a canvas the size of that area;
- `getDimensions` and its relatives answer with the area's size;
- `Renderer.splitViewport` is set to the area.

The game therefore letterboxes into the canvas, and the canvas is drawn at
the area's position.

A DS game (generation 4 and later) shows the top screen only, whatever
layout the player chose for play. On its title screen it shows the
single-screen composition: the lower screen's Pokemon behind the logo.

During the draw, and for the backdrop's game only:

- `SecondScreen.mode` answers "swap" on Gen4Title / HgssTitle / Gen5Title;
- everywhere else it answers "display", and `SecondScreen.draw` is a no-op,
  so the intros and the opening movie draw only their top screen.

What it shows is set by Settings -> BACKGROUND
(`options.launcherBackground`):

| Value | Shows |
| --- | --- |
| `game` (default) | the game being viewed, otherwise the last game played |
| `last` | always the last game played |
| a version id | that game |
| `video` | a video the player chose, copied to `launcher_background.ogv` |
| `off` | nothing |

- It waits 0.45 s for the selection to settle before switching.
- It gives up its mount (`Backdrop.stop`) before Play, an editor or an import.
- A game that fails to boot is not retried.
- The music follows Settings -> BACKGROUND MUSIC. The MUSIC button in the
  header toggles it too.

### Game art scraper

`src/import/LauncherArt.lua` runs only on request: Settings -> SCRAPE ART &
DESCRIPTIONS covers every imported game, and Tools -> Scrape Game Art covers
one.

- **Box art** comes from libretro-thumbnails `Named_Boxarts`. The imported
  ROM's own file name is tried first, then known No-Intro titles. Aliases
  there are git symlinks, which raw.github serves as the target's name; the
  scraper follows one.
- **The description** is the first two sentences of the Wikipedia REST
  summary for the game.
- Both are saved to the save folder as `launcher_art_<version>.png` and
  `launcher_art_<version>.lua`.
- They show on the game tiles and in an About card at the top of the game
  page. ROM hacks are skipped.
- The About card is drawn on every game page, with or without scraped art.
  Its bottom right holds the game's one import button: "Import ROM", or
  "Re-import ROM" once the game is imported. In the sidebar layout the ROM
  card below is hidden once the ROM is in. It comes back for an import in
  progress, a failed import, or a ROM that must be re-imported. The header
  drops IMPORT ROMS (batch import) on game pages; it stays on the game lists
  and under Tools.

### Cloud saves (sync folder)

`src/import/CloudSync.lua` syncs saves through a provider's local sync folder. It detects OneDrive, Google Drive for desktop, Dropbox and iCloud Drive, and you can pick any other folder.

**Using it:**
- Settings → CLOUD SAVES: choose the folder, BROWSE for another, or SYNC NOW.
- Each save card has a **Sync** button.
- Tools → Sync Saves syncs every imported game.

**Layout:**
- `<folder>/Gen2Recomp/saves/<version>/<device>-<slot>.lua`, with a `.info.lua` sidecar beside each save.
- Cloud backups go in `backups/`.
- Local state is kept in `cloud_sync.lua`; local backups go in `cloud_backups/`.

**Rules:**
- A slot's first sync never replaces anything. Its save is uploaded as a new entry, and any unlinked cloud entries come down as new slots.
- After that, whichever side changed is copied to the other.
- If both sides changed, the cloud copy is kept as a new local slot labelled "(cloud)".
- Each side keeps two backups.

**Checks:** `CLOUD=<scratch folder> love tools/cloud_sync_check` runs 15 checks.

**Not done:** direct OAuth sign-in to Google Drive and OneDrive. It needs app client IDs. Android has no provider sync folder, so the phone needs that sign-in.

### Settings page

In the sidebar layout, the Settings page fills the whole content area and is drawn over the footer. While Settings is open, the live background is paused (`LauncherBackdrop.setPaused`): the game doesn't update, its music is suspended, and no switch happens. This is why stepping through the BACKGROUND list no longer boots a cartridge at each step. That list only offers games that are imported, importable, and haven't failed to boot.

## Online Hub

Sidebar section "Online Hub" (`src/ui/online/LauncherHubScreen.lua`, wired by
anchored hooks in `LauncherSidebar.lua`). The Link Hub
(docs/online-design.md 2.9, `src/online/hub/`) runs inside the launcher in a
`love.thread` (`src/online/hub/HubThread.lua`), driven by
`src/online/LauncherHub.lua`.

* **HOST WITH FRIENDS**: asks once (remembered, changeable in HUB SETTINGS):
  *keep a hub running* (starts the hub, shows ONE share code with COPY, SHARE,
  TEXT MESSAGE, EMAIL and a QR code) or *just play now* (pick a game; it opens
  LINK > HOST and shows a direct code). SHARE uses `love.system.shareText` when
  a build provides that bridge, otherwise copies.
* **JOIN FRIEND**: a code field (typing, PASTE, Ctrl+V; a code already on the
  clipboard is filled in when the page opens), the hubs and games heard on this
  Wi-Fi (LAN beacon; iOS cannot listen and says so), and guidance when a hub
  can't be reached (same Wi-Fi, router mapping, swap who hosts, ask for a
  direct code). A friend's hub code is probed (`hub_ping`) and saved as this
  player's hub; a game, short or world code asks which game to open and the
  game joins as soon as its map is up.
* **Share code**: an InviteCode of kind "hub" with ticket 0 (no rendezvous
  ticket is ever 0) carrying the hub's router address (when mapped) and its
  LAN address.
* **Games launched from here** use the hub when their own LINK HUB setting is
  empty: `LauncherHub.patchLinkState` wraps `LinkState.settings` (127.0.0.1
  for the host's own games, the friend's hub otherwise) and
  `LinkState.hubEndpoint` (the host's HUB codes carry the router / LAN
  address, not 127.0.0.1). `Game:load` calls `LauncherHub.installGame` (one
  pcall line).
* **Lifetime**: the thread survives the hand-over to a game and back;
  `love.quit` stops it (and unmaps the router ports). A mods restart is a new
  process: the hub stops, and "Start hub when launcher opens" brings it back.
* **Config** (save dir `online_hub/config.json`): name, port (TCP+UDP, default
  7780), router mapping, LAN visibility, autostart, "use the hub in my
  games", relay (short codes), tournaments, GTS with the imported games that
  back each pool, the always-on world (game, name, size, port, open to
  strangers, GTS inside), caps, log file / level / IP masking / days kept, and
  the generated admin key. Data: `online_hub/data/`.

