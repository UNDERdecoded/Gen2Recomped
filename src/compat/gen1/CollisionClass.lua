-- Classify compatibility-view cells without writing the native collision grid.
-- Behavior precedence is compiled once into dispatch rows. Hoenn surf flags
-- remain live borrowed input: a provider may change a flag after setTileBits.
local MB = require("src.compat.gen1.MetatileBehavior")
local M = {}
local categories = { WATER = 0x29, TALL_GRASS = 0x18, TREE = 7, CLIFF = 7,
  COAST_CLIFF = 7, BLOCKED = 7, BUILDING = 7, DOOR = 0x71, SIGN = 0x82,
  PC = 0x93, COUNTER = 0x90, CAVE = 0x2b, LEDGE = 0xa3 }
local ledges = { E = 0xa0, W = 0xa1, N = 0xa2, S = 0xa3 }
local function seed(category, direction, kind)
  if category == "LEDGE" then return ledges[direction or "S"] or 0xa3 end
  if category == "WARP_KEEP_FACING" or (category == "DOOR" and kind == "indoor")
      or (category == "STAIR" and direction == "WARP") then return 0x72 end
  return categories[category] or 0
end
local function dispatch()
  local rows = {}
  local function add(ids, category, direction)
    for _, id in ipairs(ids) do rows[id] = { category, direction } end
  end
  return rows, add
end
local fr, add = dispatch()
add({2, 209}, "TALL_GRASS"); add({33, 43}, "SAND")
add({56}, "LEDGE", "E"); add({57}, "LEDGE", "W")
add({58}, "LEDGE", "N"); add({59}, "LEDGE", "S")
add({97, 106, 107, 108, 109, 110, 111}, "STAIR", "WARP")
add({42}, "STAIR"); add({96, 98, 99, 100, 101, 103, 105}, "DOOR")
add({102, 104, 113}, "WARP_KEEP_FACING"); add({132, 135, 136}, "SIGN")
add({131}, "PC"); add({128}, "COUNTER"); add({8}, "CAVE"); add({12}, "ROCK_DECK")
local water, shallow, scenery, piers = {}, {}, {}, {}
for _, id in ipairs({16,17,18,19,21,26,27,80,81,82,83}) do water[id] = true end
shallow[22], shallow[23] = true, true
for _, mid in ipairs({10,11,12,14,15,19}) do scenery[mid] = "TREE" end
for mid = 20, 31 do scenery[mid] = "TREE" end
for mid = 36, 39 do scenery[mid] = "TREE" end
for _, mid in ipairs({112,113,114,115,117,122,123,124,125,178,179,180,181}) do scenery[mid] = "CLIFF" end
for _, mid in ipairs({453,454,455,692,694}) do piers[mid] = true end
-- The reference's shrub list contains only IDs >= 640 and is guarded by
-- mid < 640, so it admits no cells. Do not turn that dead branch into foliage.
local function ground(kind) return kind == "town" and "TOWN_PATH" or "SHORT_GRASS" end
local Frlg = { seed = seed }
function Frlg.classify(mid, collision, behavior, kind)
  local b = behavior or 0
  if water[b] or shallow[b] then
    if (collision or 0) ~= 0 then return "BLOCKED", nil end
    return water[b] and "WATER" or "PATH", nil
  end
  local row = fr[b]
  if row then return row[1], row[2] end
  if kind ~= "indoor" and scenery[mid] then
    return collision ~= 0 and scenery[mid] or ground(kind), nil
  end
  if piers[mid] and collision == 0 then return "PIER", nil end
  if collision ~= 0 then
    if mid >= 640 then return (kind == "town" or kind == "indoor") and "BUILDING" or "CLIFF", nil end
    return "BLOCKED", nil
  end
  return ground(kind), nil
end
local rse, addRse = dispatch()
local function names(text, category, direction)
  local ids = {}; for name in text:gmatch("%S+") do ids[#ids + 1] = MB.require(name) end
  addRse(ids, category, direction)
end
names("TALL_GRASS LONG_GRASS", "TALL_GRASS"); names("SAND DEEP_SAND", "SAND")
names("JUMP_EAST", "LEDGE", "E"); names("JUMP_WEST", "LEDGE", "W")
names("JUMP_NORTH", "LEDGE", "N"); names("JUMP_SOUTH", "LEDGE", "S")
names("LADDER UP_ESCALATOR DOWN_ESCALATOR", "STAIR", "WARP")
names("ANIMATED_DOOR NON_ANIMATED_DOOR WATER_DOOR DEEP_SOUTH_WARP AQUA_HIDEOUT_WARP EAST_ARROW_WARP WEST_ARROW_WARP NORTH_ARROW_WARP SOUTH_ARROW_WARP WATER_SOUTH_ARROW_WARP SHOAL_CAVE_ENTRANCE STAIRS_OUTSIDE_ABANDONED_SHIP", "DOOR")
names("CRACKED_FLOOR_HOLE LAVARIDGE_GYM_B1F_WARP LAVARIDGE_GYM_1F_WARP MOSSDEEP_GYM_WARP MT_PYRE_HOLE BATTLE_PYRAMID_WARP", "WARP_KEEP_FACING")
for _, name in ipairs({"PC", "COUNTER", "CAVE"}) do names(name, name) end
names("MOUNTAIN_TOP", "ROCK_DECK")
local Rse = { seed = seed, TILE_FLAG_SURFABLE = 2 }
local puddle, shallowWater = MB.PUDDLE, MB.SHALLOW_WATER
function Rse.setTileBits(bits) Rse._tileBits = type(bits) == "table" and bits or nil end
local blockedRow, waterRow, pathRow = {"BLOCKED"}, {"WATER"}, {"PATH"}
local townRow, groundRow = {"TOWN_PATH"}, {"SHORT_GRASS"}
for _, row in pairs(rse) do
  row[3], row[4] = seed(row[1], row[2]), seed(row[1], row[2], "indoor")
end
for _, row in ipairs({blockedRow, waterRow, pathRow, townRow, groundRow}) do
  row[3], row[4] = seed(row[1]), seed(row[1], nil, "indoor")
end
local function rseCell(owner, collision, behavior, kind)
  local b, blocked = behavior or 0, (collision or 0) ~= 0
  local bits = owner._tileBits and owner._tileBits[b]
  if bits ~= nil and math.floor(bits / owner.TILE_FLAG_SURFABLE) % 2 == 1 then
    return blocked and blockedRow or waterRow
  end
  if b == puddle or b == shallowWater then return blocked and blockedRow or pathRow end
  return rse[b] or (blocked and blockedRow or (kind == "town" and townRow or groundRow))
end
function Rse.classify(_, collision, behavior, kind)
  local row = rseCell(Rse, collision, behavior, kind)
  return row[1], row[2]
end
local rseClassify = Rse.classify
function Frlg.fromCell(mid, collision, behavior, kind)
  local category, direction = Frlg.classify(mid, collision, behavior, kind)
  return Frlg.seed(category, direction, kind), category, direction
end
function Rse.fromCell(mid, collision, behavior, kind)
  -- The fixed rows already own both door-arrival variants. Preserve the
  -- public extension seam when a mod replaces either stage of classification.
  if Rse.classify == rseClassify and Rse.seed == seed then
    local row = rseCell(Rse, collision, behavior, kind)
    return row[kind == "indoor" and 4 or 3], row[1], row[2]
  end
  local category, direction = Rse.classify(mid, collision, behavior, kind)
  return Rse.seed(category, direction, kind), category, direction
end
function M.impl(family)
  assert(family == "frlg" or family == "rse", "unsupported compatibility collision family")
  return family == "frlg" and Frlg or Rse
end
-- Live views own their flag state. They never replace the singleton used by
-- existing consumers, nor borrow another edition's active classification.
function M.new(family, bits)
  M.impl(family)
  local instance = { seed = seed }
  if family == "rse" then
    instance.TILE_FLAG_SURFABLE = 2
    function instance.setTileBits(value) instance._tileBits = type(value) == "table" and value or nil end
    instance.setTileBits(bits)
    function instance.classify(_, collision, behavior, kind)
      local row = rseCell(instance, collision, behavior, kind)
      return row[1], row[2]
    end
  else instance.classify = Frlg.classify end
  function instance.fromCell(mid, collision, behavior, kind)
    local category, direction = instance.classify(mid, collision, behavior, kind)
    return instance.seed(category, direction, kind), category, direction
  end
  return instance
end
return M
