-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK AND WHITE'S WILD TABLES, AS THE FIELD READS THEM.
--
-- /a/1/2/6 (src/import/Gen5Encounters.lua) gives each zone seven lists --
-- grass, dark grass, the phenomenon list (shaking grass, dust clouds and
-- flying shadows all draw from it), surf, rippling surf, the Super Rod and
-- the rippling Super Rod -- and the 18 zones whose wild Pokemon change with
-- the season carry four copies, spring to winter. Encounter.forMap used to
-- hand back spring's grass, surf and rod and nothing else, all year.
--
-- Checked against PKHeX's encounter_b / encounter_w (built from the
-- cartridges): every Black table matches (261 of 261, all seasons and all
-- seven kinds); White matches except White Forest (location 51), whose
-- Pokemon are not in any zone's table (scratch bwfield/tools/cmpenc.py).

local Rules = require("src.world.Gen5FieldRules")

local W = {}

local cache = setmetatable({}, { __mode = "k" })

-- view(def, save) -> the Gen 4-shaped view Encounter.forMap returns, for
-- this month's season, with the Gen 5 kinds beside it
function W.view(def, save)
  local Encounter = require("src.world.Encounter")
  local season = Rules.seasonName(save)
  local t = def
  if def.seasons and season ~= "spring" and def.seasons[season] then t = def.seasons[season] end
  local hit = cache[def]
  if hit and hit.bwSeason == season then return hit end
  local function tbl(slots, rate) return slots and Encounter.gen4Table(slots, rate) or nil end
  local view = { family = "bw", id = def.id, bwSeason = season, raw = t }
  view.grassRate = t.grassRate
  view.grass = tbl(t.grass, t.grassRate)
  view.darkGrass = tbl(t.darkGrass, t.darkGrassRate)
  if view.darkGrass then view.darkGrass.dark = true end     -- kind 1 (no outbreak)
  view.rustling = tbl(t.rustling, t.rustlingRate)
  view.water = t.surf and tbl(t.surf.slots, t.surf.rate) or nil
  view.ripplingWater = t.ripplingSurf and tbl(t.ripplingSurf.slots, t.ripplingSurf.rate) or nil
  view.superRod = t.superRod and tbl(t.superRod.slots, t.superRod.rate) or nil
  view.ripplingRod = t.ripplingFishing and tbl(t.ripplingFishing.slots, t.ripplingFishing.rate) or nil
  -- the shapes the rest of the engine asks for (surf as `surf`, rods by name)
  view.surf = t.surf
  cache[def] = view
  return view
end

-- THE WILD BATTLE THE FIELD STARTS (OverworldState's step encounter):
--
--   * the terrain under it, for Nature Power (src/battle/Gen5MoveRules.lua):
--     water while surfing, grass, sand, a cave floor, else plain ground;
--   * DARK GRASS: the battle is a thick-grass one (`gen5ThickGrass`, the
--     capture's grass modifier in src/battle/Gen5Catching.lua), and it is a
--     DOUBLE 40% of the time when the party has two Pokemon able to battle.
--     ov21 0x021A9462: for encounter kind 1 (dark grass, the classifier at
--     0x021AA35C), `0x0201AA50(party) >= 2` (the able count) and
--     `0x021A9DC8() < 0x28` (Random() / 656, 0..99) set the double flag
--     (0x20); [+0x15] = flag + 1 Pokemon are drawn, each from the dark grass
--     list, and the flag is dropped again if the second draw comes back
--     empty (0x021AA056).
W.DOUBLE_PERCENT = 40

local function terrainOf(map, cx, cy, onWater)
  if onWater then return "water" end
  local b = Rules.behaviour(map, cx, cy)
  if b == nil then return "plain" end
  if Rules.GRASS[b] then return "grass" end
  if b == 0x0C or b == 0x23 then return "sand" end
  if Rules.CAVE_FLOOR[b] then return "cave" end
  return "plain"
end
W.terrainOf = terrainOf

local function ableCount(party)
  local n = 0
  for _, mon in ipairs(party or {}) do
    if (tonumber(mon.hp) or 0) > 0 and not mon.isEgg and not mon.egg then n = n + 1 end
  end
  return n
end

function W.prepareBattle(state, battle, view, dark, onWater, rng)
  if not battle then return end
  rng = rng or love.math.random
  local map, p = state and state.map, state and state.player
  battle.gen5Terrain = terrainOf(map, p and p.cellX, p and p.cellY, onWater)
  if not dark then return end
  battle.gen5ThickGrass = true
  local Game = state.game or require("src.core.Game")
  local save = Game.save
  if ableCount(save and save.party) < 2 or rng(0, 99) >= W.DOUBLE_PERCENT then return end
  local Encounter = require("src.world.Encounter")
  -- the second draw shares the first's lead decision and refusals (0x021A9508)
  local WL = require("src.world.Gen5WildLead")
  local enc2 = view and view.darkGrass and WL.draw(Game.data, save, view.darkGrass,
    WL.last or WL.flags(Game.data, save, rng), rng)
  if not (enc2 and enc2.species) then return end
  local BattleState = require("src.battle.BattleState")
  local tmp = BattleState.newWild(Game, enc2.species, enc2.level,
    (enc2.nature or enc2.gender) and { nature = enc2.nature, gender = enc2.gender } or nil)
  local second = tmp and tmp.enemy and tmp.enemy.mon
  if not second then return end
  battle:makeWildDouble(second)
  battle.gen5ThickGrassDouble = true
end

-- landFor(view, map, cx, cy) -> the grass-shaped table for this tile: dark
-- grass rolls its own list (ov21 0x021AB250's behaviours)
function W.landFor(view, map, cx, cy)
  if not view then return nil end
  if view.darkGrass and Rules.isDarkGrass(map, cx, cy) then return view.darkGrass end
  return view.grass
end

return W
