# Where generated data goes

The launcher's **GAME DATA FOLDER** setting points the ROM cache, installed
mods, mod storage and the imported base-file bank at a folder the player
chooses — a second drive, or an SD card on Android — instead of LÖVE's
per-user save directory (`%APPDATA%\LOVE\...` on Windows,
`getExternalFilesDir()`-based on Android).

Reported broken as: *"when in the settings you change the location for saving
game data, generated data isn't going there."*

Everything below was measured with `tools/data_location_check.lua`, which
builds three real directories (a save directory, a game source, and a folder
standing in for the player's drive), installs a LÖVE stand-in whose
mount/unmount honour PhysFS's search order, and drives the real `SaveData`,
`CacheFs`, `LuaWriter` and `RomImporter.readyReport` against them. No
cartridge and no cache are needed, and every arm is forced: desktop with the
FFI `PHYSFS_mount` symbol resolvable, Android with it, Android with only the
JNI bridge, and desktop with no mount mechanism at all.

## What was actually wrong

**The writes were already right.** Every writer of generated data goes through
`CacheFs.write` / `CacheFs.rawWrite` / `CacheFs.dataFs()`, and all of them
resolve `CacheFs.root()` on every call. Driven and measured: after
`SaveData.setDataDir`, `CacheFs.write`, `LuaWriter.write`,
`CacheFs.rawCreateDirectory`, `dataFs().write` and `dataFs().newFile(..., "w")`
all opened absolute paths under the chosen folder, and nothing opened a path
under the save directory. The sweep in the check confirms there is exactly one
bypass of that seam left in `src/` (see "The one remaining bypass" below).

Two separate faults sat on the other side of the seam.

### 1. The read path served the home the player had moved away from

PhysFS searches its **write directory** — LÖVE's save directory — ahead of
every *appended* mount. `CacheFs` mounted the chosen folder appended (at `""`,
`append = true`), so the folder's files were visible and could never win.
Worse, `CacheFs.mountVersion` then made it actively wrong:

* step 1 was `love.filesystem.mount(sub, "", false)` — a **prepend** whose
  source is a *relative* name, and LÖVE resolves a relative mount source
  against the save directory and nowhere else. So it prepended the stale copy
  of `platinum/`.
* step 3, `mountGeneratedTrees(prefix)`, mounted `prefix .. "data/generated"`
  and `prefix .. "assets/generated"` onto the **un-prefixed** paths, prepended
  — again by relative name, so again the save directory's copy, and this time
  as the last prepend, i.e. at the very front of the search path.

Measured, before the change, identically on the desktop and Android arms:

| asked | answer |
|---|---|
| on disk, save directory | `return { home = 'save-directory' }` |
| on disk, chosen folder | `return { home = 'chosen-folder' }` |
| `CacheFs.read("data/generated/constants.lua")` | `chosen-folder` |
| `love.filesystem.read("data/generated/constants.lua")` | **`save-directory`** |

`love.filesystem` is what `require("data.generated.*")`, `Data:load` and
`love.graphics.newImage` go through. So the import wrote hundreds of megabytes
into the chosen folder and the running game read none of it. That is two
sources of truth for one logical file — the exact class of bug the comment at
`src/import/CacheFs.lua:315` ("This exists because there were two of them")
was written about, reappearing on the read side.

### 2. Choosing a folder deleted the game that was already installed

`RomImporter.readyReport` opens with

```lua
if CacheFs.root() then purgeSaveDirCache() end
```

and `purgeSaveDirCache` removes every version's `data/generated`,
`assets/generated` and `rom-cache.complete` from the save directory. Its
comment reasons only about **portable** installs, where that is correct and
necessary — but `CacheFs.root()` is also non-nil for a chosen game-data folder,
and `RomImporter:setDataDir` calls `_recheckReady()`, which calls `readyReport`
for every version, the moment the folder changes.

So: choose a folder, and the launcher immediately deletes the installed game
out of AppData — a gigabyte at a time — while the new folder is still empty,
and the next line of the same report says *"no cache for this version yet."*

Measured: driving the real `readyReport` over `GameVersion.ORDER` after a
folder change left `save/platinum/data/generated/constants.lua` and
`save/platinum/rom-cache.complete` both **absent**.

It cannot be right for a chosen folder, because the launcher already offers
**MOVE EXISTING DATA HERE** (`RomImporter:startDataMove`) for exactly this
case. A purge that runs first deletes the thing the move exists to move.

**The two faults masked each other**, which is why the symptom is confusing: the
purge destroyed the stale copy, so the shadow usually had nothing to serve —
until a sequence where the one-shot `saveDirPurged` had already fired, or where
`removeTree` refused (it raises on a failed remove). Then the setting looked
like it had done nothing at all.

## What changed

`src/import/CacheFs.lua`

* `mountReadable(dir, append, mountPoint)` takes a mount point, records every
  mount it makes in `ourMounts`, and records **how** (`ffi` / `jni` / `love`).
  It refuses to serve a prepend or a mount point through
  `love.system.mountDirectory`, because that bridge takes neither and would
  silently give back the appended mount that loses to the save directory.
* `prependRootTrees(root)`, new, called once the custom or portable root is
  mounted: prepends `<root>/data/generated` at `data/generated` and
  `<root>/assets/generated` at `assets/generated`. The mount point is what
  makes the prepend safe — the folder can only ever serve names under those two
  trees, which the game source never ships, so pointing the setting at a folder
  that happens to contain a `conf.lua` cannot shadow the game's own.
* `mountGeneratedTrees(prefix)` mounts **from the live root by absolute path**,
  and falls back to the save-dir-relative name only when the save directory *is*
  the live root.
* `mountVersion` step 1 runs only when `CacheFs.root()` is nil, for the same
  reason.
* `CacheFs.forgetRoot()` now takes the previous root's mounts back off the read
  path, so an A → B change applies without a restart. Anything it cannot take
  down sets `staleMounts`, which `rootReport().restart` exposes.
* `shadowRisk` / `CacheFs.shadowRisk()`: set when `resolveMount()` cannot be
  resolved at all while a non-source root is live. On that build the chosen
  folder can be made visible and **cannot** be made to win, and a restart does
  not change that — so it is reported separately from `restart`.
* `CacheFs.dataFs()`'s reads call `CacheFs.root()` first. The chosen folder is
  only on the PhysFS path because `resolveCustomRoot` mounted it, and that runs
  the first time anything asks for the root — so a launch whose first act was to
  list mods could not see a mod installed in the chosen folder.

`src/import/RomImporter.lua`

* `purgeSaveDirCache` is portable-only, guarded twice: at the call site
  (`rootReport().kind == "portable"`) and inside the function
  (`SaveData.isPortable()`).
* `setDataDir`'s confirmation and `_dataDirNote`'s panel text say when a
  restart is needed (`report.restart`) and when a stale copy can still win
  (`report.shadowed`), naming **MOVE EXISTING DATA HERE** as the remedy for the
  second. A setting that silently does nothing is the bug; one that says
  "restart to apply" is not.

Measured after the change, same scenario: `CacheFs.read` and
`love.filesystem.read` both answer `chosen-folder`, and
`save/platinum/...constants.lua` is still on disk for the move to pick up.

## What happens to data already at the old location

**It is left exactly where it is**, and this follows the project's existing
precedent rather than inventing one: the cache is large, re-derivable from the
cartridge, and deliberately not migrated behind the player's back — the panel
has always said so ("Changing the folder points future writes at it and leaves
what is already installed where it was"), and **MOVE EXISTING DATA HERE** is the
explicit, player-initiated migration. Three consequences, all now true:

* the old copy survives the folder change, so the move still has something to
  move, and a player who switches back has their game;
* it no longer wins the read path, because the live root's generated trees are
  prepended ahead of it;
* on a build that cannot position a mount (`shadowRisk`), it still can win, and
  the panel says so instead of claiming the folder is in use.

Saves, options and the mod enable-state do not move at all. They are kilobytes,
and they are what you most want to still have when the drive this points at is
not plugged in.

## The one remaining bypass

`src/import/BorrowedTiles.lua` writes the map editor's extended tile atlas with
`ImageData:encode("png", "editor/atlas/...")`, which can only ever land in the
save directory — `love.filesystem` cannot write outside it. That is **editor
output**, not ROM-derived cache, and it is pinned at exactly one in the check's
sweep rather than ignored, so a second bypass appearing anywhere in `src/` fails
the check instead of going unnoticed.

## How Gen 1, 2 and 3 are known not to have moved

This is shared storage code, so the argument is made as an assertion rather
than a reading. Every player who has never opened the setting, and every
Crystal / Gold / Silver / Prism / Emerald install, has no chosen folder and no
portable marker, so `CacheFs.root()` is nil — and on that path the new code
takes the branch it always did: `mountVersion` step 1 runs (its new guard is
`not CacheFs.root()`, true here) and `mountGeneratedTrees` falls through to the
same `love.filesystem.mount` of the same save-dir-relative name.
`data_location_check` asserts it for a Gen 2 prefix (`gold/`) as well as a Gen 4
one (`platinum/`), on all four arms: with no folder chosen, **every** mount the
module makes is under the save directory, the read path serves the save
directory's cache, `CacheFs.read` agrees, and `unmountVersion` takes it back
off. The save editor and the mod importer resolve their paths through
`CacheFs.dataFs()`, whose reads are unchanged apart from resolving the root
first; the check drives `dataFs().write` and `dataFs().newFile` and confirms
both land under the live root.

The full suite is PASS=72, REPORT=4, NOSPEC=41, no FAIL / SKIP / ERROR /
PASS\* — the previous 71 plus this check.

## The check, and what proves it bites

`tools/data_location_check.lua` — 177 assertions, no cartridge, no cache.
Sections: the control (a real cache in the previous home, so the later
measurement has something to lose to); the setting applied mid-process; every
writer driven and its absolute destination compared against
`rootReport().path`; the previous home surviving the readiness pass; the
single-source-of-truth invariant (`CacheFs.read` and the PhysFS read path agree,
and both are the live root); a second change in the same process, with no
restart; clearing back to the default; refusals (a relative path, a folder that
cannot be created); the default install for `gold/` and `platinum/`; and the
sweep.

Faults planted, each verified to have landed by md5, each confirmed to fail with
a message that diagnoses it:

| plant | md5 moved | result |
|---|---|---|
| `mountGeneratedTrees` reverted to the save-dir-relative source | `a648…` → `fdb5…` | 6 failures: *"the PhysFS read path serves the live root, not the old home — got save-directory, want chosen-folder"* |
| both purge guards removed | `2309…` → `73e5…` | 6 failures: *"the readiness pass does not delete the previous home's cache — got nil"* |
| the whole pre-change tree | — | 15 failures |

Two findings about the check itself, recorded rather than smoothed over:

* removing **one** purge guard does not fail anything, because the call-site
  test and the in-function test are each individually sufficient. That is
  belt-and-braces on purpose; a single-guard plant cannot bite and the
  both-guards plant is the one that does.
* the pre-change tree fails *fewer* read-path assertions than plant 1 does,
  because the purge deletes the stale copy before the read-path section runs.
  The two faults mask each other. Plant 1, not the whole-file control, is what
  proves the read-path invariant.

## Play-test items

141. Desktop, non-portable, with a game already imported: open SETTINGS →
     GAME DATA FOLDER → CHOOSE FOLDER, pick a folder on another drive. The game
     you already had must still show PLAY, and `%APPDATA%\LOVE\Gen2Recomp\`
     must still contain its `data/generated`. Before this change both
     disappeared.
142. Same, then press PLAY without restarting. It must boot the game from the
     folder it was imported into, and the panel must not be saying anything
     about a restart.
143. Same, then press MOVE EXISTING DATA HERE. The old copy moves, the panel
     keeps saying "Games are installed in \<folder\>", and PLAY still works.
144. Import a second game *after* the folder change and confirm it lands in
     the chosen folder (`<folder>/<version>/data/generated`) and that the first
     game still plays.
145. Change the folder twice in one session (A → B) and press PLAY. The game
     must come from B. If the panel says "The previous folder is still on the
     read path. Restart the app to finish applying this.", restart and confirm
     it then comes from B — that message means a mount could not be dropped,
     which is reportable.
146. Point the setting at a folder, close the app, unplug/rename that drive,
     and launch. The panel must read "Set to \<path\> / NOT IN USE (…)", saves
     and options must be intact, and the game must be playable or offer an
     import — not crash.
147. Point the setting at a folder that contains a `conf.lua` and a `main.lua`
     (e.g. another LÖVE project) and launch. The game must still be the game:
     the prepend is confined to `data/generated` and `assets/generated`, and
     this is the test of that confinement.
148. USE THE DEFAULT FOLDER (RESET) with a game installed in the chosen folder.
     The panel must go back to "Games are installed in the app's own folder",
     and the chosen folder's copy must still be on disk.
149. Install a mod while a folder is chosen, restart, and open the MODS tab as
     the very first action. The mod must be listed — this is the `dataFs()`
     read-before-root fix.
150. Android, SD card: SETTINGS → CHOOSE STORAGE → pick the SD card volume,
     then import. `data/generated` must appear under the SD card's app folder,
     and the import must not report "access denied" on `data/generated`.
151. Android, with a game already imported to internal storage, then switch to
     the SD card: if the panel says "A game already imported to the default
     folder can still be the one that loads on this device. Use MOVE EXISTING
     DATA HERE to be sure.", that device cannot position a PhysFS mount — note
     the device and OS version, because it changes what the Android build can
     promise. If the message is absent, the SD card copy must be the one that
     loads.
152. Portable install (`portable.txt` beside the executable) with a leftover
     AppData cache: the AppData copy must still be purged on the first
     readiness pass, exactly as before, and the panel must say "Portable: …"
     with no folder stepper.
153. Crystal / Gold / Prism and Emerald, default install, no folder chosen:
     import and play each one. Nothing about where their data lives may have
     changed.

## Needs a real Android device

The `shadowRisk` branch is the one thing that cannot be settled from here.
Whether `ffi.load("liblove.so").PHYSFS_mount` resolves in the shipping APK
decides whether the chosen folder can be put *ahead* of internal storage or
only beside it, and that is a property of the built APK, not of this code. Item
151 is how to find out; if the message appears, the honest options are to make
`love.system.mountDirectory` take a mount point and an append flag (a change in
the Java bridge, which is not in this tree's reach) or to have the launcher
offer the move automatically on Android.
