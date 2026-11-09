# Zelda support: shared contract

Three agents work on Zelda in parallel, in the same tree. This file is the
agreement between them. Change it only with an anchored edit, and say so in
your progress file.

## Games

| Version id  | Game | Console | ROM the user imports |
|---|---|---|---|
| `alttp`     | A Link to the Past & Four Swords (USA) | GBA | 8 MiB `.gba`, game code `AZLE` |
| `minishcap` | The Minish Cap (USA)                   | GBA | 16 MiB `.gba`, game code `BZME` |

Both are GBA cartridges, so both sit under **Game Boy Advance** in the
launcher, and under a new **Zelda** series card next to **Pokemon**.

## Legal rule (hard)

- No ROM bytes, extracted graphics, music, text, maps or ROM-rendered
  screenshots in the repo, ever. Everything comes from the user's own ROM at
  import time, into the data folder (the same place the Pokemon caches go).
- Reference decomps or reimplementations are cloned read-only under
  `G:/Gen2Recomped/scratch_claude/zelda_refs/`. They are never built, never
  copied into the repo, and their asset dumps are never committed.
- Tables you need (offsets, pointers, structure layouts) may be written as code
  that reads the ROM. Do not paste data tables from the ROM into Lua.

## Ownership (who edits what)

| Owner | Files |
|---|---|
| Foundation agent | `src/core/GameVersion.lua` (the two entries), `src/import/LauncherSidebar.lua` (console/series), `src/import/RomImporter.lua` + import worker hooks, `src/zelda/ZeldaRuntime.lua`, `src/zelda/ZeldaRegistry.lua`, `src/online/zelda/*` (transport/session layer), launcher art |
| ALttP agent | `src/zelda/alttp/**`, `tests/zelda_alttp_*`, `docs/zelda/alttp.md` |
| Minish Cap agent | `src/zelda/tmc/**`, `tests/zelda_tmc_*`, `docs/zelda/minishcap.md` |

Game agents do not edit the foundation's files. They ask for a hook by writing
it under "Requests" in their progress file; the foundation agent reads those.

## Module interface (each game provides)

`src/zelda/<dir>/init.lua` returns a table:

```lua
return {
  id = "alttp",                 -- or "minishcap"
  detect = function(header) end, -- header = first 0x200 bytes; true if this ROM
  -- Runs inside the import worker thread. Reads the ROM, writes the cache with
  -- CacheFs under root (e.g. "<datadir>/alttp/"), calls progress(frac, label).
  -- Must be resumable / idempotent like the Pokemon importers.
  extract = function(romPath, root, progress) end,
  cacheVersion = 1,             -- bump to force a re-import
  isReady = function(root) end, -- true when the cache is complete
  -- The runtime. ZeldaRuntime calls these like LÖVE callbacks.
  newGame = function(opts) end, -- opts = { root, slot, save, online, options }
}
```

The object returned by `newGame` implements any of: `update(dt)`, `draw()`,
`keypressed(k)`, `keyreleased(k)`, `gamepadpressed(j,b)`, `gamepadreleased(j,b)`,
`touchpressed/moved/released`, `resize(w,h)`, `save()`, `quit()`,
and for online: `netSnapshot()`, `netApply(peerId, snap)`, `netEvent(peerId, ev)`.

Input is read through the foundation's `ZeldaRuntime.input` (A, B, L, R,
START, SELECT, D-pad), which maps keyboard, gamepad and touch the same way the
Pokemon games do. Rendering targets the native 240x160 GBA canvas; the runtime
scales it (integer scale, widescreen option later).

## Saves

Per-game, per-slot save files under the save identity, in our own format
(Lua or JSON tables), never the cartridge SRAM layout unless importing one.
Slot UI comes from the existing launcher SAVE SLOT card.

## Online

The foundation provides `src/online/zelda/ZeldaSession.lua` on top of the
existing net ladder (`src/online/net`), LinkState host/join short codes and the
Link Hub relay: a room of 2–4 players, a tick clock, reliable events and
unreliable snapshots. Each game defines what it sends:

- **alttp**: Four Swords is the cartridge's own 2–4 player mode; it is the
  main online feature. ALttP itself gets optional co-op presence (friends as
  coloured Links in your Hyrule) only if time allows.
- **minishcap**: the cartridge has no link multiplayer; online is built to fit
  it: Kinstone fusion with friends, friends visible as coloured Links in your
  Hyrule, and trading figurines/shells if time allows.

## Progress files

Each agent keeps `docs/zelda/PROGRESS-<owner>.md` up to date as it works:
milestones with [ ] / [x], what was verified and how, and Requests for other
agents. Update it at every milestone, not just at the end.

## Foundation API, as built (added by the foundation agent)

Details the interface above leaves open. `PROGRESS-foundation.md` has the
long version and the harnesses.

- **Registry**: `GameVersion.VERSIONS.alttp/minishcap` carry `engine = "zelda"`,
  `series = "zelda"`, `console = "gba"`, `module = "alttp"|"tmc"` (the dir).
  `GameVersion.isZelda(id)`, `GameVersion.engine(id)`, `GameVersion.pokemonOrder()`.
  `src/zelda/ZeldaRegistry.lua` loads `src/zelda/<module>/init.lua`; init.lua
  is required at launcher start (readiness check) and inside the import
  worker thread, so keep it cheap to require and free of love.graphics at
  require time.
- **root / cache**: `root` in `isReady(root)`, `opts.root` and `opts.cache` in
  `newGame`, and the 2nd argument of `extract` are the same kind of object, a
  `src/zelda/ZeldaCache.lua` accessor: `read(rel)`, `write(rel, data)`,
  `exists(rel)`, `remove(rel)`, `loadLua(rel)` (empty env), `imageData(rel)`,
  `image(rel)` (nearest), `source(rel, kind)`, `.prefix` (`"alttp/"`,
  `"minishcap/"`), `tostring(root)` = prefix. Paths are relative to the
  game's own subtree, which lives wherever the Pokemon caches live (save dir,
  portable folder, custom data folder).
- **extract(romPath, cache, progress, ctx)**: `romPath` MAY BE NIL (Android
  inbox, dropped file); `ctx.bytes` is ALWAYS the whole verified ROM string.
  `progress(frac 0..1, label)`. `ctx.checkpoint(op)` writes an ImportRecovery
  breadcrumb. `ctx.fresh = true`: the worker has cleared `data/generated/` and
  `assets/generated/` under the prefix and CacheFs.bulkWrites is already on;
  do not skip work because of stamps from an older import (put files under
  those two dirs, or delete your own leftovers). The launcher writes
  `rom-cache.complete` (`zelda-cache:<id>:v<cacheVersion>:<sha1>`) after
  `extract` returns; a raised error is shown to the player.
- **newGame(opts)**: `opts.version`, `root`/`cache`, `slot`, `save` (the
  decoded table or nil), `online` (a ZeldaSession or nil), `options`
  (`scale`, `musicVol`, `sfxVol` as 0..1), `input` (= `ZeldaRuntime.input`:
  `isDown(b)`, `wasPressed(b)`, `mask()`; b in a b l r start select up down
  left right), `host`, `W`=240, `H`=160, `tickHz`=59.7275. `update(dt)` is
  called once per GBA frame with dt = 1/59.7275; `draw()` draws into the
  240x160 canvas (origin top-left, already cleared to black).
- **host** (the runtime) for the game: `host:requestSave()` (calls your
  `save()` and writes it), `host:save(tbl)`, `host:volume("music"|"sfx")`,
  `host:toast(text)`, `host:session()`, `host:quit()`, `host:openLink()`.
  START is the game's; the runtime's own menu is on Escape / gamepad guide /
  SELECT+START held 0.5 s / the touch MENU button.
- **save()** returns a plain Lua table (SaveSerializer: no functions,
  userdata or cycles). Optional keys the launcher shows: `name`, `playTime`
  (seconds), `summary = { line = "..." }`. The runtime stamps `zelda = {...}`.
- **Optional game callbacks**: `pause(bool)`, `pausedUpdate(dt)` (every tick
  while the system menu or LINK PLAY is up, e.g. to keep audio fed), `focus(f)`, `optionsChanged(o)`,
  `quit()`, `touchpressed/moved/released`, and online `netAttached(session)`,
  `netDetached(reason)`, `netSnapshot()`, `netApply(peer, snap)`,
  `netEvent(peer, ev)`, `netPeerJoined(peer, info)`, `netPeerLeft(peer, info)`.
- **Online** (`src/online/zelda/ZeldaSession.lua`): `session.localId` (1 =
  host, 2-4 guests; also the player colour 1 green 2 red 3 blue 4 purple),
  `session.isHost`, `session:tick()` (shared 59.7275 Hz clock),
  `session:sendEvent(t)` (reliable, ordered, all others),
  `session:sendEventTo(id, t)`, `session:sendSnapshot(t)` (unreliable, keep
  it under ~400 bytes of JSON or it goes reliable), `session:players()`.
  The runtime sends `netSnapshot()` every 2 frames while unpaused and
  delivers everything else through the callbacks above. Host leaving closes
  the room for everyone (no migration).
