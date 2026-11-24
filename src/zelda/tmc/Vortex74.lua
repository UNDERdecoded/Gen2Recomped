-- Round 74: the arrival after a BIG_VORTEX / parachute exit (gameUtils.c InitializePlayer, playerUtils.c PlayerWarp
-- sub_0807B144, player.c DoJump).
--
-- CARTRIDGE BEHAVIOUR:
--   * Spawn type PL_SPAWN_PARACHUTE_FORWARD (10) -> PLAYER_WARP with field_0x38 = 1 -> sub_0807B144: drawn,
--     direction = animationState << 2 (the exit's facing), speed $A0, zVelocity 4.0, jump_status $81, then
--     PLAYER_NORMAL: DoJump state 1 (ANIM_HOP, SFX_PLY_JUMP, the direction kept: jump_status & $C0), state 2
--     (jump_status & $80: collisions COL_NONE, GravityUpdate(kGravityRate)) until the landing (sub_08073AD4).
--     So Link hops forward from the arrival point, 4.0 / (1/8) * 2 = 64 frames at 0.625 px a frame.
--   * PL_SPAWN_PARACHUTE_UP (11, field_0x38 = 3) -> sub_0807B178: straight up (direction $10, speed 0), same jump.
-- Port gap fixed: Vortex34's arrival put Link down on the arrival point itself.  The Veil Falls vortex's exit
-- (gUnk_0813AD88[1]) lands in the middle of a Cloud Tops hole pad: Link fell through at once and was back on Veil
-- Falls top -- the Cloud Tops could not be reached.
local bit = require("bit")
local band = bit.band

local M = {}

M.PL_SPAWN_PARACHUTE_FORWARD, M.PL_SPAWN_PARACHUTE_UP = 10, 11
M.SPEED = 0xA0 / 256       -- sub_0807B144's speed (Q8.8)
M.ZVEL = 4.0               -- Q_16_16(4.0)
M.GRAV = 32 / 256          -- kGravityRate Q_8_8(32), per frame
local ANIM_HOP = 0x80C -- Player:setAnim adds the facing
local SFX_PLY_JUMP, SFX_PLY_LAND = 0x7C, 0x7D

-- Vortex34: the exit a parachute leaves by (its spawn type / facing are what the arrival needs)
function M.note(p, ex)
  if p and ex then p.arrive74 = { kind = ex.kind, facing = ex.facing } end
end

local function dirVec(dir32)
  local a = (dir32 % 32) / 32 * 2 * math.pi
  return math.sin(a), -math.cos(a)
end

function M.hop(p)
  local h = p.hop74
  if not h then p.state, p.extUpdate = "normal", nil return end
  if p.anim then p.anim:update(1) end
  if h.speed > 0 then
    local vx, vy = dirVec(h.dir)
    p.x, p.y = p.x + vx * h.speed, p.y + vy * h.speed -- COL_NONE while jump_status & $80
  end
  local nz = (p.z or 0) + p.zv
  if nz > 0 or h.t == 0 then
    p.z, p.zv = math.max(nz, 0), p.zv - M.GRAV
    h.t = h.t + 1
    return
  end
  -- sub_08073AD4: the landing
  p.z, p.zv = 0, 0
  p.x, p.y = math.floor(p.x + 0.5), math.floor(p.y + 0.5)
  p.hop74 = nil
  p.state, p.extUpdate = "normal", nil
  p.animId = -1
  local f = p.field
  if f and f.sound then f:sound(SFX_PLY_LAND) end
end

-- after the room change (Vortex34.frame): start PlayerWarp's jump for the parachute spawn types
function M.arrive(f, p)
  local a = p and p.arrive74
  if not a then return false end
  p.arrive74 = nil
  local up = a.kind == M.PL_SPAWN_PARACHUTE_UP
  if a.kind ~= M.PL_SPAWN_PARACHUTE_FORWARD and not up then return false end
  if a.facing then p.animationState = band(a.facing, 7) end
  p.hop74 = { dir = up and 0x10 or (p.animationState or 4) * 4, speed = up and 0 or M.SPEED, t = 0 }
  p.z, p.zv = 0, M.ZVEL
  p.state, p.extUpdate = "ext", M.hop
  if p.setAnim and p.hasCap ~= false then p:setAnim(ANIM_HOP, true) end
  if f and f.sound then f:sound(SFX_PLY_JUMP) end
  return true
end

return M
