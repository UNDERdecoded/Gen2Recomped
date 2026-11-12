-- RANDOMIZER OPTIONS: the catalog of what the randomizer can change, and the
-- per-save switches.
--
--   save.runModes.random = { learnsets = true, baseStats = "shuffle", ... }
--
-- Two older switches live at the top of save.runModes (randomWild,
-- randomStarters) and are listed here with `top = true`, so the screen and the
-- FULL preset treat every option the same way.  Everything else lives in
-- `random`.  A save without the field randomizes nothing.
--
-- Each option names the generations it does something on (`gens`); the
-- screen shows the others greyed out with the reason.
--
-- The data-side options are applied by src/runmodes/RandomData.lua (moves,
-- learnsets, TM compatibility, types, abilities, base stats, evolutions,
-- prices, trainer names, field items); the rest are picked at the moment they
-- happen by src/runmodes/RunHooks.lua (wild, starters, statics and gifts,
-- trainer teams, held items, starting moves, marts, item gifts, relearner).

local RunModes = require("src.runmodes.RunModes")

local RandomOptions = {}

local ALL = { 1, 2, 3, 4, 5 }

-- cat: POKEMON / MOVES / ITEMS / TRAINERS
local LIST = {
  -- POKEMON
  { key = "randomWild", top = true, cat = "POKEMON", label = "WILD POKéMON", gens = ALL,
    help = "Every wild encounter is a random POKéMON of about the same strength." },
  { key = "randomStarters", top = true, cat = "POKEMON", label = "STARTERS", gens = ALL,
    help = "The starter POKéMON are random. The rival follows your pick." },
  { key = "statics", cat = "POKEMON", label = "GIFT & STATIC POKéMON", gens = ALL,
    help = "Gift POKéMON and one-off overworld battles are random. Legendaries keep their species." },
  { key = "types", cat = "POKEMON", label = "POKéMON TYPES", gens = ALL,
    help = "Every species gets random types (single stays single, dual stays dual)." },
  { key = "abilities", cat = "POKEMON", label = "ABILITIES", gens = { 3, 4, 5 },
    help = "Every species gets random abilities. Wonder Guard and form abilities are left out." },
  { key = "baseStats", cat = "POKEMON", label = "BASE STATS", gens = ALL,
    values = { false, "shuffle", "random" }, valueLabels = { "OFF", "SHUFFLE", "RANDOM" },
    help = "SHUFFLE swaps a species' stats around; RANDOM deals them out again. The total stays the same." },
  { key = "evolutions", cat = "POKEMON", label = "EVOLUTIONS", gens = ALL,
    help = "Each evolution leads to a random species of about the same strength. Methods stay." },
  { key = "heldItems", cat = "POKEMON", label = "HELD ITEMS", gens = { 2, 3, 4, 5 },
    help = "Items held by wild and trainer POKéMON are random." },
  -- MOVES
  { key = "learnsets", cat = "MOVES", label = "LEVEL-UP MOVES", gens = ALL,
    help = "Random level-up moves. Every other move is an attack, and level 1 always has one." },
  { key = "keepLv1", cat = "MOVES", label = " KEEP LV1 ATTACK", gens = ALL, sub = "learnsets",
    help = "With random level-up moves: keep each species' own level-1 attack." },
  { key = "startMoves", cat = "MOVES", label = "STARTING MOVES", gens = ALL,
    help = "Wild and trainer POKéMON come with four random moves, at least one an attack." },
  { key = "tmCompat", cat = "MOVES", label = "TM COMPATIBILITY", gens = ALL,
    help = "Which POKéMON can use which TM is random. HM compatibility is kept, so the way stays open." },
  { key = "tutorCompat", cat = "MOVES", label = "TUTOR COMPATIBILITY", gens = { 3, 4 },
    help = "Which POKéMON a move tutor can teach is random." },
  { key = "movePower", cat = "MOVES", label = "MOVE POWER", gens = ALL,
    help = "Attacks get a random power from 20 to 150. Fixed-damage moves stay." },
  { key = "moveAccuracy", cat = "MOVES", label = "MOVE ACCURACY", gens = ALL,
    help = "Moves get a random accuracy (attacks 70-100%). Sure-hit and one-hit KO moves stay." },
  { key = "movePP", cat = "MOVES", label = "MOVE PP", gens = ALL,
    help = "Moves get a random PP from 5 to 40." },
  { key = "moveType", cat = "MOVES", label = "MOVE TYPES", gens = ALL,
    help = "Attacks get a random type. Struggle, Curse, Hidden Power and the like keep theirs." },
  { key = "moveCategory", cat = "MOVES", label = "MOVE CATEGORY", gens = { 4, 5 },
    help = "Attacks are randomly physical or special." },
  { key = "relearner", cat = "MOVES", label = "MOVE RELEARNER", gens = { 2, 3, 4, 5 },
    help = "The move relearner offers a random list of moves for each POKéMON." },
  -- ITEMS / SHOPS
  { key = "martItems", cat = "ITEMS", label = "MART ITEMS", gens = ALL,
    help = "Each mart sells random items. POKé BALLS and POTIONS it sold stay on the shelf." },
  { key = "martPrices", cat = "ITEMS", label = "ITEM PRICES", gens = ALL,
    help = "Prices are random, between half and double. Balls never cost more than usual." },
  { key = "fieldItems", cat = "ITEMS", label = "FIELD ITEMS & GIFTS", gens = ALL,
    help = "Items on the ground, hidden items and item gifts are random. Key items and HMs stay." },
  -- TRAINERS
  { key = "trainerTeams", cat = "TRAINERS", label = "TRAINER POKéMON", gens = ALL,
    help = "Trainers' POKéMON are random, about as strong as before. Levels stay." },
  { key = "trainerNames", cat = "TRAINERS", label = "TRAINER NAMES", gens = { 2, 3, 4, 5 },
    help = "Trainers swap names within their class. Leaders, rivals and bosses keep theirs." },
}
RandomOptions.LIST = LIST

local BY_KEY = {}
for i, o in ipairs(LIST) do BY_KEY[o.key] = o; o.order = i end
RandomOptions.BY_KEY = BY_KEY

RandomOptions.CATEGORIES = {
  { id = "POKEMON", label = "POKéMON" },
  { id = "MOVES", label = "MOVES" },
  { id = "ITEMS", label = "ITEMS & SHOPS" },
  { id = "TRAINERS", label = "TRAINERS" },
}

-- the values FULL sets
RandomOptions.FULL = {}
for _, o in ipairs(LIST) do
  if o.key == "keepLv1" then
    RandomOptions.FULL[o.key] = false
  elseif o.values then
    RandomOptions.FULL[o.key] = o.values[2]
  else
    RandomOptions.FULL[o.key] = true
  end
end

-- bumped on every change, so RandomData.sync notices without hashing a save
RandomOptions.rev = 0

function RandomOptions.supports(o, gen)
  if type(o) == "string" then o = BY_KEY[o] end
  if not o then return false end
  if not gen then return true end
  for _, g in ipairs(o.gens or ALL) do if g == gen then return true end end
  return false
end

-- the value of option `key` in a runModes-like table (save.runModes, or a
-- NEW GAME choice); false when off
function RandomOptions.read(rm, key)
  if type(rm) ~= "table" then return false end
  local o = BY_KEY[key]
  local v
  if o and o.top then v = rm[key] else v = type(rm.random) == "table" and rm.random[key] or nil end
  if v == nil then return false end
  return v
end

-- the value for a save (or Game)
function RandomOptions.get(x, key)
  local rm = RunModes.get(x)
  if rm == RunModes.OFF then return false end
  return RandomOptions.read(rm, key)
end

function RandomOptions.on(x, key)
  local v = RandomOptions.get(x, key)
  return v ~= false and v ~= nil
end

-- write option `key` into a runModes-like table
function RandomOptions.write(rm, key, value)
  local o = BY_KEY[key]
  if not o or type(rm) ~= "table" then return false end
  if value == false then value = nil end
  if o.top then
    rm[key] = value and true or nil
  else
    if value ~= nil then
      rm.random = type(rm.random) == "table" and rm.random or {}
      rm.random[key] = value
    elseif type(rm.random) == "table" then
      rm.random[key] = nil
      if next(rm.random) == nil then rm.random = nil end
    end
  end
  RandomOptions.rev = RandomOptions.rev + 1
  return true
end

-- set an option on a live save: creates save.runModes (with a seed) when the
-- save has none, keeps the seed when it has one
function RandomOptions.set(save, key, value)
  if type(save) ~= "table" or not BY_KEY[key] then return false end
  local rm = save.runModes
  if type(rm) ~= "table" then
    if not value then return true end
    rm = { v = RunModes.VERSION, seed = RunModes._rollSeed() }
    save.runModes = rm
  end
  if not rm.seed then rm.seed = RunModes._rollSeed() end
  return RandomOptions.write(rm, key, value)
end

-- the next value of a cycling option (OFF -> ON, or through `values`)
function RandomOptions.nextValue(key, current)
  local o = BY_KEY[key]
  if not o then return false end
  if not o.values then return not (current and current ~= false) end
  local idx = 1
  for i, v in ipairs(o.values) do if v == (current or false) then idx = i end end
  return o.values[idx % #o.values + 1]
end

function RandomOptions.label(key, value)
  local o = BY_KEY[key]
  if o and o.values then
    for i, v in ipairs(o.values) do if v == (value or false) then return o.valueLabels[i] end end
  end
  return (value and value ~= false) and "ON" or "OFF"
end

-- FULL: every option on (supported or not -- an unsupported one is a no-op)
function RandomOptions.applyFull(rm)
  for _, o in ipairs(LIST) do RandomOptions.write(rm, o.key, RandomOptions.FULL[o.key]) end
end

function RandomOptions.clearAll(rm)
  for _, o in ipairs(LIST) do RandomOptions.write(rm, o.key, false) end
end

-- how many options are on; `gen` counts only those that do something there
function RandomOptions.count(rm, gen)
  local n = 0
  for _, o in ipairs(LIST) do
    if (not gen or RandomOptions.supports(o, gen)) and RandomOptions.read(rm, o.key) then n = n + 1 end
  end
  return n
end

function RandomOptions.isFull(rm)
  for _, o in ipairs(LIST) do
    local want = RandomOptions.FULL[o.key]
    if want and RandomOptions.read(rm, o.key) ~= want then return false end
  end
  return true
end

-- does anything data-side (RandomData) apply to this runModes table?
RandomOptions.DATA_KEYS = { "learnsets", "tmCompat", "tutorCompat", "movePower", "moveAccuracy",
  "movePP", "moveType", "moveCategory", "types", "abilities", "baseStats", "evolutions",
  "heldItems", "martPrices", "fieldItems", "trainerNames" }

function RandomOptions.anyData(rm)
  for _, k in ipairs(RandomOptions.DATA_KEYS) do
    if RandomOptions.read(rm, k) then return true end
  end
  return false
end

-- a stable signature of the data-side options (RandomData's cache key)
function RandomOptions.signature(rm)
  local parts = { tostring(type(rm) == "table" and rm.seed or "-") }
  for _, k in ipairs(RandomOptions.DATA_KEYS) do
    local v = RandomOptions.read(rm, k)
    if v then parts[#parts + 1] = k .. "=" .. tostring(v) end
  end
  if RandomOptions.read(rm, "keepLv1") then parts[#parts + 1] = "keepLv1" end
  return table.concat(parts, ";")
end

return RandomOptions
