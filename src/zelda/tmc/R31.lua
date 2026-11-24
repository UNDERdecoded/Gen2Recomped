-- Round 31: Link frozen (PL_FROZEN) and set on fire (PL_BURNING) by an
-- enemy's touch.  Listed in R27B.MODULES (playerFrame); the touch comes from
-- one hook in Enemies:update (R31.contact).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * collision.c gCollisionHandlers[12] = sub_08017C40 (the matrix entry of
--     an icy hitType against Link): Link not PL_BUSY / PL_MINISH / PL_FROZEN
--     / PL_IN_MINECART, no queued action, in PLAYER_NORMAL (action 1 / 24):
--     damage 4 (CalculateDamage), flags = PL_FROZEN, queued PLAYER_FROZEN;
--     the enemy gets knockback 12 frames at 640 and 16 iframes.
--   * player.c PlayerFrozenInit: COLLISION_OFF, timer 120, ANIM_FROZEN
--     ($294), PutAwayItems, SFX_195.  PlayerFrozenUpdate: falls to the
--     ground (GravityUpdate); every new button press takes 3 off the timer
--     and shakes him (spriteOffsetX 2, else 0); timer <= 0 -> break_out:
--     160 iframes, COLLISION_ON, FX_ICE, PLAYER_NORMAL.
--   * gCollisionHandlers[11] = CollisionFire: Link not PL_BUSY / PL_MINISH /
--     PL_BURNING / PL_IN_MINECART: LINK_FIRE ($42) type 1, PL_BURNING, Link
--     faces the fire's side; damage 4, knockback 12 frames at 384, 30
--     iframes.  PlayerNormal with PL_BURNING: speed kWalkSpeedBurning
--     (Q_8_8(3)); with the stick released he keeps running the way he
--     faces; no items, no roll, no lifting.  linkFire.c type 1: timer $F0;
--     each new button press counts; > 30 presses, PL_FROZEN / CAPTURED /
--     IN_MINECART, or $F0 frames -> PL_BURNING off and the flame gone; the
--     flame is drawn over Link (x + {0, -6, 0, 6}[facing], y - 6, 5 more
--     up facing down), its animation 0 running.
-- SIMPLIFIED: the frozen Link's shake is drawn by moving his sprite, the
--   flame is drawn as an object entity following Link.
local M = {}

M.HANDLER_FIRE, M.HANDLER_FREEZE = 11, 12
local ANIM_FROZEN = 0x294
local SFX_195 = 0x195
local SPECIAL_FX, FX_ICE = 0x0F, 0x0D
local LINK_FIRE = 0x42
M.BURN_SPEED = 3 -- kWalkSpeedBurning, Q_8_8(3)
local FIRE_DX = require("src.zelda.tmc.RomTables").t("R31.FIRE_DX") -- sLinkFire_PositionOffsets

local function anyPress(input)
  for _, k in ipairs({ "a", "b", "r", "up", "down", "left", "right" }) do -- PlayerInputPressed: directions, A, B, R
    if input.pressed and input.pressed(k) then return true end
  end
  return false
end

-- Enemies:update, Link touched with matrix handler 11 / 12: true = handled
-- (the default touch damage is skipped)
function M.contact(E, e, handler)
  local f = E.field
  local p = f.player
  if handler ~= M.HANDLER_FIRE and handler ~= M.HANDLER_FREEZE then return false end
  if p.minish or p.inCart or p.state == "dead" then return false end
  local busy = p.state ~= "normal" and p.state ~= "hurt"
  if handler == M.HANDLER_FREEZE then
    if not busy and not p.frozen31 then
      if (f.save.stats.health or 0) <= 4 then return false end -- the hit kills: the normal touch (death)
      f:modStat("health", -4)
      M.freeze(f, p)
    end
    E:knock(e, p.x, p.y, 640 / 16, 12)
    return true
  end
  -- CollisionFire
  if not busy and not p.burn31 and not p.frozen31 then M.burn(f, p, e) end
  if p:hurt(4, e.x, e.y) then
    p.invuln = 30
    p.timer = 12
    local ks = 384 / 256
    local dx, dy = p.x - e.x, p.y - e.y
    local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    p.kbx, p.kby = dx / d * ks, dy / d * ks
  end
  return true
end

function M.freeze(f, p)
  if p.carried then f:objects():dropCarried(p) end
  p.frozen31 = { timer = 120 }
  p.burn31 = nil
  p.state = "normal"
  p.invuln = 0
  p:setAnim(ANIM_FROZEN, true)
  f:sound(SFX_195)
end

local function breakOut(f, p)
  p.frozen31 = nil
  p.drawDX31 = nil
  p.invuln = 160
  f:addFx(p.x, p.y, SPECIAL_FX, FX_ICE)
  p.state = "normal"
  p.animId = -1
end

local function frozenFrame(p, input)
  local f = p.field
  local fr = p.frozen31
  p.invuln = 3 -- COLLISION_OFF (3: the blink of Player:draw stays off)
  if (p.z or 0) > 0 then
    p.zv = (p.zv or 0) - 0.125
    p.z = math.max(0, p.z + p.zv)
  end
  if anyPress(input) then fr.timer = fr.timer - 3; p.drawDX31 = 2 else p.drawDX31 = nil end
  fr.timer = fr.timer - 1
  if fr.timer <= 0 then breakOut(f, p) end
  return true
end

function M.burn(f, p, e)
  p.burn31 = { left = 0xF0, presses = 0 }
  -- Link turns toward the fire (Direction8ToAnimationState(DirectionTurnAround))
  local dx, dy = e.x - p.x, e.y - p.y
  if math.abs(dx) > math.abs(dy) then p.animationState = dx > 0 and 2 or 6 else p.animationState = dy > 0 and 4 or 0 end
  local d = f:objects():def(LINK_FIRE, 1)
  if d then
    local fe = { kind = 6, id = LINK_FIRE, form = 1, x = p.x, y = p.y - 6, z = 0, animationState = 0, field82 = 0, interactType = 0,
                 anim = require("src.zelda.tmc.Anim").new(), literalAnim = true, objAnim = 0, linkFire31 = true, layer = p.layer }
    f:objects():dress(fe, d, 0)
    fe.objAnim = 0
    f.entities[#f.entities + 1] = fe
    p.burn31.fire = fe
  end
end

local function endBurn(p)
  local b = p.burn31
  p.burn31 = nil
  if b and b.fire then b.fire.deleted = true end
end
M.endBurn = endBurn

local function placeFire(p)
  local fe = p.burn31 and p.burn31.fire
  if not fe then return end
  local s = p.animationState or 4
  fe.x = p.x + (FIRE_DX[s] or 0)
  fe.y = p.y - 6 - (s == 4 and 5 or 0)
  fe.z = p.z or 0
  fe.layer = p.layer
  if fe.anim and fe.anim.update then fe.anim:update(1) end
end

local function burnFrame(p, input)
  local f = p.field
  local b = p.burn31
  b.left = b.left - 1
  if anyPress(input) then b.presses = b.presses + 1 end
  if b.presses > 30 or b.left <= 0 or p.inCart then endBurn(p) return false end
  if p.state ~= "normal" then placeFire(p) return false end
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  if dx == 0 and dy == 0 and not require("src.zelda.tmc.Fire68").iceHold(p) then -- round 68: no burning run on the ice
    local s = p.animationState or 4
    dx, dy = (s == 2 and 1) or (s == 6 and -1) or 0, (s == 0 and -1) or (s == 4 and 1) or 0
  end
  local x0, y0 = p.x, p.y
  p:walk(dx, dy, M.BURN_SPEED, p:animFor("walk"), p:animFor("idle"))
  p.anim:update(1)
  if p.x ~= x0 or p.y ~= y0 then require("src.zelda.tmc.Layers").update(f, p) end
  placeFire(p)
  return true
end

-- R27B.playerFrame (top of Player:update): true = this module ran the frame
function M.playerFrame(p, input)
  if p.frozen31 then
    if p.state == "dead" then p.frozen31, p.drawDX31 = nil, nil return false end
    return frozenFrame(p, input)
  end
  if p.burn31 then
    if p.state == "dead" or p.minish then endBurn(p) return false end
    return burnFrame(p, input)
  end
  return false
end

-- the steam overlay (Steam31.lua): R26 / R27B.spawnManager, R27B.frame,
-- Field:drawWorld
function M.spawnManager(d, m)
  if m.id == 0x14 then return require("src.zelda.tmc.Steam31").spawn(d.field, m) end
  return nil
end
function M.frame(f)
  require("src.zelda.tmc.Steam31").frame(f)
  return false
end
function M.drawWorld(f)
  if f.steam31 then require("src.zelda.tmc.Steam31").draw(f) end
end

return M
