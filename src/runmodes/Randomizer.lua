-- RANDOMIZER: wild encounters and starters, seeded per save.
--
-- Every pick is a pure function of the save's seed and what it replaces.
-- WILD: each encounter is its own pick -- the hash also takes the save's
-- encounter counter (save.runModes.wildCount, advanced by RunHooks), so two
-- Zigzagoon in a row become two different species, and never the same one
-- twice running; the counter lives in the save, so a reload replays the
-- same sequence.  STARTERS: one stable pick per starter.  A replacement
-- keeps the original's strength band (base stat total within a window that
-- widens until it holds enough candidates -- 40 for wild mons, so a band is
-- a real choice), so Route 1 does not open on a Mewtwo.
--
-- Species ids are the dataset's own: "PIDGEY" (Gen 1/3), "SPECIES_016"
-- (Gen 2), 16 (Gen 4/5).  The pool is every species the loaded dataset can
-- show, deduped by national dex, capped at the generation's own dex.

local RunModes = require("src.runmodes.RunModes")

local Randomizer = {}

local DEX_MAX = { [1] = 151, [2] = 251, [3] = 386, [4] = 493, [5] = 649 }
Randomizer.DEX_MAX = DEX_MAX

local cache = setmetatable({}, { __mode = "k" })

local function generation()
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and GV and GV.generation then
    local okG, g = pcall(GV.generation)
    if okG and tonumber(g) then return tonumber(g) end
  end
  return nil
end

local function bst(rec)
  local s = type(rec) == "table" and rec.baseStats
  if type(s) ~= "table" then return 0 end
  local t = 0
  for _, v in pairs(s) do if type(v) == "number" then t = t + v end end
  return t
end

local function dexOf(id, rec)
  if type(rec) == "table" then
    local d = tonumber(rec.dex) or tonumber(rec.nationalDex) or tonumber(rec.national)
    if d then return d end
  end
  if type(id) == "number" then return id end
  local n = type(id) == "string" and id:match("^SPECIES_(%d+)$")
  return n and tonumber(n) or nil
end

-- the candidate list for a species table: { {id=, dex=, bst=}, ... } sorted by bst then dex
function Randomizer.pool(pokemon, gen)
  if type(pokemon) ~= "table" then return {} end
  local hit = cache[pokemon]
  if hit and hit.gen == gen then return hit.list end
  local max = DEX_MAX[gen or 0] or 649
  local byDex = {}
  for id, rec in pairs(pokemon) do
    local d = dexOf(id, rec)
    local b = bst(rec)
    if d and d >= 1 and d <= max and b > 0 then
      local cur = byDex[d]
      -- one id per dex number; prefer the plain record (numeric key / no form)
      if not cur or (type(id) == "number" and type(cur.id) ~= "number")
         or (type(id) == type(cur.id) and tostring(id) < tostring(cur.id) and type(id) ~= "number") then
        byDex[d] = { id = id, dex = d, bst = b }
      end
    end
  end
  local list = {}
  for _, row in pairs(byDex) do list[#list + 1] = row end
  table.sort(list, function(a, b)
    if a.bst ~= b.bst then return a.bst < b.bst end
    return a.dex < b.dex
  end)
  cache[pokemon] = { gen = gen, list = list }
  return list
end

local function pickNear(list, target, h, avoid, minCount)
  local n = #list
  if n == 0 then return nil end
  minCount = minCount or 12
  if not target or target <= 0 then
    return list[h % n + 1].id
  end
  -- window: +-10% of the target, widened until minCount candidates
  local lo, hi
  for _, frac in ipairs({ 0.10, 0.15, 0.25, 0.4, 0.6, 10 }) do
    lo, hi = nil, nil
    for i = 1, n do
      local b = list[i].bst
      if b >= target * (1 - frac) and b <= target * (1 + frac) then
        lo = lo or i; hi = i
      end
    end
    if lo and hi - lo + 1 >= minCount then break end
  end
  if not lo then lo, hi = 1, n end
  local span = hi - lo + 1
  for k = 0, span - 1 do
    local row = list[lo + (h + k) % span]
    if not (avoid and avoid[row.id]) then return row.id end
  end
  return list[lo + h % span].id
end

local function speciesTable(data)
  if type(data) ~= "table" then return nil end
  return data.pokemon or (data.data and data.data.pokemon)
end

Randomizer.WILD_BAND = 40

-- the replacement for wild `species` met in `area` (any string) as the
-- save's `n`-th randomized encounter (default: its counter as it stands),
-- or species unchanged when the save does not randomize wild encounters.
-- `last` (optional) is the previous pick, never repeated back to back.
function Randomizer.wild(save, data, species, area, gen, n, last)
  if species == nil or not RunModes.on(save, "randomWild") then return species end
  local pokemon = speciesTable(data)
  if not pokemon or pokemon[species] == nil then return species end
  local rm = RunModes.get(save)
  gen = gen or (data.constants and tonumber(data.constants.gen)) or generation()
  local list = Randomizer.pool(pokemon, gen)
  n = tonumber(n) or tonumber(rm.wildCount) or 0
  local h = RunModes.hash(rm.seed, "wild", tostring(area or "?"), tostring(species), n)
  local avoid = last ~= nil and { [last] = true } or nil
  return pickNear(list, bst(pokemon[species]), h, avoid, Randomizer.WILD_BAND) or species
end

-- the replacement for starter `species`.  `all` (optional) is the game's
-- whole starter set in its own order, so the three come out distinct.
function Randomizer.starter(save, data, species, all, gen)
  if species == nil or not RunModes.on(save, "randomStarters") then return species end
  local pokemon = speciesTable(data)
  if not pokemon or pokemon[species] == nil then return species end
  local rm = RunModes.get(save)
  gen = gen or (data.constants and tonumber(data.constants.gen)) or generation()
  local list = Randomizer.pool(pokemon, gen)
  if type(all) ~= "table" or #all == 0 then all = { species } end
  local taken = {}
  for _, original in ipairs(all) do
    local h = RunModes.hash(rm.seed, "starter", tostring(original))
    local pick = pickNear(list, bst(pokemon[original] or pokemon[species]), h, taken) or original
    taken[pick] = true
    if original == species then return pick end
  end
  local h = RunModes.hash(rm.seed, "starter", tostring(species))
  return pickNear(list, bst(pokemon[species]), h) or species
end

Randomizer._bst = bst
Randomizer._pickNear = pickNear
Randomizer._dexOf = dexOf
return Randomizer
