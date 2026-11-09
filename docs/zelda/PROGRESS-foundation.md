# Zelda progress: foundation

Owner: foundation agent. Contract: `docs/zelda/CONTRACT.md` (its last section,
"Foundation API, as built", is the interface the game modules code against).

## Checklist

- [x] M1 Registry: `alttp` + `minishcap` in `src/core/GameVersion.lua`
      (`engine = "zelda"`, `series = "zelda"`, `console = "gba"`, `module`,
      USA SHA-1s, `gameCode`, `onlinePlayers`), placed after White and before
      the ROM hacks in ORDER; helpers `isZelda`, `engine`, `isPokemon`,
      `pokemonOrder`. `src/import/RomRevisions.lua` names both games and their
      header codes (AZL / BZM), so another region's dump gets a real message.
- [x] M2 Audit of Pokemon-only paths (see "Audit" below).
- [x] M3 Launcher: sidebar `consoleOf`/`seriesOf` honour `info.console` /
      `info.series`; `Sidebar.SERIES` = Pokemon, **Zelda**, Pokemon ROM hacks,
      so Game Boy Advance shows a Zelda card next to Pokemon. Game page hides
      Map Editor / Translate, disables .sav import/export and the slot's Edit
      button for Zelda; slot rows show the game's own summary line. Classic
      layout gets LP / MC chips. LauncherArt has the No-Intro titles and
      Wikipedia pages (scraped only when the player asks; nothing in the repo).
- [x] M4 Import: a picked / dropped / batch / Android-inbox ROM is routed by
      SHA-1 (`GameVersion.forSha1`, same as Pokemon) to its version; the
      worker runs `src/zelda/ZeldaImport.lua` (extractor-shaped wrapper around
      the module's `extract`) with CacheFs.bulkWrites + ImportRecovery; the
      launcher writes the marker; readiness = marker + module `isReady`. With
      no module on disk the page says COMING SOON / "recognised, not playable
      yet" and an import attempt says "not supported by this build yet".
- [x] M5 Runtime: `src/zelda/ZeldaRuntime.lua` (+ ZeldaRegistry, ZeldaCache,
      ZeldaSaves, ZeldaPlaceholder). main.lua `bootGame` hands a Zelda version
      to it (unmounting the last Pokemon cache first). 240x160 canvas,
      integer (or FIT) scale, top-anchored on portrait phones; 59.7275 Hz fixed
      tick; Input + TouchControls shared with Pokemon (rebinds and touch
      layout carry over); system menu (RESUME, SAVE GAME, LINK PLAY, SCALE,
      MUSIC/SOUND VOLUME, TV/CAST when the host supports it, QUIT TO
      LAUNCHER); saves into the launcher's slots; game errors shown on screen.
- [x] M6 Online: `src/online/zelda/ZeldaSession.lua` (star room 2-4, shared
      tick, reliable events, unreliable snapshots with reliable fallback,
      join/leave/timeouts, clean host-leave), `ZeldaNet.lua` (open/join a room
      on Connector: LAN / router / forwarded port / punch / hub code; no 1:1
      relay short codes), `ZeldaLinkMenu.lua` (LINK PLAY screen). Launcher
      Online Hub HOST WITH FRIENDS / JOIN FRIEND on a Zelda game lands in LINK
      PLAY via LauncherHub's pending action. Cross-series refused:
      `CompatRules.pair` -> `cross_series` (both directions), Handshake text;
      a Zelda host answers a Pokemon hello with its own hello + a refusal.
- [x] M7 Game agents' requests: alttp asked for nothing blocking; added
      `pausedUpdate(dt)` (called while the system menu / LINK PLAY is up) so
      its chip audio can stay fed. minishcap: none filed yet.

## Verified (how)

All harness output is under `G:/Gen2Recomped/scratch_claude/zelda/`, run with
`APPDATA=G:/Gen2Recomped/scratch_claude/zelda/appdata` (scratch LÖVE save
dirs), `ROOT=<repo>`, network blocked except 127.0.0.1.

- `python tools/run_lua_check.py tests/zelda_foundation_session_test.lua`:
  37/37 (4-player loopback star: joins, ids, events relayed + ordered,
  directed events, snapshots incl. oversized fallback, shared tick within 2,
  guest leave, host close, wrong-game / Pokemon / full-room refusals,
  timeout, CompatRules + Handshake cross_series). NOTE: `/tests/*` is
  git-ignored in this repo, so this file is local only.
- `runtime/` harness (`lovec runtime`): 25/25 -- tick rate, D-pad, A edge,
  Escape menu pauses the game, SAVE writes slot1 and the launcher summary
  line + name read back, save loads on reboot, QUIT hook, game error screen,
  missing module message, touch d-pad + MENU button, LauncherHub pending
  JOIN (bad code -> reason shown) and HOST (room opens with a code).
  Shots: `shots/runtime_menu.png`, `runtime_game.png`, `runtime_native.png`,
  `runtime_error.png`, `runtime_touch_menu.png`, `runtime_link_room.png`.
- `launch/` harness MODE=import with POKEPORT_ZELDA_PLACEHOLDER=1 and the
  user's ALttP ROM: 7/7 -- the real launcher path (probe -> worker ->
  ZeldaImport -> marker), readyReport ok, Play hands `alttp` to the host,
  runtime boots after. Shot `shots/launch_after_import.png`. (Only the
  placeholder's one text file was written, into the scratch identity.)
- Integration with the REAL alttp module (src/zelda/alttp, the ALttP agent's
  work in progress): `launch/` MODE=import IDENTITY=zelda_scratch_real with
  the user's ROM -> imported through the worker, marker written, readyReport
  ok, Play -> runtime boots; `realrun/` then ran 400 frames of the game with
  no error (shot `shots/realrun_alttp.png`, scratch only, ROM-rendered).
- `launch/` MODE=shot: `shots/launch_gba_series.png` (GBA: Pokemon + Zelda
  cards), `launch_gba_zelda_list.png`, `launch_classic.png` (LP/MC chips,
  COMING SOON while no module).
- `twoproc/run.sh 3 minishcap`: same, three processes.
- `twoproc/run.sh 4 alttp`: four LÖVE processes over real ENet on
  127.0.0.1, each through the real LINK PLAY menu (host HOST A ROOM, guests
  type the code into JOIN A ROOM): all 4 in the room, each saw the 3 others'
  snapshots and events, host closed, guests saw "The host left." Shots in
  `twoproc/out/`.
- Regression: `tests/online_compat_test.lua` (emerald / crystal / heartgold
  caches) all pass; `online_transport_test` passes;
  `polished_crystal_registration_test` 38/38; `rom_revisions_test` 141/141;
  launcher_mobile_pick / rom_batch / mod_generations pass; launcher_donate,
  launcher_settings, launcher_settings_page fail exactly as before (known
  pre-existing; donate's wearsOurMark list now also names the two Zelda ids
  alongside firered/platinum/... in the same pre-existing failure).

## Audit (Pokemon-only paths vs Zelda)

- main.lua bootGame: Zelda -> ZeldaRuntime (never Game.lua / Data / mods).
- RomImporter: markerFor, requiredFiles, readyReport, blockedImportReason,
  startData (manifest/extractor), game panel tools, save import/export, slot
  Edit, unsupported-ROM message, classic chips.
- LauncherSidebar: console/series, tools usable (map/save/translate/
  saveImport/saveExport refused for Zelda), backdrop (never boots a Zelda
  "main menu"; BACKGROUND list skips Zelda), scrape-all includes Zelda.
- SaveData.slotSummary + SaveSafety.looksLikeSave: Zelda saves summarised
  and recognised (stamp `zelda = {...}`).
- translation Service.enqueue: skips Zelda. PokewalkerScreen game picker:
  skips Zelda.
- CompatRules / Handshake: `cross_series`.
- Left as is (safe): LauncherHub.installedGames (needs pokemon.lua, so Zelda
  is never offered to the hub's GTS/world data), LauncherHubScreen game grid
  (Zelda listed; HOST/JOIN route to LINK PLAY; a WORLD join shows a toast),
  LauncherSecondScreen shelf (tile = Play), CloudSync (syncs Zelda slots like
  any other), ModProfile / SaveConvert / Gen4Save / SaveVariants (only reached
  for the version asked, and every Zelda entry point to them is closed).
- Setup scripts (`scripts/setup.*`, `bootstrap.ps1`) keep their own Pokemon
  hash lists; not touched (developer tooling).

## Open issues / not done

- No device testing (Android / iOS / Switch): touch overlay and soft keyboard
  for the room code were exercised only with a forced overlay on desktop.
- TV/CAST row only changes the mode file; TOP mode (CastTop) is not wired for
  the Zelda canvas (MIRROR is what a single-screen game needs).
- Relay short codes are 1:1 (pokeserver pairing), so Zelda rooms use long /
  hub codes only. Hub-introduced punches for multi-guest rooms are driven by
  ZeldaNet.roomSource; not tested against a real hub (loopback only).
- No host migration: host leaving closes the room (documented choice).
- Box art / descriptions are fetched only on request (LauncherArt); not
  verified against libretro for these titles (no network in tests).

## Requests for other agents

- Both game agents: please read "Foundation API, as built" in CONTRACT.md.
  In particular `romPath` may be nil (use `ctx.bytes`), `ctx.fresh` is true
  on every import, and `init.lua` is required at launcher start.
- Test your module through the real path: `POKEPORT_ZELDA_PLACEHOLDER` is a
  harness-only switch; to run YOUR module in the two-process harness set
  `MODULE=src.zelda.<dir>` (see `G:/Gen2Recomped/scratch_claude/zelda/twoproc/`).
