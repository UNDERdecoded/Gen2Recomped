-- Ear check: cycling COLORS with 2 during a battle keeps the battle song (#484).
-- The COLORS change rebuilds the live map's atlas through reloadMap, which used
-- to re-enter the map and fire PlayMapMusic; ReloadMapData (home/reload_tiles.asm)
-- only re-reads the view and tile patterns, map music comes from LoadMapData
-- alone (home/overworld.asm).  The invariants are in tests/engine/battle_colors_bug484.lua.
--   POKEPORT_DRIVER=tests/drivers/battle_colors_bug484_test.lua POKEPORT_IDENTITY=bug484 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
-- No POKEPORT_SPEED: it scales the logic clock only while audio runs on its own
-- real-time accumulator in Game:update, so it desyncs the ordering being judged.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Music = require("src.core.Music")
  local PaletteFX = require("src.render.PaletteFX")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  -- pokered data/maps/objects/Route1.asm puts both youngsters at (5,24) and
  -- (15,13) and the sign at (9,27), so the top of the road is empty; the
  -- battle is pushed straight in, the cell is only somewhere to stand.
  local MAP = "ROUTE_1"
  local STAND = { x = 5, y = 6, facing = "down" }
  local PARTY = { { "BULBASAUR", 12 }, { "PIDGEOTTO", 18 } }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the ear cannot check -----------------------------------------
  local opts = game.save.options or {}
  local musicVol = opts.musicVol or 7
  local sfxVol = opts.sfxVol or 7
  if musicVol == 0 then
    U.log("FAIL MUSIC volume is 0. Everything below is about which song is")
    U.log("     playing, and at 0 there is no song. Set MUSIC to 7 in OPTION")
    U.log("     and run this again, or the whole check is worthless.")
  end
  if sfxVol == 0 then
    U.log("FAIL SFX volume is 0, so the battle menu's own click is gone too")
    U.log("     and there is no way to tell a dead audio path from a fixed bug.")
    U.log("     Set SFX to 7 in OPTION.")
  end
  check(("MUSIC volume %d, SFX volume %d"):format(musicVol, sfxVol),
        musicVol > 0 and sfxVol > 0)

  local battleSongs = (game.data.audio or {}).battle or {}
  local mapSongs = (game.data.audio or {}).mapSongs or {}
  check(MAP .. " has a map theme to wrongly cut in (" ..
        tostring(mapSongs[MAP]) .. ")", mapSongs[MAP] ~= nil)
  check("the wild battle theme exists (" .. tostring(battleSongs.wild) .. ")",
        battleSongs.wild ~= nil)
  check("they are different songs, so the swap would be audible",
        battleSongs.wild ~= nil and battleSongs.wild ~= mapSongs[MAP])
  U.log("  COLORS ladder:", table.concat(PaletteFX.MODES, ", "))

  -- Every music cue in the run, forwarded so playback is untouched.  A map
  -- cue raised while a battle owns the screen is the bug, and it is the one
  -- thing an ear can miss if the two songs happen to open alike.
  local cues = {}
  local realPlay, realPlayMap = Music.play, Music.playMap
  Music.play = function(data, song, loop, ctx)
    cues[#cues + 1] = { song = song, reason = ctx and ctx.reason or "direct" }
    return realPlay(data, song, loop, ctx)
  end
  Music.playMap = function(data, mapId, onBike, surfing)
    cues[#cues + 1] = { song = "(playMap)", reason = "map", mapId = mapId }
    return realPlayMap(data, mapId, onBike, surfing)
  end
  local function mapCuesSince(mark)
    local hits = {}
    for i = mark + 1, #cues do
      if cues[i].reason == "map" then hits[#hits + 1] = cues[i].song end
    end
    return hits
  end
  local function lastSong()
    for i = #cues, 1, -1 do
      if cues[i].song ~= "(playMap)" then return cues[i].song end
    end
    return nil
  end

  -- ---- get into a battle --------------------------------------------------
  game.save.party = {}
  for _, slot in ipairs(PARTY) do
    table.insert(game.save.party, Pokemon.new(game.data, slot[1], slot[2]))
  end
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the road: any free cell on Route 1 will do, the
    -- battle is pushed rather than walked into
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(20)
        ow = game.overworld
        break
      end
    end
  end
  check("the overworld is up on " .. MAP, ow ~= nil and ow.map.id == MAP)
  U.wait(60) -- let the route theme actually get going first
  U.log("  route theme:", tostring(lastSong()))

  local battle = BattleState.newWild(game, "RATTATA", 5)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)
  for _ = 1, 120 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  check("the battle reached its FIGHT/PKMN/ITEM/RUN menu", battle.phase == "menu")

  local songInBattle = lastSong()
  check("the battle theme is what is playing (" .. tostring(songInBattle) .. ")",
        songInBattle == battleSongs.wild)
  U.shot(game, DIR .. "/bug484_1_" .. tostring(PaletteFX.mode) .. ".png")

  -- ---- press 2, for real --------------------------------------------------
  local before = PaletteFX.mode
  local mark = #cues
  game:keypressed("2")
  U.wait(30)
  check("pressing 2 in a battle still changed COLORS ("
        .. PaletteFX.modeLabel(before) .. " -> "
        .. PaletteFX.modeLabel(PaletteFX.mode) .. ")",
        PaletteFX.mode ~= before)
  local strays = mapCuesSince(mark)
  check("no map music cue came out of it (#484)", #strays == 0)
  check("the battle theme is still the current song",
        lastSong() == songInBattle)
  U.shot(game, DIR .. "/bug484_2_" .. tostring(PaletteFX.mode) .. ".png")

  -- the whole ladder, because a partial fix can leak on one mode only
  local seen = { [before] = true, [PaletteFX.mode] = true }
  local leaked = {}
  for _ = 2, #PaletteFX.MODES do
    local m = #cues
    game:keypressed("2")
    U.wait(20)
    seen[PaletteFX.mode] = true
    for _, s in ipairs(mapCuesSince(m)) do
      leaked[#leaked + 1] = PaletteFX.modeLabel(PaletteFX.mode) .. " (" .. s .. ")"
    end
  end
  local modes = 0
  for _ in pairs(seen) do modes = modes + 1 end
  check(("all %d COLORS modes were reachable from inside the battle"):format(modes),
        modes == #PaletteFX.MODES)
  check("no mode on the ladder started the route theme", #leaked == 0)
  if #leaked > 0 then U.log("  leaked on:", table.concat(leaked, ", ")) end
  check("still the battle theme after the full ladder",
        lastSong() == songInBattle)
  U.shot(game, DIR .. "/bug484_3_" .. tostring(PaletteFX.mode) .. ".png")

  -- ---- over to you --------------------------------------------------------
  U.log("You are at the battle menu with the wild theme running. Press 2 a few")
  U.log("times: the wash behind the two pics, RATTATA's shading and the HP bars")
  U.log("move mode to mode (shots 1 and 2 are one press apart), and the music")
  U.log("underneath keeps going without a seam. #484 dropped Route 1's theme")
  U.log("over it on the first press. The near miss to listen for is the battle")
  U.log("theme restarting from its opening bar rather than being replaced, and")
  U.log("the near miss to look for is nothing moving at all -- a hotkey switched")
  U.log("off in battle is not a fix. A on the menu clicks, so that click is your")
  U.log("proof the audio path is up at all.")
  U.log("Shots: " .. DIR .. "/bug484_*.png")

  -- keeps reporting after the hand-off: a map cue with a battle on top is the
  -- bug whether or not the two songs are easy to tell apart by ear
  local reported = #cues -- only what happens from the hand-off on
  while true do
    local top = game.stack:top()
    local inBattle = top == battle or (top and top.battle == battle)
    if inBattle and #cues > reported then
      for i = reported + 1, #cues do
        if cues[i].reason == "map" then
          U.log("FAIL map music cue during the battle:", tostring(cues[i].song),
                tostring(cues[i].mapId))
        end
      end
    end
    reported = #cues
    coroutine.yield()
  end
end
