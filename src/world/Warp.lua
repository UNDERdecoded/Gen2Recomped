-- Warp resolution.  A warp fires when:
--   * the player finishes a step onto a warp cell whose collision tile is a
--     door tile or warp tile (stairs, doors, mats, cave entrances), or
--   * the player stands on a warp cell and tries to walk off the map edge
--     (exit carpets at the bottom of interiors), or
--   * the player stands on a warp cell and the "extra" check passes -- on
--     arrival with the d-pad held, or on a blocked step (route-gate
--     doorways, the Vermilion dock entrance, ...).
-- This mirrors pokered's CheckWarpsNoCollision / CheckWarpsCollision /
-- ExtraWarpCheck (home/overworld.asm).

local Runtime = require("src.mods.Runtime")

local Warp = {}

-- Returns the warp entry to take when arriving at (cx,cy), or nil.
function Warp.onArrive(map, cx, cy)
  local w = map:warpAtCell(cx, cy)
  if w and map:isWarpTileCell(cx, cy) then
    return w
  end
  return nil
end

local function inList(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

-- ExtraWarpCheck: may the player standing at (cx,cy) facing dir warp
-- without a door/warp tile underfoot?  On the carpet maps/tilesets the
-- tile in FRONT of the player must be a warp-carpet tile for the facing
-- direction (IsWarpTileInFrontOfPlayer; SS_ANNE_BOW tests one hardcoded
-- tile instead); everywhere else the player must face the map edge
-- (IsPlayerFacingEdgeOfMap).  carpets = field.warpCarpets.
function Warp.extraCheck(map, carpets, cx, cy, dir)
  local Collision = require("src.world.Collision")
  local facingEdge =
    (dir == "up" and cy == 0)
    or (dir == "down" and cy == map.heightCells - 1)
    or (dir == "left" and cx == 0)
    or (dir == "right" and cx == map.widthCells - 1)
  if not carpets then return facingEdge end
  -- the map exceptions are tested before the tileset (ExtraWarpCheck)
  local useCarpet
  if inList(carpets.edgeMaps, map.id) then
    useCarpet = false
  elseif inList(carpets.function2Maps, map.id) then
    useCarpet = true
  else
    useCarpet = inList(carpets.function2Tilesets, map.def.tileset)
  end
  if not useCarpet then return facingEdge end
  local tx, ty = Collision.target(cx, cy, dir)
  local front = map:cellTile(tx, ty)
  if map.id == carpets.ssAnneBow.map then
    return front == carpets.ssAnneBow.tile
  end
  return inList(carpets.tiles[dir], front)
end

-- Returns the warp entry when standing on (cx,cy) and the extra check
-- passes toward dir (fired from a blocked step, or on arrival with the
-- d-pad held).
function Warp.onCollision(map, carpets, cx, cy, dir)
  local w = map:warpAtCell(cx, cy)
  if w and Warp.extraCheck(map, carpets, cx, cy, dir) then
    return w
  end
  return nil
end

-- Returns the warp entry when standing on (cx,cy) and moving toward dir
-- takes the player out of bounds.
function Warp.onEdge(map, cx, cy, dir)
  local w = map:warpAtCell(cx, cy)
  if not w then return nil end
  local Collision = require("src.world.Collision")
  local tx, ty = Collision.target(cx, cy, dir)
  if not map:inBounds(tx, ty) then
    return w
  end
  return nil
end

-- Resolve a warp's destination to map id + cell.  LAST_MAP destinations
-- (returning from an interior) resolve against the remembered outdoor
-- map; the landing cell is that map's warp entry named by the warp id
-- (wDestinationWarpID placement -- two-sided route gates land you on
-- the side you exit, not where you entered).
local function resolve(data, warpDef, lastMap, backupWarp)
  local destMap = warpDef.destMap
  -- Gen2 warp id $FF: land back on the warp tile we last stepped through,
  -- whatever map that was (EnterMapWarp's wBackupWarp).
  if destMap == "LAST_WARP" then
    if backupWarp and data.maps[backupWarp.id] then
      return backupWarp.id, backupWarp.x, backupWarp.y
    end
    destMap = "LAST_MAP"
  end
  if destMap == "LAST_MAP" then
    assert(lastMap, "LAST_MAP warp with no remembered outdoor map")
    destMap = lastMap.id
    local destDef = data.maps[destMap]
    local dw = destDef and destDef.warps[warpDef.destWarp]
    if dw then
      return destMap, dw.x, dw.y
    end
    -- out-of-range data: fall back to where the player entered
    return destMap, lastMap.x, lastMap.y
  end
  local destDef = data.maps[destMap]
  if not destDef then
    -- Gen2 alias not yet resolved: warn and stay at current position
    require("src.core.Logger").warn("warp to unknown map %s (alias not resolved)", tostring(destMap))
    local fallback = (lastMap and lastMap.id) or destMap
    local fb = data.maps[fallback]
    return fallback, (fb and fb.warps and fb.warps[1] and fb.warps[1].x) or 3,
                    (fb and fb.warps and fb.warps[1] and fb.warps[1].y) or 3
  end
  local dw = destDef.warps[warpDef.destWarp]
  if not dw then
    -- AN OUT-OF-RANGE WARP ID IS REAL DATA, not corruption.  Prism's
    -- Battle Tower is the case: BattleTowerHallway's first warp names
    -- warp 3 of BATTLE_TOWER_ELEVATOR and the elevator has two, because
    -- that door is script-driven -- the elevator's own trigger warps you
    -- on, so the id in the table is never meant to be honoured.
    --
    -- Landing at the map's geometric CENTRE, which is what this did,
    -- puts the player wherever that happens to be -- and in a 2x2-block
    -- elevator that is not a tile you can walk off, which is being
    -- locked in the tower.  Prefer the destination's own way BACK: the
    -- warp that returns to the map being left, then its first warp,
    -- and only then the centre.  All three are walkable by
    -- construction -- a warp tile is somewhere the player stands.
    local from = warpDef.sourceMap or (lastMap and lastMap.id)
    local back
    if from then
      for _, w in ipairs(destDef.warps or {}) do
        if w.destMap == from then back = w break end
      end
    end
    back = back or (destDef.warps and destDef.warps[1])
    if back then return destMap, back.x, back.y end
    return destMap, destDef.width * 2 / 2, destDef.height * 2 / 2
  end
  return destMap, dw.x, dw.y
end

-- the resolved destination passes through warp.destination, so a mod can
-- reroute one door without owning the warp table (ctx carries the warp
-- record and the remembered outdoor side the resolution used)
local function warped(mapId, x, y) return mapId, x, y end

function Warp.destination(data, warpDef, lastMap, backupWarp)
  local destMap, x, y = resolve(data, warpDef, lastMap, backupWarp)
  if not Runtime.wantsHook("warp.destination") then return destMap, x, y end
  return Runtime.call("warp.destination", warped, destMap, x, y,
                      { warp = warpDef, lastMap = lastMap, data = data })
end

return Warp
