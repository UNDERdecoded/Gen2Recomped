-- Round 26 (team A): ROC'S CAPE ($14): src/item/itemRocsCape.c (ItemRocsCape,
-- sub_08076758) and the jump of src/player.c (DoJump: sub_08073924,
-- sub_08073968, sub_080739EC, sub_08073A94, sub_08073AD4, sub_08073B60).
--
--   Use (ItemRocsCape, stateID 0): Link not busy (no sword / item / held
--     object / gust jar / mole mitts), not on a door or pit floor, on the
--     ground: zVelocity Q_16_16(2.0), jump_status 1, SFX_PLY_VO4 ($78).
--   DoJump 1 (sub_08073968): ANIM_HOP ($80C; no cap ANIM_HOP_NOCAP $41C,
--     Minish keeps his animation), SFX_PLY_JUMP ($7C), jump_status 2.
--   DoJump 2 (sub_080739EC): GravityUpdate kGravityRate (Q_8_8(32) = 1/8 px
--     a frame), halved while jump_status bit $10 (the cape spread) is set.
--   sub_08076758 (each frame of the item): the cape's button still held, the
--     first jump past its apex (zVelocity <= 0) and bit $10 clear -> stateID
--     2, zVelocity 2.0 again, bit $10, ANIM_ROCS_CAPE ($288), SFX_172; the
--     button let go after that -> bit $10 cleared (full gravity).
--   Landing (sub_08073AD4): ANIM_LAND ($820; no cap $424), SFX_PLY_LAND
--     ($7D); jump_status 3 (sub_08073A94) until the animation is done, then
--     SetPlayerActionNormal (sub_08073B60).
--   In the air Link uses the jump collision table (Player:blocked tab 4) and
--     Dungeon:checkFall ignores pits / water / lava: the cape crosses gaps.
--   The Down Thrust ($4E): the sword pressed in the air hands over to
--     SwordSkills.downThrust / downThrustFrame / downThrustLand.
-- SIMPLIFIED: the air control (sub_08008926, the ice-velocity table of
--   asm/src/player.s) is a plain walk at kWalkSpeed toward the pad; the
--   pit check sub_0806F854 (double gravity over a pit) is not ported.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local C = {}
C.ITEM = 0x14
C.GRAVITY = 0x2000 / 0x10000     -- kGravityRate
C.JUMP_V = 2.0                   -- Q_16_16(2.0)
C.ANIM_HOP, C.ANIM_HOP_NOCAP = 0x80C, 0x41C
C.ANIM_ROCS_CAPE = 0x288
C.ANIM_LAND, C.ANIM_LAND_NOCAP = 0x820, 0x424
C.SFX_VO4, C.SFX_JUMP, C.SFX_LAND, C.SFX_CAPE = 0x78, 0x7C, 0x7D, 0x172

local function skills() return require("src.zelda.tmc.SwordSkills") end
local function isSword(i) return i and ((i >= 1 and i <= 6)) end

local function dirInput(input)
  local dx, dy = 0, 0
  if input then
    if input.down("left") then dx = dx - 1 end
    if input.down("right") then dx = dx + 1 end
    if input.down("up") then dy = dy - 1 end
    if input.down("down") then dy = dy + 1 end
  end
  return dx, dy
end

local function finish(p)
  p.state = "normal"
  p.extUpdate, p.jump, p.jumping = nil, nil, nil
  p.z, p.zv = 0, 0
  p.animId = -1
end

local function land(p)
  local f = p.field
  p.z, p.zv = 0, 0
  p.jumping = nil
  if p.downThrust and skills().downThrustLand and skills().downThrustLand(p) then p.jump = nil return end
  p.jump.phase = 3
  if not p.minish then p:setAnim(p.hasCap and C.ANIM_LAND or C.ANIM_LAND_NOCAP, true) end
  f:sound(C.SFX_LAND)
end

function C.step(p, input)
  local f, j = p.field, p.jump
  if not j then return end
  if j.phase == 3 then -- sub_08073A94
    p.anim:update(1)
    if p.anim.done or band(p.anim.flags or 0, 0x80) ~= 0 or p.minish then finish(p) end
    return
  end
  if j.phase == 1 then -- sub_08073968
    if not p.minish then p:setAnim(p.hasCap and C.ANIM_HOP or C.ANIM_HOP_NOCAP, true) end
    f:sound(C.SFX_JUMP)
    j.phase = 2
  end
  -- the item's own frame (sub_08076758)
  local held = input and input.down(j.button)
  if held then
    if j.stage < 2 and p.zv <= 0 and not j.cape then
      j.stage, j.cape = 2, true
      p.zv = C.JUMP_V
      if not p.minish then p:setAnim(C.ANIM_ROCS_CAPE, true) end
      f:sound(C.SFX_CAPE)
    end
  elseif j.stage > 1 then
    j.cape = false
  end
  -- the sword in the air: the Down Thrust (SwordSkills.lua)
  if input and not p.downThrust then
    for _, b in ipairs({ "b", "a" }) do
      if input.pressed(b) and isSword(f:equipped(b)) and skills().downThrust then
        p.swordButton = b
        if skills().downThrust(p) then break end
      end
    end
  end
  -- movement (simplified air control)
  local hop = p.downThrust and p.downThrust.hop
  if not hop then
    local dx, dy = dirInput(input)
    if dx ~= 0 or dy ~= 0 then
      local s = require("src.zelda.tmc.Player").WALK_SPEED
      if dx ~= 0 and dy ~= 0 then s = s * 0.70710678 end
      p:moveBy(dx * s, dy * s)
    end
  end
  -- gravity (sub_080739EC)
  local g = C.GRAVITY
  if j.cape then g = g / 2 end
  p.z = p.z + p.zv
  p.zv = p.zv - g
  if p.downThrust and skills().downThrustFrame then skills().downThrustFrame(p) end
  p.anim:update(1)
  if p.z <= 0 then land(p) end
end

function C.use(p, item, button, input)
  if item ~= C.ITEM then return nil end
  if p.state ~= "normal" or p.carried or (p.z or 0) < 0 then return nil end
  if p.swimming then return nil end
  local f = p.field
  p.jump = { phase = 1, stage = 1, button = button, cape = false }
  p.jumping = true
  p.zv = C.JUMP_V
  p.z = 0.01
  p.state = "ext"
  p.extUpdate = function(pl, inp) C.step(pl, inp) end
  f:sound(C.SFX_VO4)
  return true
end

-- the state survives a room change badly: Field:enterRoom resets extUpdate
function C.frame(p)
  if p.jump and p.state ~= "ext" then p.jump, p.jumping = nil, nil; p.z = 0 end
  return nil
end

return C
