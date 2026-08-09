-- Driver: manual audio check for the wild battle intro cry (#303).
-- pokered SlidePlayerAndEnemySilhouettesOnScreen (engine/battle/core.asm)
-- ends in PrintBeginningBattleText (engine/battle/common_text.asm:10-19),
-- which calls PlayCry then PrintText, so the cry lands with the "Wild X
-- appeared!" box.  No POKEPORT_SPEED: audio has its own real-time clock.
--   POKEPORT_DRIVER=tests/drivers/wild_cry_bug303_test.lua POKEPORT_IDENTITY=bug303 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  -- Route 1 is all PIDGEY and RATTATA, whose cries are short and distinct.
  -- (10, 6) is the west end of the northern grass patch, read out of
  -- data/generated/maps.lua and re-derived below if a map edit moves it.
  local MAP = "ROUTE_1"
  local GRASS = { x = 10, y = 6 }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Sound.playCry reads data.audio.cries[species]; a missing key is a silent
  -- no-op with no error, which sounds exactly like the bug
  local cries = game.data.audio and game.data.audio.cries
  check("data.audio.cries resolves", cries ~= nil)
  local encounters = game.data.encounters and game.data.encounters[MAP]
  local slots = encounters and encounters.grass and encounters.grass.slots
  local species = {}
  for _, slot in ipairs(slots or {}) do
    local id = slot.species
    if type(id) == "string" and not species[id] then
      species[id] = true
      species[#species + 1] = id
    end
  end
  check(MAP .. " has a wild encounter table", #species > 0)
  local missing = {}
  for _, id in ipairs(species) do
    if not (cries and cries[id]) then missing[#missing + 1] = id end
  end
  check("every " .. MAP .. " species has a cry sample", #missing == 0)
  if #missing > 0 then
    U.log("  species with no cry:", table.concat(missing, ", "))
  end
  U.log("  " .. MAP .. " wild species:", table.concat(species, ", "))

  local vol = game.save.options and game.save.options.sfxVol
  U.log("audio device present:", love.audio ~= nil,
        "  SFX VOL (0-7):", tostring(vol))
  if not love.audio or vol == 0 then
    U.log("WARNING: sound output is off, so nothing below will be audible;",
          "raise SFX VOL in OPTION first")
  end

  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "SQUIRTLE", 12))
    U.log("party was empty; added a level 12 SQUIRTLE")
  end

  U.teleport(game, MAP, GRASS.x, GRASS.y, "up")
  U.wait(10)

  -- if a map edit or a mod turns that cell to stone no encounter can ever
  -- roll, which looks exactly like a broken fix; sweep for a real one
  local function firstGrassCell(map)
    for y = 0, (map.heightCells or 0) - 1 do
      for x = 0, (map.widthCells or 0) - 1 do
        if map:isGrassCell(x, y) and map:isWalkableCell(x, y) then
          return x, y
        end
      end
    end
  end

  local ow = game.overworld
  if ow and not ow.map:isGrassCell(ow.player.cellX, ow.player.cellY) then
    local gx, gy = firstGrassCell(ow.map)
    if gx then
      U.log(("(%d, %d) is not grass; standing on"):format(GRASS.x, GRASS.y),
            gx, gy)
      U.teleport(game, MAP, gx, gy, "up")
      U.wait(10)
    else
      U.log("FAIL no walkable grass cell found on " .. MAP)
    end
  end
  U.log("standing on", MAP, "at",
        game.overworld and game.overworld.player.cellX,
        game.overworld and game.overworld.player.cellY)

  -- the moment lasts about a second and cannot be replayed, so say what to
  -- listen for before the encounter rolls, not after
  U.log("An encounter is about to be walked into for you.  The cry should")
  U.log("sound the instant the silhouettes land and the \"Wild X appeared!\"")
  U.log("box opens (#303 fired it mid-slide).  The HP bar only arrives once")
  U.log("you clear that box, which is correct.")
  U.log("walking into the grass in 3 seconds, ears up")
  U.wait(180)

  -- ---- walk until the encounter rolls ------------------------------------
  local BattleState = require("src.battle.BattleState")
  local function liveBattle()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == BattleState then return s end
    end
    return nil
  end

  -- pace back and forth; each step gets its own encounter roll
  local DIRS = { "up", "down", "left", "right" }
  local battle
  for i = 1, 400 do
    U.hold(game, DIRS[(i - 1) % #DIRS + 1], 10)
    battle = liveBattle()
    if battle then break end
  end

  check("a wild battle started", battle ~= nil)
  if battle then
    U.log("   encounter:", battle.enemy and battle.enemy.mon
          and battle.enemy.mon.species, "at level",
          battle.enemy and battle.enemy.mon and battle.enemy.mon.level)
    check("it is a wild battle (trainers cry at a different point)",
          battle.kind ~= "trainer")
  else
    U.log("no encounter after 400 steps -- walk into the grass yourself")
  end

  -- hand off, then stay out of the way
  U.log("Controls are yours; run from the battle and walk back into the")
  U.log("grass to hear it again.")

  while true do
    coroutine.yield()
  end
end
