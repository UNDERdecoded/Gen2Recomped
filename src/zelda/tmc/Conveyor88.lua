-- Round 88: the conveyor surfaces (SURFACE_D / E / F / 10, src/player.c SurfaceAction_ConveyerNorth / South /
-- West / East + conveyer_push).  An R27A module: it wraps Dungeon.checkFall when it is required (as Cracked86).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * The act tile under Link goes through gMapActTileToSurfaceType (read from the ROM: Hole42.SURFACE) to his
--     floor type; SURFACE_D -> ConveyerNorth, SURFACE_E -> South, SURFACE_F -> West, SURFACE_10 -> East.  In the
--     Palace of Winds these are the cloud rims (acts $2A .. $2D): a Link that ends up on a rim is carried back
--     onto the cloud (the rim on a cloud's west side pushes east, and so on).
--   * Each: not when sub_080741C4 (jumping with jump_status & 7 != 3, or z != 0) and not Minish:
--     animationState / direction = the conveyor's, then conveyer_push: ResetActiveItems, speed = kWalkSpeed
--     ($140 = 1.25 px a frame), PL_CONVEYOR_PUSHED, LinearMoveUpdate (no tile test).
-- SIMPLIFIED: the push runs in the port's states that run Dungeon.checkFall (normal, gust, shield);
--   ResetActiveItems is not done (an item in use keeps going); PL_CONVEYOR_PUSHED is p.conveyor88 for this frame.
local M = {}

M.SURFACE_D, M.SURFACE_E, M.SURFACE_F, M.SURFACE_10 = 0x0D, 0x0E, 0x0F, 0x10
M.WALK_SPEED = 1.25 -- kWalkSpeed $140 / 256
-- surface -> { animationState, dx, dy }
M.PUSH = {
  [M.SURFACE_D] = { 0, 0, -1 },  -- ConveyerNorth: IdleNorth, DirectionNorth
  [M.SURFACE_E] = { 4, 0, 1 },   -- ConveyerSouth
  [M.SURFACE_F] = { 6, -1, 0 },  -- ConveyerWest
  [M.SURFACE_10] = { 2, 1, 0 },  -- ConveyerEast
}

local SURFACE = require("src.zelda.tmc.RomTables").t("Hole42.SURFACE") -- gMapActTileToSurfaceType, from the ROM
local override
function M.useSurfaces(map) override = map end -- tests: a stand-in act -> surface map

local function surfaceOf(act)
  if act == nil then return nil end
  if override then return override[act] end
  local ok, v = pcall(function() return SURFACE[act] end)
  if ok then return v end
  return nil
end
M.surfaceOf = surfaceOf

-- sub_080741C4: in a jump or off the ground
local function airborne(p)
  return (p.z or 0) ~= 0 or p.jump ~= nil or p.jumping
end

-- one frame of the floor's conveyor for the player; returns the push { anim, dx, dy } or nil
function M.playerFrame(d, p)
  p.conveyor88 = nil
  if p.minish or airborne(p) then return nil end
  local layer = p.layer == 2 and 2 or 1
  local s = M.PUSH[surfaceOf(d:actAt(p.x, p.y, layer)) or -1]
  if not s then return nil end
  p.animationState = s[1]
  p.x = p.x + s[2] * M.WALK_SPEED
  p.y = p.y + s[3] * M.WALK_SPEED
  p.conveyor88 = true
  return s
end

local Dungeon = require("src.zelda.tmc.Dungeon")
if not Dungeon.conveyor88Installed then
  Dungeon.conveyor88Installed = true
  local checkFall = Dungeon.checkFall
  Dungeon.checkFall = function(self, ...)
    local p = self.field and self.field.player
    if p and (p.state == "normal" or p.state == "gust" or p.state == "shield") then M.playerFrame(self, p) end
    return checkFall(self, ...)
  end
end

return M
