-- Round 42: full-size Link on a hole tile (player.c PlayerInHole).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * UpdateFloorType: the surface is gMapActTileToSurfaceType[act tile]
--     ($08007CAC in the USA ROM: ACT_TILE_25 ($19) and $F0 ->
--     SURFACE_HOLE, ACT_TILE_13 ($0D) -> SURFACE_PIT).
--   * SurfaceAction_Hole: Minish Link takes SurfaceAction_Pit (falls);
--     full-size Link (not on a platform, field_0x14) gets PLAYER_INHOLE --
--     no fall, no damage.
--   * PlayerInHoleInit: x = (x & ~$F) | 8, y = (y & ~$F) | 10, collision
--     off, ANIM_FALL_IN_HOLE ($61C; no cap $950), SFX_81.  A hole charged
--     by the Cane of Pacci (SPECIAL_TILE_32) springs instead (Pacci.lua
--     holeLaunch, checked first).
--   * PlayerInHoleUpdate: the animation to its end, then ANIM_IN_HOLE
--     ($620; no cap $954).
--   * sub_08072ACC: no direction held -> the counter resets; a direction
--     held for more than 7 frames hops out that way: collision on,
--     zVelocity kJumpSpeedHoleZ (1.625), speed kJumpSpeedHoleForward
--     ($78 = 0.46875 px a frame), jump_status $41 (the player's own
--     movement, walls stop it), gravity kGravityRate (0.125).
-- SIMPLIFIED: SPECIAL_TILE_112 is not put on the hole while Link sits in it
-- (RestorePrevTileEntity on the way out has nothing to restore).
local Hole42 = {}

local ANIM_FALL_IN_HOLE, ANIM_FALL_IN_HOLE_NOCAP = 0x61C, 0x950
local ANIM_IN_HOLE, ANIM_IN_HOLE_NOCAP = 0x620, 0x954
local ANIM_JUMP = 0x810
local SFX_81, SFX_PLY_JUMP = 0x81, 0x7C
local HOLE_Z, HOLE_SPEED, GRAVITY = 1.625, 0x78 / 256, 0.125
local SURFACE_HOLE = 0x27 -- SurfaceType enum (player.h)
local SURFACE = require("src.zelda.tmc.RomTables").t("Hole42.SURFACE") -- gMapActTileToSurfaceType, read from the ROM
function Hole42.surfaceOf(act) return SURFACE[act or -1] end

local function dirOf(input)
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  return dx, dy
end

-- the hop out (jump_status $41: PlayerSetNormalAndCollide, then DoJump)
local function hop(f, p, dx, dy)
  local n = math.sqrt(dx * dx + dy * dy)
  local vx, vy = dx / n * HOLE_SPEED, dy / n * HOLE_SPEED
  p.z, p.zv = 0.01, HOLE_Z
  p.hop42 = true
  p:setAnim(ANIM_JUMP, true)
  f:sound(SFX_PLY_JUMP)
  p.extUpdate = function(pl)
    pl:moveBy(vx, vy)
    pl.zv = pl.zv - GRAVITY
    pl.z = pl.z + pl.zv
    pl.anim:update(1)
    if pl.z <= 0 then
      pl.z, pl.zv = 0, 0
      pl.state = "normal"
      pl.extUpdate = nil
      pl.inHole42, pl.hop42 = nil, nil
      pl.animId = -1
    end
  end
end

-- Dungeon:checkFall: the act tile under Link is a SURFACE_HOLE one
function Hole42.enter(d, p, rawAct)
  if p.minish or Hole42.surfaceOf(rawAct) ~= SURFACE_HOLE then return false end
  -- a HOLE_MANAGER room's pit still drops Link to the room below (Holes.lua)
  if require("src.zelda.tmc.Holes").exitFor(d, p) then return false end
  local f = d.field
  p.state = "ext"
  p.inHole42 = true
  p.x = math.floor(p.x / 16) * 16 + 8
  p.y = math.floor((p.y - 1) / 16) * 16 + 10
  p.z, p.zv = 0, 0
  p:setAnim(p.hasCap and ANIM_FALL_IN_HOLE or ANIM_FALL_IN_HOLE_NOCAP, true)
  f:sound(SFX_81)
  local phase, held = 1, 0
  p.extUpdate = function(pl, input)
    if phase == 1 then
      pl.anim:update(1)
      if pl.anim.done then
        phase = 2
        pl:setAnim(pl.hasCap and ANIM_IN_HOLE or ANIM_IN_HOLE_NOCAP, true)
      end
      return
    end
    pl.anim:update(1)
    local dx, dy = 0, 0
    if input and not f:inputLocked() then dx, dy = dirOf(input) end
    if dx == 0 and dy == 0 then held = 0 return end
    if held > 7 then return hop(f, pl, dx, dy) end
    -- Direction8ToAnimationState: Link turns while the counter runs
    if dx ~= 0 then pl.animationState = dx > 0 and 2 or 6 else pl.animationState = dy > 0 and 4 or 0 end
    held = held + 1
  end
  return true
end

return Hole42
