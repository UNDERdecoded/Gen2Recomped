-- Round 10: getting onto and off a Minish portal (the stump in the Minish
-- Woods and the other ACT_TILE_61 portals).
--
-- CARTRIDGE BEHAVIOUR (src/beanstalkSubtask.c ACT_TILE_61, src/player.c
-- PlayerUsePortal):
--   * Walking into an ACT_TILE_61 tile ($3D) in the facing direction for
--     6 frames (entity subtimer >= 6) starts PLAYER_USEPORTAL: zVelocity 2.0,
--     collision off, jump_status $81.
--   * PortalJumpOnUpdate: Link moves toward (portal_x, portal_y) at
--     kJumpSpeedForward (1 px / frame) while the jump runs; on landing he
--     stands on the portal facing south (PortalStandUpdate).
--   * PortalStandUpdate: a direction held (the same one) for 8 frames hops
--     off: zVelocity 2.0, speed 1, PLAYER_MINISH's hop (subAction 7).
--   * R on the portal (portal_mode 2) activates it: Objects:tryPortal.
-- Round 11: DoJump's sub-states (player.c sub_08073968 / sub_080739EC /
-- sub_08073AD4 / sub_08073A94): ANIM_HOP and SFX_PLY_JUMP on the first
-- frame, GravityUpdate with kGravityRate (z - zVelocity; landing when it
-- reaches the ground, zVelocity 0), then ANIM_LAND with SFX_PLY_LAND
-- until the animation is done; meanwhile Link moves toward the portal at
-- kJumpSpeedForward along CalculateDirectionTo (32 directions, the sine
-- table), whole-pixel arrival.  The hop off (PLAYER_MINISH subAction 7,
-- sub_080740D8) moves along the held direction while the tile ahead of
-- his hitbox edge is free, and lands without a landing animation
-- (PlayerSetNormalAndCollide).
local P = {}
local band = require("bit").band

local ACT_TILE_61 = 0x3D
local GRAV = 0.125 -- kGravityRate Q_8_8(32)
local SFX_PLY_JUMP, SFX_PLY_LAND = 0x7C, 0x7D
local ANIM_HOP, ANIM_HOP_NOCAP, ANIM_LAND, ANIM_LAND_NOCAP = 0x80C, 0x41C, 0x820, 0x424

local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
-- LinearMoveUpdate: direction 0..31 (0 north, clockwise), speed $100 = 1 px
local function linear(pl, dir, speed)
  local a = (dir * 8) % 256
  pl.x = pl.x + SIN[a] * speed / 65536
  pl.y = pl.y - SIN[(a + 64) % 256] * speed / 65536
end
-- GravityUpdate (code_08003FC4.s): z up-positive here
local function gravity(pl, g)
  local nz = (pl.z or 0) + pl.zv
  if nz <= 0 then pl.z, pl.zv = 0, 0 return false end
  pl.z, pl.zv = nz, pl.zv - g
  return true
end

local function frontAct(pl)
  local f = pl.field
  local r = f.room
  local fx, fy = pl:frontPoint(6)
  local tt = r:tileType(pl.layer or 1, math.floor(fx / 16), math.floor(fy / 16))
  if not tt or tt >= 0x4000 then return nil end
  return f.assets.actTile[tt]
end

local function nearestPortal(pl)
  local best, bd
  for _, p in ipairs(pl.field.portals or {}) do
    local d = math.abs(pl.x - p.x) + math.abs(pl.y - p.y)
    if d <= 0x40 and (not bd or d < bd) then best, bd = p, d end
  end
  return best
end

local KEY = { [0] = "up", [2] = "right", [4] = "down", [6] = "left" }

local function stand(pl, input)
  local f = pl.field
  pl:setAnim(pl:animFor("idle"))
  pl.anim:update(1)
  if not pl.control or f:inputLocked() then return end
  if input.pressed("r") and f:objects():tryPortal(pl) then return end
  local held
  for s, k in pairs(KEY) do if input.down(k) then held = s end end
  if held then
    if pl.hopDir ~= held then pl.hopDir, pl.hopT = held, 8 end
    pl.hopT = pl.hopT - 1
    if pl.hopT <= 0 then
      pl.animationState = held
      pl.portalMode = "hop"
      pl.zv = 2.0
      pl.z = pl.z or 0
      pl:setAnim(pl.hasCap and 0x80C or 0x41C, true) -- ANIM_HOP / _NOCAP
    end
  else
    pl.hopDir = nil
  end
end

local function update(pl, input)
  local mode = pl.portalMode
  if mode == "stand" then return stand(pl, input) end
  if mode == "jump" then
    -- PortalJumpOnUpdate: move, DoJump, UpdateAnimationSingleFrame
    local t = pl.portalTarget
    if math.floor(pl.x) ~= t.x or math.floor(pl.y) ~= t.y then
      local d = require("src.zelda.tmc.RouteNatives").dir32(math.floor(pl.x), math.floor(pl.y), t.x, t.y)
      linear(pl, d, 0x100)
    end
    local js = pl.jumpStatus or 2
    if js == 1 then
      -- sub_08073968: ANIM_HOP (ANIM_HOP_NOCAP), SFX_PLY_JUMP, no gravity yet
      pl.jumpStatus = 2
      pl:setAnim(pl.hasCap and ANIM_HOP or ANIM_HOP_NOCAP, true)
      if pl.field.sound then pl.field:sound(SFX_PLY_JUMP) end
      return
    elseif js == 2 then
      if not gravity(pl, GRAV) then
        pl.jumpStatus = 3
        pl:setAnim(pl.hasCap and ANIM_LAND or ANIM_LAND_NOCAP, true)
        if pl.field.sound then pl.field:sound(SFX_PLY_LAND) end
        return
      end
    elseif js == 3 then
      if pl.anim.done then
        pl.jumpStatus = 0
        pl.x, pl.y = math.floor(pl.x), math.floor(pl.y)
        pl.portalMode = "stand"
        pl.animationState = 4
        pl.entFlip = false
        pl.onPortal = true
        return
      end
    end
    pl.anim:update(1)
    return
  end
  -- hop off (sub_080740D8)
  do
    -- the probe sits on the hitbox edge ahead (unk2[0] east/west, unk2[3]
    -- north/south) and tests Link's normal collision table
    -- (sub_080086B4 returns the solid bit): while it is on the solid stump
    -- Link moves; the first free probe stops him for a frame and turns the
    -- probe round (subtimer 1), so he keeps going until his back edge is
    -- off the stump too; the hop keeps its direction
    local s = pl.animationState
    local dir = band(s, 6) * 4
    local pdir = pl.hopBack and ((dir + 16) % 32) or dir
    local hb = require("src.zelda.tmc.Hitboxes").player(pl.field, { minish = false })
    local ox, oy = hb and hb.x or 0, hb and hb.y or -3
    local ew, ns = hb and hb.u[1] or 5, hb and hb.u[4] or 5
    local px, py = math.floor(pl.x) + ox, math.floor(pl.y) + oy
    if pdir == 24 then px = px - ew elseif pdir == 8 then px = px + ew
    elseif pdir == 16 then py = py + ns else py = py - ns end
    if pl.field.room:isSolidPlayer(px, py, pl.layer or 1, 0, false) then
      pl.x = pl.x + ((s == 2 and 1) or (s == 6 and -1) or 0)
      pl.y = pl.y + ((s == 4 and 1) or (s == 0 and -1) or 0)
    else
      pl.hopBack = true
    end
  end
  pl.anim:update(1)
  if not gravity(pl, GRAV) then
    pl.portalMode = nil
    pl.hopBack = nil
    pl.onPortal = nil
    pl.state = "normal"
    pl.extUpdate = nil
  end
end

-- after the normal walk: count frames pushed into a portal tile
function P.check(pl, dx, dy, x0, y0)
  if pl.minish or pl.state ~= "normal" then pl.portalPush = 0 return end
  if (dx == 0 and dy == 0) or pl.x ~= x0 or pl.y ~= y0 then pl.portalPush = 0 return end
  if frontAct(pl) ~= ACT_TILE_61 then pl.portalPush = 0 return end
  pl.portalPush = (pl.portalPush or 0) + 1
  if pl.portalPush < 6 then return end
  local p = nearestPortal(pl)
  if not p then return end
  pl.portalPush = 0
  pl.state = "ext"
  pl.extUpdate = update
  pl.portalMode = "jump"
  pl.portalTarget = { x = p.x, y = p.y }
  pl.zv, pl.z = 2.0, 0
  pl.jumpStatus = 1 -- jump_status $81: DoJump starts at sub_08073968
end

-- PortalShrinkUpdate's grow side ends with Link standing on the portal
-- (PL_USE_PORTAL, PortalStandUpdate): hop off with a held direction
function P.standOn(pl, p)
  pl.state = "ext"
  pl.extUpdate = update
  pl.portalMode = "stand"
  pl.portalTarget = { x = p.x, y = p.y }
  pl.x, pl.y, pl.z, pl.zv = p.x, p.y, 0, 0
  pl.animationState = 4
  pl.entFlip = false
  pl.onPortal = true
end

-- Objects:portalDone puts Link back to normal; clear the stand state
function P.clear(pl)
  pl.portalMode, pl.onPortal, pl.extUpdate = nil, nil, nil
end

return P
