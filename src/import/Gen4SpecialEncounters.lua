-- THE DAILY SPECIAL ENCOUNTER LISTS, out of `/arc/encdata_ex.narc`, members
-- 8..11 (pokeplatinum src/overlay006/trophy_garden_daily_encounters.c,
-- great_marsh_daily_encounters.c and great_marsh_binoculars.c):
--
--   member 8:  u32 species[16]   -- the Trophy Garden's daily Pokemon, which
--                                   Mr. Backlot adds one of a day
--   member 9:  u32 species[32]   -- the Great Marsh's daily pair, National Dex
--   member 10: u32 species[32]   -- ...and before it
--   member 11: { u16 x, u16 z }[36] -- where the lookout's binoculars look
--
-- Written to the cache module `gen4_special_encounters`.

local Gen4SpecialEncounters = {}

Gen4SpecialEncounters.PATH = "/arc/encdata_ex.narc"

local function u32list(b)
  local out = {}
  if type(b) ~= "string" then return out end
  for j = 0, #b - 4, 4 do
    local a, c, d, e = b:byte(j + 1, j + 4)
    out[#out + 1] = a + c * 256 + d * 65536 + e * 16777216
  end
  return out
end

function Gen4SpecialEncounters.parse(m8, m9, m10, m11)
  local trophy = u32list(m8)
  local natdex, before = u32list(m9), u32list(m10)
  if #trophy ~= 16 then return nil, "trophy garden list is " .. #trophy .. " long" end
  if #natdex ~= 32 or #before ~= 32 then return nil, "great marsh lists are not 32 long" end
  local coords = {}
  for i, v in ipairs(u32list(m11)) do
    coords[i] = { x = v % 65536, z = math.floor(v / 65536) }
  end
  return {
    trophyGarden = trophy,
    greatMarsh = { natdex = natdex, regional = before },
    lookoutCoords = coords,
  }
end

function Gen4SpecialEncounters.extract(rom)
  local raw = rom and rom:read(Gen4SpecialEncounters.PATH)
  if not raw then return nil, "no " .. Gen4SpecialEncounters.PATH end
  local arc = require("src.import.NarcArchive").parse(raw)
  if not arc then return nil, "encdata_ex did not parse" end
  return Gen4SpecialEncounters.parse(arc:get(8), arc:get(9), arc:get(10), arc:get(11))
end

return Gen4SpecialEncounters
