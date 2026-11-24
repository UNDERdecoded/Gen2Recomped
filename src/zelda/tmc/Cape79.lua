-- Round 79: Roc's Cape in the air (asm/src/player.s sub_08008942 with
-- jump_status != 0, player.c PlayerNormal / DoJump, playerUtils.c
-- CheckPlayerVelocity) -- replaces ItemCape's simplified air control.
--
-- CARTRIDGE BEHAVIOUR:
--   * DoJump state 1 (sub_08073968) calls CheckPlayerVelocity: the d-pad
--     direction (dir32) at that frame gives vel = (gSineTable[d * 8],
--     -gSineTable[d * 8 + $40]) ($100 = 1 px a frame); no direction -> 0.
--     So a jump from a walk starts at 1 px a frame, a jump in place at 0.
--   * Each frame of the jump (jump_status & 7 != 3, no Down Thrust bit $20)
--     PlayerNormal sets speed 0 and calls sub_08008926 (sub_08008942): with
--     a direction held, r = (dir8 - (animationState & ~1) + 2) & 7; r <= 4
--     (forward, the diagonals forward, either side) adds velocities1[dir8],
--     r 5..7 (back) adds velocities3[animationState >> 1] (literal pool
--     $08008A78 / $08008A7C, read from the player's ROM: RomTablesCat
--     Cape79.AIR_VEL / AIR_BACK); each axis is clamped to +-$180
--     (ClampPlayerVelocity); then Link moves by vel_x and vel_y
--     (LinearMoveDirectionOLD + sub_0807A5B8, the collision).  The velocity
--     does not decay in the air (sub_08008A1A only runs with jump_status 0):
--     with the pad let go Link keeps flying the way he was going.
--   * Landing (jump_status & 7 == 3) moves nothing; the cape can be used
--     again at once from that state (ItemRocsCape: jump_status 0 or
--     (jump_status & 7) == 3 starts a new jump).
-- SIMPLIFIED: Link's facing in the air is the one he had when he jumped
--   (the port's ItemCape never turns him there either).
local bit = require("bit")
local band = bit.band

local M = {}

M.CLAMP = 0x180
M.ITEM = 0x14
local AIR = require("src.zelda.tmc.RomTables").t("Cape79.AIR_VEL")   -- velocities1 (rows by dir8)
local BACK = require("src.zelda.tmc.RomTables").t("Cape79.AIR_BACK") -- velocities3 (rows by facing / 2)

-- gSineTable (256 steps a turn, $100 = 1)
local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
M.SIN = SIN

local DIRS = { left = true, right = true, up = true, down = true }

function M.dir8(dx, dy)
  if dx == 0 and dy < 0 then return 0 elseif dx > 0 and dy < 0 then return 1 elseif dx > 0 and dy == 0 then return 2
  elseif dx > 0 and dy > 0 then return 3 elseif dx == 0 and dy > 0 then return 4 elseif dx < 0 and dy > 0 then return 5
  elseif dx < 0 and dy == 0 then return 6 elseif dx < 0 and dy < 0 then return 7 end
  return nil
end

function M.clamp(v)
  if v >= M.CLAMP then return M.CLAMP end
  if v < -M.CLAMP then return -M.CLAMP end
  return v
end

local function pad(input)
  local dx, dy = 0, 0
  if input and input.down then
    if input.down("left") then dx = dx - 1 end
    if input.down("right") then dx = dx + 1 end
    if input.down("up") then dy = dy - 1 end
    if input.down("down") then dy = dy + 1 end
  end
  return dx, dy
end
M.pad = pad

-- CheckPlayerVelocity: the starting velocity
function M.startVel(dx, dy)
  local d8 = M.dir8(dx, dy)
  if not d8 then return 0, 0 end
  local a = d8 * 4 -- dir32
  return SIN[(a * 8) % 256], -SIN[(a * 8 + 0x40) % 256]
end

-- which table a held direction adds from (sub_08008942): "fwd" (velocities1) or "back" (velocities3)
function M.kind(d8, facing)
  local r = band(d8 - band(facing or 0, 6) + 2, 7)
  return r <= 4 and "fwd" or "back"
end

-- one frame's velocity change; tables passed for tests (default the ROM's)
function M.accel(vx, vy, d8, facing, air, back)
  air, back = air or AIR, back or BACK
  if d8 then
    local a
    if M.kind(d8, facing) == "fwd" then a = air[d8] else a = back[band(facing or 0, 6) / 2] end
    vx, vy = M.clamp(vx + a[1]), M.clamp(vy + a[2])
  end
  return vx, vy
end

-- one frame of the jump's movement
function M.air(p, dx, dy)
  local vx, vy = M.accel(p.airVx or 0, p.airVy or 0, M.dir8(dx, dy), p.animationState)
  p.airVx, p.airVy = vx, vy
  local C80 = require("src.zelda.tmc.Collide80") -- round 80: both axes use the collisions taken before them
  if p.field and p.field.room and p.field.room.coll and C80.ready() then p.coll80 = C80.collisions(p) end
  if vx ~= 0 then p:moveBy(vx / 256, 0) end
  if vy ~= 0 then p:moveBy(0, vy / 256) end
  p.coll80 = nil
end

-- the input ItemCape.step sees: no d-pad (its own walk in the air is replaced)
local function noPad(input)
  if not input then return input end
  return setmetatable({ down = function(k) if DIRS[k] then return false end return input.down(k) end }, { __index = input })
end

function M.install(IC)
  if IC._cape79 then return end
  IC._cape79 = true
  local step0 = IC.step
  IC.step = function(p, input)
    local j = p.jump
    if not j then return step0(p, input) end
    -- ItemRocsCape from the landing state: a new jump at once
    if j.phase == 3 and input and input.pressed and input.pressed(j.button)
       and p.field and p.field.equipped and p.field:equipped(j.button) == M.ITEM then
      p.state, p.extUpdate, p.jump, p.jumping = "normal", nil, nil, nil
      p.z, p.zv = 0, 0
      if IC.use(p, M.ITEM, j.button, input) then return end
      return
    end
    if j.phase == 1 then p.airVx, p.airVy = M.startVel(pad(input)) end
    step0(p, noPad(input))
    if p.jump == j and j.phase == 2 and not p.downThrust then M.air(p, pad(input)) end
  end
end

return M
