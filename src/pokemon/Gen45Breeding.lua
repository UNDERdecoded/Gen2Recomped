-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHERE PLATINUM, HEARTGOLD / SOULSILVER AND BLACK / WHITE BREED DIFFERENTLY.
-- src/pokemon/Gen4DayCare.lua is Platinum's day care and served all three;
-- these are the per-game rules it now asks for.
--
-- IV INHERITANCE (three stats, each from a random parent)
--   Platinum (pokeplatinum overlay005/daycare.c Egg_InheritIVs): READ. The
--     stat list is compacted by removing POSITION i instead of the stat just
--     picked (RemoveIVIndexFromList(availableIVs, i)), so the same stat can
--     be picked twice and HP can only come from the first pick.
--   HGSS (pokeheartgold get_egg.c InheritIVs): READ. Fixed (three different
--     stats), and a parent holding a Power item (Weight HP, Bracer Atk, Belt
--     Def, Anklet Spe, Lens SpA, Band SpD) passes that stat first; both
--     holding one, a coin flip picks the parent.
--   Black / White: INFERRED as HGSS (the Destiny Knot does nothing in
--     breeding before X / Y).
-- NATURE (the Everstone, 50%)
--   Platinum: READ -- only the mother's (or Ditto's) Everstone counts.
--   HGSS (Daycare_EverstoneCheck): READ -- either parent's; both holding
--     one, a coin flip picks which.
--   Black / White: INFERRED -- the mother's or Ditto's, as Platinum.
-- THE MASUDA METHOD (parents of different languages)
--   Platinum / HGSS (Egg_SetInitialData / SetBreedEggStats): READ -- a
--     personality that is not shiny is advanced up to 4 times with the ARNG
--     (x * 0x6C078965 + 1), stopping at the first shiny one.
--   Black / White: INFERRED -- 5 more tries (six chances in all).
-- ABILITY (Black / White only, INFERRED): a female (bred with a male, not
--   with Ditto) that has her Hidden Ability passes it 60% of the time.

local M = {}

local STATS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
M.STATS = STATS
-- ITEM_POWER_* -> stat index (STAT_HP 1 .. STAT_SPDEF 6 in the order above)
M.POWER = { [294] = 1, [289] = 2, [290] = 3, [293] = 4, [291] = 5, [292] = 6 }
M.EVERSTONE, M.DITTO = 229, 132

local function rand(lo, hi) return (love and love.math and love.math.random or math.random)(lo, hi) end
local function rand16() return rand(0, 65535) end
local function family()
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not ok then return "platinum" end
  if GV.isGen5 and GV.isGen5() then return "bw" end
  return (GV.family and GV.family()) or "platinum"
end
M.family = family
local function itemNum(mon)
  local v = mon and (mon.item or mon.heldItem)
  return tonumber(v) or tonumber(tostring(v or ""):match("(%d+)%s*$")) or 0
end
local function speciesNum(mon)
  local v = mon and mon.species
  return tonumber(v) or tonumber(tostring(v or ""):match("(%d+)%s*$")) or 0
end

-- -> { {stat index, parent index}, x3 }
function M.ivPicks(parents, fam)
  fam = fam or family()
  local picks = {}
  local list = { 1, 2, 3, 4, 5, 6 }
  if fam == "platinum" then
    for i = 1, 3 do
      picks[i] = { list[rand16() % (6 - i + 1) + 1] }
      table.remove(list, i)            -- position i (the cartridge's bug)
    end
    for i = 1, 3 do picks[i][2] = rand16() % 2 + 1 end
    return picks
  end
  local start = 1
  local power = {}
  for i = 1, 2 do power[i] = M.POWER[itemNum(parents[i])] end
  local slot
  if power[1] and power[2] then slot = (rand16() % 2 ~= 0) and 1 or 2
  elseif power[1] then slot = 1 elseif power[2] then slot = 2 end
  if slot then
    picks[1] = { power[slot], slot }
    for j, s in ipairs(list) do if s == power[slot] then table.remove(list, j) break end end
    start = 2
  end
  for i = start, 3 do
    local at = rand16() % (6 - i + 1) + 1
    picks[i] = { list[at] }
    table.remove(list, at)
  end
  for i = start, 3 do picks[i][2] = rand16() % 2 + 1 end
  return picks
end

function M.inheritIVs(egg, parents, fam)
  egg.ivs = egg.ivs or {}
  for _, p in ipairs(M.ivPicks(parents, fam)) do
    local from = parents[p[2]]
    local key = STATS[p[1]]
    local iv = from and from.ivs and from.ivs[key]
    if iv then egg.ivs[key] = iv end
  end
end

-- the parent (1 or 2) whose nature the Everstone passes, or nil
-- `natureSlot` is Platinum's Daycare_GetParentToInheritNature slot (the
-- mother / Ditto), used by Platinum and Black / White
function M.everstoneParent(mons, natureSlot, fam)
  fam = fam or family()
  if fam == "hgss" then
    local n, idx = 0, nil
    for i = 1, 2 do if mons[i] and itemNum(mons[i]) == M.EVERSTONE then n = n + 1; idx = i end end
    if n == 0 then return nil end
    if n == 2 then idx = (rand16() % 2 == 0) and 2 or 1 end
    if rand16() >= 0x7FFF then return nil end
    return idx
  end
  if natureSlot and mons[natureSlot] and itemNum(mons[natureSlot]) == M.EVERSTONE
     and rand16() < 0x7FFF then
    return natureSlot
  end
  return nil
end

-- ARNG (the DS's second LCG): x * 0x6C078965 + 1 mod 2^32
function M.arng(x)
  x = (tonumber(x) or 0) % 4294967296
  local lo, hi = x % 65536, math.floor(x / 65536)
  local a = 0x6C078965
  local alo, ahi = a % 65536, math.floor(a / 65536)
  local low = lo * alo
  local mid = (lo * ahi + hi * alo) % 65536
  return (low + mid * 65536 + 1) % 4294967296
end

local function shiny(p, otId)
  local ok, Stats = pcall(require, "src.pokemon.Stats")
  return ok and Stats.isShinyGen3(p, otId) or false
end
function M.languageOf(save, mon)
  return require("src.pokemon.Gen45Language").of(save, mon)
end
function M.masuda(save, mons, personality, otId, fam)
  fam = fam or family()
  if not (mons[1] and mons[2]) then return personality end
  if M.languageOf(save, mons[1]) == M.languageOf(save, mons[2]) then return personality end
  if otId == nil or shiny(personality, otId) then return personality end
  local tries = (fam == "bw") and 5 or 4
  local p = personality
  for _ = 1, tries do
    p = M.arng(p)
    if shiny(p, otId) then return p end
  end
  return p
end

-- Black / White hidden ability (INFERRED): slot 3 of abilityIds
-- READ from Black's overlay 21 (egg builder 0x21C38F8): the parent kept
-- in the second slot -- the female, or Ditto when the other is male or
-- genderless (0x21C3A00 / 0x21C3A44 swaps on gender param 0x6E) -- has its
-- ability looked up among ITS species' three (0x21C452C, first match, slot
-- 1 when none), and Random(100) (0x21C3D1C) picks the egg's slot:
--   parent slot 1: < 80 slot 1, else slot 2
--   parent slot 2: < 20 slot 1, else slot 2
--   parent slot 3 (Hidden): < 20 slot 1, < 40 slot 2, else the Hidden Ability
-- (this replaces the earlier inferred "60% from a female, never with Ditto").
-- Then 0x21C3DA8: with a Ditto on either side the slot is re-rolled
-- Random(2) -- slot 1 or 2, never the Hidden one -- and 0x21C3DE4 writes the
-- ABILITY ITSELF into the egg from that slot. Black stores the ability apart
-- from the personality, so the personality is left alone (Pokemon.
-- abilitySlotFor keeps a Black / White Pokemon's slot on a re-seed).
local function genderOf(data, mon)
  local ok, g = pcall(require("src.pokemon.Pokemon").genderOf, data, mon)
  return ok and g or "none"
end
function M.abilityParent(data, a, b)
  local first, second = a, b
  if genderOf(data, first) == "female" then first, second = second, first end
  if genderOf(data, second) == "male" then first, second = second, first end
  if speciesNum(first) == M.DITTO and genderOf(data, second) == "none" then first, second = second, first end
  return second
end
function M.parentSlot(data, mon)
  local def = data and data.pokemon and (data.pokemon[mon.species] or data.pokemon[speciesNum(mon)])
  local ids = def and def.abilityIds
  local slot = tonumber(mon.abilitySlot) or 1
  if type(ids) == "table" then
    local mine = tonumber(ids[slot]) or 0
    for i = 1, 3 do if (tonumber(ids[i]) or 0) == mine then return i end end
    return 1
  end
  return slot
end
function M.hiddenAbility(data, egg, mother, father, parents)
  if family() ~= "bw" then return end
  local a, b = parents and parents[1], parents and parents[2]
  if not (a and b) then return end
  local parent = M.abilityParent(data, a, b)
  local slot = M.parentSlot(data, parent)
  local r = rand(0, 99)
  local out
  if slot == 1 then out = (r < 80) and 1 or 2
  elseif slot == 2 then out = (r < 20) and 1 or 2
  else out = (r < 20) and 1 or ((r < 40) and 2 or 3) end
  local def = data and data.pokemon and (data.pokemon[egg.species] or data.pokemon[speciesNum(egg)])
  local ids = def and def.abilityIds
  if speciesNum(a) == M.DITTO or speciesNum(b) == M.DITTO then
    out = (rand(0, 1) == 0) and 1 or 2
  end
  if out == 3 and not (ids and (tonumber(ids[3]) or 0) ~= 0) then out = 1 end
  -- 0x21C3DE4: a slot naming no ability (a 0) falls back to the first
  if out == 2 and ids and (tonumber(ids[2]) or 0) == 0 then out = 1 end
  egg.abilitySlot = out
end

return M
