-- Round 90: the room exit lists the Four Sword swaps in (src/movement.c, called from the rooms' sub_StateChange).
--
-- sub_080AF2E4 (sub_StateChange_Sanctuary_Hall, $78:00): with ITEM_FOURSWORD the hall's exits are gUnk_0813A76C --
--   its south door leads to the Dark Hyrule Castle's outside garden instead of the Sanctuary entrance.  (The port
--   kept the hall's own list: after the Four Sword and Vaati's reveal Link walked back to the old castle.)
-- sub_080AF284 (sub_StateChange_CastleGarden_Main, $07:00): Link in the region (0x78, height - 0x50) +- (0x78, 0x50)
--   -> gUnk_08135048 (the south border only); else with ITEM_FOURSWORD -> gUnk_08134FBC (the castle's door now
--   leads into Dark Hyrule Castle's 1F entrance).
-- The lists are read from the player's ROM (RomTables "Exits90.*").  The room's own list is kept (exits0) and put
-- back when the condition does not hold on a later visit.
local M = {}

local RT = require("src.zelda.tmc.RomTables")
M.tables = { HALL = RT.t("Exits90.HALL"), GARDEN = RT.t("Exits90.GARDEN"), GARDEN_SOUTH = RT.t("Exits90.GARDEN_SOUTH") }
local ITEM_FOURSWORD = 0x06

local function copyList(src)
  local t = {}
  for i, e in ipairs(src or {}) do
    if e.warpType ~= 0xFFFF then local c = {} for k, v in pairs(e) do c[k] = v end t[#t + 1] = c end
  end
  return t
end
M.copyList = copyList

local function setExits(r, list)
  r.exits0 = r.exits0 or r.exits
  if list then r.exits = copyList(list) else r.exits = r.exits0 end
end

local function hasFourSword(f) local v = f:inventory(ITEM_FOURSWORD) return v == true or (type(v) == "number" and v ~= 0) end

-- CheckPlayerInRegion(centerX, centerY, radiusX, radiusY), room coordinates: (unsigned) cx - (px - rx) < 2 rx
function M.inRegion(px, py, cx, cy, hw, hh)
  local dx, dy = cx - (math.floor(px) - hw), cy - (math.floor(py) - hh)
  return dx >= 0 and dx < 2 * hw and dy >= 0 and dy < 2 * hh
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  if r.area == 0x78 and r.room == 0x00 then -- sub_080AF2E4
    setExits(r, hasFourSword(f) and M.tables.HALL or nil)
  elseif r.area == 0x07 and r.room == 0x00 then -- sub_080AF284
    local p = f.player
    local h = r.height or 0
    if p and M.inRegion(p.x, p.y, 0x78, h - 0x50, 0x78, 0x50) then setExits(r, M.tables.GARDEN_SOUTH)
    elseif hasFourSword(f) then setExits(r, M.tables.GARDEN)
    else setExits(r, nil) end
  end
end

return M
