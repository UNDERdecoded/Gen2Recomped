-- Round 29: lifting, carrying and throwing a pot (or another plain liftable
-- object), as the cartridge does it.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * src/object/pot.c Pot_Init: y += 3, InitializeAnimation(5) (sprite 167
--     frame 5: two mirrored 8x16 halves at spriteVramOffset 240).  The port
--     drew animation 0 (a 16x16 piece of the same tiles: a scroll and a box,
--     not a pot) on the ground, over Link's head and in the air.
--   * src/item/itemTryPickupObject.c sub_08076088 / sub_08076488: ANIM_PICKUP
--     runs to its end (playerFrame & $80) before Link may walk or throw
--     (PL_STATE_HOLD); sub_08076518: R / A / B (INPUT_LIFT_THROW | CANCEL |
--     INTERACT) -> ANIM_THROW, the held object's subAction 2.
--   * src/playerUtils.c sub_08078D60 (UpdateCarriedObject): the carried
--     object sits at Link's x + gUnk_0811C0E8[carryFlags >> 4][frame],
--     z = Link's z + spriteOffsetY + table[frame + 1], y = Link's y, where
--     frame = gPlayerEntity.frame & $7F (the animation keyframe's flags byte),
--     x mirrored while Link's spriteSettings.flipX (facing left).
--   * src/playerItem/playerItemHeldObject.c: SubAction2 waits for Link's
--     frame & 1 (ANIM_THROW's third keyframe), then sub_080AD27C: speed
--     gUnk_081320CC[carryFlags >> 4] ($400 = 4 px a frame for a pot),
--     zVelocity gUnk_081320D4 (0), z = the object's z + 8; every frame
--     ProcessMovement10 (walls stop it, they do not break it) and
--     GravityUpdate(Q_8_8(32)) = 1/8 px per frame^2; on landing the act tile
--     picks FX_FALL_DOWN (13), FX_WATER_SPLASH (16/17), FX_GREEN_SPLASH (19),
--     FX_LAVA_SPLASH (90) and no shards, else the pot breaks (BreakPot via
--     Pot_Action2 sub_0808259C).
local bit = require("bit")
local band = bit.band

local M = {}

M.POT = 0x05
M.POT_ANIM = 5 -- Pot_Init: InitializeAnimation(super, 5)

-- gUnk_0811C0B8 / C0D8 / C0B8 / C0C8 ({x, z} at [frame], [frame + 1])
local T0 = require("src.zelda.tmc.RomTables").t("PotCarry.T0")
local T1 = require("src.zelda.tmc.RomTables").t("PotCarry.T1")
local T3 = require("src.zelda.tmc.RomTables").t("PotCarry.T3")
M.CARRY_POS = { [0] = T0, T1, T0, T3 }
local THROW_SPEED_Q8 = require("src.zelda.tmc.RomTables").t("PotCarry.THROW_SPEED") -- gUnk_081320CC (Q8.8)
local THROW_ZV_Q16 = require("src.zelda.tmc.RomTables").t("PotCarry.THROW_ZV")     -- gUnk_081320D4 (Q16.16)
M.THROW_SPEED = setmetatable({}, { __index = function(_, k) local v = THROW_SPEED_Q8[k] return v and v / 256 end })
M.THROW_ZV = setmetatable({}, { __index = function(_, k) local v = THROW_ZV_Q16[k] return v and v / 65536 end })
M.GRAVITY = 32 / 256                      -- Q_8_8(32.0)
M.ACT_FX = { [13] = 0x00, [16] = 0x0B, [17] = 0x0B, [19] = 0x52, [90] = 0x0C }

-- a plain carried object (not a bomb, not an entity carried by its own hook)
function M.plain(c) return c and not c.bomb and not c.hook end

-- sub_08078D60: {dx, dz} (dz < 0 = up) for Link's current keyframe
function M.offset(p, c)
  local t = M.CARRY_POS[band(c and c.carryFlags or 0, 0xF0) / 16] or T0
  local fr = band(p.anim and p.anim.flags or 0, 0x7F)
  local dx, dz = t[fr] or 0, t[fr + 1] or 0
  if p.entFlip then dx = -dx end
  return dx, dz + (p.spriteOY or 0)
end

-- the carry state before Link's walking; true = the frame is handled
function M.carryFrame(p, input, locked)
  local c = p.carried
  if not M.plain(c) then p.liftPhase = nil return false end
  if p.liftPhase then
    -- sub_08076488: ANIM_PICKUP plays out, Link stands still
    p.anim:update(1)
    if p.anim.done then p.liftPhase = nil end
    return true
  end
  if not locked and (input.pressed("r") or input.pressed("a") or input.pressed("b")) then
    -- sub_08076518: ANIM_THROW; the object leaves on the keyframe with frame & 1
    local dx, dz = M.offset(p, c)
    c.throwing, c.throwDx, c.throwDz = true, dx, dz
    p.throwR29 = true
    p.state = "throw"
    p.timer = 60
    p:setAnim(0x344, true) -- ANIM_THROW (the port's Player.ANIM.throw)
    return true
  end
  return false
end

-- the throw state; true = handled
function M.throwFrame(p)
  if not p.throwR29 then return false end
  local c = p.carried
  p.anim:update(1)
  if M.plain(c) and c.throwing and band(p.anim.flags or 0, 1) ~= 0 then M.release(p.field, p) end
  -- sub_080765E0: the throw ends with the animation
  p.timer = (p.timer or 1) - 1
  if (p.anim.done and not p.carried) or p.timer <= 0 then
    if p.carried and p.carried.throwing then M.release(p.field, p) end
    p.throwR29, p.state = nil, "normal"
  end
  return true
end

function M.release(f, p)
  local c = p.carried
  p.carried = nil
  if not c then return end
  local O = f:objects()
  local s = p.animationState or 4
  local sp = M.THROW_SPEED[band(c.carryFlags or 0, 0xF0) / 16] or 4
  local vx = (s == 2 and 1 or s == 6 and -1 or 0) * sp
  local vy = (s == 4 and 1 or s == 0 and -1 or 0) * sp
  local id = c.obj or M.POT
  local e = { kind = 6, id = id, form = c.form, x = p.x, y = p.y,
              z = math.max(0, -((c.throwDz or -16) + 8)), zv = M.THROW_ZV[band(c.carryFlags or 0, 0xF0) / 16] or 0,
              grav = M.GRAVITY, vx = vx, vy = vy, thrown = true, r29 = true, layer = p.layer or 1,
              animationState = 0, field82 = 0, interactType = 0, anim = require("src.zelda.tmc.Anim").new(),
              potParam = c.potParam, potType2 = c.potType2, potFlag = c.potFlag } -- round 30: + type2 / flag (Pot30.lua)
  if c.def then O:dress(e, c.def, c.form or 0) end
  if id == M.POT then e.objAnim = M.POT_ANIM end
  f.entities[#f.entities + 1] = e
  f:sound(0x7C)
end

-- PlayerItemHeldObject_SubAction2 for a released object; true = handled
function M.updateThrown(O, e)
  if not e.r29 then return false end
  local f = O.field
  local r = f.room
  local L = e.layer or 1
  local nx, ny = e.x + (e.vx or 0), e.y + (e.vy or 0)
  -- ProcessMovement10 with the held object's box (gUnk_081320E4: 4 x 4)
  local function solid(x, y)
    return r:isSolid(x - 3, y - 3, L) or r:isSolid(x + 3, y - 3, L) or r:isSolid(x - 3, y + 3, L) or r:isSolid(x + 3, y + 3, L)
  end
  if (e.vx ~= 0 or e.vy ~= 0) then
    if solid(nx, ny) then e.vx, e.vy = 0, 0 else e.x, e.y = nx, ny end
  end
  e.z = e.z + e.zv
  e.zv = e.zv - e.grav
  local landed = e.z <= 0
  if not landed and f:enemies():hitByObject(e) then landed = true end -- CONTACT_NOW: z = 0
  if not landed then return true end
  e.z = 0
  e.deleted = true
  local tt = r:tileType(L, math.floor(e.x / 16), math.floor(e.y / 16))
  local act = tt and tt < 0x4000 and f.assets.actTile and f.assets.actTile[tt] or nil
  local fx = act and M.ACT_FX[act]
  if fx then
    if f.addFx then f:addFx(e.x, e.y, 0x0F, fx) end
    return true
  end
  O:breakThrown(e)
  return true
end

-- Objects:drawCarried: where the carried object is drawn (x, y = Link's
-- drawn position, his z already applied)
function M.drawPos(p, c, x, y)
  local dx, dz = M.offset(p, c)
  if c.throwing then dx, dz = c.throwDx or dx, c.throwDz or dz end
  return x + dx, y + dz
end

return M
