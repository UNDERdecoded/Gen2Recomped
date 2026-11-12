-- Round 26 (team A): PEGASUS BOOTS ($15): src/item/itemPegasusBoots.c
-- (ItemPegasusBoots, sub_080768F8, sub_08076964, sub_08076A88), the dash
-- attack's src/playerItem/playerItemDashSword.c (PlayerItemDashSword_Init /
-- _Action1, sub_0801B938) and src/player.c PlayerBounce (PlayerBounceInit,
-- PlayerBounceUpdate, sub_08070E7C).
--
--   sub_080768F8 (use): not jumping / holding / gusting / in a cart:
--     dash_state 1, timer $10 (Minish: ANIM_DASH_CHARGE_MINISH $C14),
--     the item animation = gItemDefinitions[$15].frameIndex = ANIM_WALK.
--   ItemPegasusBoots (each frame): timer - 1; every 8 frames SFX_PLY_LAND
--     ($7D) and (not Minish) FX_DASH under Link (y + 2, the charge jitters
--     it +-3 / +-7).
--   sub_08076964 (the charge): the button held, on the ground: the walk
--     animation runs at double speed (UpdateItemAnim twice; Minish once),
--     dash_state + 1; at $1E: dash_state $40, stateID 2, and with a sword
--     on A / B and ITEM_SKILL_DASH_ATTACK ($4A): ANIM_DASH ($298) + the
--     DASH_SWORD; else ANIM_WALK (Minish ANIM_DASH_MINISH $C10).
--   sub_08076A88 (the dash): speed $300 (Minish $280); blocked straight
--     ahead (gUnk_0800275C's collision bits for the facing): the first
--     frame only marks it (subtimer 1), the second -> PLAYER_BOUNCE; the
--     pad pressed against the run (gUnk_0811BE38) ends it; any other
--     direction turns the run one 1/32 step a frame toward the pad.
--   PlayerBounce: direction = the facing turned round, speed Q_8_8(1.0),
--     zVelocity Q_16_16(2.0) (Minish 3/4), ANIM_BOUNCE ($114; no cap $418,
--     Minish $C18), screen shake 16, SFX_14C; gravity kGravityRate; on the
--     ground: timer (field_0x38 = 0) out -> ANIM_DEFAULT for 8 frames ->
--     normal.
--   DASH_SWORD: frame = Link's frameIndex + $2E while his animation is
--     ANIM_DASH ($98..$9B), hitbox gUnk_080B7850 by facing, tile probe
--     gUnk_080B7848 (DoTileInteractionOffset filter 1 with Rock Breaker,
--     else 0).
-- SIMPLIFIED: the blade hits with the plain sword hurtType (4); the swamp
--   splash (FX_GREEN_SPLASH) is not drawn; the gUnk_0811BE38 "against the
--   run" keys are the opposite d-pad direction (its .bin is not in the
--   decomp's C source); FX_DASH puffs go through f:addFx when present.
local bit = require("bit")
local band = bit.band

local B = {}
B.ITEM = 0x15
B.SKILL_DASH = 0x4A
B.SKILL_ROCK = 0x4B
B.CHARGE = 0x1E
B.SPEED, B.SPEED_MINISH = 0x300 / 256, 0x280 / 256
B.ANIM_WALK, B.ANIM_DASH = 0x104, 0x298
B.ANIM_DASH_MINISH, B.ANIM_CHARGE_MINISH = 0xC10, 0xC14
B.ANIM_BOUNCE, B.ANIM_BOUNCE_NOCAP, B.ANIM_BOUNCE_MINISH = 0x114, 0x418, 0xC18
B.SFX_LAND, B.SFX_BOUNCE = 0x7D, 0x14C
B.PROBE = { [0] = { 0, -15 }, { 12, -3 }, { 0, 9 }, { -12, -3 } } -- gUnk_080B7848
B.HITBOX = { [0] = { 0, -18, 4, 8 }, { 16, 0, 8, 4 }, { 2, 11, 4, 8 }, { -16, 0, 8, 4 } } -- gUnk_080B7850
local SWORD_SPRITE = { [1] = 14, [2] = 15, [3] = 15, [4] = 15, [5] = 15, [6] = 16 }
local OPP = { [0] = "down", [2] = "left", [4] = "up", [6] = "right" }
local VEC = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }

local function isSword(i) return i and i >= 1 and i <= 6 end
local function dirVec(d) local a = d / 32 * 2 * math.pi return math.sin(a), -math.cos(a) end
local function padDir(input)
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  if dx == 0 and dy == 0 then return nil end
  return math.floor(math.atan2(dx, -dy) / (2 * math.pi) * 32 + 32.5) % 32
end

function B.swordItem(f)
  local a, b = f:equipped("a"), f:equipped("b")
  if isSword(a) then return a end
  if isSword(b) then return b end
  return nil
end

local function stop(p)
  p.dash = nil
  p.state = "normal"
  p.extUpdate = nil
  p.animId = -1
end

-- PlayerBounce
local function bounce(p)
  local f = p.field
  local s = p.animationState
  local v = VEC[s] or VEC[4]
  p.dash = nil
  p.bounce = { vx = -v[1] * 1.0, vy = -v[2] * 1.0, t = 0 }
  p.zv = p.minish and 1.5 or 2.0
  p.z = 0.01
  p:setAnim(p.minish and B.ANIM_BOUNCE_MINISH or (p.hasCap and B.ANIM_BOUNCE or B.ANIM_BOUNCE_NOCAP), true)
  if not p.minish then f:shake(16, 0) end
  f:sound(B.SFX_BOUNCE)
  p.extUpdate = function(pl)
    local bo = pl.bounce
    pl.anim:update(1)
    if bo.t == 0 then
      pl:moveBy(bo.vx, bo.vy)
      pl.z = pl.z + pl.zv
      pl.zv = pl.zv - 0x2000 / 0x10000
      if pl.z <= 0 then pl.z, pl.zv = 0, 0; bo.t = 8; pl.animId = -1; pl:setAnim(pl:animFor("idle"), true) end
    else
      bo.t = bo.t - 1
      if bo.t <= 0 then pl.bounce = nil; stop(pl) end
    end
  end
end

local function fx(f, p, jitter)
  if p.minish or not f.addFx then return end
  local x, y = p.x, p.y + 2
  if jitter then
    local r = math.random(0, 3); if math.random(0, 1) == 1 then r = -r end
    y = y + r
    r = math.random(0, 7); if math.random(0, 1) == 1 then r = -r end
    x = x + r
  end
  f:addFx(x, y, 0x0F, 0x10) -- FX_DASH
end

-- the blade (sub_0801B938)
local function bladeFrame(f, p)
  local d = p.dash
  if not d.sword then return end
  local s = p.animationState / 2
  local pr = B.PROBE[s]
  local filter = (f:inventory(B.SKILL_ROCK) or 0) ~= 0 and 1 or 0
  pcall(require("src.zelda.tmc.Bombs").interact, f, filter, p.x + pr[1], p.y + pr[2], p.layer)
  local hb = B.HITBOX[s]
  local box = { x = p.x + hb[1], y = p.y + hb[2], w = hb[3], h = hb[4] }
  local E = f:enemies()
  for _, e in ipairs(f.entities) do
    if e.enemy and not e.dying and not e.deleted and e.hitbox then
      local h = e.hitbox
      if math.abs((e.x + (h.x or 0)) - box.x) < (h.w or 6) + box.w and math.abs((e.y + (h.y or 0)) - box.y) < (h.h or 6) + box.h then
        E:hit(e, 4, p.x, p.y)
      end
    end
  end
  f.swordBoxNow = { x = box.x, y = box.y, w = box.w, h = box.h, t = f.frame }
end

function B.step(p, input)
  local f, d = p.field, p.dash
  if not d then return stop(p) end
  d.timer = (d.timer - 1) % 256
  if band(d.timer, 7) == 0 then
    f:sound(B.SFX_LAND)
    fx(f, p, d.stage ~= 2)
  end
  local held = input and input.down(d.button)
  if d.stage == 1 then -- sub_08076964
    if not held or (p.z or 0) ~= 0 then return stop(p) end
    p.anim:update(1)
    if not p.minish then p.anim:update(1) end
    d.state = d.state + 1
    if d.state == B.CHARGE then
      d.state, d.stage = 0x40, 2
      d.dir = p.animationState * 4
      local sw = B.swordItem(f)
      if sw and not p.minish and require("src.zelda.tmc.SwordSkills").skill(f, B.SKILL_DASH) then -- round 27A: also a skill BladeBrothers_LearnSkill gave (Story27Town2.lua)
        d.sword = sw
        p.lastSwordMove = 3 -- SWORD_MOVE_DASH
        p:setAnim(B.ANIM_DASH, true)
      elseif not p.minish then p:setAnim(B.ANIM_WALK, true)
      else p:setAnim(B.ANIM_DASH_MINISH, true) end
    end
    return
  end
  -- sub_08076A88
  if not held then return stop(p) end
  if input.down(OPP[band(p.animationState, 6)] or "down") then return stop(p) end
  local want = padDir(input)
  if want and want ~= d.dir then
    if band(want - d.dir, 31) < 16 then d.dir = d.dir + 2 end
    d.dir = band(d.dir - 1, 31)
  end
  local spd = p.minish and B.SPEED_MINISH or B.SPEED
  local vx, vy = dirVec(d.dir)
  local x0, y0 = p.x, p.y
  -- blocked straight ahead
  local v = VEC[band(p.animationState, 6)]
  if p:blocked(p.x + v[1] * spd, p.y + v[2] * spd) then
    if d.bump then return bounce(p) end
    d.bump = true
    return
  end
  p:moveBy(vx * spd, vy * spd)
  p.anim:update(1)
  bladeFrame(f, p)
  require("src.zelda.tmc.Ledge").check(p, vx, vy)
  if p.x ~= x0 or p.y ~= y0 then require("src.zelda.tmc.Layers").update(f, p) end
end

function B.use(p, item, button, input)
  if item ~= B.ITEM then return nil end
  if p.state ~= "normal" or p.carried or p.inCart or (p.z or 0) ~= 0 then return nil end
  local f = p.field
  p.dash = { stage = 1, state = 2, timer = 0x10, button = button } -- dash_state 1, and sub_080768F8 runs sub_08076964 at once (+1)
  p.state = "ext"
  if p.minish then p:setAnim(B.ANIM_CHARGE_MINISH, true) else p:setAnim(B.ANIM_WALK, true) end
  p.extUpdate = function(pl, inp) B.step(pl, inp) end
  return true
end

function B.frame(p)
  if (p.dash or p.bounce) and p.state ~= "ext" then
    if p.bounce then p.z, p.zv = 0, 0 end -- a room change cut the bounce short (enterRoom keeps z)
    p.dash, p.bounce = nil, nil
  end
  return nil
end

-- the DASH_SWORD blade: Link's frameIndex + $2E while ANIM_DASH plays
function B.draw(p, x, y)
  local d = p.dash
  if not (d and d.sword and d.stage == 2) or p.state ~= "ext" then return nil end
  local lo = band(p.animId or 0, 0xFF)
  if band(lo + 0x68, 0xFF) >= 4 then return nil end
  local A = p.field.assets
  local img, ox, oy = A:spriteFrame(SWORD_SPRITE[d.sword] or 15, (p.anim.frame or 0) + 0x2E, A:objPalette(1), "sword")
  if not img then return nil end
  local flip = p.entFlip or false
  if band(p.animationState or 0, 2) ~= 0 then flip = not flip end
  if flip then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
  return nil
end

return B
