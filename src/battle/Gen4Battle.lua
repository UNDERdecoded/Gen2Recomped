-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/battle/Gen4Battle.lua -- WHERE A SINNOH BATTLE HAPPENS.
--
-- Platinum's battle screen does not exist in this engine yet: `src/battle/`
-- has BattleState, Damage, Gen3Battle and the rulesets, and BattleState has a
-- Gen 3 layout arm and nothing for Gen 4, so a Platinum fight runs on the GAME
-- BOY screen -- name-and-level boxes, the two-panel FIGHT menu, blank paper.
--
-- This file answers three things: WHICH BACKGROUND AND WHICH TWO PLATFORMS
-- this battle is fought on, WHERE EVERYTHING STANDS, and -- as of this pass --
-- it DRAWS the field and the two battlers. Every number is read out of
-- pokeplatinum and, where two tables state the same thing, checked against
-- both.
--
-- WHAT IS STILL THE ENGINE'S OWN, AND SAID HERE SO IT IS NOT MISTAKEN FOR
-- PLATINUM'S: the text/menu area, and the two GAUGE BARS inside a healthbox.
-- The healthbox FRAME is Platinum's now -- see the healthbox block below for
-- where its size and origin come from -- and the name, level and HP read out of
-- the battler. The HP and EXP bars are not drawn yet, for a reason given there.
--
-- THE PLATFORM POSITIONS ARE NOT THE SPRITE TEMPLATES, which is the trap this
-- file exists to have already walked into. `sTerrainSpriteTemplates`
-- (terrain.c) says `{x = 336, y = 136}` for the player's side and
-- `{x = -80, y = 88}` for the foe's -- on a 256-pixel screen, both entirely
-- OFF it. Those are the off-screen START of the intro slide. The settled
-- positions are set outright in `battle_display.c`:
--
--     ManagedSprite_SetPositionXY(terrain, 24 * 8, 8 * 11)   -- enemy (192, 88)
--     ManagedSprite_SetPositionXY(terrain, 64, 128 + 8)      -- player (64, 136)
--
-- and the two agree in a way that could not be a coincidence: the y values are
-- IDENTICAL to the templates' (only x slides), and both sides travel exactly
-- 34 steps of 8 pixels -- (336 - 64) / 8 and (192 - -80) / 8. That symmetry is
-- what says the reading is right, and `tools/gen4_battlescene_check.lua`
-- asserts it rather than leaving it as a remark.

local Assets = require("src.render.Assets")
local Timing = require("src.core.Timing")

local Gen4Battle = {}

-- Platinum fights on the DS's own screen, not the Game Boy's 160x144.
Gen4Battle.WIDTH, Gen4Battle.HEIGHT = 256, 192

-- Widescreen keeps Platinum's 192-pixel-tall composition and only grows the
-- horizontal surface. The extractor's battle backdrop is already 512 pixels
-- wide, so this reveals real cartridge art instead of stretching 256 pixels.
function Gen4Battle.surfaceWidth(pw, ph, fill, maxWidth)
  local least = Gen4Battle.WIDTH
  local most = math.floor(tonumber(maxWidth) or 512)
  if most < least then most = least end
  pw, ph = tonumber(pw), tonumber(ph)
  if not (pw and ph and pw > 0 and ph > 0) then return least end
  local want
  if fill then
    want = math.floor(Gen4Battle.HEIGHT * pw / ph / 8 + 0.5) * 8
  else
    local s = math.max(1, math.floor(ph / Gen4Battle.HEIGHT))
    want = math.floor(pw / s / 8) * 8
  end
  return math.max(least, math.min(most, want))
end

function Gen4Battle.width(battle)
  local fn = battle and battle.gen4SurfaceWidth
  if type(fn) ~= "function" then return Gen4Battle.WIDTH end
  local ok, w = pcall(fn, battle)
  if not (ok and type(w) == "number" and w >= Gen4Battle.WIDTH) then
    return Gen4Battle.WIDTH
  end
  return math.floor(w / 8) * 8
end

function Gen4Battle.extra(battle)
  return Gen4Battle.width(battle) - Gen4Battle.WIDTH
end

-- Player-side field objects stay attached to the left half; enemy-side ones
-- stay attached to the right. At 256px this returns the cartridge coordinates
-- byte-for-byte.
function Gen4Battle.battlerPos(battle, slot)
  local p = Gen4Battle.BATTLER_POS[slot]
  if not p then return nil end
  local shift = (slot == 1 or slot == 3 or slot == 5) and Gen4Battle.extra(battle) or 0
  return { x = p.x + shift, y = p.y }
end

function Gen4Battle.healthboxPos(battle, slot)
  local p = Gen4Battle.HEALTHBOX_POS[slot]
  if not p then return nil end
  local shift = (slot == 0 or slot == 2 or slot == 4) and Gen4Battle.extra(battle) or 0
  return { x = p.x + shift, y = p.y }
end

-- ---------------------------------------------------------------------------
-- The two enumerations, 0-based, from generated/battle_backgrounds.txt and
-- generated/battle_terrains.txt. They are NOT the same list and do not line up
-- past the first entry -- BACKGROUND_CITY is 2 and TERRAIN_GRASS is 2 -- which
-- is the whole reason `TERRAIN_FOR_BACKGROUND` below exists as a table.
-- ---------------------------------------------------------------------------

Gen4Battle.BACKGROUNDS = {
  [0] = "plain", "water", "city", "forest", "mountain", "snow",
  "indoors_1", "indoors_2", "indoors_3", "cave_1", "cave_2", "cave_3",
  "aaron", "bertha", "flint", "lucian", "cynthia", "distortion_world",
  "battle_tower", "battle_factory", "battle_arcade", "battle_castle",
  "battle_hall",
}

Gen4Battle.TERRAINS = {
  [0] = "plain", "sand", "grass", "puddle", "mountain", "cave", "snow",
  "water", "ice", "building", "great_marsh", "bridge",
  "aaron", "bertha", "flint", "lucian", "cynthia", "distortion_world",
  "battle_tower", "battle_factory", "battle_arcade", "battle_castle",
  "battle_hall", "giratina",
}

-- `sTerrainForBackground` (field_battle_data_transfer.c), transcribed by name
-- rather than by position so a mis-transcription reads as a wrong WORD rather
-- than as a plausible number. The three INDOORS backgrounds and the CITY all
-- land on BUILDING, and the three CAVES all land on CAVE -- 23 backgrounds,
-- 18 distinct terrains.
Gen4Battle.TERRAIN_FOR_BACKGROUND = {
  plain = "plain", water = "water", city = "building", forest = "grass",
  mountain = "mountain", snow = "snow",
  indoors_1 = "building", indoors_2 = "building", indoors_3 = "building",
  cave_1 = "cave", cave_2 = "cave", cave_3 = "cave",
  aaron = "aaron", bertha = "bertha", flint = "flint", lucian = "lucian",
  cynthia = "cynthia", distortion_world = "distortion_world",
  battle_tower = "battle_tower", battle_factory = "battle_factory",
  battle_arcade = "battle_arcade", battle_castle = "battle_castle",
  battle_hall = "battle_hall",
}

-- ---------------------------------------------------------------------------
-- THE TILE UNDER THE PLAYER DECIDES THE TERRAIN, NOT THE MAP.
--
-- `CalcTerrain` asks the behaviour byte first and only falls through to the
-- map's background when none of these match. So a battle in the tall grass on
-- a CITY map is fought on grass, and the same trainer on the paving beside it
-- is fought on a building floor.
--
-- Values from include/constants/field/map_tile_behaviors.h. They are worth
-- writing down as numbers because they are NOT contiguous by kind: snow is
-- 161,162,163 and 168, with the three MUD values sitting between them.
-- ---------------------------------------------------------------------------

local TALL_GRASS, VERY_TALL_GRASS = 2, 3
local CAVE_FLOOR = 8
local ICE, SAND = 32, 33
local SNOW = { [161] = true, [162] = true, [163] = true, [168] = true }
local MUD  = { [164] = true, [165] = true, [166] = true, [167] = true }

-- `TileBehavior_IsSurfable` reads a FLAG rather than comparing values, and the
-- sixteen behaviours carrying it are not a range: the two bike bridges and the
-- ordinary bridge over water are surfable at 115, 120 and 124, a long way from
-- the water block at 16..21. Listed rather than bounded for that reason.
local SURFABLE = {
  [16] = true, [17] = true, [18] = true, [19] = true, [20] = true,
  [21] = true, [25] = true, [34] = true, [42] = true,
  [80] = true, [81] = true, [82] = true, [83] = true,
  [115] = true, [120] = true, [124] = true,
}

-- The behaviour byte under the player, or nil.
--
-- A GEN 4 MAP STORES THE BEHAVIOUR IN THE CELL ITSELF. `Gen4Maps.mapDef`
-- writes `word % 256` -- the behaviour byte -- into the same slot Gen 1-3 put
-- a block id in, so `Map:blockAt` IS the behaviour here and the Gen 2/3
-- `Map:cellBehaviour` (which goes through a tileset's collision table) does
-- not answer at all. That is why this does not call it.
function Gen4Battle.behaviourUnder(game)
  local ow = game and game.overworld
  local map = ow and ow.map
  if not (map and map.blockAt) then return nil end
  local player = ow.player
  local cx = player and (player.cellX or player.x)
  local cy = player and (player.cellY or player.y)
  if not (cx and cy) then return nil end
  local ok, value = pcall(map.blockAt, map, cx, cy)
  if not (ok and type(value) == "number") then return nil end
  return value
end

-- The background this map fights on, as a NAME.
--
-- `SetBackgroundAndTerrain`: the map header's own byte, overridden to WATER
-- for the whole time the player is surfing. Measured over the cartridge's 593
-- headers, every one carries a value in 0..17 -- the five Frontier backgrounds
-- never appear on a map because those battles set their own.
function Gen4Battle.backgroundFor(game)
  local ow = game and game.overworld
  local player = ow and ow.player
  if player and player.surfing then return "water" end
  local def = ow and ow.map and ow.map.def
  local index = def and tonumber(def.battleBackground)
  return Gen4Battle.BACKGROUNDS[index or 0] or "plain"
end

-- ...and the terrain, as a NAME. `CalcTerrain`, in its own order: the first
-- match wins and surfable is asked LAST of the tile tests, so a bridge over
-- water that is also cave floor would be a cave. (None is; the order is the
-- cartridge's and is kept rather than sorted.)
function Gen4Battle.terrainFor(game)
  local b = Gen4Battle.behaviourUnder(game)
  if b then
    if b == ICE then return "ice" end
    if b == TALL_GRASS or b == VERY_TALL_GRASS then return "grass" end
    if b == SAND then return "sand" end
    if SNOW[b] then return "snow" end
    if MUD[b] then return "great_marsh" end
    if b == CAVE_FLOOR then return "cave" end
    if SURFABLE[b] then return "water" end
  end
  local background = Gen4Battle.backgroundFor(game)
  return Gen4Battle.TERRAIN_FOR_BACKGROUND[background] or "plain"
end

-- ---------------------------------------------------------------------------
-- TIME OF DAY, AND ONLY FOR SIX OF THE TWENTY-THREE.
--
-- `BattleSystem_GetBackgroundTimeOffset` switches on the BACKGROUND first:
-- PLAIN, WATER, CITY, FOREST, MOUNTAIN and SNOW take a real offset and
-- EVERYTHING ELSE IS ALWAYS 0. An indoor room does not get darker at night,
-- which is also why the extractor found the indoor palettes listing one "all"
-- entry three times. For the six that do:
--     MORNING, DAY      -> day        TWILIGHT -> evening
--     NIGHT, LATE_NIGHT -> night
--
-- WHAT THIS ENGINE CAN ANSWER: its clock has Gen 2's THREE bands
-- (MORNING / DAY / NITE), not Platinum's five, so TWILIGHT has nothing to come
-- from and `evening` is unreachable until a Gen 4 clock exists. Said here
-- rather than approximated: inventing a twilight window would put the wrong
-- palette on the six outdoor backgrounds for however many hours it guessed.
-- ---------------------------------------------------------------------------

local TIMED_BACKGROUND = {
  plain = true, water = true, city = true, forest = true,
  mountain = true, snow = true,
}

function Gen4Battle.timeOfDay(game, background)
  background = background or Gen4Battle.backgroundFor(game)
  if not TIMED_BACKGROUND[background] then return "day" end
  local ow = game and game.overworld
  local tod = ow and (ow.objectTod or ow.tod)
  if tod == "NITE" or tod == "NIGHT" then return "night" end
  return "day"
end

-- ---------------------------------------------------------------------------
-- The pictures, out of `gen4_graphics`, which the graphics stage already wrote
-- (69 backgrounds = 23 x three times of day; 88 platform sheets keyed
-- <art>_<side>). Nothing here extracts anything.
-- ---------------------------------------------------------------------------

local function image(path)
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  return ok and img or nil
end

local function graphics(battle)
  local data = battle and (battle.data or (battle.game and battle.game.data))
  return data and data.gen4_graphics or nil
end

-- backdrop(battle) -> image, key
--
-- 512x256, because the cartridge scrolls it; the visible screen is the LEFT
-- 256x192 of it and the caller decides how much of the rest it wants.
function Gen4Battle.backdrop(battle)
  local gfx = graphics(battle)
  local rows = gfx and gfx.backgrounds
  if not rows then return nil end
  local game = battle and battle.game
  local background = Gen4Battle.backgroundFor(game)
  local key = background .. "_" .. Gen4Battle.timeOfDay(game, background)
  -- `SetBgGrayscale` swaps the WHOLE picture for its grey twin, which the graphics
  -- stage wrote beside it. Falls back to the colour one rather than declining, so a
  -- cache imported before that stage plays those five moves in colour instead of
  -- playing them on black.
  if Gen4Battle.grayscale(battle) then
    local grey = rows[key .. "_gray"] or rows[background .. "_day_gray"]
    if grey then return image(grey.path), key .. "_gray" end
  end
  local row = rows[key] or rows[background .. "_day"]
  if not row then return nil end
  return image(row.path), key
end

-- grayscale(battle) -> is the background grey right now
--
-- Only the BACKDROP. The Pokemon and the terrain platforms are OBJs in a different
-- palette buffer and the cartridge does not touch them; the switched effect
-- background is sub-palette 9, outside the 128 entries it greys.
function Gen4Battle.grayscale(battle)
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not (player and player.bgGrayscale) then return false end
  local got, grey = pcall(player.bgGrayscale, player)
  return got and grey == true
end

-- effectArt(battle, id, variant) -> image, row
--
-- The MOVE ANIMATION background, which is a different set of pictures from the
-- backdrops above even though they live in the same archive: 58 of them, each with
-- a normal, a mirrored and a contest arrangement. The graphics stage writes 81
-- distinct images and points all 174 keys at them.
function Gen4Battle.effectArt(battle, id, variant)
  local gfx = graphics(battle)
  local rows = gfx and gfx.effects
  if not (rows and id) then return nil end
  local row = rows[("%d_%s"):format(id, variant or "normal")]
    or rows[("%d_normal"):format(id)]
  if not row then return nil end
  return image(row.path), row
end

-- backdropOffset(battle) -> dx, dy
--
-- WHY THE BACKDROP MOVES AT ALL. `shakebg` names a LAYER, and the layer it names
-- 41 times out of 42 is the effect layer -- which is the layer the ordinary battle
-- backdrop lives on when no move has switched it. 22 of those 42 calls happen with
-- no switch up, so what they shake is this picture. The platforms and the Pokemon
-- are on other layers and do not move with it, which is why this is an offset on
-- one draw rather than a translate around the whole field.
function Gen4Battle.backdropOffset(battle)
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not (player and player.bgLayerState) then return 0, 0 end
  local got, st = pcall(player.bgLayerState, player)
  if not (got and st) then return 0, 0 end
  -- Once a switch is up the effect layer is the switched picture, and the shake
  -- belongs to that instead.
  if st.id then return 0, 0 end
  return st.offsetX or 0, st.offsetY or 0
end

-- platforms(battle) -> playerImage, enemyImage, terrainName
--
-- The player's is 256x32 and the foe's is 128x64 -- both from the SAME two
-- cell banks for all 24 terrains, which is why every platform sheet in the
-- cartridge is exactly 128 tiles.
function Gen4Battle.platforms(battle)
  local gfx = graphics(battle)
  local rows = gfx and gfx.terrain
  if not rows then return nil end
  local game = battle and battle.game
  local terrain = Gen4Battle.terrainFor(game)
  -- WHICH ONE OF THE THREE, and it used to be whichever `pairs` reached first.
  --
  -- The stage writes a row per terrain PER TIME OF DAY -- `grass_player_day`,
  -- `_evening`, `_night` -- and this walked the table in hash order and took
  -- the first row whose terrain matched. So the platform under the player was
  -- an arbitrary one of the three, it could differ between the two sides, and
  -- it could differ between two runs of the same build.
  --
  -- The backdrop above already asks the right question (`<name>_<time>`, then
  -- `<name>_day`); this asks it the same way, which also means the platform and
  -- the ground behind it are lit for the same hour. The bare `<name>_<side>`
  -- fallback is for the nine terrains the stage marks timeless -- the caves,
  -- the league rooms and the Frontier, which have one sheet each.
  local time = Gen4Battle.timeOfDay(game, Gen4Battle.backgroundFor(game))
  local function side(which)
    local stem = terrain .. "_" .. which
    local row = rows[stem .. "_" .. time] or rows[stem .. "_day"] or rows[stem]
    if not row then
      -- A terrain whose art is filed under another name still has a row; fall
      -- back to the scan rather than drawing no platform at all.
      for _, r in pairs(rows) do
        if r.terrain ~= nil and r.side == which
           and Gen4Battle.TERRAINS[tonumber(r.terrain)] == terrain then
          row = r
          break
        end
      end
    end
    return row and image(row.path) or nil
  end
  return side("player"), side("enemy"), terrain
end

-- ---------------------------------------------------------------------------
-- WHERE EVERYTHING STANDS, on the DS's own 256x192.
--
-- All of these are SPRITE CENTRES, because the cartridge's cells are centred
-- (see Gen4Cells: OAM rectangles at signed offsets from a centre). A caller
-- drawing a w x h picture puts its top-left at (x - w/2, y - h/2).
--
-- THE SIX BATTLER POSITIONS ARE STATED TWICE AND THE TWO AGREE.
-- `BATTLER_POS_*` in include/constants/battle/battle_anim.h feeds
-- `sBattleAnimBattlerPositions`, and `gBattlerEncounterX` in
-- ov12_022380BC.c lists the same six x values independently:
-- 64, 192, 40, 216, 80, 176 both times. Two tables written for different
-- systems agreeing on all six is worth more than either on its own.
-- ---------------------------------------------------------------------------

-- battler type -> { x, y }.  0/1 are the singles pair; 2..5 are the doubles
-- slots, and note the foe's two are NOT level with each other (50 and 42) --
-- the far slot sits higher up the field.
Gen4Battle.BATTLER_POS = {
  [0] = { x = 64,  y = 112 },   -- solo player
  [1] = { x = 192, y = 48  },   -- solo enemy
  [2] = { x = 40,  y = 112 },   -- player slot 1
  [3] = { x = 216, y = 50  },   -- enemy slot 1
  [4] = { x = 80,  y = 120 },   -- player slot 2
  [5] = { x = 176, y = 42  },   -- enemy slot 2
}

-- ...and where each one's healthbox sits (healthbox.c's own #defines, which
-- are written as offsets from the two solo positions and are resolved here).
-- The player's doubles boxes straddle the solo one at -13 and +16; the foe's
-- at -20 and +9.
Gen4Battle.HEALTHBOX_POS = {
  [0] = { x = 192, y = 116 },   -- solo player
  [1] = { x = 58,  y = 36  },   -- solo enemy
  [2] = { x = 192, y = 103 },   -- player slot 1
  [3] = { x = 64,  y = 16  },   -- enemy slot 1
  [4] = { x = 198, y = 132 },   -- player slot 2
  [5] = { x = 58,  y = 45  },   -- enemy slot 2
}

-- The two platforms, settled.  `PLATFORM_START` is where each one begins the
-- intro at and `PLATFORM_STEP` is how far it travels a frame; y never moves.
Gen4Battle.PLATFORM_POS   = { player = { x = 64, y = 136 },
                              enemy  = { x = 192, y = 88 } }
Gen4Battle.PLATFORM_START = { player = 336, enemy = -80 }
Gen4Battle.PLATFORM_STEP  = 8

-- The sizes the graphics stage wrote, kept here so a caller can place a
-- platform without having loaded its picture: ALL 24 TERRAINS SHARE TWO CELL
-- BANKS, which is why every platform sheet in the cartridge is 128 tiles.
Gen4Battle.PLATFORM_SIZE = { player = { w = 256, h = 32 },
                             enemy  = { w = 128, h = 64 } }

-- Where the two trainers walk in from (`gSlideTrainerInCoords`) -- the OPPOSITE
-- side from the platform that will be under them, which is why they cross the
-- field on the way in.
Gen4Battle.TRAINER_START = { player = { x = -80, y = 112 },
                             enemy  = { x = 336, y = 50 } }

-- How far a platform has left to travel at step `n` of the intro, or 0 once it
-- has arrived.  Written as arithmetic rather than a table because the two
-- sides take the SAME number of steps and stating that once is what makes the
-- symmetry checkable.
function Gen4Battle.platformSlideSteps()
  -- floor()ed because Lua's `/` is float division in every version this
  -- engine runs on, and a step COUNT that prints as 34.0 reads as a rounding
  -- problem it does not have.
  local p = math.floor((Gen4Battle.PLATFORM_START.player
                        - Gen4Battle.PLATFORM_POS.player.x)
                       / Gen4Battle.PLATFORM_STEP)
  local e = math.floor((Gen4Battle.PLATFORM_POS.enemy.x
                        - Gen4Battle.PLATFORM_START.enemy)
                       / Gen4Battle.PLATFORM_STEP)
  return p, e
end

-- platformAt(side, step) -> x, y
function Gen4Battle.platformAt(side, step)
  local settled = Gen4Battle.PLATFORM_POS[side]
  if not settled then return nil end
  local total = select(side == "player" and 1 or 2,
                       Gen4Battle.platformSlideSteps())
  local left = math.max(0, total - (tonumber(step) or total))
  local dx = left * Gen4Battle.PLATFORM_STEP
  if side == "player" then return settled.x + dx, settled.y end
  return settled.x - dx, settled.y
end

-- platformSlideElapsed(battle, side) -> how many slide steps have ALREADY run.
--
-- THE TWO COUNTERS RUN OPPOSITE WAYS AND THAT IS THE WHOLE OF THIS FUNCTION.
-- `platformAt` takes steps ELAPSED -- 0 is off-screen, `platformSlideSteps()`
-- is settled -- because that is what its own name promises and what
-- `tools/gen4_battlescene_check.lua` asserts.  `BattleState.introSlide` is
-- frames REMAINING: `startBattle` sets it to `Timing.BATTLE_SLIDE_IN_FRAMES`
-- and `update` counts it DOWN to 0, which is why `drawBattlerPic` can
-- multiply it straight by `BATTLE_SLIDE_PX_PER_FRAME` to get an offset that
-- shrinks to nothing.  Converting between them is this function's only job.
--
-- Reported from play: "the locations of the land the pokemon are on in battle
-- still arent right".  `drawField` had been passing `introSlide` in RAW, so a
-- settled battle -- introSlide 0, which is every frame after the first 72 and
-- every frame of a save resumed mid-battle -- asked for step 0 and got both
-- platforms parked where they BEGIN the intro: the player's 256-wide slab
-- centred at 336, showing only x 208..256 in the bottom-right corner, and the
-- foe's centred at -80, spanning -144..-16, entirely off the left edge.  That
-- is the corner sliver under nothing and the foe standing on nothing.  During
-- the intro it was inverted: 36 frames remaining asked for step 36, past the
-- 34-step total, so the platforms sat SETTLED while the battlers were still
-- travelling.
--
-- A battle with no counter at all is SETTLED, not at step zero -- a headless
-- caller, a resumed save, and every frame after the intro all land here.
function Gen4Battle.platformSlideElapsed(battle, side)
  local total = select(side == "player" and 1 or 2,
                       Gen4Battle.platformSlideSteps())
  local frames = tonumber(battle and battle.introSlide)
  if not frames or frames <= 0 then return total end
  local all = tonumber(Timing.BATTLE_SLIDE_IN_FRAMES)
  if not all or all <= 0 then return total end
  if frames >= all then return 0 end
  -- +0.5 to round rather than truncate: the platform should be at its settled
  -- x on the frame the battlers arrive, and flooring leaves it one step short.
  return math.floor(total * (all - frames) / all + 0.5)
end

-- ---------------------------------------------------------------------------
-- DRAWING
-- ---------------------------------------------------------------------------

-- A centred sprite's top-left, which is the conversion every draw below needs:
-- the cartridge's positions are centres and love.graphics.draw takes a corner.
local function corner(cx, cy, image)
  if not image then return cx, cy end
  return cx - image:getWidth() / 2, cy - image:getHeight() / 2
end

-- HOW FAR DOWN A SPECIES' PICTURE SITS IN ITS OWN FRAME.
--
-- Reported from play: "the enemy pokemon is standing a bit too high".  It was,
-- and only the enemy -- the player's back sprite looked planted.
--
-- Every battle sprite is an 80x80 frame and the Pokemon does not fill it.
-- MEASURED on the extracted PNGs: Piplup's front has 23 empty rows under it,
-- Starly's 20, and Chimchar's BACK only 8.  Drawn centred on the frame, a
-- front sprite's visible feet therefore land about fifteen pixels higher than
-- a back sprite's -- which is the gap, and why it showed on one side only.
--
-- THE CARTRIDGE STATES THE CORRECTION and the port already extracts it:
-- `BoxPokemon_SpriteYOffset` reads `poketool/pokegra/height.narc`, and the
-- import writes it as `gen4_species_sprites.species[id].frontOffset` /
-- `.backOffset`.  NOTHING IN `src/` HAD EVER READ EITHER.
--
-- AND THE TWO SOURCES AGREE EXACTLY, which is what makes this a derivation
-- rather than a nudge: the cartridge's offset for Piplup is 23 and its PNG has
-- 23 empty rows; Starly 20 and 20; Chimchar's back 8 and 8.  Three species,
-- two independent sources, no discrepancy.
--
-- THE SIGN IS THE CARTRIDGE'S TOO.  `send_phase.c` positions with
-- `y = (100 - 20) + BoxPokemon_SpriteYOffset(...)` -- it ADDS, so a bigger
-- offset pushes the picture DOWN, which is what a mon with more empty space
-- beneath it needs.
function Gen4Battle.spriteYOffset(battle, battler)
  local mon = battler and battler.mon
  local id = mon and tonumber(mon.species)
  if not id then return 0 end
  local data = (battle and (battle.data or (battle.game or {}).data)) or {}
  local rec = ((data.gen4_species_sprites or {}).species or {})[id]
  if type(rec) ~= "table" then return 0 end
  local back = (battle and battler == battle.player)
  local n = tonumber(back and rec.backOffset or rec.frontOffset)
  return n or 0
end

-- The field: the backdrop, then the two platforms over it.
--
-- THE BACKDROP IS 512 WIDE AND THE SCREEN IS 256. The cartridge scrolls it and
-- the visible screen is the LEFT half; drawing it at 0 is therefore the whole
-- of what a still frame needs, and the right half is there for the scroll this
-- port does not do yet.
function Gen4Battle.drawField(battle)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local ground = Gen4Battle.backdrop(battle)
  if ground then
    -- `shakebg` aimed at the effect layer with no switch up moves THIS, because
    -- outside a switch the effect layer is where the backdrop lives. Wrapped, for
    -- the same reason the switched layer is.
    local sx, sy = Gen4Battle.backdropOffset(battle)
    if sx == 0 and sy == 0 then
      g.draw(ground, 0, 0)
    else
      local gw, gh = ground:getWidth(), ground:getHeight()
      local ox, oy = -(sx % gw), -(sy % gh)
      for _, dx in ipairs({ 0, gw }) do
        for _, dy in ipairs({ 0, gh }) do
          if ox + dx < Gen4Battle.width(battle) and oy + dy < Gen4Battle.HEIGHT then
            g.draw(ground, ox + dx, oy + dy)
          end
        end
      end
    end
  else
    -- No backdrop in this cache: black rather than the Game Boy's white paper,
    -- because every piece of Gen 4 art on top of it is drawn for a dark field
    -- and white would show as a bright border round each platform.
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, Gen4Battle.width(battle), Gen4Battle.HEIGHT)
    g.setColor(1, 1, 1, 1)
  end

  local player, enemy = Gen4Battle.platforms(battle)
  -- The intro slides them in from off-screen.  `platformSlideElapsed` is what
  -- turns `BattleState`'s frames-REMAINING counter into the steps-ELAPSED
  -- count `platformAt` takes; passing `introSlide` in raw is what had parked
  -- both platforms off-screen on every settled frame.  Read its comment before
  -- touching either side of this.
  if enemy then
    local ex, ey = Gen4Battle.platformAt(
      "enemy", Gen4Battle.platformSlideElapsed(battle, "enemy"))
    ex = ex + Gen4Battle.extra(battle)
    g.draw(enemy, corner(ex, ey, enemy))
  end
  if player then
    local px, py = Gen4Battle.platformAt(
      "player", Gen4Battle.platformSlideElapsed(battle, "player"))
    g.draw(player, corner(px, py, player))
  end
end

-- IS THE ANIMATION HOLDING THIS POKEMON OFF THE FIELD.
--
-- `Func_HideBattler` (40) is 50 calls over 16 programs and UNTIL NOW IT DREW
-- NOTHING: the animator tracked `hidden` per side and `Player:monHidden` had no
-- caller anywhere in the port, so every move that takes a battler off the field
-- left the Pokemon standing there. Measured over the whole corpus, both
-- directions: 534 frames in which a side should not have been on screen.
--
-- ASKED HERE RATHER THAN IN `BattleState:drawBattlerPic`, which Kanto, Johto and
-- Hoenn also draw through -- a Gen 4 question belongs on the Gen 4 screen.
-- ballAbsorb(battle, battler) -> scale, blend, or nil.
--
-- Nil for every battler a thrown ball is not swallowing, which is all of them
-- most of the time, so the ordinary draw path is the default rather than a
-- special case of the absorb.
function Gen4Battle.ballAbsorb(battle, battler)
  local ball = battle and battle.gen4Ball
  if not (ball and ball.absorbFor and battler) then return nil end
  local ok, scale, blend = pcall(ball.absorbFor, ball, battler == battle.player)
  if ok and scale then return scale, blend or 0 end
  return nil
end

function Gen4Battle.battlerHidden(battle, battler)
  -- THE PLAYER'S POKEMON IS STILL IN ITS BALL while the trainer's back is up.
  --
  -- `showPlayerBack` is the engine's own flag for "the first Pokemon has not
  -- been sent out yet", and the Gen 3 path already honours it -- this one did
  -- not, so Sinnoh drew the Pokemon through the whole intro and, once the
  -- trainer was drawn too, drew BOTH at once standing in the same place.
  if battle and battle.showPlayerBack and battler and battler == battle.player then
    return true
  end
  -- ...AND THE FOE'S, while its trainer stands on the platform or the ball is
  -- on its way: the same three flags the shared pic layer honours
  -- (showEnemyTrainer, enemySendingOut, enemyHidden).  Without them a trainer
  -- battle opened with the Pokemon already out and no trainer at all.
  if battle and battler and battler == battle.enemy
     and (battle.showEnemyTrainer or battle.enemySendingOut or battle.enemyHidden) then
    return true
  end

  -- A POKEMON INSIDE A THROWN BALL IS NOT ON THE FIELD.  Asked through the
  -- same seam a move animation uses, rather than a second hiding rule.
  local ball = battle and battle.gen4Ball
  if ball and ball.hidesMon and battler then
    local okBall, hid = pcall(ball.hidesMon, ball, battler == battle.player)
    if okBall and hid then return true end
  end
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not (player and player.monHidden and battler) then return false end
  local got, hidden = pcall(player.monHidden, player, battler == battle.player)
  return got and hidden == true
end

-- WHERE THE HARDWARE WINDOW CUTS THIS POKEMON OFF, as a scissor height, or nil.
--
-- Dark Void's window IS the void: there is no hole drawn anywhere, the Pokemon is
-- simply not rendered below the window's top edge. `Player.MON_WINDOW` carries the
-- two rectangles and why an inside plane of BG0-3 against an outside plane that
-- also holds OBJ means "every sprite disappears in here".
--
-- A SINGLE SCISSOR IS EXACT, AND THAT IS MEASURED RATHER THAN HOPED. Both windows
-- run from their top edge to the bottom of the screen and each covers one half
-- horizontally, so for a battler whose picture lies INSIDE the window's x span
-- "inside the window" reduces to "below the top edge". An 80-wide Sinnoh picture
-- centred on 64 spans 24..104 and one centred on 192 spans 152..232, so neither
-- solo battler straddles either window's x edge and the two-draw case does not
-- arise -- the check asserts that rather than this comment being the argument.
-- A picture that DID straddle gets no clip at all: drawing a whole Pokemon is a
-- better failure than clipping the wrong half of it.
--
-- The scissor is in UI-surface units, which is what `Gen3RegionMap` and
-- `Gen3TitleFRLG` already scissor in, and the caller puts back whatever was set.
function Gen4Battle.monWindowClip(battle, pos, pic)
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not (player and player.monWindow and pos and pic and pic.getWidth) then
    return nil
  end
  local got, win = pcall(player.monWindow, player)
  if not (got and type(win) == "table" and win.top) then return nil end
  local half = pic:getWidth() / 2
  if (pos.x - half) < (win.left or 0) then return nil end
  if (pos.x + half) > (win.right or Gen4Battle.WIDTH) then return nil end
  return win.top
end

-- The two Pokemon, at the cartridge's own battler positions.
--
-- Drawn through `BattleState:drawBattlerPic` rather than by blitting here: that
-- method carries the grow-in scale, the hit shake, the squash and the rotate,
-- and a second draw path would have none of them. It takes a TOP-LEFT, which is
-- why `corner` exists.
-- THE TRAINER'S BACK, before the first Pokemon is out.
--
-- Item 7 of the play-test list: *"No trainer sprite in battle before the Pokemon
-- is sent out"*.  There was none, and it was NOT because the state machine was
-- missing: `showPlayerBack` arms correctly on a Sinnoh battle and the player's
-- Pokemon is correctly withheld while it is set.  This file simply had no
-- reference to a trainer back anywhere, so the player's side was empty.
--
-- Measured before it was written: rendered with the back picture injected as
-- the boy, injected as the girl, and not injected at all, all three frames came
-- out PIXEL-IDENTICAL -- which is what says the gap is the drawing rather than
-- only the data.
--
-- Placed by the same `corner` the battlers use, on the player's own slot, so
-- the trainer stands where the Pokemon it is about to send out will stand
-- rather than at a second set of coordinates that could drift from it.
function Gen4Battle.drawTrainerBack(battle)
  if not (battle and battle.showPlayerBack and battle.playerBackPic) then
    return false
  end
  local img = battle.picImage and battle:picImage(battle.playerBackPic)
             or battle.playerBackPic
  if not (img and img.getWidth) then return false end
  local pos = Gen4Battle.battlerPos(battle, 0)
  if not pos then return false end
  local g = love.graphics
  local x, y = corner(pos.x, pos.y, img)
  g.setColor(1, 1, 1, 1)
  g.draw(img, x, y)
  return true
end

-- THE OPPOSING TRAINER, on the foe's platform until the send-out and again
-- after the last Pokemon falls.  Reported from play: *"Trainer sprites are
-- missing from battle"* -- the shared pic layer has the branch, this layout
-- never called it, so a Sinnoh trainer battle opened on the Pokemon.  Placed by
-- the foe's own `corner`, as the player's back is by the player's, and slid by
-- the engine's own "foe" pic offset (the slide off before the send-out and back
-- on at the end).  A second trainer, when two walked up, stands on the second
-- foe's slot.
function Gen4Battle.drawEnemyTrainer(battle)
  if not (battle and battle.showEnemyTrainer and battle.trainerPic) then return false end
  local g = love.graphics
  local off = battle.picOffset and battle:picOffset("foe") or 0
  local function one(pic, slot)
    local img = battle.picImage and battle:picImage(pic) or pic
    if not (img and img.getWidth) then return false end
    local pos = Gen4Battle.battlerPos(battle, slot)
    if not pos then return false end
    local x, y = corner(pos.x, pos.y, img)
    g.setColor(1, 1, 1, 1)
    g.draw(img, x + off, y)
    return true
  end
  if battle.trainerPicB and battle.isDouble and battle:isDouble() then pcall(one, battle.trainerPicB, 3) end
  return one(battle.trainerPic, 1)
end

function Gen4Battle.drawBattlers(battle)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  -- The foe first, so where the two overlap the player's Pokemon is in front --
  -- which is what standing nearer the camera means.
  local pairs_ = {
    { battler = battle.enemy,  pos = Gen4Battle.battlerPos(battle, 1) },
    { battler = battle.player, pos = Gen4Battle.battlerPos(battle, 0) },
  }
  for _, row in ipairs(pairs_) do
    local battler = row.battler
    if battler and not battler.fainted
       and not Gen4Battle.battlerHidden(battle, battler) then
      local pic = battle.battlerPic and battle:battlerPic(battler)
      if pic then
        local x, y = corner(row.pos.x, row.pos.y, pic)
        -- ...and then down by the species' own offset, BEFORE the three
        -- branches below, because each of them derives from this y.
        y = y + Gen4Battle.spriteYOffset(battle, battler)
        local clip = Gen4Battle.monWindowClip(battle, row.pos, pic)
        if clip then
          -- SAVE AND PUT BACK, rather than `setScissor()`: a screen that scissors
          -- for its own reasons must not have it cleared out from under it by a
          -- battler draw, and this runs inside whatever the caller had set.
          local sx, sy, sw, sh = g.getScissor()
          g.setScissor(0, 0, Gen4Battle.width(battle), math.max(0, math.floor(clip)))
          local drew, err = pcall(battle.drawBattlerPic, battle,
                                  battler, x, y, 1)
          if sx then g.setScissor(sx, sy, sw, sh) else g.setScissor() end
          if not drew then error(err) end
        else
          -- BEING DRAWN INTO A BALL, if one is open under this battler: the
          -- picture shrinks and its centre travels to the ball's, which is what
          -- makes it read as absorbed rather than as simply switched off.
          local scale, blend = Gen4Battle.ballAbsorb(battle, battler)
          if scale then
            local cx = x + pic:getWidth() / 2
            local cy = y + pic:getHeight() / 2
            local ball = battle.gen4Ball
            cx = cx + ((ball.x or cx) - cx) * blend
            cy = cy + ((ball.y or cy) - cy) * blend
            battle:drawBattlerPic(battler,
              cx - pic:getWidth() * scale / 2,
              cy - pic:getHeight() * scale / 2, scale)
          else
            battle:drawBattlerPic(battler, x, y, 1)
          end
        end
      end
    end
  end
  -- THE MOVE'S PARTICLES, IN FRONT OF BOTH POKEMON.
  --
  -- The cartridge draws them in a 3D scene and they genuinely pass behind a
  -- battler sometimes; this port draws them on top, which is the simplification
  -- rather than a claim the two look identical. Depth WITHIN the effect is
  -- honoured -- `System:draw` sorts by z, farthest first -- so a burst that
  -- layers over itself still layers correctly.
  Gen4Battle.drawParticles(battle)
  -- ...AND THE FLAT 2D SPRITES, on top of the particles. 32 of the 501 programs
  -- build one out of four separate archives and until now they drew nothing.
  Gen4Battle.drawCellActors(battle)
end

-- drawBackgroundFade(battle) -> true if anything was drawn
--
-- A FILLED RECTANGLE IS THE EXACT OPERATION, not an approximation of it.
-- `BlendColor(src, target, fraction)` is `src + ((target - src) * fraction >> 4)`
-- -- which is alpha compositing of `target` at `fraction/16` over `src`, the same
-- arithmetic LOVE does for a coloured quad. So the fade the cartridge performs by
-- rewriting sixteen palette entries is reproduced here by drawing one quad over
-- the pixels those entries coloured. What differs is only the rounding: the DS
-- floors a 5-bit channel, this blends in the display's own space.
--
-- 105 OF THE 501 MOVES REACH THIS, over 8,502 frames of the corpus. It was a
-- `hold` task until now -- the right number of frames, nothing drawn.
function Gen4Battle.drawBackgroundFade(battle)
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not (player and player.groupTint) then return false end
  local got, r, g, b, a = pcall(player.groupTint, player, "base")
  if not (got and a and a > 0) then return false end
  local gfx = love.graphics
  gfx.setColor(r or 0, g or 0, b or 0, a)
  gfx.rectangle("fill", 0, 0, Gen4Battle.width(battle), Gen4Battle.HEIGHT)
  gfx.setColor(1, 1, 1, 1)
  return true
end

-- THIS USED TO TINT THE PARTICLES AND THE 2D SPRITES, AND THAT WAS WRONG.
-- `fadebg` type 2 is `BATTLE_BG_PALETTE_FLAG_EFFECT`, which is BG palette SLOT 9 --
-- the sixteen colours of the move-animation background layer. It has nothing to do
-- with the OBJ palettes the particles and cell actors use. Both of the cartridge's
-- two type-2 calls are in program 87, both inside its `switchbg` window, and both
-- are fading the switched picture toward white and back.
--
-- So the tint moved to `drawEffectBackground`, where the layer is, and this is kept
-- as the identity so the two call sites below keep their shape rather than growing
-- a branch. Deleting it outright would be tidier and would also delete the record
-- of what it used to do.
local function effectFade(player, r, g, b)
  return r, g, b
end

-- drawEffectBackground(battle) -> true if anything was drawn
--
-- WHERE IT SITS. Between the field and the battlers, and that is the hardware's
-- order rather than a choice: `BATTLE_BG_EFFECT` is BG3, below every OBJ, and the
-- palette fade that blacks the field out is already drawn just above this.
--
-- THE TWO MODES ARE GENUINELY DIFFERENT OPERATIONS, which is why this is not one
-- draw with a varying alpha.
--
--   MODE_FADE (127 of the 129 calls) never blends the two layers at all. It fades
--   every palette but the effect one to black or white, overwrites the effect
--   layer with the new picture while that picture is also at the fade colour, and
--   then fades the effect palette back. So the field is simply BLACK underneath --
--   which the base group's tint quad has already drawn -- and this layer goes on
--   top opaquely, wearing its own tint.
--
--   MODE_BLEND (2 calls, both in program 433) cross-fades: EVA on the effect layer
--   rises while EVB on the base layer falls, and the DS adds the two weighted
--   planes. That is a dim of the field plus an ADDITIVE draw of the picture, and
--   the sum is allowed to clip -- which is why the middle of a cross-fade looks
--   bright on hardware and looks bright here.
--
-- THE TINT IS ONLY DRAWN OVER ART THAT COVERS THE SCREEN. `fadebg` type 2 blends
-- this layer's sixteen palette entries and nothing else, so the flat quad that
-- reproduces it is only equivalent where there are no holes for the field to show
-- through. 35 of the 81 pictures cover the visible 256x192 completely, the thinnest
-- covers 72.7%, and the graphics stage records which is which. The one program in
-- the cartridge that uses the type-2 fade -- 87, twice, toward white -- switches to
-- background 19, which is one of the 35.
function Gen4Battle.drawEffectBackground(battle)
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not (player and player.bgLayerState) then return false end
  local got, st = pcall(player.bgLayerState, player)
  if not (got and st and st.id) then return false end

  local g = love.graphics
  local drew = false

  -- The cross-fade's half: the field dimmed to its coefficient.
  if st.blend and (st.base or 1) < 1 then
    g.setColor(0, 0, 0, 1 - st.base)
    g.rectangle("fill", 0, 0, Gen4Battle.width(battle), Gen4Battle.HEIGHT)
    g.setColor(1, 1, 1, 1)
    drew = true
  end

  local art, row = Gen4Battle.effectArt(battle, st.id, st.variant)
  if not art then
    -- No effect art in this cache. The field is still blacked out by the fade,
    -- which is the cartridge's own first half of the switch -- so a move plays
    -- against black rather than against the wrong background, and that is the
    -- honest state of an unimported cache rather than a guess at the picture.
    return drew
  end

  local w, h = art:getWidth(), art:getHeight()
  local ox = -((st.offsetX or 0) % w)
  local oy = -((st.offsetY or 0) % h)

  -- ADDITIVE FOR THE CROSS-FADE, ordinary alpha for the fade mode.
  if st.blend then
    g.setBlendMode("add", "alphamultiply")
    local k = st.effect or 1
    g.setColor(k, k, k, 1)
  else
    g.setColor(1, 1, 1, 1)
  end
  -- THE LAYER WRAPS, because the hardware's offset registers do: a background is a
  -- torus and a scroll of 300 shows the left of the picture again. Two draws a axis
  -- is enough while the picture is at least as big as the screen, and every one of
  -- the 81 is 256 or 512 wide by 256 tall.
  for _, dx in ipairs({ 0, w }) do
    for _, dy in ipairs({ 0, h }) do
      if ox + dx < Gen4Battle.width(battle) and oy + dy < Gen4Battle.HEIGHT then
        g.draw(art, ox + dx, oy + dy)
      end
    end
  end
  if st.blend then g.setBlendMode("alpha", "alphamultiply") end
  g.setColor(1, 1, 1, 1)

  -- ...and this layer's own palette blend, where the art has no holes for it to
  -- leak through.
  local tint = st.tint
  if tint and tint[4] and tint[4] > 0 and row and row.opaque then
    g.setColor(tint[1] or 0, tint[2] or 0, tint[3] or 0, tint[4])
    g.rectangle("fill", 0, 0, Gen4Battle.width(battle), Gen4Battle.HEIGHT)
    g.setColor(1, 1, 1, 1)
  end
  return true
end

-- drawCellActors(battle) -> how many were drawn
--
-- The cartridge places these at the DEFENDER and the per-move callback moves them
-- from there; this port honours the placement and the animation, applies the five
-- callbacks it has read (see `SPRITE_MOTION` in the player) and names the motion
-- it does not apply. Drawn from the sprite's own centre for the same reason the
-- particles are: a cell bank's OAM offsets are measured from the sprite's origin,
-- so the assembled image is centred on it.
local EffectProjection=require('src.battle.Gen4EffectProjection')
function Gen4Battle.effectPosition(battle,name,attacker,x,y,absoluteX,absoluteY)
 local ox,oy=Gen4Battle.particleOrigin(battle,name,attacker)
 if battle.dramaticNativePositions then
  ox,oy=EffectProjection.origin(name,attacker)
  return EffectProjection.point(battle.dramaticNativePositions,absoluteX or ox+(x or 0),absoluteY or oy+(y or 0))
 end
 return absoluteX or ox+(x or 0),absoluteY or oy+(y or 0),1,0
end
function Gen4Battle.drawCellActors(battle)
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not player then return 0 end
  local got, list = pcall(player.cells, player)
  if not (got and type(list) == "table") then return 0 end
  local g = love.graphics
  local drawn = 0
  for _, s in ipairs(list) do
    -- A BLANK FRAME IS SKIPPED, NOT TREATED AS A FAULT: see `Player:cells`.
    local img = (not s.blank) and s.art and image(s.art.path) or nil
    if img then
      local ox, oy = Gen4Battle.particleOrigin(battle, s.origin,
                                               player.attackerIsPlayer)
      -- AN ABSOLUTE COORDINATE REPLACES THE ORIGIN'S, AND THE OFFSET WITH IT.
      -- Two callbacks reach this and for the same reason: their position is not
      -- an offset from a battler at all. Fissure's crack opens at a fixed screen
      -- Y -- 126 or 32 by the defender's side -- whichever Pokemon is standing
      -- there; IcicleSpear's icicles fly along a path BETWEEN the two battlers,
      -- which no offset from either could express. Both axes are separate: a
      -- record may pin its Y and still be offset in X.
      local sx = tonumber(s.x) or 0
      local sy = tonumber(s.y) or 0
      local absX, absY = tonumber(s.absoluteX), tonumber(s.absoluteY)
      local fx,fy,perspective,turn=Gen4Battle.effectPosition(battle,s.origin,player.attackerIsPlayer,sx,sy,absX,absY)
      -- +Y IS DOWN, as it is on the hardware. The offsets on these records are
      -- what `ManagedSprite_OffsetPositionXY` would have added, and every
      -- constant in pret is written in that frame -- move 265's (0, 24) puts its
      -- sprite twenty-four pixels BELOW the battler's centre. The particle path
      -- above adds its Y for the same reason, so the two layers now agree.
      --
      -- WHAT THE CALLBACK DID TO IT: a scale, a rotation, a horizontal flip and
      -- an alpha, all identity on a sprite whose callback is not ported, so the
      -- same four lines serve every sprite and a missing callback cannot silently
      -- tint or shrink anything. The flip is a negative X scale about the centre,
      -- which is what `SetFlipMode` is on the hardware.
      local scaleX = tonumber(s.scaleX) or 1
      local scaleY = tonumber(s.scaleY) or 1
      if s.flipX then scaleX = -scaleX end
      local alpha = tonumber(s.alpha)
      if alpha == nil then alpha = 1 end
      local cr, cg, cb = effectFade(player, 1, 1, 1)
      g.setColor(cr, cg, cb, alpha)
      g.draw(img, fx, fy, (tonumber(s.rotation) or 0)+turn, scaleX*perspective, scaleY*perspective,
             img:getWidth() / 2, img:getHeight() / 2)
      drawn = drawn + 1
    end
  end
  g.setColor(1, 1, 1, 1)
  return drawn
end

-- WHERE AN EMITTER'S PARTICLES ARE MEASURED FROM.
--
-- `Gen4MoveAnimPlayer` hands over an origin NAME, not a point, because the name
-- is what the cartridge's callback table says and the point is this screen's
-- business. The names come from pret's own `sEmitterCallbackTable`; see the
-- table in the player.
--
-- `emitter` and `midpoint` both land between the two Pokemon, and for different
-- reasons: `midpoint` is what SetPosBasedOnBattlers means, and `emitter` is the
-- callback that moves the emitter nowhere at all -- so its particles sit at the
-- resource's own stored position, which is expressed relative to the middle of
-- the field. Those two agreeing is a coincidence of this layout, not one fact.
function Gen4Battle.particleOrigin(battle, name, attackerIsPlayer)
  local me = Gen4Battle.battlerPos(battle, 0)
  local foe = Gen4Battle.battlerPos(battle, 1)
  if name == "player" then return me.x, me.y end
  if name == "enemy" then return foe.x, foe.y end
  local attacker = attackerIsPlayer and me or foe
  local defender = attackerIsPlayer and foe or me
  if name == "attacker" then return attacker.x, attacker.y end
  if name == "defender" then return defender.x, defender.y end
  return (me.x + foe.x) / 2, (me.y + foe.y) / 2
end

-- A REPEATED TEXTURE, AND THE QUAD THAT MAKES ONE.
--
-- `textureS = FX32_ONE << textureTileCountS`, so the field is a power-of-two
-- repeat across the particle's own quad: 534 of the cartridge's emitters tile
-- 2x2, 67 tile 2x1 and 46 tile 1x2. The particle does not get BIGGER -- the
-- texture repeats inside the same footprint -- so the quad is widened and the
-- scale divided by the same factor.
--
-- CACHED BY SHAPE, because a Quad allocated per particle per frame would be
-- thousands of objects a second for a handful of distinct shapes.
local tileQuads = {}

local function tiledQuad(width, height, tileS, tileT)
  local key = ("%d:%d:%d:%d"):format(width, height, tileS, tileT)
  local quad = tileQuads[key]
  if not quad then
    quad = love.graphics.newQuad(0, 0, width * tileS, height * tileT,
                                 width, height)
    tileQuads[key] = quad
  end
  return quad
end

-- drawParticles(battle) -> how many were drawn
--
-- Returns the count because a silent nothing is the failure mode here: every
-- part of this can be right and produce an empty screen if the art did not
-- import, and a number is what a diagnostic can look at.
function Gen4Battle.drawParticles(battle)
  local player = battle and battle.gen4AnimPlaying and battle.gen4Anim
  if not player then return 0 end
  local got, list = pcall(player.particles, player)
  if not (got and type(list) == "table") then return 0 end
  local g = love.graphics
  local drawn = 0
  for _, q in ipairs(list) do
    local img = q.art and image(q.art.path)
    if img then
      local ox, oy = Gen4Battle.particleOrigin(battle, q.origin,
                                               player.attackerIsPlayer)
      -- DRAWN FROM ITS CENTRE. A particle's position is its middle in the
      -- cartridge and its scale grows both ways from there; anchoring the
      -- top-left instead makes every effect drift down and right as it grows.
      local fx,fy,perspective,turn=Gen4Battle.effectPosition(battle,q.origin,player.attackerIsPlayer,q.x,q.y)
      local w, h = img:getWidth(), img:getHeight()
      -- TWO SCALES. 445 of the cartridge's 1,468 emitters set an aspect ratio,
      -- and 175 of them animate only one axis, so a single scale draws a third
      -- of the game's particles the wrong shape.
      local sx = tonumber(q.scaleX) or tonumber(q.scale) or 1
      local sy = tonumber(q.scaleY) or tonumber(q.scale) or 1
      local a = tonumber(q.alpha) or 1
      if a < 0 then a = 0 elseif a > 1 then a = 1 end
      -- THE COLOUR ANIMATION MODULATES THE TEXTURE, which is what the DS's
      -- polygon colour does to it. Nil when the resource has no colour curve,
      -- and then the art is drawn as it was extracted.
      local c = q.colour
      if c then
        local cr, cg, cb = effectFade(player, (c[1] or 255) / 255,
                                     (c[2] or 255) / 255, (c[3] or 255) / 255)
        g.setColor(cr, cg, cb, a)
      else
        local cr, cg, cb = effectFade(player, 1, 1, 1)
        g.setColor(cr, cg, cb, a)
      end
      -- ROTATION COMES THROUGH IN RADIANS. A particle with no `hasRotation` bit
      -- gets zero, so this costs nothing where the cartridge does not ask for it.
      local tileS = math.max(1, math.floor(tonumber(q.tileS) or 1))
      local tileT = math.max(1, math.floor(tonumber(q.tileT) or 1))
      if tileS > 1 or tileT > 1 then
        -- REPEAT WRAP IS SET ON THE IMAGE ITSELF, which is shared through the
        -- asset cache -- safe here because a particle texture is drawn from
        -- nowhere else, and stated so the next caller knows.
        img:setWrap("repeat", "repeat")
        g.draw(img, tiledQuad(w, h, tileS, tileT),
               fx, fy, (tonumber(q.rotation) or 0)+turn,
               sx*perspective / tileS, sy*perspective / tileT, w * tileS / 2, h * tileT / 2)
      else
        g.draw(img, fx, fy, (tonumber(q.rotation) or 0)+turn,
               sx*perspective, sy*perspective, w / 2, h / 2)
      end
      drawn = drawn + 1
    end
  end
  g.setColor(1, 1, 1, 1)
  return drawn
end

-- WHERE THE ENGINE'S OWN HUD AND MESSAGE BOX GO, UNTIL PLATINUM'S EXIST.
--
-- The Game Boy composition is 160x144 and this screen is 256x192, so it is
-- translated by half the difference on each axis -- (48, 48). That is not a
-- fudge chosen to look right: it lands the Game Boy's enemy panel (tiles 0,0
-- to 11,3 -> 48,48 to 136,80) on top of where Platinum's enemy healthbox goes
-- (centre 58,36, so 6,4 to 122,68), and its player panel (136,104 to 208,128)
-- on Platinum's player box (centre 192,116, so 128,84 to 256,148). Both land
-- within a dozen pixels of the real thing, which is why a plain centring is
-- worth more here than a hand-placed guess.
Gen4Battle.CLASSIC_DX = (256 - 160) / 2
Gen4Battle.CLASSIC_DY = (192 - 144) / 2

-- ---------------------------------------------------------------------------
-- THE HEALTHBOXES
--
-- WHAT THE CELL BANKS SAY, decoded out of the cartridge rather than guessed:
-- `healthbox/short_cell` and `healthbox/tall_cell` are each ONE cell of TWO
-- 64x64 OAM squares side by side, so an assembled box is 128x64 -- and the two
-- differ ONLY in where their origin sits:
--
--     short_cell  (enemy, player doubles)  extent 128x64 at (-64, -28)
--     tall_cell   (player singles)         extent 128x64 at (-64, -32)
--
-- Those offsets are from the sprite CENTRE, which is what HEALTHBOX_POS holds,
-- so the top-left of a drawn box is centre + origin. The four-pixel difference
-- between them is the whole reason there are two banks.
--
-- THE SECOND OAM CONFIRMS THE TILE ORDER. It names tile 32, and Platinum's
-- mapping mode is 1, so an index steps two tiles: 32 x 2 = 64, i.e. the left
-- square is tiles 0..63 and the right 64..127. That is what says the blocks are
-- laid out sequentially rather than interleaved.
--
-- THE NAME WINDOW IS THE TOP-LEFT 64x16. `healthbox.c` writes it at
-- HEALTHBOX_NAME_WINDOW_OFFSET 0 and it is 8x2 blocks of 32 bytes -- 16 tiles,
-- starting at tile 0. With the order above, tiles 0..15 are the first two rows
-- of the left square.
--
-- THE TWO GAUGES ARE DELIBERATELY NOT DRAWN YET. Their positions are VRAM BYTE
-- OFFSETS (`sHPGaugeVRAMTransfer`, and 1632 / 3584 for the EXP bar) that have to
-- be turned into tiles and then into pixels, and while the arithmetic is
-- straightforward the step from tile number to screen position rests on the 1D
-- row-major layout above -- which the OAM corroborates but nothing SECOND states
-- outright. Every other number on this screen is stated twice. These are not,
-- and the thing that would settle them is looking at the assembled art, which
-- does not exist until the cell-bank fix has been through an import. So they
-- wait for that rather than being written down now and checked later.
-- ---------------------------------------------------------------------------

-- side -> { image key, the cell bank's origin relative to the sprite centre }
Gen4Battle.HEALTHBOX_ART = {
  player = { key = "healthbox_player_singles", ox = -64, oy = -32 },
  enemy  = { key = "healthbox_enemy",          ox = -64, oy = -28 },
}
Gen4Battle.HEALTHBOX_SIZE = { w = 128, h = 64 }

-- The name window, in pixels from the box's own top-left.
Gen4Battle.HEALTHBOX_NAME = { x = 0, y = 0, w = 64, h = 16 }

-- !! AND THAT RECT IS THE VRAM'S, NOT THE PICTURE'S.
--
-- 8x2 blocks from tile 0 is where the cartridge's name window lives in the
-- sprite's CHARACTER DATA. The assembled picture is the CELL BANK'S
-- arrangement of that data, and the two are not the same grid: drawing the
-- name at the picture's (0, 0) put it on the box's decorative tail, which on
-- the foe's box hangs off the LEFT EDGE OF THE SCREEN. Reported from play as
-- "theyre missing the pokemon names for the HUD ui" -- they were being drawn
-- at x = -4.
--
-- So the panel is MEASURED off the assembled art instead: the green field
-- (107, 115, 90) above the brown trough, which comes out as a clean rectangle
-- in each of the three boxes and at a consistent ~106 x 14. The three differ
-- where their tails are -- the player's on the left, the foe's on the right --
-- which is exactly why one rect could never have served all three.
Gen4Battle.HEALTHBOX_PANEL = {
  healthbox_player_singles = { x = 23, y = 16, w = 105, h = 15 },
  healthbox_enemy          = { x = 6,  y = 17, w = 106, h = 14 },
  healthbox_player_doubles = { x = 15, y = 17, w = 107, h = 14 },
}

-- The band under the trough, where the player's solo box shows its numbers --
-- the green field again, between the trough's last row and the EXP groove.
-- NINE ROWS, which is the measurement that says these cannot be dialogue text.
-- Kept for the FALLBACK path only: a cache imported before the digit strip
-- existed still right-aligns the system face in here.
Gen4Battle.HEALTHBOX_HP_TEXT = { x = 23, y = 39, w = 105, h = 9 }

-- ---------------------------------------------------------------------------
-- WHERE EVERY NUMBER ON A HEALTHBOX SITS
--
-- !! AND A CORRECTION, BECAUSE THIS FILE PREVIOUSLY SAID SOMETHING FALSE.
-- It said the HP numbers were blitted from the parts blob as
-- HEALTHBOX_PART_NUMBERS_LEFT / _RIGHT / _SLASH "(healthbox.c 840-845)".
-- Those parts are at those lines and they are NOT the numbers: 840 is inside
-- `Healthbox_ToggleHPDisplayMode`, which switches on the box type and RETURNS
-- for anything but the two DOUBLES boxes -- it is the empty number FIELD that
-- swaps in where the bar was.  It also said DrawLevelNumber and DrawMaxHP use
-- FONT_SYSTEM "(1316, 1355)"; those two lines are the SAFARI BALL COUNTER.
-- Only the NICKNAME is set in the system face (1143).
--
-- Every number -- the level, the current HP, the max HP -- goes through
-- FontSpecialChars_DrawBattleScreenText off a 23-tile glyph strip.  See
-- src/import/Gen4SpecialChars.lua.
--
-- HOW THE POSITIONS WERE GOT.  Each drawer names a VRAM byte offset into the
-- box's own character data, and the box is two 64x64 OAM squares side by side
-- with tiles 0..63 in the left and 64..127 in the right (the cell bank says so;
-- see the healthbox section of docs/gen4-platinum.md).  So offset / 32 is a
-- tile index and the tile index is a position:
--
--     tile t < 64   -> ( (t % 8) * 8,       (t // 8) * 8 )
--     tile t >= 64  -> ( 64 + (u % 8) * 8,  (u // 8) * 8 )   u = t - 64
--
-- THREE THINGS CONFIRM IT, none of them the arithmetic itself:
--   * the level digits land at the RIGHT-HAND END of the green panel measured
--     for HEALTHBOX_PANEL -- 104..127 against a panel ending at 127 on the
--     solo box, 88..111 against one ending at 111 on the foe's;
--   * the current HP (64..87) and the max HP (96..119) leave EXACTLY ONE
--     eight-pixel column between them -- and the assembled box art has a
--     diagonal "/" baked into x 88..95, y 41..46.  The slash is in the
--     picture because it never changes; the numbers are not because they do;
--   * the HP row lands at y 40..47, inside the nine-row band this file had
--     already measured off the art for a different reason.
Gen4Battle.HEALTHBOX_LV = {
  healthbox_player_singles = { x = 88, y = 16 },
  healthbox_enemy          = { x = 72, y = 16 },
  healthbox_player_doubles = { x = 80, y = 16 },
}

-- THE LEVEL NUMBER IS FOUR PIXELS DOWN FROM ITS TILE, and that is not a nudge.
-- HealthBox_DrawLevelNumber copies the glyph's first 16 bytes into the BOTTOM
-- half of the upper tile and its last 16 into the TOP half of the lower one, so
-- an eight-row digit straddles the boundary at y = 16: rows 20..27.
Gen4Battle.HEALTHBOX_LEVEL_NUM = {
  healthbox_player_singles = { x = 104, y = 20 },
  healthbox_enemy          = { x = 88,  y = 20 },
  healthbox_player_doubles = { x = 96,  y = 20 },
}

Gen4Battle.HEALTHBOX_HP_NOW = {
  healthbox_player_singles = { x = 64, y = 40 },
  healthbox_player_doubles = { x = 64, y = 32 },
}
Gen4Battle.HEALTHBOX_HP_MAX = {
  healthbox_player_singles = { x = 96, y = 40 },
  healthbox_player_doubles = { x = 96, y = 32 },
}

-- Three columns each, stated: every call passes `3` for numDigits.
Gen4Battle.HEALTHBOX_NUM_CELLS = 3

-- THE "Lv" IS A PICTURE AND IT IS GENDERED.  HealthBox_DrawLevelText picks
-- LEVEL_MALE / _FEMALE / _GENDERLESS and copies a TOP pair and a BOTTOM pair
-- out of the parts blob, so the block is 16 wide and 16 tall.  Zero-based part
-- indices, straight off enum HealthBoxPart.
Gen4Battle.LEVEL_PARTS = {
  female = { top = 60, bottom = 72 },
  male   = { top = 62, bottom = 74 },
  none   = { top = 64, bottom = 76 },
}

local function healthboxImage(battle, key)
  local gfx = graphics(battle)
  local row = gfx and gfx.battleObjects and gfx.battleObjects[key]
  if not row then return nil end
  -- A box the import has not re-assembled yet is flagged `provisionalLayout`:
  -- correct pixels, placeholder arrangement. Drawing it would put a handful of
  -- scattered strips where the box goes, which reads as a rendering bug rather
  -- than as a stale cache -- so it is declined, and the caller falls back.
  if row.provisionalLayout then return nil, "provisional" end
  return image(row.path)
end

-- ---------------------------------------------------------------------------
-- The parts sheet and the digit strip
--
-- `partsFor` used to live beside the gauges, three hundred lines below this.
-- It was moved UP rather than forward-declared when the "Lv" block started
-- reading it too: a file-local called above its own `local function` line is
-- resolved as a global, gets nil, and raises -- which this port has now paid
-- for twice (Gen4Commands' itemKey, this file's own bottomScreenUp).  Moving
-- the definition is the fix that cannot be got wrong later.
-- ---------------------------------------------------------------------------

local partsSheet = { path = nil, image = nil, quads = nil, wide = nil }

local function partsFor(battle)
  local gfx = graphics(battle)
  local rec = gfx and gfx.healthboxParts
  if not (rec and rec.image) then return nil end
  if partsSheet.path ~= rec.image then
    partsSheet.path = rec.image
    partsSheet.image = image(rec.image)
    partsSheet.quads, partsSheet.wide = nil, nil
    if partsSheet.image then
      local iw, ih = partsSheet.image:getDimensions()
      local wide = rec.tilesWide or 9
      local quads = {}
      for p = 0, (rec.count or 0) - 1 do
        quads[p] = love.graphics.newQuad((p % wide) * 8,
                                         math.floor(p / wide) * 8, 8, 8, iw, ih)
      end
      partsSheet.quads, partsSheet.wide = quads, wide
    end
  end
  if not (partsSheet.image and partsSheet.quads) then return nil end
  return rec, partsSheet.image, partsSheet.quads
end


-- Cached exactly like the parts sheet above it: one image and one quad per
-- glyph, rebuilt only when the cache changes underneath.
local digitSheet = { path = nil, image = nil, quads = nil }

local function digitsFor(battle)
  local gfx = graphics(battle)
  local rec = gfx and gfx.healthboxDigits
  if not (rec and rec.image) then return nil end
  if digitSheet.path ~= rec.image then
    digitSheet.path = rec.image
    digitSheet.image = image(rec.image)
    digitSheet.quads = nil
    if digitSheet.image then
      local iw, ih = digitSheet.image:getDimensions()
      local tile = rec.tile or 8
      local quads = {}
      -- ONE ROW, which is how the stage writes it: glyph n is at x = n * tile.
      for n = 0, (rec.count or 0) - 1 do
        quads[n] = love.graphics.newQuad(n * tile, 0, tile, tile, iw, ih)
      end
      digitSheet.quads = quads
    end
  end
  if not (digitSheet.image and digitSheet.quads) then return nil end
  return rec, digitSheet.image, digitSheet.quads
end

local POWERS = { 1, 10, 100, 1000 }

-- CharCode_FromInt, which is where the ALIGNMENT lives -- and it is the only
-- thing that decides it, because every call asks for the same three columns.
--
--   "none"    a leading zero emits NOTHING, so the number comes out SHORT and
--             LEFT-justified.  The level and the max HP.
--   "spaces"  a leading zero emits a blank, so the number fills all three
--             columns and is RIGHT-justified.  The current HP -- which is why
--             it sits hard against the slash while the max HP starts after it.
--
-- A digit of ten or more emits CHAR_WIDE_QUESTION, which is not one of
-- CHAR_WIDE_0..9, and the drawer fills any non-digit with the background.  So
-- it comes out BLANK here rather than as a glyph this strip does not carry.
local function numberCells(value, cells, pad)
  local out = {}
  local i = math.max(0, math.floor(tonumber(value) or 0))
  local mode = pad
  for k = cells, 1, -1 do
    local j = POWERS[k] or 1
    local digit = math.floor(i / j)
    local diff = i - j * digit
    if mode == "zeroes" then
      out[#out + 1] = (digit < 10) and digit or false
    elseif digit ~= 0 or j == 1 then
      mode = "zeroes"
      out[#out + 1] = (digit < 10) and digit or false
    elseif mode == "spaces" then
      out[#out + 1] = false
    end
    i = diff
  end
  return out
end

Gen4Battle.numberCells = numberCells

-- Blit one number.  A blank column draws NOTHING: the cartridge fills it with
-- palette 15, which is the colour the box already is under the band -- measured
-- (107, 115, 90) on both, and the reason the strip is written with a
-- transparent background rather than an opaque one.
local function drawNumber(battle, x, y, value, cells, pad)
  local rec, img, quads = digitsFor(battle)
  if not (rec and img and quads) then return false end
  local tile = rec.tile or 8
  local glyphs = numberCells(value, cells or Gen4Battle.HEALTHBOX_NUM_CELLS, pad)
  love.graphics.setColor(1, 1, 1, 1)
  for n = 1, #glyphs do
    local digit = glyphs[n]
    if digit then
      local quad = quads[(rec.digit0 or 0) + digit]
      if quad then love.graphics.draw(img, quad, x + (n - 1) * tile, y) end
    end
  end
  return true
end

-- The gendered "Lv" block: a top pair and a bottom pair out of the parts
-- sheet, 16 x 16 in all.  Gender is asked of Pokemon.genderOf rather than of
-- `mon.gender`, because a Pokemon that has never been asked carries none and
-- the answer has to come from the species ratio -- the same trap ATTRACT paid
-- for once.
local function drawLevelIcon(battle, key, mon, boxX, boxY)
  local spot = Gen4Battle.HEALTHBOX_LV[key]
  local rec, img, quads = partsFor(battle)
  if not (spot and rec and img and quads) then return false end
  local gender
  local okMon, Pokemon = pcall(require, "src.pokemon.Pokemon")
  if okMon and Pokemon and Pokemon.genderOf then
    gender = Pokemon.genderOf(battle and battle.game and battle.game.data, mon)
  end
  local parts = Gen4Battle.LEVEL_PARTS[gender or "none"]
              or Gen4Battle.LEVEL_PARTS.none
  love.graphics.setColor(1, 1, 1, 1)
  local drew = false
  for i = 0, 1 do
    local top = quads[parts.top + i]
    local bottom = quads[parts.bottom + i]
    if top then
      love.graphics.draw(img, top, boxX + spot.x + i * 8, boxY + spot.y)
      drew = true
    end
    if bottom then
      love.graphics.draw(img, bottom, boxX + spot.x + i * 8, boxY + spot.y + 8)
    end
  end
  return drew
end

-- Both together, so the caller gets one answer: either the box is lettered the
-- cartridge's way or it is not, and a half-lettered box (a picture "Lv" beside
-- a system-face number) would look worse than either.
function Gen4Battle.drawHealthboxNumbers(battle, key, battler, boxX, boxY)
  local mon = battler and battler.mon
  if not mon then return false end
  if not digitsFor(battle) then return false end

  local lvSpot = Gen4Battle.HEALTHBOX_LEVEL_NUM[key]
  if not (lvSpot and drawLevelIcon(battle, key, mon, boxX, boxY)) then
    return false
  end
  -- PADDING_MODE_NONE: left-justified against the "Lv" block.
  if not drawNumber(battle, boxX + lvSpot.x, boxY + lvSpot.y,
                    tonumber(mon.level) or 0,
                    Gen4Battle.HEALTHBOX_NUM_CELLS, "none") then
    return false
  end

  -- WHICH BOX SHOWS NUMBERS IS STATED, not chosen: HealthBox_Draw clears
  -- HEALTHBOX_INFO_NOT_ON_ENEMY for all three enemy types, and on a DOUBLES
  -- slot `numberMode` makes the numbers and the bar alternatives.  So they
  -- belong to the player's SOLO box and nowhere else here.
  local now = Gen4Battle.HEALTHBOX_HP_NOW[key]
  local max = Gen4Battle.HEALTHBOX_HP_MAX[key]
  if now and max and key == "healthbox_player_singles"
     and battler == battle.player then
    local maxHP = math.max(1, (mon.stats and mon.stats.hp) or 1)
    local curHP = math.max(0, math.floor(battler.shownHP or mon.hp or 0))
    drawNumber(battle, boxX + now.x, boxY + now.y, curHP,
               Gen4Battle.HEALTHBOX_NUM_CELLS, "spaces")
    drawNumber(battle, boxX + max.x, boxY + max.y, maxHP,
               Gen4Battle.HEALTHBOX_NUM_CELLS, "none")
  end
  return true
end

-- drawHealthboxes(battle) -> true when BOTH were drawn
--
-- All or nothing on purpose: one Platinum box beside one Game Boy panel is
-- worse than two of either, and the caller's fallback is the whole stand-in.
function Gen4Battle.drawHealthboxes(battle)
  local g = love.graphics
  local sides = {
    { side = "enemy",  battler = battle.enemy,  slot = 1 },
    { side = "player", battler = battle.player, slot = 0 },
  }
  local drew = 0
  for _, row in ipairs(sides) do
    local art = Gen4Battle.HEALTHBOX_ART[row.side]
    -- THE SAFARI BOX stands where the player's would: "SAFARI BALLS" and
    -- "Left: NN" in FONT_SYSTEM at the cell rows HealthBox_DrawBallCount and
    -- _DrawBallsLeftMessage copy them to (tile rows 2 and 4, from column 2).
    if row.side == "player" and battle.gen4Safari then
      local img = healthboxImage(battle, "healthbox_safari")
      local centre = Gen4Battle.healthboxPos(battle, row.slot)
      if img and centre then
        local x, y = centre.x + art.ox, centre.y + art.oy
        g.setColor(1, 1, 1, 1)
        g.draw(img, x, y)
        local Font = require("src.render.Font")
        local G = require("src.battle.Gen4Safari")
        local balls = battle.safari and battle.safari.balls or 0
        local faced = Font.pushFace("system")
        g.setColor(0.2, 0.2, 0.2, 1)
        Font.draw(G.text(battle.data, G.TEXT.boxTitle) or "SAFARI BALLS", x + 16, y + 16)
        Font.draw(G.text(battle.data, G.TEXT.boxLeft, ("%2d"):format(balls))
                  or ("Left: %2d"):format(balls), x + 16, y + 32)
        if faced then Font.popFace() end
        g.setColor(1, 1, 1, 1)
        drew = drew + 1
      end
      goto continue
    end
    local img = art and healthboxImage(battle, art.key)
    local centre = Gen4Battle.healthboxPos(battle, row.slot)
    -- A BOX COMES IN WITH ITS POKEMON: none for the foe while its trainer
    -- still stands on the platform or its ball is in the air, none for the
    -- player while the trainer's back is up.
    local notOut = (row.side == "enemy" and (battle.showEnemyTrainer or battle.enemySendingOut))
        or (row.side == "player" and battle.showPlayerBack)
    -- (a box held back on purpose is handled, not missing: it must not send
    -- the caller to its stand-in HUD, which would draw over the other box)
    if notOut then drew = drew + 1 end
    if img and centre and row.battler and row.battler.mon and not notOut then
      local x, y = centre.x + art.ox, centre.y + art.oy
      g.setColor(1, 1, 1, 1)
      g.draw(img, x, y)
      -- The bars before the words: the gauge tiles carry their own trough, so
      -- they go straight over the frame, and nothing is written on top of them.
      pcall(Gen4Battle.drawGauges, battle, art.key, row.battler, x, y)
      -- The numbers are TILES and the name is TEXT, and they are drawn by two
      -- different things for that reason.  The numbers go first because the
      -- name is fitted to the room the "Lv" block leaves.
      local okNum, lettered =
        pcall(Gen4Battle.drawHealthboxNumbers, battle, art.key, row.battler, x, y)
      Gen4Battle.drawHealthboxText(battle, row.battler, x, y, art.key,
                                   okNum and lettered or false)
      drew = drew + 1
    end
    ::continue::
  end
  return drew == 2
end

-- The words on a box.  `lettered` is what drawHealthboxNumbers answered: true
-- means the level and the HP are already on the box as CARTRIDGE TILES and all
-- that is left here is the nickname.
--
-- ONE THING ON A HEALTHBOX IS TEXT AND IT IS THE NICKNAME.
-- HealthBox_DrawBattlerName prints it with FONT_SYSTEM (healthbox.c 1143) --
-- not FONT_MESSAGE, which is the face every other screen in this port uses,
-- and which is what made the lettering look wrong when it was first reported
-- from play.  The cache publishes both (`faces.system` beside `pages.message`)
-- and Font.pushFace picks one.
--
-- EVERYTHING ELSE IS NOT TEXT.  See the correction above HEALTHBOX_LV: the
-- level, the current HP and the max HP are glyph tiles, and the two lines this
-- file used to cite for FONT_SYSTEM are the Safari ball counter.
function Gen4Battle.drawHealthboxText(battle, battler, boxX, boxY, key, lettered)
  local Font = require("src.render.Font")
  local mon = battler and battler.mon
  if not mon then return end
  -- !! AND `mon.name` IS NOT A FIELD, WHICH IS WHY EVERY BOX WAS NAMELESS.
  --
  -- Reported from play: *"names and gender are missing still"*. This read
  -- `mon.nickname or mon.name` -- and a Pokemon record in this engine has no
  -- `name`; the SPECIES has one and the BATTLER carries the resolved answer.
  -- `BattleState` sets `name = mon.nickname or def.name` when it puts a battler
  -- on the field (line 845), so with no nickname the whole expression came out
  -- as the empty string and `Font.draw("")` drew nothing. Not a layout bug, not
  -- a font bug: the string was empty.
  --
  -- Reading the BATTLER's is also what keeps two other rules working, both of
  -- which this had been quietly ignoring: the Pokemon Tower's unidentified
  -- GHOST (BattleState renames the battler, not the mon) and the doubles rule
  -- that a left flank keeps its old name when its partner is swapped.
  local name = battler.name
  if name == nil or name == "" then
    local def = battle and battle.data and battle.data.pokemon
                and battle.data.pokemon[mon.species]
    name = (mon.nickname ~= nil and mon.nickname ~= "" and mon.nickname)
           or (def and def.name) or ""
  end
  name = tostring(name)
  local level = tonumber(mon.level) or 0
  local win = Gen4Battle.HEALTHBOX_PANEL[key] or Gen4Battle.HEALTHBOX_NAME

  local pushed = Font.pushFace and Font.hasFace and Font.hasFace("system")
                 and Font.pushFace("system")
  local glyphH = Font.glyphHeight and Font.glyphHeight() or 12
  local ty = boxY + win.y + math.floor((win.h - glyphH) / 2)

  love.graphics.setColor(0, 0, 0, 1)

  -- HOW MUCH ROOM THE NAME HAS, and the two answers are different pictures.
  -- With the tiles up, the "Lv" block starts at a stated x and the name stops
  -- there.  Without them, the level is printed in the system face at the
  -- panel's right edge and the name stops short of THAT.
  local room
  if lettered then
    local lvSpot = Gen4Battle.HEALTHBOX_LV[key]
    room = (lvSpot and (lvSpot.x - win.x - 2)) or (win.w - 24)
  else
    local lv = "Lv" .. level
    local lvW = Font.width and Font.width(lv) or (#lv * 8)
    Font.draw(lv, boxX + win.x + win.w - lvW, ty)
    room = win.w - lvW - 6
  end
  Font.draw(Font.fit and Font.fit(name, room) or name, boxX + win.x, ty)

  -- THE FALLBACK, and it is the whole of what this function used to do.
  -- A cache imported before the digit strip existed has no tiles to blit, so
  -- the numbers are set in the system face and right-aligned in the band --
  -- which is the wrong face at the wrong size, and is still better than a box
  -- with no numbers on it at all.  It goes away on the next import.
  if not lettered and key == "healthbox_player_singles"
     and battler == battle.player then
    local max = math.max(1, (mon.stats and mon.stats.hp) or 1)
    local now = math.max(0, math.floor(battler.shownHP or mon.hp or 0))
    local text = ("%d/ %d"):format(now, max)
    local band = Gen4Battle.HEALTHBOX_HP_TEXT
    local tw = Font.width and Font.width(text) or (#text * 8)
    Font.draw(text, boxX + band.x + band.w - tw,
              boxY + band.y + math.floor((band.h - glyphH) / 2))
  end
  if pushed and Font.popFace then Font.popFace() end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- THE MESSAGE BOX AND THE MENUS
-- ---------------------------------------------------------------------------

-- PLATINUM'S BATTLE MESSAGE BOX IS THE FIELD'S, AT THE SAME TILES, and the
-- cartridge states it three separate times rather than once:
--
--     battle_main.c:465   Window_Add(bgConfig, windows,     1, 2, 19, 27, 4, 11, 31)
--     battle_main.c:559   Window_Add(bgConfig, &windows[0], 1, 2, 19, 27, 4, 11, 31)
--     battle_main.c:1682  Window_Add(bgConfig, window,      1, 2, 19, 27, 4, 11, 31)
--
-- (the third is the link-battle comm screen), against field_message.c's
-- (2, 19, 27, 4) for the overworld.  `Window_Add`'s signature is
-- (bgConfig, window, bgLayer, tilemapLeft, tilemapTop, width, height, palette,
-- baseTile) -- include/bg_window.h -- so: left 2, top 19, 27 tiles wide, 4
-- tall.  That is the TEXT INTERIOR: x 16..232, y 152..184.
--
-- The FRAME is drawn round it afterwards by
-- Window_DrawMessageBoxWithScrollCursor -> DrawMessageBoxFrame, which reaches
-- two tiles to the left of the window and three to the right, one row above
-- and one below.  On a 32x24-tile screen that is columns 0..31 and rows 18..23:
-- Platinum's battle message box is the FULL WIDTH of the DS screen and 48
-- pixels deep, y 144..192.
--
-- None of that arithmetic is done here.  Font.drawDialogueBox does it, from
-- the port's own rect convention -- interior plus one tile of border on each
-- side -- so what this table holds is that rect and nothing cleverer.
Gen4Battle.MESSAGE_WINDOW = { left = 2, top = 19, width = 27, height = 4 }
Gen4Battle.MESSAGE_BOX = { tx = 1, ty = 18, tw = 29, th = 6 }

-- TWO LINES OF SIXTEEN PIXELS, and the sixteen is not a choice either:
-- FONT_MESSAGE is `maxLetterWidth = 11, maxLetterHeight = 16, letterSpacing =
-- 0, lineSpacing = 0` (src/font.c sFontAttributes), and the window is four
-- tiles -- 32 pixels -- tall.  32 / 16 = 2.
--
-- BattleSystem_ShowMessage prints with Text_AddPrinterWithParams(window,
-- FONT_MESSAGE, string, 0, 0, ...) -- battle_system.c:1608, 1639, 1646 and
-- 1662, four times over -- so the x and y offsets inside the window are ZERO
-- and the first line starts at the window's own origin.
Gen4Battle.MESSAGE_TEXT = { x = 16, y = 152, w = 216, h = 32 }
Gen4Battle.MESSAGE_LINE_H = 16
Gen4Battle.MESSAGE_ROWS = { 152, 168 }

-- THE ACTION MENU AND THE MOVE LIST ARE ON THE TOUCH SCREEN, and this engine
-- draws one screen -- so what follows is in two halves which must not be
-- mistaken for each other.
--
-- DERIVED -- the cartridge's own button rectangles, out of battle_subscreen.c.
-- A `TouchScreenRect` is { top, bottom, left, right } in that order
-- (include/touch_screen.h), in bottom-screen pixels:
--
--     sActionMenuTouchRects            result (BattleControllerPlayerInput)
--       { 0x18, 0x90, 0x00, 0xFF }      1  FIGHT  y  24..144, full width
--       { 0x90, 0xC0, 0x00, 0x50 }      2  ITEM   y 144..192, x   0.. 80
--       { 0x90, 0xC0, 0xB0, 0xFF }      3  PARTY  y 144..192, x 176..255
--       { 0x98, 0xC0, 0x58, 0xA8 }      4  RUN    y 152..192, x  88..168
--
-- and the keypad grid laid over the same buttons agrees, which is what makes
-- this a reading rather than a guess at a screenshot:
--
--     sBattleMenuButtonLayout[2][3] = { {0,0,0}, {1,3,2} }
--
-- Two rows of three.  FIGHT (button 0) spans the whole top row; underneath,
-- left to right, button 1 (ITEM), button 3 (RUN), button 2 (PARTY).  The x
-- ranges and the table say the same thing twice over.
Gen4Battle.ACTION_RECTS = {
  fight = { top = 24,  bottom = 144, left = 0,   right = 255 },
  item  = { top = 144, bottom = 192, left = 0,   right = 80  },
  party = { top = 144, bottom = 192, left = 176, right = 255 },
  run   = { top = 152, bottom = 192, left = 88,  right = 168 },
}
Gen4Battle.ACTION_GRID = {
  { "fight", "fight", "fight" },
  { "item",  "run",   "party" },
}

-- The move list, the same way -- sMoveSelectMenuTouchRects with
-- sMoveSelectButtonResults beside it, and sMoveMenuButtonLayout[3][2] =
-- { {1,2}, {3,4}, {0,0} } confirming a 2x2 grid over a full-width cancel bar:
--
--       { 0x98, 0xC0, 0x08, 0xF8 }  0xFF  cancel  y 152..192, x   8..248
--       { 0x18, 0x50, 0x00, 0x80 }     1  move 1  y  24.. 80, x   0..128
--       { 0x18, 0x50, 0x80, 0xFF }     2  move 2  y  24.. 80, x 128..255
--       { 0x58, 0x90, 0x00, 0x80 }     3  move 3  y  88..144, x   0..128
--       { 0x58, 0x90, 0x80, 0xFF }     4  move 4  y  88..144, x 128..255
--
-- Note where the column split falls: 128 of 256, exactly half.  That is the
-- one number the staged layout below borrows from the cartridge.
Gen4Battle.MOVE_RECTS = {
  [1] = { top = 24, bottom = 80,  left = 0,   right = 128 },
  [2] = { top = 24, bottom = 80,  left = 128, right = 255 },
  [3] = { top = 88, bottom = 144, left = 0,   right = 128 },
  [4] = { top = 88, bottom = 144, left = 128, right = 255 },
}
Gen4Battle.MOVE_CANCEL = { top = 152, bottom = 192, left = 8, right = 248 }

-- STAGED -- and marked, the way Gen3Battle marks its own reconstructions.
--
-- The four rectangles above are a whole 256x192 surface.  Drawn over the main
-- screen they would cover the battle; drawn on the second screen they are the
-- cartridge's picture exactly, which is where they belong and what
-- src/ui/SecondScreen.lua exists for.  That route is the next piece of work
-- and these constants are what it will use.
--
-- Until then the menus go where every other version in this launcher puts
-- them: inside the message box, which is the one region of this screen the
-- cartridge already gives to words.  Two columns rather than the cartridge's
-- three, because two lines of sixteen is what the window holds -- so the
-- three-wide bottom row folds to two, and dropping the middle cell leaves
-- ITEM then PARTY, with RUN last:
--
--     FIGHT      BAG
--     POKeMON    RUN
--
-- which is the same order Gen3Battle reads out of Emerald's own menu string.
-- That agreement is the point: BAG and POKeMON do not swap places when a
-- player crosses from Hoenn to Sinnoh in this launcher.
Gen4Battle.ACTIONS = { "fight", "item", "pkmn", "run" }
Gen4Battle.ACTION_LABELS = { "FIGHT", "BAG", "POKeMON", "RUN" }

-- The move box: the same width as the message box, directly above it, so its
-- bottom border row (17) sits on the message box's top border row (18) rather
-- than overlapping it.  Four interior rows -> two lines of sixteen, two
-- columns, four moves.
Gen4Battle.MOVE_BOX = { tx = 1, ty = 12, tw = 29, th = 6 }
Gen4Battle.MOVE_ROWS = { 104, 120 }

-- The cartridge's own half-width split, carried onto the interior: the buttons
-- divide at 128 of 256, and the interior is 216 wide from x 16.
Gen4Battle.MENU_GAP = 108

-- Labels, overridable.  A later extractor stage can publish Platinum's own
-- four words as `constants.gen4BattleMenu` and they will be used without this
-- file changing; the literals are the floor, and they are the English the
-- cartridge prints.
function Gen4Battle.actionLabels(battle)
  local Strings = require("src.core.Strings")
  -- THE GREAT MARSH'S FOUR, in the same four places (BattleSubscreen_
  -- DrawActionMenu swaps the strings and nothing else).
  if battle and battle.gen4Safari then
    local G = require("src.battle.Gen4Safari")
    local out, fallback = {}, { "BALL", "BAIT", "MUD", "RUN" }
    for i, id in ipairs({ G.TEXT.labelBall, G.TEXT.labelBait, G.TEXT.labelMud, G.TEXT.labelRun }) do
      out[i] = G.text(battle.data, id) or Strings(fallback[i])
    end
    return out
  end
  local rec = battle and battle.data and battle.data.constants
             and battle.data.constants.gen4BattleMenu
  local out = {}
  for i = 1, 4 do
    local word = type(rec) == "table" and rec[i]
    out[i] = Strings(type(word) == "string" and word
                     or Gen4Battle.ACTION_LABELS[i])
  end
  return out
end

-- A line of already-encoded glyph codes, laid out proportionally.
--
-- The codes are what BattleState:startMessage typed -- Font.encode'd and
-- revealed one at a time -- so the drawing has to be code-wise, not
-- string-wise.  The PEN ADVANCES BY EACH GLYPH'S OWN WIDTH: Platinum's face is
-- proportional and a flat eight makes an 'i' as wide as a 'W', which is the
-- trap the Game Boy path does not have because Red's font is monospaced.
local function drawCodes(codes, x, y)
  local Font = require("src.render.Font")
  local pen = x
  for i = 1, #codes do
    Font.drawCode(codes[i], pen, y)
    pen = pen + Font.advanceOf(codes[i])
  end
  return pen
end

-- !! FORWARD-DECLARED, AND THIS IS NOT STYLE -- IT IS THE WHOLE TEXT AREA.
--
-- `bottomScreenUp` is defined with the menus, three hundred lines below, and
-- `Gen4Battle.drawTextArea` calls it. A FILE-LOCAL REFERENCED ABOVE ITS
-- `local function` LINE IS NOT THAT LOCAL: Lua resolves the name as a GLOBAL,
-- finds nil, and the call raises.
--
-- Reported from play as the text box, the FIGHT/BAG/POKeMON/RUN buttons and the
-- move list ALL MISSING -- which is exactly what it looks like from the outside,
-- because `Gen4Battle.draw` wraps the text area in a pcall so that a raise
-- there cannot take the field and the battlers down with it. The guard worked;
-- it just made the fault invisible. See below for what now makes it audible.
--
-- The same shape cost this project a whole command once before
-- (`itemKey` in Gen4Commands -- every buffertmhmmovename raised). The scan that
-- finds it is mechanical: for each `local function NAME`, look for `NAME(` at a
-- LOWER line number.
local bottomScreenUp
-- ...and the move-button data, read by drawTextArea above its definition.
local moveButtons

-- The selected move's type and PP. On the cartridge these are printed on the
-- BUTTON, and on either presentation the button is somewhere this cannot
-- write -- the other screen, or a slot too small for two lines -- so they go
-- in the message box, which is empty while a move is being chosen either way.
function Gen4Battle.drawMoveDetail(battle)
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local T, ROWS = Gen4Battle.MESSAGE_TEXT, Gen4Battle.MESSAGE_ROWS
  local chooser = battle:menuBattler()
  local mi = battle.moveIndex or 1
  local sel = chooser and chooser.curMoves and chooser.curMoves[mi]
  if not sel then return end
  local def = battle.data.moves[sel.id]
  love.graphics.setColor(0, 0, 0, 1)
  if chooser.disabledSlot == mi then
    Font.draw(Strings("disabled!"), T.x, ROWS[1])
  elseif def then
    local TypeChart = require("src.battle.TypeChart")
    Font.draw(Strings("TYPE/") ..
              (def.type and TypeChart.displayName(def.type) or ""),
              T.x, ROWS[1])
    local maxPP = def.pp + (sel.ppUps or 0) * math.floor(def.pp / 5)
    Font.draw(("PP %2d/%2d"):format(sel.pp, maxPP), T.x, ROWS[2])
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- WHICH OF THE THREE MENU PRESENTATIONS THIS FRAME GETS.
--
-- A DECISION WORTH TESTING IS WORTH NAMING. This lived inline in drawTextArea,
-- which meant the one thing a player can actually get wrong -- "I turned the
-- second screen off and still got the big one" -- could only be checked by
-- playing. It is a function now, and `tools/gen4_battlescene_check.lua` walks
-- every combination of the two settings and the one cache fact.
--
--   "bottom"   the bottom screen is up: the cartridge's whole picture goes on
--              that surface, at whatever size SecondScreen puts it
--   "compact"  put away: Platinum's four buttons nine-sliced into the strip
--   "words"    this cache has no subscreen art yet: the labels in the box
--
-- Returns nil for any phase that has no menu, which is what tells the caller
-- to draw the message box and nothing else.
function Gen4Battle.menuPresentation(battle, phase)
  phase = phase or (battle and battle.phase)
  if phase ~= "menu" and phase ~= "moveSelect" then return nil, nil end
  local up, SecondScreen = bottomScreenUp(battle and battle.game)
  if up then return "bottom", SecondScreen end
  if Gen4Battle.hasSubscreenArt(battle) then return "compact", SecondScreen end
  return "words", SecondScreen
end

-- PLATINUM'S TEXT AREA.
--
-- Reached through BattleState:drawTextArea rather than around it, for the
-- reason that method's own comment gives: a mod wrapping that name has to see
-- a Sinnoh battle too.
function Gen4Battle.drawTextArea(battle)
  local g = love.graphics
  local Font = require("src.render.Font")
  local Theme = require("src.ui.Theme")
  local Strings = require("src.core.Strings")
  local T, ROWS = Gen4Battle.MESSAGE_TEXT, Gen4Battle.MESSAGE_ROWS
  local LINE_H, GAP = Gen4Battle.MESSAGE_LINE_H, Gen4Battle.MENU_GAP
  local B = Gen4Battle.MESSAGE_BOX
  if Gen4Battle.extra(battle) > 0 then
    local copy = {}
    for k,v in pairs(B) do copy[k] = v end
    copy.tw = (copy.tw or 0) + Gen4Battle.extra(battle) / 8
    copy.w = (copy.w or 0) + Gen4Battle.extra(battle)
    B = copy
  end
  local phase = battle.phase

  -- WHICH PRESENTATION, DECIDED BEFORE ANYTHING IS DRAWN -- because the answer
  -- changes whether the message box's frame belongs on screen at all.
  --
  --   "bottom"   the bottom screen is up: the cartridge's whole picture goes
  --              on that surface and the strip here keeps the message box.
  --   "compact"  put away: Platinum's four buttons ARE the strip, so no frame
  --              is drawn under them -- a window with four buttons crammed
  --              inside reads as a mistake, and the buttons carry their own
  --              borders already.
  --   "words"    no subscreen art in this cache: the labels in the box, which
  --              is what this screen did before the art existed.
  local presentation, SecondScreen = Gen4Battle.menuPresentation(battle, phase)

  -- The move box sits above the message box and is drawn first, so the message
  -- box's own top border lands on top of the move box's bottom one. It is the
  -- fallback's furniture only: the other two presentations have their own.
  if phase == "moveSelect" and presentation == "words" then
    local M = Gen4Battle.MOVE_BOX
    Font.drawDialogueBox(M.tx, M.ty, M.tw, M.th)
  end
  if presentation ~= "compact" then
    Font.drawDialogueBox(B.tx, B.ty, B.tw, B.th)
  end
  g.setColor(0, 0, 0, 1)

  -- THE MESSAGE PHASE IS SINNOH'S, WITH OR WITHOUT WORDS IN IT.
  --
  -- Item 8 of the play-test list: *"A stray extra textbox appears in battle"*.
  -- This is it, and the condition above is where it came from.
  --
  -- Platinum's frame is already on screen by this point -- `drawDialogueBox`
  -- ran a few lines up, unconditionally.  The test used to be
  -- `phase == "messages" AND (battle.current or battle.animPlaying)`, so a
  -- message phase with no line to show right now -- the opening, while the
  -- queue is working through its waits and its callbacks -- matched NONE of the
  -- branches and fell through to the fallback at the bottom, which pushes the
  -- Game Boy's centring translate and calls `drawTextAreaInner`.  That function
  -- opens with `Font.drawBox(0, 12, 20, 6)`.
  --
  -- So the screen carried Platinum's message box AND the Game Boy's, the second
  -- one floating over the field where the centring translate put it.  Measured
  -- in the battle harness: a white box at x 55..200, y 127..160 present at tick
  -- 20 and gone by tick 120 -- gone because by then a line HAD arrived and the
  -- branch was taken.
  --
  -- An empty message box is the right answer for a message phase with nothing
  -- to say.  The Game Boy's box is not.
  if phase == "messages" then
   if battle.current or battle.animPlaying then
    -- The rolling two-line window and its one-row slide, exactly as the Game
    -- Boy path runs them -- only the rows and the pitch are Platinum's.
    if battle.scrollPx and battle.scrollPx > 0 then
      battle.scrollPx = battle.scrollPx - 2
      if battle.scrollPx <= 0 then battle.scrollPx = nil end
    end
    local off = battle.scrollPx or 0
    for li, line in ipairs(battle.shown or {}) do
      drawCodes(line, T.x, (ROWS[li] or ROWS[2]) + off)
    end
    -- The blinking wait marker.  STAGED: the cartridge builds this as a
    -- sprite out of frame tiles 10 and 11 (DrawMessageBoxScrollCursor) and
    -- positions it from the text printer, which this engine does not have --
    -- so it is the port's own arrow at the interior's bottom-right corner,
    -- which is where every other version in the launcher puts it.
    if (battle.msgWaiting or battle.msgPrompt)
       and (battle.frame or 0) % 60 < 30 then
      Font.drawCode(Theme.moreArrow, T.x + T.w + Gen4Battle.extra(battle) - 10, ROWS[2] + 4)
    end
   end
    return
  end

  if phase == "menu" then
    if presentation == "bottom"
       and Gen4Battle.drawBottomScreen(battle, SecondScreen, "action") then
      return
    end
    if presentation == "compact" and Gen4Battle.drawCompactActions(battle) then
      return
    end
    -- A presentation that said it could draw and then could not leaves the
    -- strip bare, so the words run anyway -- and because the frame was skipped
    -- for `compact`, draw it now rather than printing on the field.
    if presentation == "compact" then
      Font.drawDialogueBox(B.tx, B.ty, B.tw, B.th)
      g.setColor(0, 0, 0, 1)
    end
    -- THE WORDS FALLBACK LAYS OUT THE SAME SHAPE THE BUTTONS DO, which it did
    -- not before: it printed a 2x2 while the d-pad now walks Platinum's
    -- FIGHT-over-ITEM/RUN/PARTY grid, and a cursor that moves through a layout
    -- the player cannot see is the fault this pass was reported for. Two
    -- presentations of one menu have to agree about where things are.
    local labels = Gen4Battle.actionLabels(battle)
    local bottom = Gen4Battle.ACTION_BOTTOM
    local third = math.floor(T.w / 3)
    local function spot(index)
      for c, which in ipairs(bottom) do
        if which == index then return T.x + (c - 1) * third, ROWS[2] end
      end
      return T.x, ROWS[1]                     -- FIGHT, on its own row
    end
    local fx, fy = spot(Gen4Battle.ACTION_TOP)
    Font.draw(labels[Gen4Battle.ACTION_TOP] or "", fx + 10, fy)
    for c, which in ipairs(bottom) do
      Font.draw(labels[which] or "", T.x + (c - 1) * third + 10, ROWS[2])
    end
    local cx, cy = spot(battle.menuIndex)
    Font.drawCode(Theme.cursor, cx, cy)
    return
  end

  if phase == "moveSelect" then
    if presentation == "bottom"
       and Gen4Battle.drawBottomScreen(battle, SecondScreen, "moves") then
      -- The type and PP are ON THE BUTTONS now, as the cartridge prints them;
      -- a cache without the button data still gets them in the box.
      if not moveButtons(battle) then Gen4Battle.drawMoveDetail(battle) end
      return
    end
    if presentation == "compact" and Gen4Battle.drawCompactMoves(battle) then
      if not moveButtons(battle) then Gen4Battle.drawMoveDetail(battle) end
      return
    end
    if presentation == "compact" then
      Font.drawDialogueBox(Gen4Battle.MOVE_BOX.tx, Gen4Battle.MOVE_BOX.ty,
                           Gen4Battle.MOVE_BOX.tw, Gen4Battle.MOVE_BOX.th)
      Font.drawDialogueBox(B.tx, B.ty, B.tw, B.th)
      g.setColor(0, 0, 0, 1)
    end
    local chooser = battle:menuBattler()
    local rows = Gen4Battle.MOVE_ROWS
    for i, mv in ipairs(chooser.curMoves or {}) do
      local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
      local def = battle.data.moves[mv.id]
      Font.draw(def and def.name or tostring(mv.id),
                T.x + 10 + c * GAP, rows[r + 1] or rows[2])
    end
    local mi = battle.moveIndex
    local mc, mr = (mi - 1) % 2, math.floor((mi - 1) / 2)
    Font.drawCode((battle.moveSwapIndex == mi) and Theme.cursorHollow
                  or Theme.cursor,
                  T.x + mc * GAP, rows[mr + 1] or rows[2])
    if battle.moveSwapIndex and battle.moveSwapIndex ~= mi then
      local sc = (battle.moveSwapIndex - 1) % 2
      local sr = math.floor((battle.moveSwapIndex - 1) / 2)
      Font.drawCode(Theme.cursorHollow, T.x + sc * GAP, rows[sr + 1] or rows[2])
    end
    Gen4Battle.drawMoveDetail(battle)
    return
  end

  -- Anything else -- Mimic's copy menu, the demo script -- is still the
  -- engine's own, and the engine's own is Game Boy geometry, so it keeps the
  -- centring translate it had before.
  g.push()
  g.translate(Gen4Battle.CLASSIC_DX, Gen4Battle.CLASSIC_DY)
  pcall(function() battle:drawTextAreaInner() end)
  g.pop()
  g.setColor(1, 1, 1, 1)
end


-- ---------------------------------------------------------------------------
-- THE TWO GAUGES
--
-- These waited a long time on purpose. Their positions in the cartridge are
-- VRAM BYTE OFFSETS (sHPGaugeVRAMTransfer) that would have to become tiles and
-- then pixels, and the tile-to-pixel step rests on a layout the OAM
-- corroborates but nothing states twice. Every other number on this screen is
-- stated twice, so rather than write these down and check them later they were
-- left undrawn until the assembled art existed to check against.
--
-- IT EXISTS NOW, AND THREE SOURCES AGREE.
--
--  MEASURED OFF THE ART. In all three boxes the brown trough runs y 31..38,
--  and inside it, on rows 35 and 36, there is a dark channel of exactly 48
--  pixels -- at x 72 (player singles), 56 (enemy) and 64 (player doubles). The
--  singles box alone carries a second groove, 96 pixels at row 50, x 24.
--
--  STATED IN THE CARTRIDGE. HEALTHBOX_HP_CELL_COUNT is 6 and
--  HEALTHBOX_EXP_CELL_COUNT is 12, and CalcGaugeFill's own comment says
--  "gauges have 8 pixels per 'square' of fill". 6 x 8 = 48. 12 x 8 = 96.
--
--  STATED AGAIN. sHPGaugeVRAMTransfer's two runs per box sum to 0xC0 bytes =
--  6 tiles, in the same { position, size } format the name window's own
--  transfers use.
--
-- AND THEN THE ALIGNMENT PROVED ITSELF. The gauge is a tile substitution in the
-- healthbox sprite's character data, so it MUST fall on the box's own 8x8 grid.
-- The parts tile puts the HP bar on its rows 3-4 and the EXP bar on its row 2,
-- so the tiles' tops land at box rows 35-3 = 32 and 50-2 = 48. THOSE ARE BOTH
-- MULTIPLES OF EIGHT, and so are all three HP x's and the EXP x. Six
-- measurements taken off a picture with no knowledge of that constraint, and
-- all six satisfy it.
Gen4Battle.GAUGE_HP = {
  healthbox_player_singles = { x = 72, y = 32 },
  healthbox_enemy          = { x = 56, y = 32 },
  healthbox_player_doubles = { x = 64, y = 32 },
}
-- The EXP bar is the player's solo box and nothing else -- healthbox.c clears
-- HEALTHBOX_INFO_EXP_GAUGE for every enemy type and for both doubles slots.
Gen4Battle.GAUGE_EXP = { key = "healthbox_player_singles", x = 24, y = 48 }

-- App_BarColor (src/unk_0208C098.c), and the thing worth noticing is that it
-- is handed PIXELS, not HP: `App_BarColor(pixels, 8 * HEALTHBOX_HP_CELL_COUNT)`.
-- The ramp therefore steps where the BAR steps, not where the fraction does --
-- a mon on 25.1% of its HP shows yellow only once the bar has actually fallen
-- to ten pixels.
local function barRamp(pixels, width)
  if pixels > width / 2 then return "hp_green" end
  if pixels > width / 5 then return "hp_yellow" end
  return "hp_red"
end

-- FillCells / App_PixelCount: integer division, and BOTH of them force a
-- minimum of one pixel while the value is above zero. That is the rule that
-- keeps a sliver of HP visible instead of rounding a live Pokemon to an empty
-- bar.
local function gaugePixels(cur, max, width)
  max = math.max(1, tonumber(max) or 1)
  cur = math.max(0, math.min(max, tonumber(cur) or 0))
  local px = math.floor(cur * width / max)
  if px == 0 and cur > 0 then px = 1 end
  return px
end

-- Draw one gauge: `cells` tiles side by side, each showing how much of its own
-- eight pixels is filled. This is exactly what DrawGauge does -- it picks a
-- ramp, then copies one of FILL_0..FILL_8 into each cell's tile.
-- !! "hp" IS NOT A RAMP THE CACHE CARRIES, AND THE GUARD ASKED FOR IT ANYWAY.
--
-- This opened `local gauge = rec.gauges[rampName]` and bailed on nil -- which
-- is right for "exp" and WRONG for "hp", because there is no `gauges.hp`:
-- the cache carries `hp_green`, `hp_yellow` and `hp_red` and the ramp is
-- chosen from the fill BELOW, twelve lines after the guard had already
-- returned.  So the HP bar never drew, on any box, in any battle, while the
-- EXP bar beside it worked -- and `drawGauges` is called inside a `pcall`, so
-- nothing said anything either.
--
-- The width has to come from a real ramp too, and all three are the same six
-- cells; `hp_green` stands in for measuring it, with the other two accepted
-- in case an odd cache carries only one.
local function drawGauge(battle, rampName, x, y, cur, max)
  local rec, img, quads = partsFor(battle)
  if not (rec and rec.gauges and img and quads) then return false end
  local ramp = rec.gauges[rampName]
  local sizer = ramp
  if rampName == "hp" then
    sizer = rec.gauges.hp_green or rec.gauges.hp_yellow or rec.gauges.hp_red
  end
  if not sizer then return false end
  local width = sizer.width or ((sizer.cells or 0) * 8)
  if width <= 0 then return false end
  local px = gaugePixels(cur, max, width)
  if rampName == "hp" then
    ramp = rec.gauges[barRamp(px, width)]
  end
  if not ramp then return false end
  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, (ramp.cells or 0) - 1 do
    local filled = math.max(0, math.min(8, px - i * 8))
    local quad = quads[(ramp.part or 0) + filled]
    if quad then love.graphics.draw(img, quad, x + i * 8, y) end
  end
  return true
end

-- The gauges on one box, in the box's own pixels.
--
-- WHICH BOX SHOWS WHAT is the cartridge's rule, not a choice
-- (HealthBox_Draw, healthbox.c):
--   enemy boxes       never current HP, max HP, or the EXP bar
--   player doubles    never the EXP bar
--   player solo       never the caught-species ball
function Gen4Battle.drawGauges(battle, key, battler, boxX, boxY)
  local mon = battler and battler.mon
  if not mon then return end
  local hp = Gen4Battle.GAUGE_HP[key]
  if hp then
    local max = math.max(1, (mon.stats and mon.stats.hp) or 1)
    local now = math.max(0, math.floor(battler.shownHP or mon.hp or 0))
    drawGauge(battle, "hp", boxX + hp.x, boxY + hp.y, now, max)
  end
  local exp = Gen4Battle.GAUGE_EXP
  if key == exp.key and battler == battle.player and battle.expFraction then
    -- HOW FULL THE BAR IS, ASKED OF THE ENGINE rather than worked out here.
    -- BattleState:expFraction already answers "how much of this level has been
    -- earned" for the Gen 3 screen, and asking it again is what keeps the two
    -- bars agreeing while a level-up animation runs. Scaled to a thousand
    -- so the integer division above still lands on whole pixels.
    local ok, frac = pcall(battle.expFraction, battle)
    if ok and type(frac) == "number" then
      drawGauge(battle, "exp", boxX + exp.x, boxY + exp.y,
                math.max(0, math.min(1000, math.floor(frac * 1000 + 0.5))), 1000)
    end
  end
end


-- ---------------------------------------------------------------------------
-- THE MENUS, DRAWN FROM PLATINUM'S OWN BUTTONS
--
-- From the brief: *"for the two screen mode, when the bottom screen is up show
-- the fight run bag and pokemon buttons on there but when they have it put
-- away draw the button tiles next to the text box on the bottom of the screen
-- in the same art style but fit to the text boxes size"*.
--
-- So there are two presentations of one menu, and they share their art:
--
--   BOTTOM SCREEN UP    the cartridge's picture, untouched, at its own
--                       coordinates -- the base panel with the action layer
--                       over it, through src/ui/SecondScreen.lua.
--   PUT AWAY            the same four buttons NINE-SLICED into the message
--                       box's own strip, so they keep their colours, corners
--                       and bevel at a size that fits.
--
-- A DS'S BOTTOM SCREEN IS ON UNTIL YOU PUT IT AWAY, and a battle's menu is not
-- something the player opens -- it is where the menu lives until they say
-- otherwise. So this asks `SecondScreen.stowed`, the player's standing answer,
-- and NOT `raised`.
--
-- !! THOSE TWO ARE DIFFERENT QUESTIONS AND FOLDING THEM COST A REAL BUG.
-- `raised` is transient and belongs to whatever is on the bottom surface right
-- now: the Poketch sets it on open and clears it on close. Reading it here
-- meant that a player who had looked at the Poketch once in the field left it
-- false behind them, and every battle afterwards came up with its menu stowed
-- for no reason they could see -- with no way back, because nothing in a
-- battle set it again.
function bottomScreenUp(game)
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok or SecondScreen.mode(game) == "off" then return false, nil end
  return not SecondScreen.stowed(game), SecondScreen
end
Gen4Battle.bottomScreenUp = bottomScreenUp

local subscreenSheets = {}

-- WHICH BACKGROUND, AS A NUMBER. `backgroundFor` answers with a NAME, because
-- that is what the backdrop and platform pictures are keyed by; the subscreen's
-- recolouring layers are keyed by the cartridge's own INDEX, which is the map
-- header byte. Same rule, including the surfing override -- asked the other way
-- round rather than re-derived, so the two cannot disagree.
local BACKGROUND_INDEX
function Gen4Battle.backgroundIndexFor(game)
  if not BACKGROUND_INDEX then
    BACKGROUND_INDEX = {}
    for i, name in pairs(Gen4Battle.BACKGROUNDS) do BACKGROUND_INDEX[name] = i end
  end
  return BACKGROUND_INDEX[Gen4Battle.backgroundFor(game)] or 0
end

-- One composed layer of the bottom screen, for this battle's background.
-- `base`, `moves` and the rest follow the backdrop; `action` does not, and
-- Gen4Subscreen is what knows which.
local function subscreenLayer(battle, name)
  local gfx = graphics(battle)
  local rec = gfx and gfx.subscreen
  local row = rec and rec.layers and rec.layers[name]
  if not row then return nil end
  local bg = row.recolours and Gen4Battle.backgroundIndexFor(battle.game) or 0
  local path = row.images and (row.images[bg] or row.images[0])
  if not path then return nil end
  local sheet = subscreenSheets[path]
  if sheet == nil then
    sheet = image(path) or false
    subscreenSheets[path] = sheet
  end
  return sheet or nil
end

-- A nine-slice of one button, drawn at any size.
--
-- The corners and the top and bottom bands keep their own pixels; only the
-- flat middle stretches. The inset is CLAMPED to the target as well as the
-- source, because the compact strip asks for buttons shorter than twice the
-- corner -- without the clamp the two corners would overlap and the middle
-- would have negative height.
local sliceQuads = {}
local function nineSlice(img, src, dx, dy, dw, dh)
  if not (img and src) or dw < 3 or dh < 3 then return false end
  local inset = math.min(src.inset or 8,
                         math.floor((src.w - 1) / 2), math.floor((src.h - 1) / 2),
                         math.floor((dw - 1) / 2), math.floor((dh - 1) / 2))
  if inset < 1 then return false end
  local key = ("%s:%d,%d,%d,%d,%d"):format(tostring(img), src.x, src.y,
                                           src.w, src.h, inset)
  local q = sliceQuads[key]
  if not q then
    local iw, ih = img:getDimensions()
    local sx = { src.x, src.x + inset, src.x + src.w - inset }
    local sy = { src.y, src.y + inset, src.y + src.h - inset }
    local sw = { inset, src.w - inset * 2, inset }
    local sh = { inset, src.h - inset * 2, inset }
    q = {}
    for r = 1, 3 do
      for c = 1, 3 do
        q[(r - 1) * 3 + c] =
          love.graphics.newQuad(sx[c], sy[r], sw[c], sh[r], iw, ih)
      end
    end
    q.sw, q.sh = sw, sh
    sliceQuads[key] = q
  end
  local dws = { inset, dw - inset * 2, inset }
  local dhs = { inset, dh - inset * 2, inset }
  local ox = { dx, dx + inset, dx + dw - inset }
  local oy = { dy, dy + inset, dy + dh - inset }
  love.graphics.setColor(1, 1, 1, 1)
  for r = 1, 3 do
    for c = 1, 3 do
      local sw, sh = q.sw[c], q.sh[r]
      if sw > 0 and sh > 0 and dws[c] > 0 and dhs[r] > 0 then
        love.graphics.draw(img, q[(r - 1) * 3 + c], ox[c], oy[r], 0,
                           dws[c] / sw, dhs[r] / sh)
      end
    end
  end
  return true
end
Gen4Battle.nineSlice = nineSlice

-- WHERE THE COMPACT BUTTONS GO, and the split between what is derived and what
-- is this port's.
--
-- DERIVED -- the HORIZONTAL layout is the cartridge's own, taken straight from
-- sActionMenuTouchRects: FIGHT spans the width, and underneath it BAG at
-- x 0..80, RUN at 88..168 and POKeMON at 176..255. Those columns are why the
-- strip reads as Platinum's even at a fifth of the height.
--
-- THE PORT'S -- the VERTICAL split. The cartridge gives FIGHT 71% of a
-- 168-pixel column; compressed into a strip that same share leaves the three
-- small buttons 15 to 18 pixels tall, and the dialogue face is SIXTEEN. So the
-- strip is halved instead, which is the one number here that was chosen rather
-- than read, and it is chosen for the only reason that matters at this size:
-- the words have to fit inside the buttons.
--
-- The strip is 64 pixels -- the bottom eight tile rows -- rather than the
-- message box's 48, because 48 halved is 24 and a 24-pixel button with a
-- 9-pixel corner at each end has six pixels of middle. It reaches one tile row
-- above the box's frame, over field that is empty backdrop while a menu is up.
--
-- !! AND IT WAS SIXTEEN PIXELS TOO HIGH AND SIXTEEN TOO TALL.
--
-- Reported from play: *"this is a little too tall, it should sit under the
-- players pokemons hp hud"*. It was `{ y = 128, h = 64 }` -- y 128..192 -- and
-- the player's solo healthbox is 128x64 drawn at (128, 84), so the two
-- overlapped by twenty pixels and the FIGHT button sat across the bottom of the
-- box.
--
-- MEASURED, off the assembled art rather than guessed: the player's singles box
-- is opaque on rows 11..52 of its 64, so on screen its plaque ends at
-- 84 + 52 = 136. And the strip has somewhere exact to go -- Platinum's own
-- message box is the full width of the screen at y 144..192
-- (MESSAGE_BOX above, and the frame arithmetic beside it). That is the one band
-- of this screen the cartridge already gives to the interface, it is 48 pixels
-- deep, and it clears the healthbox by eight.
--
-- So the strip IS the message box's band. Two rows of 24 rather than two of 32,
-- which is also what stops the buttons looking like a second HUD.
Gen4Battle.STRIP = { x = 0, y = 144, w = 256, h = 48 }
Gen4Battle.STRIP_PAD = 2

-- The four slots, in the engine's own menuIndex order. `x` and `w` are the
-- cartridge's columns; `row` is which half of the strip.
Gen4Battle.COMPACT_SLOTS = {
  { art = "fight", x = 0,   w = 256, row = 0 },
  { art = "item",  x = 0,   w = 80,  row = 1 },
  { art = "party", x = 176, w = 80,  row = 1 },
  { art = "run",   x = 88,  w = 80,  row = 1 },
}

-- MOVING BETWEEN THEM, and the engine's own 2x2 is not the shape on screen.
--
-- Reported from play: *"for gen4 im not able to smoothly select the options by
-- hitting up down left or right for the battle menu options"*. BattleState
-- walks the action menu as a 2x2 -- `col = (i-1) % 2`, `row = (i-1) // 2` --
-- which is right for every older game in this launcher and is not what Platinum
-- draws. The cartridge's own keypad grid is `sBattleMenuButtonLayout[2][3] =
-- { {0,0,0}, {1,3,2} }` (see ACTION_GRID above): FIGHT across the whole top
-- row, then ITEM, RUN, PARTY beneath it. Walking a 2x2 over a 1+3 layout is why
-- the cursor jumped about.
--
-- THE REMEMBERED COLUMN IS WHAT MAKES IT SMOOTH. FIGHT spans all three columns,
-- so "down" out of it has no single answer; keeping the column the player last
-- stood in means down-then-up returns you where you were instead of snapping to
-- an end. Left and right do nothing on FIGHT, because there is nowhere to go --
-- the button already occupies the whole row.
Gen4Battle.ACTION_TOP = 1               -- menuIndex of FIGHT
Gen4Battle.ACTION_BOTTOM = { 2, 4, 3 }  -- ITEM, RUN, PARTY, left to right

-- actionMove(index, dir, col) -> newIndex, newCol
function Gen4Battle.actionMove(index, dir, col)
  local bottom = Gen4Battle.ACTION_BOTTOM
  col = math.max(1, math.min(#bottom, math.floor(tonumber(col) or 1)))
  local where
  for i, v in ipairs(bottom) do if v == index then where = i end end
  if not where then
    -- on FIGHT (or anywhere unrecognised, which lands on FIGHT)
    if dir == "down" then return bottom[col], col end
    return Gen4Battle.ACTION_TOP, col
  end
  col = where
  if dir == "up" then return Gen4Battle.ACTION_TOP, col end
  if dir == "left" then col = math.max(1, col - 1) end
  if dir == "right" then col = math.min(#bottom, col + 1) end
  return bottom[col], col
end

function Gen4Battle.compactButtonRect(i)
  local S, pad = Gen4Battle.STRIP, Gen4Battle.STRIP_PAD
  local slot = Gen4Battle.COMPACT_SLOTS[i]
  if not slot then return S.x, S.y, 0, 0 end
  local h = S.h / 2
  return S.x + slot.x + pad, S.y + slot.row * h + pad,
         slot.w - pad * 2, h - pad * 2
end

-- THE MOVE LIST GOES TO THE BOTTOM OF THE SCREEN, and carries its own PP.
--
-- Requested from play: *"currently it shows the pp below the move tiles, move
-- them down so theyre on the bottom of the screen and include the pp of the
-- move as well as any other info the normal move tiles include"*. It was eight
-- rows above the message box with TYPE/PP printed in the box under it. Each
-- tile now carries what the cartridge's own button does -- name, type icon,
-- "PP cur/max" in its PP colour, the type's button colours -- so the box has
-- nothing left to say and the tiles take the bottom of the screen instead:
-- y 136..192, starting where the player's healthbox plaque ends (measured at
-- 84 + 52, see STRIP above), two rows of 28.
Gen4Battle.MOVE_STRIP = { x = 0, y = 136, w = 256, h = 56 }
Gen4Battle.MOVE_STRIP_PAD = 0
-- The cartridge's button is a dark frame round a panel that holds both lines
-- (measured off the mask: frame rows 0..11 and 51..54, panel between). Sliced
-- at its own 8-pixel inset into a 28-row tile the frame took 16 of the 28 rows
-- and the name landed on it, clipped; a 4-pixel inset keeps the frame's dark
-- edge and gives the panel the room.
Gen4Battle.MOVE_STRIP_INSET = 4

function Gen4Battle.compactMoveRect(i)
  local S, pad = Gen4Battle.MOVE_STRIP, Gen4Battle.MOVE_STRIP_PAD
  local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
  local w, h = S.w / 2, S.h / 2
  return S.x + c * w + pad, S.y + r * h + pad, w - pad * 2, h - pad * 2
end

-- Does this cache carry the bottom screen at all? Asked once, before anything
-- is drawn, because the answer decides whether a window frame goes down first.
--
-- A DATA QUESTION, DELIBERATELY -- it asks what the cache DECLARES, not whether
-- the picture loaded. Those are different failures and they want different
-- answers: a cache with no subscreen stage in it has no buttons and never will
-- until the next import, which is the "words" presentation; an image that
-- declines to load on one frame is a fault, and the draw returning false
-- already puts the frame and the labels down for it.
--
-- Folding them also made the decision untestable, because asking "did it load"
-- needs a graphics device and the check harness has none. A decision nobody can
-- test off-device is one that gets tested by playing.
function Gen4Battle.hasSubscreenArt(battle)
  local gfx = graphics(battle)
  local rec = gfx and gfx.subscreen
  local row = rec and rec.layers and rec.layers.action
  return (row and row.images and next(row.images) ~= nil) and true or false
end

-- ---------------------------------------------------------------------------
-- What a Platinum move button carries (src/import/Gen4MoveButtons.lua)
-- ---------------------------------------------------------------------------

moveButtons = function(battle)
  local data = battle and (battle.data or (battle.game and battle.game.data))
  return data and data.gen4_move_buttons or nil
end
Gen4Battle.hasMoveButtons = function(battle) return moveButtons(battle) ~= nil end

-- The move in slot i: its definition, type id and PP, or nil for an empty slot.
function Gen4Battle.moveSlot(battle, i)
  local chooser = battle.menuBattler and battle:menuBattler()
  local mv = chooser and chooser.curMoves and chooser.curMoves[i]
  if not mv then return nil end
  local def = battle.data and battle.data.moves and battle.data.moves[mv.id]
  local maxPP = def and def.pp and (def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)) or 0
  return { move = mv, def = def, typeId = def and tonumber(def.typeId),
           pp = tonumber(mv.pp) or 0, maxPP = maxPP }
end

-- The button body in its move's TYPE colours (`LoadMoveSelectPltt`), or in the
-- empty slot's (`LoadEmptyMoveSlotBg`), as an image the size of the button:
-- every pixel the mask says is drawn from the slot sub-palette, painted from
-- the same entry of the chosen palette. Cached per slot and type.
local buttonImages = {}
function Gen4Battle.moveButtonImage(battle, slot, typeId)
  local rec = moveButtons(battle)
  local mask = rec and rec.masks and rec.masks[slot]
  if not mask then return nil end
  local key = slot .. ":" .. tostring(typeId)
  local held = buttonImages[key]
  if held ~= nil then return held or nil end
  local pal = (typeId and rec.types[typeId]) or rec.empty
  local ok, img = pcall(function()
    local data = love.image.newImageData(mask.w, mask.h)
    for y = 0, mask.h - 1 do
      for x = 0, mask.w - 1 do
        local k = mask.index:byte(y * mask.w + x + 1)
        local c = k and k > 0 and pal[k + 1]
        if c then data:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1) end
      end
    end
    local made = love.graphics.newImage(data)
    made:setFilter("nearest", "nearest")
    return made
  end)
  buttonImages[key] = ok and img or false
  return ok and img or nil
end

local function rgb01(c)
  c = c or {}
  return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, 1 }
end

-- The button's words and icon, laid out as `BattleSubscreen_DrawMoveSelectMenu`
-- does within a 128-wide column whose left edge is `colX`: the name centred
-- on x 64 (FONT_SUBSCREEN, TEXT_COLOR(7,8,9) on OBJ palette 3) in the window
-- whose top is `nameTop`; the type icon at x 16 and "PP" at x 59 and the
-- count at x 76 (FONT_SYSTEM, `GetPPTextColor` on OBJ palette 4), all on the
-- row whose top is `infoTop`. An empty slot carries nothing.
-- `small`: the single-screen strip's tiles, which are half the cartridge
-- button's height. Requested from play: *"shrink the type icon for the moves
-- and the pp/pp text to better fit in the buttons"* -- so the info row is
-- drawn at three-quarter size, its icon, "PP" and count packed left to right
-- under the name rather than spread across the cartridge's 128-wide layout.
Gen4Battle.SMALL_INFO_SCALE = 0.75
function Gen4Battle.drawMoveFace(battle, i, colX, nameTop, infoTop, small)
  local slot = Gen4Battle.moveSlot(battle, i)
  if not slot then return end
  local Font = require("src.render.Font")
  local Sub = require("src.import.Gen4MoveButtons")
  local rec = moveButtons(battle)
  local text = rec and rec.text
  local g = love.graphics
  local name = slot.def and slot.def.name or tostring(slot.move.id)
  local faced = Font.pushFace("subscreen")
  local tone = text and Font.beginTwoTone(rgb01(text.name[8]), rgb01(text.name[9]))
  if not tone then g.setColor(0, 0, 0, 1) end
  local tw = Font.width and Font.width(name) or (#name * 8)
  Font.draw(name, math.floor(colX + 64 - tw / 2), nameTop)
  if tone then Font.endTwoTone() end
  if faced then Font.popFace() end
  g.setColor(1, 1, 1, 1)
  local typeName = slot.def and slot.def.type and tostring(slot.def.type):lower()
  local icon = typeName and image("assets/generated/gen4/battle/type_icons_" .. typeName .. ".png")
  local ink, shadow = Sub.ppColour(slot.pp, slot.maxPP)
  local count = ("%2d/%2d"):format(slot.pp, slot.maxPP)
  if small then
    -- One row, centred in the column: icon, gap, "PP", gap, count -- all at
    -- SMALL_INFO_SCALE, drawn in a scaled space so the pixel font stays crisp
    -- relative to itself.
    local k = Gen4Battle.SMALL_INFO_SCALE
    faced = Font.pushFace("system")
    local ppW = Font.width and Font.width("PP") or 16
    local cW = Font.width and Font.width(count) or 40
    if faced then Font.popFace() end
    local iconW = icon and (icon:getWidth()) or 0
    local total = iconW + 4 + ppW + 3 + cW
    local x0 = colX + 64 - total * k / 2
    g.push()
    g.translate(math.floor(x0), infoTop)
    g.scale(k, k)
    if icon then g.draw(icon, 0, 0) end
    faced = Font.pushFace("system")
    tone = text and Font.beginTwoTone(rgb01(text.pp[ink + 1]), rgb01(text.pp[shadow + 1]))
    if not tone then g.setColor(0, 0, 0, 1) end
    Font.draw("PP", iconW + 4, 0)
    Font.draw(count, iconW + 4 + ppW + 3, 0)
    if tone then Font.endTwoTone() end
    if faced then Font.popFace() end
    g.pop()
    g.setColor(1, 1, 1, 1)
    return
  end
  if icon then g.draw(icon, colX + 16, infoTop) end
  faced = Font.pushFace("system")
  tone = text and Font.beginTwoTone(rgb01(text.pp[ink + 1]), rgb01(text.pp[shadow + 1]))
  if not tone then g.setColor(0, 0, 0, 1) end
  Font.draw("PP", colX + 59, infoTop)
  Font.draw(count, colX + 76, infoTop)
  if tone then Font.endTwoTone() end
  if faced then Font.popFace() end
  g.setColor(1, 1, 1, 1)
end

-- The compact MOVE list: the four buttons along the bottom of the screen, each
-- carrying its own type colours, type icon and PP (see MOVE_STRIP).
function Gen4Battle.drawCompactMoves(battle)
  local Font = require("src.render.Font")
  local ok, Sub = pcall(require, "src.import.Gen4Subscreen")
  local art = subscreenLayer(battle, "moves")
  local chooser = battle:menuBattler()
  if not (ok and art and chooser) then return false end
  local sel = battle.moveIndex or 1
  local full = moveButtons(battle) ~= nil
  for i = 1, 4 do
    local src = Sub.MOVE_BUTTONS[i]
    local x, y, w, h = Gen4Battle.compactMoveRect(i)
    local inset = full and Gen4Battle.MOVE_STRIP_INSET or src.inset
    local cut = { x = src.x, y = src.y, w = src.w, h = src.h, inset = inset }
    if not nineSlice(art, cut, x, y, w, h) then return false end
    local slot = Gen4Battle.moveSlot(battle, i)
    if full then
      local body = Gen4Battle.moveButtonImage(battle, i, slot and slot.typeId)
      if body then
        nineSlice(body, { x = 0, y = 0, w = src.w, h = src.h, inset = inset },
                  x, y, w, h)
      end
    end
    if i == sel then
      love.graphics.setColor(1, 1, 1, 0.28)
      love.graphics.rectangle("fill", x + 2, y + 2, w - 4, h - 4)
      love.graphics.setColor(1, 1, 1, 1)
    end
    if full then
      -- The column's left edge, so the cartridge's x offsets land as they do on
      -- its 128-wide half of the screen; the two rows squeezed into the tile.
      local colX = ((i - 1) % 2) * 128
      Gen4Battle.drawMoveFace(battle, i, colX, y, y + h - 14, true)
    else
      local mv = chooser.curMoves and chooser.curMoves[i]
      local def = mv and battle.data.moves[mv.id]
      local text = def and def.name or (mv and tostring(mv.id)) or "-"
      local tw = Font.width and Font.width(text) or (#text * 8)
      local th = Font.glyphHeight and Font.glyphHeight() or 8
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(text, math.floor(x + (w - tw) / 2), math.floor(y + (h - th) / 2))
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  return true
end

-- The compact action menu: Platinum's four buttons in the message box's strip.
function Gen4Battle.drawCompactActions(battle)
  local Font = require("src.render.Font")
  local ok, Sub = pcall(require, "src.import.Gen4Subscreen")
  local art = subscreenLayer(battle, "action")
  if not (ok and art) then return false end
  local labels = Gen4Battle.actionLabels(battle)
  local selected = battle.menuIndex or 1
  for i = 1, 4 do
    local slot = Gen4Battle.COMPACT_SLOTS[i]
    local src = Sub.ACTION_BUTTONS[slot and slot.art]
    local x, y, w, h = Gen4Battle.compactButtonRect(i)
    if not nineSlice(art, src, x, y, w, h) then return false end
    -- THE SELECTED ONE IS LIT, NOT OUTLINED. The cartridge highlights a
    -- pressed button by swapping in a whole second tilemap (`moves_pressed`);
    -- there is no pressed art for the action buttons, so this is the port's
    -- own mark and is said to be. A wash rather than a border because the
    -- buttons already have borders and a second one reads as a glitch.
    if i == selected then
      love.graphics.setColor(1, 1, 1, 0.28)
      love.graphics.rectangle("fill", x + 2, y + 2, w - 4, h - 4)
      love.graphics.setColor(1, 1, 1, 1)
    end
    local text = labels[i] or ""
    local tw = Font.width and Font.width(text) or (#text * 8)
    local th = Font.glyphHeight and Font.glyphHeight() or 8
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(text, math.floor(x + (w - tw) / 2),
              math.floor(y + (h - th) / 2))
    love.graphics.setColor(1, 1, 1, 1)
  end
  return true
end

-- The whole bottom screen, as the cartridge draws it: the base panel with the
-- action layer over it. Drawn through SecondScreen, which owns where that
-- surface is and at what scale -- whole window on `swap`, a corner panel on
-- `inset` -- so nothing here has to know.
-- THE WORDS, which the cartridge's art does not carry.
--
-- Reported from play: *"in battles with the bottom screen theres no text for the
-- moves or fight, bag, pkmn, or run buttons"*.  Opening the extracted layers
-- settles why in a second: `action.png` is a big red panel and three small
-- coloured ones, `moves_00.png` is four cream panels and a blue bar, and there is
-- not a letter anywhere in either.  The DS prints the words into WINDOWS over the
-- buttons at run time rather than baking them into the tilemap, so a port that
-- draws the tilemap and stops gets exactly what was reported: the right buttons,
-- unlabelled.
--
-- The compact presentation has drawn these all along (`drawCompactActions`,
-- `drawCompactMoves`); the bottom-screen one never did.  Same labels, same
-- source, centred in the cartridge's own rectangles.
local function centreText(text, rect)
  local Font = require("src.render.Font")
  if not (text and rect) then return end
  local tw = Font.width and Font.width(text) or (#text * 8)
  local th = Font.glyphHeight and Font.glyphHeight() or 8
  Font.draw(text, math.floor(rect.left + (rect.right - rect.left - tw) / 2),
            math.floor(rect.top + (rect.bottom - rect.top - th) / 2))
end

-- Black, because every one of these panels is a light or saturated fill and the
-- compact buttons are lettered the same way.
-- THE CARTRIDGE'S OWN LABELS, where `BattleSubscreen_DrawActionMenu` and
-- `_DrawMoveSelectMenu` put them: FONT_SUBSCREEN centred on x, `y` the centre
-- of a 16-row window, each in its own TEXT_COLOR trio on sub OBJ palette 2.
-- menuIndex order: FIGHT, BAG, POKeMON, RUN.
Gen4Battle.ACTION_LABEL_SPOTS = {
  { x = 128, y = 84,  ink = 1,  shadow = 2 },
  { x = 40,  y = 170, ink = 4,  shadow = 5 },
  { x = 216, y = 170, ink = 7,  shadow = 8 },
  { x = 128, y = 178, ink = 10, shadow = 11 },
}
Gen4Battle.CANCEL_LABEL_SPOT = { x = 128, y = 178, ink = 10, shadow = 11 }

local function drawLabelAt(battle, text, spot)
  local Font = require("src.render.Font")
  local rec = moveButtons(battle)
  local pal = rec and rec.text and rec.text.action
  local faced = Font.pushFace("subscreen")
  local tone = pal and Font.beginTwoTone(rgb01(pal[spot.ink + 1]), rgb01(pal[spot.shadow + 1]))
  if not tone then love.graphics.setColor(0, 0, 0, 1) end
  local tw = Font.width and Font.width(text) or (#text * 8)
  Font.draw(text, math.floor(spot.x - tw / 2), spot.y - 8)
  if tone then Font.endTwoTone() end
  if faced then Font.popFace() end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4Battle.drawBottomLabels(battle, over)
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  if over == "action" and moveButtons(battle) then
    local labels = Gen4Battle.actionLabels(battle)
    for i = 1, 4 do
      if labels[i] then drawLabelAt(battle, labels[i], Gen4Battle.ACTION_LABEL_SPOTS[i]) end
    end
  elseif over == "action" then
    local labels = Gen4Battle.actionLabels(battle)
    for i = 1, 4 do
      local slot = Gen4Battle.COMPACT_SLOTS[i]
      centreText(labels[i], slot and Gen4Battle.ACTION_RECTS[slot.art])
    end
  elseif over == "moves" and moveButtons(battle) then
    -- THE CARTRIDGE'S OWN BUTTON FACE: name, type icon and PP, at
    -- `BattleSubscreen_DrawMoveSelectMenu`'s positions (font OAM y is the
    -- centre of a 16-row window, so the windows' tops are 38 and 54).
    g.setColor(1, 1, 1, 1)
    for i = 1, 4 do
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      Gen4Battle.drawMoveFace(battle, i, col * 128, 38 + row * 64, 54 + row * 64)
    end
    -- ...and the bar under them, which the cartridge labels too.
    local Strings = require("src.core.Strings")
    drawLabelAt(battle, Strings("CANCEL"), Gen4Battle.CANCEL_LABEL_SPOT)
  elseif over == "moves" then
    local chooser = battle.menuBattler and battle:menuBattler()
    for i = 1, 4 do
      local mv = chooser and chooser.curMoves and chooser.curMoves[i]
      -- An empty slot is left BLANK rather than drawn with a dash: the
      -- cartridge hides the button entirely, and a labelled empty button is an
      -- invitation to press something that does nothing.
      if mv then
        local def = battle.data and battle.data.moves and battle.data.moves[mv.id]
        centreText(def and def.name or tostring(mv.id), Gen4Battle.MOVE_RECTS[i])
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- WHICH BUTTON A TAP LANDED ON, in bottom-screen pixels.  The rectangles are the
-- cartridge's own touch rects -- sBattleMenuTouchRects and
-- sMoveSelectMenuTouchRects -- so this is the same hit test the DS does, not a
-- second set of boxes drawn to match the first.
--
-- Returns "action"|"move" with an index, or "cancel", or nil.
function Gen4Battle.bottomHit(x, y, over)
  -- HALF-OPEN, because the cartridge's compare is unsigned:
  --
  --     (touchX - left < right - left) & (touchY - top < bottom - top)
  --
  -- On u32, `touchX - left` wraps to something enormous when touchX is left of
  -- the rect, so that one expression is `touchX >= left and touchX < right`.
  -- Bottom and right are EXCLUSIVE.
  --
  -- Written inclusive first, and the check caught it: FIGHT's bottom is 144 and
  -- ITEM's and PARTY's top is 144, so an inclusive test makes row 144 belong to
  -- two buttons at once and the first one wins. One row of pixels, and the kind
  -- of thing nobody ever notices and nobody can explain when they do.
  local function inside(r)
    return r and x >= r.left and x < r.right and y >= r.top and y < r.bottom
  end
  if over == "action" then
    for i = 1, 4 do
      local slot = Gen4Battle.COMPACT_SLOTS[i]
      if inside(slot and Gen4Battle.ACTION_RECTS[slot.art]) then return "action", i end
    end
  elseif over == "moves" then
    -- CANCEL FIRST.  Its bar overlaps nothing, but the move rects run to y 144
    -- and the bar starts at 152, so testing it last would still be right and
    -- testing it first makes that independent of the numbers.
    if inside(Gen4Battle.MOVE_CANCEL) then return "cancel" end
    for i = 1, 4 do
      if inside(Gen4Battle.MOVE_RECTS[i]) then return "move", i end
    end
  end
  return nil
end
function Gen4Battle.drawBottomScreen(battle, SecondScreen, over)
  local base = subscreenLayer(battle, "base")
  local top = subscreenLayer(battle, over)
  if not (base or top) then return false end
  local g = love.graphics
  SecondScreen.draw(battle.game, function()
    g.setColor(1, 1, 1, 1)
    if base then g.draw(base, 0, 0) end
    if top then g.draw(top, 0, 0) end
    -- Each move button in its move's TYPE colours, or the empty slot's.
    if over == "moves" and moveButtons(battle) then
      local Sub = require("src.import.Gen4Subscreen")
      for i = 1, 4 do
        local slot = Gen4Battle.moveSlot(battle, i)
        local body = Gen4Battle.moveButtonImage(battle, i, slot and slot.typeId)
        local r = Sub.MOVE_BUTTONS[i]
        if body and r then g.draw(body, r.x, r.y) end
      end
    end
    -- Over the buttons and UNDER the cursor wash, so the highlight tints the
    -- word with the button rather than covering it.
    Gen4Battle.drawBottomLabels(battle, over)
    -- The cursor, in the engine's own marker rather than the cartridge's
    -- `cursor` tilemap: that layer draws all four move outlines at once and
    -- has nothing for the action buttons, so it cannot say WHICH is chosen.
    local Theme = require("src.ui.Theme")
    local Font = require("src.render.Font")
    local rect
    if over == "action" then
      local slot = Gen4Battle.COMPACT_SLOTS[battle.menuIndex or 1]
      rect = slot and Gen4Battle.ACTION_RECTS[slot.art]
    else
      rect = Gen4Battle.MOVE_RECTS[battle.moveIndex or 1]
    end
    if rect then
      g.setColor(1, 1, 1, 0.25)
      g.rectangle("fill", rect.left, rect.top,
                  rect.right - rect.left, rect.bottom - rect.top)
      g.setColor(0, 0, 0, 1)
      Font.drawCode(Theme.cursor, rect.left + 4, rect.top + 4)
      g.setColor(1, 1, 1, 1)
    end
  end)
  SecondScreen.drawFrame(battle.game)
  return true
end

-- THE THROWN BALL, over the Pokemon and under the HUD.
--
-- Over, because a ball that vanishes behind the thing it is being thrown at is
-- the one placement that is certainly wrong; under the HUD, because the boxes
-- are the screen's furniture and nothing in a battle draws on top of them.
--
-- The timing and the cell come from `Gen4BallAnim`, which reads the
-- cartridge's own NANR; this only puts the named cell where the anim says.
function Gen4Battle.drawThrownBall(battle)
  local anim = battle and battle.gen4Ball
  if not (anim and anim.visible) then return false end
  local Gen4BattleRT = require("src.battle.Gen4Battle")
  local name = anim.ball
  local gfx = graphics(battle)
  local key = Gen4BattleRT.ballThrowFrame(name, anim.cell or 0)
  local row = gfx and gfx.battleObjects and gfx.battleObjects[key]
  if not row then
    -- SAID ONCE, because a ball that silently does not draw is exactly the
    -- failure this whole item started as.
    if not battle.saidBallMissing then
      battle.saidBallMissing = true
      Logger.warn("gen4 ball: no frame '%s' in the cache -- the throw will not "
                  .. "draw (run tools/gen4_ball_throw_check.lua)", tostring(key))
    end
    return false
  end
  local img = image(row.path)
  if not img then return false end
  local g = love.graphics
  local w, h = img:getDimensions()
  g.setColor(1, 1, 1, 1)
  -- Rotated about its own centre, so a shake rocks the ball rather than
  -- swinging it around a corner.
  g.draw(img, anim.x, anim.y, anim.angle or 0, 1, 1, w / 2, h / 2)
  return true
end

function Gen4Battle.draw(battle)
  local g = love.graphics
  battle:drawBattleField()
  if battle.blankForAskName then return end

  -- THE BACKGROUND'S OWN PALETTE FADE, BETWEEN THE FIELD AND THE BATTLERS.
  -- `fadebg` blends the BACKGROUND's palettes and nothing else, so it has to land
  -- after the field is drawn and before the Pokemon are -- a tint over the whole
  -- screen would dim them too, which the cartridge does not.
  Gen4Battle.drawBackgroundFade(battle)

  -- ...and then the switched background itself, over the blacked-out field and
  -- under the Pokemon, which is where BG3 sits.
  Gen4Battle.drawEffectBackground(battle)

  Gen4Battle.drawBattlers(battle)
  pcall(Gen4Battle.drawEnemyTrainer, battle)

  -- The trainer, while the first Pokemon is still in its ball.  Before the
  -- thrown ball so a send-out throw draws over the trainer rather than under.
  pcall(Gen4Battle.drawTrainerBack, battle)

  -- ...and the thrown ball on top of them.
  pcall(Gen4Battle.drawThrownBall, battle)

  -- Platinum's own boxes when the cache has them assembled; otherwise nothing
  -- here and the stand-in below carries the whole HUD as it did before.
  local boxes = false
  local okBoxes, result = pcall(Gen4Battle.drawHealthboxes, battle)
  if okBoxes then boxes = result end

  -- The name-and-level panels are STILL the engine's when Platinum's boxes have
  -- not assembled, and the engine's are Game Boy geometry -- so they keep the
  -- centring translate, pushed and popped around so nothing downstream inherits
  -- it.  A transform left on is the kind of thing that moves the NEXT screen
  -- instead of this one.
  if not boxes then
    g.push()
    g.translate(Gen4Battle.CLASSIC_DX, Gen4Battle.CLASSIC_DY)
    pcall(function() battle:drawHUDs(0) end)
    g.pop()
  end

  -- THE TEXT AREA IS PLATINUM'S NOW and is written in DS coordinates, so it is
  -- drawn OUTSIDE the translate.  Through the method rather than around it:
  -- BattleState:drawTextArea dispatches here, which is what keeps a mod that
  -- wraps that name working on a Sinnoh battle.
  --
  -- A raise inside it must not take the whole battle down with it: the field,
  -- the battlers and the boxes above are already on screen and are the part
  -- this file is responsible for.
  --
  -- !! BUT IT MUST NOT BE SILENT EITHER. This guard once hid a nil-global raise
  -- for a whole session: every menu frame raised, the pcall caught it, and the
  -- bottom of the screen was simply blank -- which reads as "the text box was
  -- never written" rather than "the text box is crashing". Said ONCE, because
  -- it raises sixty times a second and a log that scrolls is a log nobody
  -- reads.
  local ok, err = pcall(function() battle:drawTextArea() end)
  if not ok then
    g.setColor(1, 1, 1, 1)
    if not Gen4Battle._textAreaRaised then
      Gen4Battle._textAreaRaised = true
      local okLog, Logger = pcall(require, "src.core.Logger")
      if okLog and Logger and Logger.warn then
        Logger.warn("gen4 battle: the text area raised and was caught -- the "
                    .. "message box and menus will be missing until it is "
                    .. "fixed: %s", tostring(err))
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- THE BALL THROW: WHICH ART EACH BALL USES
-- ---------------------------------------------------------------------------
--
-- For item 6, *"Ball catching animations do not play"*.  The art was already
-- being extracted -- `ball_throws/` has been in `OBJ_FAMILIES` above all along
-- and the cache holds twenty sets of ten 16x16 frames -- but nothing said which
-- set belongs to which ball, so nothing could use them.
--
-- THE ARCHIVE THIS PORT EXTRACTED FOR THIS IS THE WRONG ONE, and that is worth
-- writing down because it cost a pass.  `ball_particle.narc`'s 117 effects are
-- the BALL CAPSULE SEALS: pokeplatinum opens that NARC in exactly one place,
-- `ov12_02235E94.c`, from `BallCapsuleSealEffect`, and nowhere else.  The throw
-- is not a particle effect at all -- it is a 2D cell animation out of
-- `pl_batt_obj`, the archive this file already describes.
--
-- THE ORDER IS `sBallThrowGraphics`, and the row is `ballId - 1`
-- (`ov12_02235E94`), with an id outside the table falling back to row 3, the
-- plain Poke Ball.  The ball id IS an item id -- `MON_DATA_POKEBALL` is
-- compared straight against `ITEM_LUXURY_BALL` in `item_use_pokemon.c`.
--
-- CROSS-CHECKED TWO WAYS rather than taken from the one source: pret's table
-- runs master, ultra, great, poke, safari... and this port's OWN extracted item
-- cache numbers them 1 Master, 2 Ultra, 3 Great, 4 Poke, 5 Safari, ... 16
-- Cherish.  The two orders agree, which is what makes `ballId - 1` a
-- measurement rather than a guess.
--
-- Rows 17-19 are the Safari Zone throws -- park, mud, bait -- which are not
-- reached by an item id and are named here so a caller can ask for them
-- directly.
Gen4Battle.BALL_THROWS = {
  [0] = "master_ball",
  "ultra_ball", "great_ball", "poke_ball", "safari_ball", "net_ball",
  "dive_ball", "nest_ball", "repeat_ball", "timer_ball", "luxury_ball",
  "premier_ball", "dusk_ball", "heal_ball", "quick_ball", "cherish_ball",
  "park_ball", "mud", "bait",
}

-- The row an out-of-range id falls back to: `ov12_02235E94` answers 4 and then
-- subtracts one, which is the plain Poke Ball and not the first row.
Gen4Battle.BALL_THROW_DEFAULT = 3

-- How the `gen4_graphics` stage names a frame of one of these.
function Gen4Battle.ballThrowFrame(name, frame)
  return ("ball_throws_%s_%02d"):format(tostring(name), tonumber(frame) or 0)
end

-- ballThrowFor(itemId) -> the art name, never nil.
--
-- `ov12_02235E94` transcribed: an id of 1..(0xFF+20) indexes directly, anything
-- else takes the Poke Ball.  The 0xFF+ band is how the cartridge reaches the
-- Safari throws, which have no item of their own.
function Gen4Battle.ballThrowFor(itemId)
  local id = tonumber(itemId)
  local row
  if not id or id < 1 or id > (0xFF + 20) then
    row = Gen4Battle.BALL_THROW_DEFAULT
  elseif id >= 0xFF then
    row = id - 0xFF - 1
  else
    row = id - 1
  end
  return Gen4Battle.BALL_THROWS[row]
         or Gen4Battle.BALL_THROWS[Gen4Battle.BALL_THROW_DEFAULT]
end

return Gen4Battle
