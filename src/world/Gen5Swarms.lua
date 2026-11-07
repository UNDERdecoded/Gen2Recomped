-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE'S MASS OUTBREAKS (swarms), after the Hall of Fame.
--
-- READ (Pokemon Black ov21; White's ov21 holds the same table at the same
-- place, +8 for its load address):
--   * the day's outbreak is an index 0..16 at save block 0x38 +0x30, zeroed at
--     a new game (0x0200D424) and redrawn as Random(17) by the daily update
--     (ov10 0x02169004 -> arm9 0x0200D440)
--   * 0x021A99A8: no outbreak unless event flag 0x960 (2400, set by common
--     script 9601 after the game is cleared); an index >= 17 reads entry 0;
--     the entry is 8 bytes of the table at 0x021D8DE8 { u16 zone, u16 species,
--     u8 form, u8 min, u8 max, u8 pad }
--   * 0x021A99E4, called first by the slot builder 0x021A9A5C: the zone must
--     be the entry's, the encounter kind ordinary grass (0: not dark grass,
--     not a phenomenon, not water), and Random(1000) <= 400; then the whole
--     table is that one slot (selector 3, one slot) -- the lead's rules still
--     apply (Hustle's +5 and the rest)
--   Every entry is level 15..55, form 0.

local M = {}

M.FLAG = 0x960

-- { zone, species } in table order; Black and White differ in four
M.BLACK = {
  { 317, 83 }, { 319, 360 }, { 321, 313 }, { 326, 449 }, { 329, 235 }, { 331, 311 },
  { 337, 161 }, { 345, 453 }, { 348, 228 }, { 355, 236 }, { 365, 285 }, { 368, 84 },
  { 370, 353 }, { 374, 193 }, { 378, 56 }, { 383, 204 }, { 387, 102 },
}
M.WHITE = {
  { 317, 83 }, { 319, 360 }, { 321, 314 }, { 326, 449 }, { 329, 235 }, { 331, 312 },
  { 337, 161 }, { 345, 453 }, { 348, 261 }, { 355, 236 }, { 365, 46 }, { 368, 84 },
  { 370, 353 }, { 374, 193 }, { 378, 56 }, { 383, 204 }, { 387, 102 },
}
M.MIN, M.MAX = 15, 55

local function list()
  local GV = require("src.core.GameVersion")
  return (GV.get and GV.get() == "white") and M.WHITE or M.BLACK
end

function M.index(save)
  local i = tonumber(save and save.gen5SwarmIndex) or 0
  if i < 0 or i >= 17 then i = 0 end
  return i
end

-- the daily update's redraw (Gen5Daily.poll)
function M.newDay(save, rng)
  if not save then return end
  save.gen5SwarmIndex = (rng or love.math.random)(0, 16)
end

local function flagSet(save)
  return save and save.flags and save.flags[("FLAG_G4_%04X"):format(M.FLAG)] == true
end

-- today's { zone, species }, or nil before the game is cleared
function M.today(save)
  if not flagSet(save) then return nil end
  return list()[M.index(save) + 1]
end

-- tableFor(save, zone, rng) -> the one-slot table when the outbreak takes this
-- ordinary-grass encounter, else nil
function M.tableFor(save, zone, rng)
  local e = M.today(save)
  if not e or tonumber(zone) ~= e[1] then return nil end
  if (rng or love.math.random)(0, 999) > 400 then return nil end
  local slots = { { species = e[2], minLevel = M.MIN, maxLevel = M.MAX, chance = 100, form = 0 } }
  return { rate = 100, rateMax = 100, slots = slots, buckets = { 100 }, bucketSpan = 100, swarm = true }
end

return M
