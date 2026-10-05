-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- PLATINUM'S TWO PATHS THAT ARE NOT ALWAYS THERE.
--
-- `FieldMapChange_InitTerrainCollisionManager` (pokeplatinum
-- src/field_map_change.c) loads the map matrix and then, on EVERY map change,
-- rewrites four cells of the overworld matrix depending on the save:
--
--     if (SystemVars_CheckHiddenLocation(.., HIDDEN_LOCATION_SEABREAK_PATH))
--         MapMatrix_RevealSeabreakPath(mapMatrix);
--     if (!SystemVars_CheckHiddenLocation(.., HIDDEN_LOCATION_SPRING_PATH))
--         MapMatrix_RevealSpringPath(mapMatrix);
--
-- NOTE THE SECOND `!`. The shipped matrix CONTAINS Spring Path, and the
-- function named "reveal" is what HIDES it -- land 176 at altitude 2 over its
-- four chunks -- until the location is unlocked. Seabreak Path is the other
-- way round: the shipped matrix has plain Route 224 sea there, and lands
-- 119..122 are patched in once Oak's Letter has been used.
--
-- Collision follows the land, because `TerrainCollisionManager` reads the
-- permission block of whichever chunk is loaded. So a hidden path is not only
-- invisible on the cartridge -- it is not there to walk on.
--
-- The port had neither half: `sethiddenlocation` was lowered to a no-op, so no
-- location could ever be unlocked, and nothing patched the matrix -- Spring
-- Path stood open from the start of the game and Seabreak Path never appeared.

local Gen4HiddenPaths = {}

-- `enum HiddenLocation`, and `sHiddenLocationMagicNumbers` (src/system_vars.c):
-- a location is unlocked when its var holds exactly this number, not merely a
-- non-zero one.
Gen4HiddenPaths.FULLMOON_ISLAND = 0
Gen4HiddenPaths.NEWMOON_ISLAND  = 1
Gen4HiddenPaths.SPRING_PATH     = 2
Gen4HiddenPaths.SEABREAK_PATH   = 3
Gen4HiddenPaths.MAGIC = { [0] = 0x0208, [1] = 0x0229, [2] = 0x0312, [3] = 0x1028 }

-- VAR_HIDDEN_LOCATION_FULL_MOON_ISLAND, evaluated from pokeplatinum's
-- generated/vars_flags.txt by C enum rules; the four locations are consecutive
-- and VAR_AMITY_SQUARE_STEP_COUNT (0x403A) follows them.
Gen4HiddenPaths.VAR_BASE = 0x4036

-- The overworld is matrix 0, and both functions return early on any other.
local OVERWORLD = 0

-- { x, y, land, altitude } in matrix cells. Altitude nil = leave it alone,
-- which is what `MapMatrix_RevealSeabreakPath` does.
local SPRING_HIDDEN = {
  { 23, 21, 176, 2 }, { 24, 21, 176, 2 },
  { 23, 22, 176, 2 }, { 24, 22, 176, 2 },
}
local SEABREAK_SHOWN = {
  { 28, 15, 119 }, { 27, 16, 120 }, { 28, 16, 121 }, { 27, 17, 122 },
}

local function vars(save)
  return type(save) == "table" and type(save.gen4Vars) == "table"
    and save.gen4Vars or nil
end

function Gen4HiddenPaths.unlocked(save, location)
  local store = vars(save)
  local v = store and store[Gen4HiddenPaths.VAR_BASE + location]
  return v ~= nil and tonumber(v) == Gen4HiddenPaths.MAGIC[location]
end

-- `ScrCmd_SetHiddenLocation`: set the magic number, or clear to 0.
function Gen4HiddenPaths.set(save, location, enable)
  location = tonumber(location)
  if not (location and Gen4HiddenPaths.MAGIC[location]) then return false end
  if type(save) ~= "table" then return false end
  save.gen4Vars = save.gen4Vars or {}
  save.gen4Vars[Gen4HiddenPaths.VAR_BASE + location] =
    enable and Gen4HiddenPaths.MAGIC[location] or 0
  return true
end

-- SAVES MADE WHILE `sethiddenlocation` WAS A NO-OP.
--
-- A player already past the Spring Path event has no magic number in its var,
-- and without this would find the path sealed in front of them. The
-- cartridge's own script leaves a second trace: the unlock in
-- scripts M0389/S0062 is followed directly by `setvarfromvalue 16554, 1`, and
-- 16554 is a progress var that only ever goes up (2 and 3 later in the same
-- story; no script resets it, and no script ever re-locks a location). So a
-- save with 16554 >= 1 has unlocked Spring Path, and gets the magic number.
local SPRING_PROGRESS_VAR = 16554
function Gen4HiddenPaths.migrate(save)
  local store = vars(save)
  if not store then return end
  local key = Gen4HiddenPaths.VAR_BASE + Gen4HiddenPaths.SPRING_PATH
  if (tonumber(store[SPRING_PROGRESS_VAR]) or 0) >= 1
     and tonumber(store[key]) ~= Gen4HiddenPaths.MAGIC[Gen4HiddenPaths.SPRING_PATH] then
    store[key] = Gen4HiddenPaths.MAGIC[Gen4HiddenPaths.SPRING_PATH]
  end
end

-- The cells to rewrite for this save, in the cartridge's order (Seabreak
-- first, then Spring -- they do not overlap, so the order is only fidelity).
function Gen4HiddenPaths.patches(save)
  Gen4HiddenPaths.migrate(save)
  local out = {}
  if Gen4HiddenPaths.unlocked(save, Gen4HiddenPaths.SEABREAK_PATH) then
    for _, p in ipairs(SEABREAK_SHOWN) do out[#out + 1] = p end
  end
  if not Gen4HiddenPaths.unlocked(save, Gen4HiddenPaths.SPRING_PATH) then
    for _, p in ipairs(SPRING_HIDDEN) do out[#out + 1] = p end
  end
  return out
end

-- A short string naming which patches apply, so a cached map can tell whether
-- it was built for the state the save is in now.
function Gen4HiddenPaths.key(save)
  Gen4HiddenPaths.migrate(save)
  return (Gen4HiddenPaths.unlocked(save, Gen4HiddenPaths.SEABREAK_PATH) and "S" or "s")
    .. (Gen4HiddenPaths.unlocked(save, Gen4HiddenPaths.SPRING_PATH) and "P" or "p")
end

-- The ground's grid and altitudes with the patches applied, as COPIES: the
-- terrain tables are shared by every map on the overworld and by the cache.
function Gen4HiddenPaths.grid(layout, grid, altitudes, save)
  if layout ~= OVERWORLD or not (grid and grid.land) then return grid, altitudes end
  local list = Gen4HiddenPaths.patches(save)
  if #list == 0 then return grid, altitudes end
  local land, alt = {}, nil
  for i, v in ipairs(grid.land) do land[i] = v end
  if altitudes then
    alt = {}
    for i, v in ipairs(altitudes) do alt[i] = v end
  end
  for _, p in ipairs(list) do
    if p[1] < grid.width and p[2] < grid.height then
      local i = p[2] * grid.width + p[1] + 1
      land[i] = p[3]
      if p[4] ~= nil then
        alt = alt or {}
        for k = 1, grid.width * grid.height do alt[k] = alt[k] or 0 end
        alt[i] = p[4]
      end
    end
  end
  local out = {}
  for k, v in pairs(grid) do out[k] = v end
  out.land = land
  return out, alt
end

-- The map def's collision, rebuilt for this save from a pristine snapshot so
-- that unlocking AND re-locking both land correctly. Each patched chunk's
-- cells are recomputed from the replacement land's permission block, the way
-- `Gen4Maps.mapDef` builds them at import.
local CHUNK, BLOCKED = 32, 255
local COLLISION = 0x8000
function Gen4HiddenPaths.applyToDef(data, def, save)
  if not (def and def.generation == 4 and def.layout == OVERWORLD) then return false end
  if type(def.blocks) ~= "string" or type(def.behaviorCells) ~= "string" then return false end
  local key = Gen4HiddenPaths.key(save)
  if def.gen4HiddenKey == key then return false end
  if not def.gen4HiddenBase then
    def.gen4HiddenBase = { blocks = def.blocks, behaviorCells = def.behaviorCells }
  end
  local blocks, behav = def.gen4HiddenBase.blocks, def.gen4HiddenBase.behaviorCells
  local perms = data and data.gen4_map_permissions
  local w, h = def.width or 0, def.height or 0
  local ox, oy = def.originX or 0, def.originY or 0
  local list = Gen4HiddenPaths.patches(save)
  if #list > 0 and perms then
    local cells, bytes = {}, {}
    for i = 1, w * h do
      cells[i] = blocks:sub(i * 2 - 1, i * 2)
      bytes[i] = behav:sub(i, i)
    end
    local touched = false
    for _, p in ipairs(list) do
      local block = perms[p[3]]
      if type(block) == "string" then
        for ty = 0, CHUNK - 1 do
          for tx = 0, CHUNK - 1 do
            local mx, my = p[1] * CHUNK + tx - ox, p[2] * CHUNK + ty - oy
            if mx >= 0 and my >= 0 and mx < w and my < h then
              local at = (ty * CHUNK + tx) * 2
              local lo, hi = block:byte(at + 1, at + 2)
              local word = lo and hi and (lo + hi * 256) or nil
              local v = (word == nil or word >= COLLISION) and BLOCKED or (word % 256)
              local i = my * w + mx + 1
              cells[i] = string.char(v % 256, math.floor(v / 256))
              bytes[i] = string.char(word and word % 256 or 255)
              touched = true
            end
          end
        end
      end
    end
    if touched then
      blocks, behav = table.concat(cells), table.concat(bytes)
    end
  end
  def.blocks, def.behaviorCells = blocks, behav
  -- `Map`'s decoded copy of the blocks is cached on the def; a stale one would
  -- keep the old collision however the string changed.
  def._blockArray = nil
  def.gen4HiddenKey = key
  return true
end

return Gen4HiddenPaths
