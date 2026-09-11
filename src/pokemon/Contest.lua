-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A Pokémon's CONDITION, and the ribbons it has won for it.
--
-- Gen 3 is the first generation where a Pokémon carries five numbers that
-- have nothing to do with fighting.  They live in the same save substruct as
-- the EVs -- six bytes right behind them -- and this port read them when
-- converting a cartridge save and then threw them away, because no engine
-- structure had anywhere to put them.  That is why the POKéNAV's CONDITION
-- screen had nothing to draw, why contests could not be scored, and why
-- FEEBAS could not evolve.
--
-- THE PENTAGON IS NOT A PICTURE OF THE FIVE STATS.  Contest_GetMonCondition
-- (0x080DAFE0) is
--
--     condition(c) = stat[c] + (stat[prev(c)] + stat[next(c)] + sheen) >> 1
--
-- walking COOL -> BEAUTY -> CUTE -> SMART -> TOUGH -> COOL, so each vertex
-- borrows half of its two neighbours and half the sheen.  A mon fed nothing
-- but Dry Pokéblocks still shows something at CUTE, through BEAUTY.
--
-- SHEEN IS A BUDGET, not a stat.  Every Pokéblock adds its `feel` to it, and
-- once it reaches 255 the feeding routine returns before touching anything:
-- no more condition, ever, for that Pokémon.
local Contest = {}

-- Clockwise from the top, which is both the pentagon's order and the order
-- the neighbours are taken in.
Contest.ORDER = { "cool", "beauty", "cute", "smart", "tough" }
Contest.MAX = 255

local INDEX = {}
for i, key in ipairs(Contest.ORDER) do INDEX[key] = i end
Contest.INDEX = INDEX

-- A blank set, which is what a Pokémon comes into the world with.
function Contest.blank()
  return { cool = 0, beauty = 0, cute = 0, smart = 0, tough = 0, sheen = 0 }
end

-- The stats a mon carries, creating them on a Gen 3 mon that predates this
-- field so an older save does not have to be converted.
function Contest.of(mon)
  if type(mon) ~= "table" then return nil end
  if type(mon.contest) ~= "table" then mon.contest = Contest.blank() end
  return mon.contest
end

function Contest.get(mon, key)
  local c = Contest.of(mon)
  return c and math.floor(tonumber(c[key]) or 0) or 0
end

-- Contest_GetMonCondition.  `category` is one of Contest.ORDER.
function Contest.condition(mon, category)
  local c = Contest.of(mon)
  if not c then return 0 end
  local i = INDEX[category]
  if not i then return 0 end
  local prev = Contest.ORDER[(i - 2) % 5 + 1]
  local next_ = Contest.ORDER[i % 5 + 1]
  local pair = (tonumber(c[prev]) or 0) + (tonumber(c[next_]) or 0)
                 + (tonumber(c.sheen) or 0)
  -- `>> 1` on a value that cannot be negative, which is a floor
  return math.floor(tonumber(c[category]) or 0) + math.floor(pair / 2)
end

-- The shine the summary screen draws: ten levels, and the top one is reserved
-- for a Pokémon whose sheen is exactly full.
function Contest.sheenLevel(mon, record)
  local step = math.max(1, math.floor((record and record.sheenStep) or 29))
  local top = math.floor((record and record.sheenMax) or 9)
  local s = Contest.get(mon, "sheen")
  if s >= Contest.MAX then return top end
  return math.min(top - 1, math.floor(s / step))
end

-- How far out a vertex sits for a condition value.  The cartridge's own LUT
-- when the import has one -- it is deliberately non-linear, spending most of
-- its resolution below 60 -- and a straight ramp between the same two ends
-- when it does not.
function Contest.radius(record, value)
  value = math.max(0, math.min(Contest.MAX, math.floor(value or 0)))
  local lut = record and record.radius
  if type(lut) == "table" and lut[value] then return lut[value] end
  return 4 + math.floor(value * 31 / Contest.MAX)
end

-- WHAT THE GRAPH IS DRAWN FROM, which is NOT what a contest is judged on.
--
-- Reported from play: "in the pokenav condition menu im not able to see any
-- values for smart, cool, tough etc for each pokemon they all look the same".
-- Two things made that so, and this is the second of them.
--
-- Contest.condition above is Contest_GetMonCondition -- the number a contest
-- JUDGES you on, which folds in half of each neighbour and half the sheen.
-- The POKéNAV's graph does not use it.  GetMonConditionGraphData reads the
-- five stats RAW, and the difference is not cosmetic: a Pokémon with a
-- hundred COOL and nothing else graphs as 100/0/0/0/0 raw, and as
-- 100/50/0/0/50 through the contest formula -- a rounder, blunter shape.  Put
-- every Pokémon through that and they all converge on the same pentagon,
-- which is exactly what was on the screen.
--
-- So the graph, the search ordering and the number beside each row all read
-- this, and the contest's own calculation is left for the contest.
function Contest.graph(mon, category)
  return Contest.get(mon, category)
end

-- The five vertices, in screen pixels, for one Pokémon.
--
-- CalcConditionGraphVertices multiplies the cartridge's own sine table -- 256
-- steps to the circle, 256 to the unit -- and shifts down by 8, so the
-- arithmetic here is integer for the same reason it is there.
-- THE FIVE DIRECTIONS, in the cartridge's 256ths -- 256 steps to the circle
-- and 256 to the unit, which is why nothing here is a float.
--
-- One place, because there are TWO things pointed along them: the data's own
-- pentagon and the FRAME the five category words hang off.  The frame used to
-- compute them again beside the graph, and its fallback -- for a dataset with
-- no ripped vertex table -- had all five directions pointing straight up, so
-- every word landed on the same spot.  Two copies of one piece of trigonometry
-- is two chances to get it wrong, and it was wrong in the copy nobody looked
-- at.
function Contest.directions(record)
  local unit = record and record.vertices
  local out = {}
  for i in ipairs(Contest.ORDER) do
    local u = unit and unit[i]
    -- straight up is a quarter turn, and the five step a fifth of a turn --
    -- 256/5 -- clockwise from it, which is the order Contest.ORDER is in
    local angle = (64 - (i - 1) * 51.2) * 2 * math.pi / 256
    out[i] = {
      cos = (u and u.cos) or math.floor(math.cos(angle) * 256),
      sin = (u and u.sin) or math.floor(math.sin(angle) * 256),
    }
  end
  return out
end

function Contest.vertices(mon, record)
  local centre = (record and record.centre) or { x = 155, y = 91 }
  local dirs = Contest.directions(record)
  local out = {}
  for i, key in ipairs(Contest.ORDER) do
    local r = Contest.radius(record, Contest.graph(mon, key))
    out[i] = {
      key = key,
      x = centre.x + math.floor(dirs[i].cos * r / 256),
      y = centre.y - math.floor(dirs[i].sin * r / 256),
    }
  end
  return out
end

-- ---------------------------------------------------------------------------
-- RIBBONS
--
-- One 32-bit word on the cartridge, unpacked by a seventeen-row table of bit
-- widths: a 1-bit CHAMPION, five 3-bit contest counters that hold "the
-- highest rank cleared" rather than five separate ribbons, four more 1-bit
-- ribbons and seven gift bits.  Thirty-two kinds out of twenty-seven bits.
--
-- This engine keeps them the way they READ rather than the way they are
-- packed -- five counters and a set of booleans -- because nothing here has
-- to fit in four bytes, and the ribbon screen wants the counters anyway.
-- ---------------------------------------------------------------------------
Contest.RIBBON_SINGLES = {
  "champion", "winning", "victory", "artist", "effort",
  "marine", "land", "sky", "country", "national", "earth", "world",
}
Contest.RIBBON_RANKS = 4

function Contest.ribbons(mon)
  if type(mon) ~= "table" then return nil end
  if type(mon.ribbons) ~= "table" then mon.ribbons = {} end
  return mon.ribbons
end

-- How many ribbons a Pokémon has, which is what the POKéNAV counts to decide
-- whether the RIBBONS row will open at all.
function Contest.ribbonCount(mon)
  local r = mon and mon.ribbons
  if type(r) ~= "table" then return 0 end
  local n = 0
  for _, key in ipairs(Contest.ORDER) do
    n = n + math.max(0, math.min(Contest.RIBBON_RANKS,
                                 math.floor(tonumber(r[key]) or 0)))
  end
  for _, key in ipairs(Contest.RIBBON_SINGLES) do
    if r[key] then n = n + 1 end
  end
  return n
end

-- The ribbon ids a Pokémon owns, in the order the ribbon screen lays them
-- out: CHAMPION, then the twenty contest ribbons rank by rank, then the four
-- singles, then the gifts.  Ids match the cartridge's own numbering, which is
-- what the icon and description tables are indexed by.
Contest.RIBBON_IDS = {
  champion = 0,
  cool = 1, beauty = 5, cute = 9, smart = 13, tough = 17,
  winning = 21, victory = 22, artist = 23, effort = 24,
  marine = 25, land = 26, sky = 27, country = 28,
  national = 29, earth = 30, world = 31,
}

function Contest.ribbonIds(mon)
  local r = mon and mon.ribbons
  local out = {}
  if type(r) ~= "table" then return out end
  if r.champion then out[#out + 1] = Contest.RIBBON_IDS.champion end
  for _, key in ipairs(Contest.ORDER) do
    local n = math.max(0, math.min(Contest.RIBBON_RANKS,
                                   math.floor(tonumber(r[key]) or 0)))
    for i = 0, n - 1 do out[#out + 1] = Contest.RIBBON_IDS[key] + i end
  end
  for _, key in ipairs(Contest.RIBBON_SINGLES) do
    if key ~= "champion" and r[key] then
      out[#out + 1] = Contest.RIBBON_IDS[key]
    end
  end
  table.sort(out)
  return out
end

-- GiveMonContestRibbon: the counter only ever goes UP, only by one, and only
-- when the mon has already cleared every rank below the one it just won.
function Contest.giveContestRibbon(mon, category, rank)
  local r = Contest.ribbons(mon)
  if not (r and INDEX[category]) then return false end
  local have = math.floor(tonumber(r[category]) or 0)
  if have > rank then return false end
  if have >= Contest.RIBBON_RANKS then return false end
  r[category] = have + 1
  return true
end

-- ---------------------------------------------------------------------------
-- POKéBLOCKS, applied
--
-- The feeding routine (0x08167054) in full, and every one of its edges
-- matters:
--
--   * a Pokémon whose sheen is already 255 gains NOTHING -- the function
--     returns before it touches a single stat, and it does not rewrite the
--     sheen either;
--   * each of the five stats moves by its own flavour's value, floored at 0
--     and capped at 255;
--   * exactly ONE of them is adjusted by ten percent, and which one depends
--     on the nature: the liked flavour's stat gains a tenth more when the
--     block is a net positive for that nature, the disliked flavour's stat
--     loses a tenth when it is a net negative, and a neutral nature -- or a
--     block whose likes and dislikes cancel -- adjusts nothing at all;
--   * the ten percent is rounded HALF UP, and it is computed off the raw
--     flavour value rather than the running total;
--   * sheen then takes the block's raw `feel`, capped at 255.  Not the
--     `min(feel, 99)` the menus display -- that clamp is for the number on
--     the screen, and a block whose feel is 108 really does spend 108.
-- ---------------------------------------------------------------------------

-- flavour -> the stat it feeds, in the order the cartridge's own two parallel
-- tables pair them
Contest.FLAVOURS = { "spicy", "dry", "sweet", "bitter", "sour" }
Contest.FLAVOUR_STAT = {
  spicy = "cool", dry = "beauty", sweet = "cute",
  bitter = "smart", sour = "tough",
}

-- PokeblockGetGain: the SIGN of this is what decides which stat gets the ten
-- percent, and the magnitude is thrown away.
function Contest.blockGain(natureTable, nature, block)
  if not (natureTable and nature and block) then return 0 end
  local row = natureTable[nature]
  if type(row) ~= "table" then return 0 end
  local total = 0
  for i, flavour in ipairs(Contest.FLAVOURS) do
    local v = math.floor(tonumber(block[flavour]) or 0)
    if v > 0 then total = total + v * (math.floor(tonumber(row[i]) or 0)) end
  end
  return total
end

local function roundTenth(v)
  local tenth = math.floor(v / 10)
  if v % 10 > 4 then tenth = tenth + 1 end
  return tenth
end

-- Feeds one Pokéblock.  Returns the deltas actually applied, or nil when the
-- Pokémon is too shiny to gain anything.
function Contest.feed(mon, block, natureTable, nature)
  local c = Contest.of(mon)
  if not (c and type(block) == "table") then return nil end
  if (tonumber(c.sheen) or 0) >= Contest.MAX then return nil end

  local gain = Contest.blockGain(natureTable, nature, block)
  local sign = (gain > 0 and 1) or (gain < 0 and -1) or 0
  local row = (sign ~= 0 and natureTable and natureTable[nature]) or nil

  local deltas = {}
  for i, flavour in ipairs(Contest.FLAVOURS) do
    local stat = Contest.FLAVOUR_STAT[flavour]
    local raw = math.floor(tonumber(block[flavour]) or 0)
    local delta = raw
    if row then
      local rel = math.floor(tonumber(row[i]) or 0)
      if rel == sign then delta = delta + roundTenth(raw) * rel end
    end
    local now = math.max(0, math.min(Contest.MAX,
                                     (tonumber(c[stat]) or 0) + delta))
    deltas[stat] = now - (tonumber(c[stat]) or 0)
    c[stat] = now
  end
  local feel = math.floor(tonumber(block.feel) or 0)
  c.sheen = math.min(Contest.MAX, (tonumber(c.sheen) or 0) + feel)
  deltas.sheen = feel
  deltas.liked = sign
  return deltas
end

return Contest
