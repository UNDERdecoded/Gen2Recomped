-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- POKéBLOCKS: the case, and the Berry Blender that fills it.
--
-- A Pokéblock is eight bytes -- a colour, five flavour values and a `feel` --
-- and the case holds forty of them.  Nothing in this port had any of it, so
-- the whole condition half of Hoenn was unreachable: no blocks, no condition,
-- no contests, and a FEEBAS that could never become a MILOTIC.
--
-- THE BLENDER'S ARITHMETIC IS NOT "add up the berries".  CalculatePokeblock
-- (0x08081BE0) does six things in order, and getting any of them wrong makes
-- a plausible block that is not the cartridge's:
--
--   1. sum each flavour over every participant's berry, smoothness included;
--   2. subtract each flavour from the one BEFORE it round the ring
--      spicy-dry-sweet-bitter-sour -- so a berry set that is flat in every
--      flavour comes out as nothing at all;
--   3. zero whatever went negative, and COUNT how many did;
--   4. take that count off every flavour that is still positive;
--   5. multiply what is left by `100 + maxRPM/333` percent -- and do it as
--      the cartridge does, two truncating divides with a round-half-up on the
--      second, not one divide by a hundred;
--   6. `feel` is the smoothness sum divided by the number of players, less
--      the number of players.
--
-- ...and then, if the result is BLACK, the whole flavour set is thrown away
-- and replaced by one of ten fixed patterns of 2s picked at random.  That is
-- the cartridge being kind: a black block is worthless, so it is at least
-- made harmless.
--
-- THERE IS NO SINGLE-PLAYER CASE.  StartBlender is only ever called with two,
-- three or four participants; blending alone at Lilycove still means two or
-- three NPCs each throwing a berry in, and `numPlayers` both divides the
-- smoothness and is subtracted from it.
local Pokeblocks = {}

local Contest = require("src.pokemon.Contest")

Pokeblocks.FLAVOURS = { "spicy", "dry", "sweet", "bitter", "sour" }
Pokeblocks.CASE_SIZE = 40
Pokeblocks.MAX = 255
-- GetPokeblockColor's own numbering; 0 is "no block"
Pokeblocks.BLACK = 12
Pokeblocks.WHITE = 13
Pokeblocks.GRAY = 11
Pokeblocks.GOLD = 14

local function record(data)
  return (data and data.constants and data.constants.gen3Pokeblocks) or nil
end
Pokeblocks.record = record

function Pokeblocks.caseSize(data)
  local r = record(data)
  return math.max(1, math.floor((r and r.caseSize) or Pokeblocks.CASE_SIZE))
end

-- The case lives on the save, as a sparse array: a slot is either a block or
-- nil.  `firstFree` is the cartridge's own allocator -- the LOWEST empty
-- slot, not the end -- which is what makes a tossed block's place reusable.
function Pokeblocks.case(save)
  if type(save) ~= "table" then return {} end
  save.pokeblocks = save.pokeblocks or {}
  return save.pokeblocks
end

function Pokeblocks.firstFree(save, data)
  local case = Pokeblocks.case(save)
  for i = 1, Pokeblocks.caseSize(data) do
    if case[i] == nil then return i end
  end
  return nil
end

function Pokeblocks.count(save, data)
  local case = Pokeblocks.case(save)
  local n = 0
  for i = 1, Pokeblocks.caseSize(data) do
    if case[i] ~= nil then n = n + 1 end
  end
  return n
end

function Pokeblocks.add(save, block, data)
  local slot = Pokeblocks.firstFree(save, data)
  if not slot then return nil end
  Pokeblocks.case(save)[slot] = block
  return slot
end

function Pokeblocks.remove(save, slot)
  local case = Pokeblocks.case(save)
  local block = case[slot]
  case[slot] = nil
  return block
end

-- The number the menus print.  It is NOT the number the Pokémon spends:
-- GetPokeblockFeel clamps the display at 99 while the feeding routine adds
-- the raw byte, so a block that shows 99 can really cost 108 of a Pokémon's
-- 255 sheen.
function Pokeblocks.shownFeel(block)
  return math.min(99, math.floor(tonumber(block and block.feel) or 0))
end

function Pokeblocks.name(data, block)
  local r = record(data)
  local colour = math.floor(tonumber(block and block.colour) or 0)
  local word = r and r.names and r.names[colour]
  if not word then
    word = (r and r.colours and r.colours[colour])
           or Pokeblocks.COLOUR_FALLBACK[colour] or "?"
  end
  return word .. " POKéBLOCK"
end

Pokeblocks.COLOUR_FALLBACK = {
  "RED", "BLUE", "PINK", "GREEN", "YELLOW", "PURPLE", "INDIGO", "BROWN",
  "LITEBLUE", "OLIVE", "GRAY", "BLACK", "WHITE", "GOLD",
}

-- GetPokeblockColor, in the order it decides.  `same` is true when two
-- participants threw in the identical berry, which the cartridge punishes.
function Pokeblocks.colour(flavours, negatives, same)
  local positives, highest, highestAt, secondAt = 0, -1, nil, nil
  local any = false
  local best2 = -1
  for i = 1, 5 do
    local v = math.floor(tonumber(flavours[i]) or 0)
    if v ~= 0 then any = true end
    if v > 0 then
      positives = positives + 1
      if v > highest then
        best2, secondAt = highest, highestAt
        highest, highestAt = v, i
      elseif v > best2 then
        best2, secondAt = v, i
      end
    end
  end
  if not any then return Pokeblocks.BLACK end
  if (negatives or 0) > 3 then return Pokeblocks.BLACK end
  if same then return Pokeblocks.BLACK end
  if positives > 3 then return Pokeblocks.WHITE end
  if positives == 3 then return Pokeblocks.GRAY end
  if highest > 50 then return Pokeblocks.GOLD end
  if positives == 1 then return highestAt end
  if positives == 2 then return 5 + highestAt end
  return 0
end

-- CalculatePokeblock.  `berries` is a list of { spicy, dry, sweet, bitter,
-- sour, smoothness, item }, one per participant; `maxRPM` is in HUNDREDTHS of
-- an RPM, which is how the blender stores it.
function Pokeblocks.blend(data, berries, maxRPM, rng)
  local r = record(data)
  local players = #berries
  if players < 2 then return nil end
  rng = rng or love.math.random

  -- 1. sum, smoothness included
  local f = { 0, 0, 0, 0, 0, 0 }
  local keys = { "spicy", "dry", "sweet", "bitter", "sour", "smoothness" }
  for _, berry in ipairs(berries) do
    for i = 1, 6 do
      f[i] = f[i] + math.floor(tonumber(berry[keys[i]]) or 0)
    end
  end

  -- 2. the ring subtraction, and the FIRST value has to be saved before it is
  -- overwritten because the last row reads it
  local firstSpicy = f[1]
  f[1] = f[1] - f[2]
  f[2] = f[2] - f[3]
  f[3] = f[3] - f[4]
  f[4] = f[4] - f[5]
  f[5] = f[5] - firstSpicy

  -- 3. zero the negatives, and count them
  local negatives = 0
  for i = 1, 5 do
    if f[i] < 0 then f[i] = 0; negatives = negatives + 1 end
  end

  -- 4. every surviving flavour pays for them
  for i = 1, 5 do
    if f[i] > 0 then
      f[i] = (f[i] >= negatives) and (f[i] - negatives) or 0
    end
  end

  -- 5. the RPM multiplier, two truncating divides with a round-half-up
  local rpm = math.max(0, math.floor(tonumber(maxRPM) or 0))
  local base = (r and r.rpm and r.rpm.base) or 100
  local divisor = (r and r.rpm and r.rpm.divisor) or 333
  local mult = base + math.floor(rpm / divisor)
  for i = 1, 5 do
    local q1 = math.floor(f[i] * mult / 10)
    local q2 = math.floor(q1 / 10)
    if q1 % 10 > 4 then q2 = q2 + 1 end
    f[i] = q2
  end

  -- did two participants throw in the same berry?
  local same = false
  for i = 1, players do
    for j = i + 1, players do
      if berries[i].item and berries[i].item == berries[j].item then
        same = true
      end
    end
  end

  local colour = Pokeblocks.colour(f, negatives, same)

  -- 6. feel, off the smoothness sum
  local feel = math.floor(f[6] / players) - players
  if feel < 0 then feel = 0 end

  -- ...and the mercy re-roll for a black block
  if colour == Pokeblocks.BLACK then
    local bits = r and r.blackBits
    local pattern = bits and bits[rng(1, #bits)] or 0
    for i = 1, 5 do
      f[i] = (math.floor(pattern / 2 ^ (i - 1)) % 2 == 1) and 2 or 0
    end
  end

  local block = { colour = colour, feel = math.min(Pokeblocks.MAX, feel) }
  for i, key in ipairs(Pokeblocks.FLAVOURS) do
    block[key] = math.min(Pokeblocks.MAX, math.max(0, f[i]))
  end
  return block
end

-- One berry's contribution, off the extracted berry table.
--
-- THE FLAVOURS ARE NOT ON THE ITEM.  This looked for `spicy` on
-- `data.items[id]`, and gItems carries a price, a pocket, a hold effect and a
-- description -- and no flavours at all.  They are gBerries, which the import
-- writes as `constants.gen3Berries`, a list of 43 rows each naming the item it
-- belongs to.
--
-- So this returned nil for EVERY berry, and DoBerryBlending's first act after
-- the player picks one is
--
--     local mine = PB.berryFlavours(...)
--     if not mine then ... return end
--
-- -- so the Berry Blender bailed the instant a berry was chosen, with the
-- case in the bag and the machine's own script having already agreed to run.
-- Nothing came out and nothing said why.
-- The index is cached per berry TABLE rather than written into it: the
-- dataset is shared, and a stray key in it would end up in anything that
-- serialises constants back out.  Weak keys so a reloaded dataset is not
-- pinned.
local berryIndexCache = setmetatable({}, { __mode = "k" })

local function berryIndex(data)
  local list = data and data.constants and data.constants.gen3Berries
  if type(list) ~= "table" then return nil end
  local cached = berryIndexCache[list]
  if cached then return cached end
  local byItem = {}
  for _, row in ipairs(list) do
    if type(row) == "table" and type(row.item) == "string" then
      byItem[row.item] = row
    end
  end
  berryIndexCache[list] = byItem
  return byItem
end

function Pokeblocks.berryFlavours(data, id)
  local byItem = berryIndex(data)
  local berry = byItem and byItem[id]
  -- ...and an item that carries its own flavours still works, which is what
  -- a mod or a hand-built fixture hands over
  if type(berry) ~= "table" then
    local def = data and data.items and data.items[id]
    berry = def and def.berry
    if type(berry) ~= "table" and type(def) == "table" and def.spicy then
      berry = def
    end
  end
  if type(berry) ~= "table" or berry.spicy == nil then return nil end
  return {
    item = id,
    spicy = berry.spicy or 0, dry = berry.dry or 0, sweet = berry.sweet or 0,
    bitter = berry.bitter or 0, sour = berry.sour or 0,
    smoothness = berry.smoothness or 0,
  }
end

-- Feeding, which is Contest.feed with the nature table looked up for it.
function Pokeblocks.feed(data, mon, block)
  local r = record(data)
  return Contest.feed(mon, block, r and r.natures, mon and mon.nature)
end

-- Which block a Pokémon of this nature likes best, which is the only thing
-- special 280 is asked.  The cartridge answers it by trying five dummy blocks
-- of twenty in one flavour each and taking the first with a positive gain.
function Pokeblocks.favourite(data, nature)
  local r = record(data)
  local natures = r and r.natures
  local row = natures and natures[nature]
  if type(row) ~= "table" then return nil end
  for i = 1, 5 do
    if (tonumber(row[i]) or 0) > 0 then
      local word = (r.names and r.names[i]) or Pokeblocks.COLOUR_FALLBACK[i]
      return i, word
    end
  end
  return nil
end

return Pokeblocks
