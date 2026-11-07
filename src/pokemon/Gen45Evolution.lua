-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- GEN 4 AND GEN 5 EVOLUTION METHODS, for Evolution.METHODS.
--
-- Platinum / HeartGold / SoulSilver records carry the method by NAME
-- (src/import/Gen4Species.lua EVOLUTION_METHODS, 26 of them, each identified
-- from the cartridge's own evolutions); Black / White's carry the raw NUMBER
-- (src/import/Gen5Data.lua), and Black / White's enum is Gen 4's with one
-- method put in at 7 -- the trade for a particular Pokemon (Karrablast 588 and
-- Shelmet 616, each `7 -> the other`) -- and the rest moved up one, which the
-- cartridge's own rows confirm: 8 Pikachu with a Thunder Stone (83), 9..11
-- Tyrogue at 20, 12/13 Wurmple, 14/15 Nincada, 16 Feebas at beauty 170,
-- 17/18 Kirlia / Snorunt with a Dawn Stone (109), 19 Happiny with an Oval
-- Stone (110), 20 Gligar / Sneasel holding Razor Fang / Claw, 21 knows a move,
-- 22 Mantyke with Remoraid (223), 23/24 Burmy, 25 Magneton / Nosepass,
-- 26 Leafeon, 27 Glaceon.
--
-- Only `level` was registered, so every other evolution of both generations --
-- friendship, stones, trades, Tyrogue, Wurmple, the held-item and location
-- ones -- could not happen, and Black / White's numbers matched nothing at all.
--
-- `param` is a level, an item, a move, a species or a beauty by method, never
-- one thing; it is read per method below. Friendship evolves at 220 (as in
-- Gen 2/3). Day and night are Gen 4's: night 20:00-03:59.

local M = {}

local function E() return require("src.pokemon.Evolution") end
local function num(v) return tonumber(v) or 0 end
local function levelOf(mon) return num(mon.level) end
local function friendship(game, mon)
  local v = tonumber(mon.happiness or mon.friendship)
  if v then return v end
  local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return num(def and (def.baseFriendship or def.friendship))
end
function M.isNight(hour)
  hour = tonumber(hour) or tonumber(os.date("%H")) or 12
  return hour >= 20 or hour < 4
end
-- Pokemon_GetEvolutionTargetSpecies: the Everstone stops every evolution
-- but an item's -- except KADABRA's ("bypasses Everstone", both decomps)
local KADABRA = 64
-- ITEM_EVERSTONE is 229 in all three games; Black / White's item records
-- carry the hold effect as a number, which holdsEverstone cannot read
local EVERSTONE = 229
local function everstoneBlocks(game, mon)
  local held = tonumber(mon.item) or tonumber(tostring(mon.item or ""):match("(%d+)%s*$"))
  local stone = held == EVERSTONE or E().holdsEverstone(game, mon)
  return stone and (tonumber(mon.species) or 0) ~= KADABRA
end
M.everstoneBlocks = everstoneBlocks
local function levelUp(game, mon, trigger)
  return trigger.kind == "levelup" and not everstoneBlocks(game, mon)
end
local function gender(game, mon)
  if mon.gender == "male" or mon.gender == 0 then return "male" end
  if mon.gender == "female" or mon.gender == 1 then return "female" end
  local ok, g = pcall(require("src.pokemon.Gen4DayCare").gender, game and game.data, mon)
  return ok and g or "none"
end
local function holds(game, mon, item)
  return mon.item ~= nil and (num(mon.item) == num(item) or E().itemMatches(game, mon.item, item))
end
local function itemIs(trigger, item)
  return trigger.kind == "item" and (num(trigger.item) == num(item) or num(trigger.rawItem) == num(item))
end
local function stat(mon, key) return num(mon.stats and mon.stats[key]) end
local function speciesNum(v) return tonumber(v) or tonumber(tostring(v or ""):match("(%d+)%s*$")) or 0 end
local function knowsMove(mon, move)
  for _, m in ipairs(mon.moves or {}) do
    if num(type(m) == "table" and m.id or m) == num(move) then return true end
  end
  return false
end
local function inParty(game, species)
  for _, m in ipairs((game.save and game.save.party) or {}) do
    if not m.isEgg and speciesNum(m.species) == num(species) then return true end
  end
  return false
end
-- the map the player stands on, by its label: Mt. Coronet / Chargestone Cave
-- for the magnetic field, Eterna Forest / Pinwheel Forest for the Moss Rock,
-- Route 217 / Twist Mountain for the Ice Rock (the cartridges test the map)
--
-- PLATINUM tests the MAP HEADER, not the name (map_header.c
-- MapHeader_GetMapEvolutionMethod): Route 217 (385) only -- not its houses;
-- Eterna Forest (203) only -- not the outside map (202); Mt. Coronet
-- 207..219, Spear Pillar 220/221/584/585 and the Hall of Origin 510/511 --
-- not the Iceberg Ruins (589), though it is labelled Mt. Coronet.
-- HEARTGOLD / SOULSILVER have none (MapHeader_GetMapEvolutionMethod returns
-- EVO_NONE: "Leftover from D/P/Pl."). Black / White keep the label match
-- (INFERRED).
M.PLACES = {
  magnetic = { "Mt. Coronet", "Chargestone Cave" },
  moss = { "Eterna Forest", "Pinwheel Forest" },
  ice = { "Route 217", "Twist Mountain" },
}
M.PT_HEADERS = { [385] = "ice", [203] = "moss", [220] = "magnetic", [221] = "magnetic",
  [510] = "magnetic", [511] = "magnetic", [584] = "magnetic", [585] = "magnetic" }
for h = 207, 219 do M.PT_HEADERS[h] = "magnetic" end
local function family()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.family and GV.family() or nil
end
local function placeIs(game, kind)
  local ow
  for i = #((game.stack and game.stack.states) or {}), 1, -1 do
    local st = game.stack.states[i]
    if type(st) == "table" and st.player and st.map then ow = st break end
  end
  local def = ow and ow.map and ow.map.def
  local fam = family()
  if fam == "hgss" then return false end
  if fam == "platinum" then
    return def ~= nil and M.PT_HEADERS[tonumber(def.header) or -1] == kind
  end
  local label = def and (def.label or def.name)
  if type(label) ~= "string" then return false end
  for _, name in ipairs(M.PLACES[kind] or {}) do
    if label == name or label:find(name, 1, true) then return true end
  end
  return false
end

M.TRADE_PAIR = { [588] = 616, [616] = 588 }

local function rec(check, describe, extra)
  local r = { check = check, describe = describe or function() return "" end }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

M.BY_NAME = {
  friendship = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and friendship(game, mon) >= 220
  end, function() return "Friendship" end),
  friendshipDay = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and friendship(game, mon) >= 220 and not M.isNight()
  end, function() return "Friendship (day)" end),
  friendshipNight = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and friendship(game, mon) >= 220 and M.isNight()
  end, function() return "Friendship (night)" end),
  trade = rec(function(game, mon, evo, t)
    return t.kind == "trade" and not everstoneBlocks(game, mon)
  end, function() return "Trade" end),
  tradeWithItem = rec(function(game, mon, evo, t)
    return t.kind == "trade" and holds(game, mon, evo.param)
  end, function() return "Trade holding an item" end, { consumesHeldItem = true }),
  -- the rows carry no partner (param 0): the pair is Karrablast and Shelmet,
  -- each traded for the other
  tradeForSpecies = rec(function(game, mon, evo, t)
    local partner = M.TRADE_PAIR[speciesNum(mon.species)]
    return t.kind == "trade" and not everstoneBlocks(game, mon)
      and partner ~= nil and speciesNum(t.partnerSpecies) == partner
  end, function() return "Trade for a particular Pokemon" end),
  useItem = rec(function(game, mon, evo, t) return itemIs(t, evo.param) end,
    function() return "Use an item" end, { consumesItem = true }),
  useItemMale = rec(function(game, mon, evo, t) return itemIs(t, evo.param) and gender(game, mon) == "male" end,
    function() return "Use an item (male)" end, { consumesItem = true }),
  useItemFemale = rec(function(game, mon, evo, t) return itemIs(t, evo.param) and gender(game, mon) == "female" end,
    function() return "Use an item (female)" end, { consumesItem = true }),
  levelAtkGreater = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param) and stat(mon, "attack") > stat(mon, "defense")
  end),
  levelAtkEqual = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param) and stat(mon, "attack") == stat(mon, "defense")
  end),
  levelAtkLess = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param) and stat(mon, "attack") < stat(mon, "defense")
  end),
  -- Wurmple: (personality >> 16) % 10, 0..4 one way and 5..9 the other
  levelPidLow = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param)
      and math.floor(num(mon.personality) / 65536) % 10 < 5
  end),
  levelPidHigh = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param)
      and math.floor(num(mon.personality) / 65536) % 10 >= 5
  end),
  levelNinjask = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param)
  end),
  -- the Shedinja row never evolves the Pokemon itself: the Ninjask row's
  -- evolution makes it (Evolution's LEVEL_SHEDINJA path does the same)
  levelShedinja = rec(function() return false end),
  beauty = rec(function(game, mon, evo, t)
    local b = num(mon.beauty or (mon.contest and mon.contest.beauty) or (mon.condition and mon.condition.beauty))
    return levelUp(game, mon, t) and b >= num(evo.param)
  end),
  levelHoldingItemDay = rec(function(game, mon, evo, t)
    return t.kind == "levelup" and holds(game, mon, evo.param) and not M.isNight()
  end, nil, { consumesHeldItem = true }),
  levelHoldingItemNight = rec(function(game, mon, evo, t)
    return t.kind == "levelup" and holds(game, mon, evo.param) and M.isNight()
  end, nil, { consumesHeldItem = true }),
  levelKnowsMove = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and knowsMove(mon, evo.param)
  end),
  levelSpeciesInParty = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and inParty(game, evo.param)
  end),
  levelMale = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param) and gender(game, mon) == "male"
  end),
  levelFemale = rec(function(game, mon, evo, t)
    return levelUp(game, mon, t) and levelOf(mon) >= num(evo.param) and gender(game, mon) == "female"
  end),
  magneticField = rec(function(game, mon, evo, t) return levelUp(game, mon, t) and placeIs(game, "magnetic") end),
  mossRock = rec(function(game, mon, evo, t) return levelUp(game, mon, t) and placeIs(game, "moss") end),
  iceRock = rec(function(game, mon, evo, t) return levelUp(game, mon, t) and placeIs(game, "ice") end),
}

-- Black / White's numbers
M.BW = {
  [1] = "friendship", [2] = "friendshipDay", [3] = "friendshipNight", [4] = "level",
  [5] = "trade", [6] = "tradeWithItem", [7] = "tradeForSpecies", [8] = "useItem",
  [9] = "levelAtkGreater", [10] = "levelAtkEqual", [11] = "levelAtkLess",
  [12] = "levelPidLow", [13] = "levelPidHigh", [14] = "levelNinjask", [15] = "levelShedinja",
  [16] = "beauty", [17] = "useItemMale", [18] = "useItemFemale",
  [19] = "levelHoldingItemDay", [20] = "levelHoldingItemNight",
  [21] = "levelKnowsMove", [22] = "levelSpeciesInParty", [23] = "levelMale", [24] = "levelFemale",
  [25] = "magneticField", [26] = "mossRock", [27] = "iceRock",
}

-- into Evolution.METHODS: the names (kept where already defined). The
-- methods registry takes string ids only, so Black / White's NUMBERS are not
-- registered: Evolution.pendingFor asks M.nameOf for them at lookup
-- HGSS: "Spiky-ear Pichu cannot evolve" (pokeheartgold GetMonEvolutionInternal)
function M.blocked(game, mon)
  return (tonumber(mon.species) or 0) == 172 and (tonumber(mon.form) or 0) == 1
end
for _, r in pairs(M.BY_NAME) do
  local check = r.check
  r.check = function(game, mon, evo, t)
    if M.blocked(game, mon) then return false end
    return check(game, mon, evo, t)
  end
end
function M.install(methods)
  for name, r in pairs(M.BY_NAME) do
    if methods[name] == nil then methods[name] = r end
  end
end
-- an evolution the player cannot stop with B (Gen 4 / 5 only)
M.FORCED = { trade = true, tradeWithItem = true, tradeForSpecies = true, useItem = true,
  useItemMale = true, useItemFemale = true }
function M.forced(via)
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not (ok and (GV.isGen4() or GV.isGen5())) then return false end
  if via == nil then return true end
  local name = (type(via) == "number") and M.BW[via] or via
  return M.FORCED[name] == true
end
function M.nameOf(method)
  return type(method) == "number" and M.BW[method] or nil
end

-- AFTER THE EVOLUTION (Evolution.apply calls this once the species and
-- stats have changed):
--   * a held-item method (trade with an item, level holding one by day /
--     night) uses the item up -- the Metal Coat, the Oval Stone, the Razor Fang
--   * Nincada -> Ninjask makes the Shedinja too: a free party slot and a Poke
--     Ball in the Bag (item 4, used up), a copy of the evolved Pokemon as the
--     levelShedinja row's species with nothing held and no nickname
local function methodName(evo)
  if not evo then return nil end
  return (type(evo.method) == "number") and M.BW[evo.method] or evo.method
end
M.POKE_BALL = 4
function M.afterApply(game, mon, fromSpecies, evo)
  local name = methodName(evo)
  local r = name and M.BY_NAME[name]
  if r and r.consumesHeldItem then mon.item = nil end
  if name ~= "levelNinjask" then return nil end
  local save, data = game.save, game.data
  if not (save and data) or #(save.party or {}) >= 6 then return nil end
  local inv = save.inventory or {}
  local key = (inv[M.POKE_BALL] ~= nil) and M.POKE_BALL or tostring(M.POKE_BALL)
  if (tonumber(inv[key]) or 0) < 1 then return nil end
  local original = data.pokemon and data.pokemon[fromSpecies]
  local target
  for _, row in ipairs((original and original.evolutions) or {}) do
    if methodName(row) == "levelShedinja" then target = row.species or row.target end
  end
  local def = target and data.pokemon[target]
  if not def then return nil end
  local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
  end
  local extra = copy(mon)
  extra.species, extra.nickname, extra.item, extra.heldItem, extra.mail = target, nil, nil, nil, nil
  extra.status, extra.ribbons = nil, {}
  -- Evolution_ProcessEvolutionEffects: in a Poke Ball, no markings, the
  -- ability recalculated (Shedinja has one)
  extra.ball, extra.markings, extra.abilitySlot = M.POKE_BALL, 0, 1
  local Stats = require("src.pokemon.Stats")
  extra.stats = Stats.calc(def, extra.level, extra.ivs, nil, extra.evs, extra.nature)
  extra.hp = extra.stats.hp
  inv[key] = (tonumber(inv[key]) or 0) - 1
  if inv[key] <= 0 then inv[key] = nil end
  save.party[#save.party + 1] = extra
  if save.pokedex then
    save.pokedex.seen = save.pokedex.seen or {}
    save.pokedex.owned = save.pokedex.owned or {}
    save.pokedex.seen[target], save.pokedex.owned[target] = true, true
  end
  return extra
end

-- The species a Gen 4 / 5 evolution item turns this Pokemon into (or nil):
-- what the Bag's stone path asks, the trigger an item use is
function M.itemTarget(data, mon, itemId, rawItemId)
  local game = { data = data }
  local def = data and data.pokemon and data.pokemon[mon.species]
  def = def and require("src.pokemon.Gen4Forms").definition(data, mon) or def
  for _, evo in ipairs((def and def.evolutions) or {}) do
    local name = (type(evo.method) == "number") and M.BW[evo.method] or evo.method
    if name == "useItem" or name == "useItemMale" or name == "useItemFemale" then
      local r = M.BY_NAME[name]
      if r.check(game, mon, evo, { kind = "item", item = itemId, rawItem = rawItemId }) then
        return evo.species or evo.target
      end
    end
  end
  return nil
end

return M
