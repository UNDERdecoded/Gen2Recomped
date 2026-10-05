-- PLATINUM'S POFFINS (pokeplatinum src/poffin.c, src/overlay083/ov83_0223F7F4.c,
-- src/applications/poffin_case/main.c).
--
-- A Poffin is { type, flavors = {spicy, dry, sweet, bitter, sour}, smoothness }.
-- The case holds MAX_POFFINS (100) in save.gen4Poffins, a dense list.
--
-- TYPES (Poffin_MakePoffin): one flavor -> f*5+f; two -> the stronger first,
-- strongest*5+other; three -> Rich (25); four or five -> Overripe (26); none,
-- or a foul cook -> Foul (27) with three random zero flavors set to 2; any
-- flavor >= 50 -> Mild (28). Names are bank 465 entry `type`.
--
-- COOKING (ov83_0223F7F4 + its result function), n berries:
--   sum each flavor over the berries; smoothness = sum(smoothness)/n - n
--   foul when the same berry appears twice (n > 1)
--   d[i] = sum[i] - sum[(i+1)%5]; k = the count of negative d; every d -= k;
--   foul when k >= 4
--   factor = round(1800000 / frames) / 10 (frames at 30 Hz: one minute = 100%)
--   flavor[i] = max(0, round(d[i] * factor / 100) - (burns + spills))
--   smoothness -= the group-sync bonus (multiplayer only), floor 15
--
-- FEEDING (PoffinCase_UpdateMonContestStats): spicy..sour onto cool..tough and
-- smoothness onto sheen, the liked flavor x1.1 and the disliked x0.9 (each
-- truncated), every stat capped at 255; friendship +1. The nature table is
-- sFlavorPreferences; a mon whose sheen is 255 eats no more.

local Gen4Poffin = {}

Gen4Poffin.MAX = 100
Gen4Poffin.RICH, Gen4Poffin.OVERRIPE, Gen4Poffin.FOUL, Gen4Poffin.MILD = 25, 26, 27, 28
Gen4Poffin.TYPE_BANK = 465
Gen4Poffin.STATS = { "cool", "beauty", "cute", "smart", "tough" }

local function rng(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end

-- Poffin_MakeFoul
local function foul(poffin, smoothness, random)
  random = random or rng
  local f = poffin.flavors
  local set = 0
  while set < 3 do
    local i = random(5) + 1
    if f[i] == 0 then f[i] = 2; set = set + 1 end
  end
  poffin.type = Gen4Poffin.FOUL
  poffin.smoothness = smoothness
  return poffin
end

-- Poffin_MakePoffin
function Gen4Poffin.make(flavors, smoothness, isFoul, random)
  local p = { flavors = { 0, 0, 0, 0, 0 }, smoothness = smoothness }
  if isFoul then return foul(p, smoothness, random) end
  local present, mild = {}, false
  for i = 1, 5 do
    if (flavors[i] or 0) > 0 then
      if flavors[i] >= 50 then mild = true end
      present[#present + 1] = i - 1
    end
  end
  local n, t = #present, nil
  if n == 0 then return foul(p, smoothness, random)
  elseif n == 1 then t = present[1] * 5 + present[1]
  elseif n == 2 then
    local a, b = present[1], present[2]
    if flavors[a + 1] >= flavors[b + 1] then t = a * 5 + b else t = b * 5 + a end
  elseif n == 3 then t = Gen4Poffin.RICH
  else t = Gen4Poffin.OVERRIPE end
  if mild then t = Gen4Poffin.MILD end
  for i = 1, 5 do p.flavors[i] = flavors[i] or 0 end
  p.type = t
  return p
end

-- Poffin_CalcLevel
function Gen4Poffin.level(p)
  local f = p.flavors
  local col = math.floor(p.type / 5)
  local level
  if col <= 4 then level = f[col + 1]
  else
    level = 0
    for i = 1, 5 do if f[i] > level then level = f[i] end end
  end
  return math.min(99, level)
end

function Gen4Poffin.name(data, p)
  local T = require("src.import.Gen4Text")
  local s = data and data.text and data.text[T.label(Gen4Poffin.TYPE_BANK, p.type)]
  return s or "Poffin"
end

-- The cooking result. `berries` is a list of { flavors = {5}, smoothness, item }.
function Gen4Poffin.cook(berries, frames, burns, spills, syncBonus, random)
  local n = #berries
  local sum, smooth, maxDup = { 0, 0, 0, 0, 0 }, 0, 0
  for i, b in ipairs(berries) do
    local dup = 0
    for _, c in ipairs(berries) do if c.item == b.item then dup = dup + 1 end end
    if dup > maxDup then maxDup = dup end
    for k = 1, 5 do sum[k] = sum[k] + (b.flavors[k] or 0) end
    smooth = smooth + (b.smoothness or 0)
  end
  local isFoul = maxDup >= 2 and n > 1
  local smoothness = math.floor(smooth / n) - n
  local d, negatives = {}, 0
  for i = 1, 5 do
    d[i] = sum[i] - sum[i % 5 + 1]
    if d[i] < 0 then negatives = negatives + 1 end
  end
  for i = 1, 5 do d[i] = d[i] - negatives end
  if negatives >= 4 then isFoul = true end
  local factor = math.floor(1800000 / math.max(1, frames))
  if factor % 10 >= 5 then factor = factor + 10 end
  factor = math.floor(factor / 10)
  local out = {}
  for i = 1, 5 do
    local v = d[i] * factor
    -- C's % and / truncate toward zero
    local q = v >= 0 and math.floor(v / 100) or -math.floor(-v / 100)
    local r = v - q * 100
    if r >= 50 then q = q + 1 end
    out[i] = math.max(0, q - ((burns or 0) + (spills or 0)))
  end
  if n > 1 then smoothness = smoothness - math.min(10, syncBonus or 0) end
  if smoothness < 15 then smoothness = 15 end
  return Gen4Poffin.make(out, smoothness, isFoul, random)
end

-- ----------------------------------------------------------------- case --

function Gen4Poffin.case(save)
  save.gen4Poffins = save.gen4Poffins or {}
  return save.gen4Poffins
end

function Gen4Poffin.count(save) return #(save and save.gen4Poffins or {}) end
function Gen4Poffin.empty(save) return Gen4Poffin.MAX - Gen4Poffin.count(save) end

-- PoffinCase_AddPoffin: false when full (POFFIN_NONE).
function Gen4Poffin.add(save, p)
  local c = Gen4Poffin.case(save)
  if #c >= Gen4Poffin.MAX then return false end
  c[#c + 1] = p
  return true
end

function Gen4Poffin.remove(save, index)
  local c = Gen4Poffin.case(save)
  return table.remove(c, index)
end

-- -------------------------------------------------------------- feeding --

-- sFlavorPreferences, by nature 0..24: { liked, disliked } as 0-based
-- flavors, nil for the five neutral natures.
local S, D, SW, B, SO = 0, 1, 2, 3, 4
Gen4Poffin.PREFERENCES = {
  [1] = { S, SO }, [2] = { S, SW }, [3] = { S, D }, [4] = { S, B },
  [5] = { SO, S }, [7] = { SO, SW }, [8] = { SO, D }, [9] = { SO, B },
  [10] = { SW, S }, [11] = { SW, SO }, [13] = { SW, D }, [14] = { SW, B },
  [15] = { D, S }, [16] = { D, SO }, [17] = { D, SW }, [19] = { D, B },
  [20] = { B, S }, [21] = { B, SO }, [22] = { B, SW }, [23] = { B, D },
}

local function nature(mon) return math.floor(tonumber(mon.personality) or 0) % 25 end

-- PoffinCase_GetPoffinPreference: "like", "dislike" or "neutral".
function Gen4Poffin.preference(p, mon)
  local pref = Gen4Poffin.PREFERENCES[nature(mon)]
  if not pref then return "neutral" end
  local liked, disliked = p.flavors[pref[1] + 1], p.flavors[pref[2] + 1]
  if liked == disliked then return "neutral" end
  return liked > disliked and "like" or "dislike"
end

function Gen4Poffin.canEat(mon)
  local c = require("src.pokemon.Contest").of(mon)
  return (tonumber(c and c.sheen) or 0) < 255
end

-- PoffinCase_UpdateMonContestStats
function Gen4Poffin.feed(p, mon)
  local c = require("src.pokemon.Contest").of(mon)
  local adj = { p.flavors[1], p.flavors[2], p.flavors[3], p.flavors[4], p.flavors[5] }
  local pref = Gen4Poffin.PREFERENCES[nature(mon)]
  if pref then
    adj[pref[1] + 1] = math.floor(adj[pref[1] + 1] * 1.1)
    adj[pref[2] + 1] = math.floor(adj[pref[2] + 1] * 0.9)
  end
  for i, key in ipairs(Gen4Poffin.STATS) do
    c[key] = math.min(255, (tonumber(c[key]) or 0) + adj[i])
  end
  c.sheen = math.min(255, (tonumber(c.sheen) or 0) + (p.smoothness or 0))
  local f = tonumber(mon.happiness or mon.friendship) or 0
  if f < 255 then mon.happiness = f + 1 end
end

-- The berries a save can cook with: every berry pocket entry with flavor data.
function Gen4Poffin.berries(data, save)
  local rec = data and data.gen4_berry_flavors
  local out = {}
  if not rec then return out end
  for id = 149, 212 do
    local n = tonumber((save.inventory or {})[id]) or 0
    if n > 0 and rec[id] then out[#out + 1] = { item = id, count = n } end
  end
  return out
end

return Gen4Poffin
