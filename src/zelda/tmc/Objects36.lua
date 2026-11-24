-- Round 36: PRESSURE_PLATE $24 (src/object/pressurePlate.c).  The round 34
-- survey found its one room ($47:02, type 2: Link and three Four Sword
-- clones open the locked door, flag $B1) with the plate drawn as nothing.
-- In R34.MODULES (spawnObject); runs from Dungeon:update (extUpdate).
--
-- CARTRIDGE BEHAVIOUR:
--   * Init: action 1, drawn, spritePriority 7, hitbox gUnk_080FD1D4,
--     dir = animationState (0).
--   * weight = the puzzle entities within 16 px of its top-left corner
--     (x - 8, y - 8, gRoomVars.puzzleEntities[0..7]) + Link colliding
--     (IsCollidingPlayer) + each Four Sword clone colliding; every one of
--     them gets spriteOffsetY = sSpriteOffsets[dir].
--   * Action1: weight >= type + 2 -> action 2, animation 4, SetFlag(flag),
--     SFX_PRESSURE_PLATE; else a heavier weight -> animation weight (weight +
--     1 for 4 frames when it is type + 1, then dir = that animation),
--     SFX_BUTTON_PRESS; a lighter one -> animation weight.
--   * Action2 (canToggle, paramC low half): weight < type + 2 -> action 1,
--     ClearFlag(flag).
-- The flag is paramC's high half (+$86), canToggle its low half (+$70).
local bit = require("bit")
local band = bit.band

local M = {}
M.PRESSURE_PLATE = 0x24
M.SFX = { PRESSURE_PLATE = 0x16B, BUTTON_PRESS = 0x10C }
local SPRITE_OFF = require("src.zelda.tmc.RomTables").t("Objects36.PLATE_SPRITE_OFF") -- sSpriteOffsets
local PLATE_HB = require("src.zelda.tmc.RomTables").t("Objects36.PLATE_HB")           -- gUnk_080FD1D4
M.SPRITE_OFF, M.PLATE_HB = SPRITE_OFF, PLATE_HB

local function setAnim(f, e, n)
  e.objAnim, e.animIndex = n, n
  if e.anim and e.sprite then e.anim:set(f.assets:sprite(e.sprite), n, true) end
end

-- IsCollidingPlayer / IsColliding(plate, clone): Link's hitbox against the plate's
local function touches(f, who, e)
  local HB = require("src.zelda.tmc.Hitboxes")
  local t = HB.touches(f, who, e)
  if t == nil then
    local hb = e.hitbox
    t = math.abs(math.floor(who.x) - math.floor(e.x) - hb.x) <= hb.w + 6
        and math.abs(math.floor(who.y) - 3 - math.floor(e.y) - hb.y) <= hb.h + 6
  end
  return t
end

local function standOn(f, who, off)
  who.spriteOY, who.spriteOYFrame = off, f.frame
end

-- sub_08088938 + get_standing_count
function M.weight(f, e)
  local n = 0
  local off = SPRITE_OFF[e.dir or 0] or 0
  local x0, y0 = math.floor(e.x) - 8, math.floor(e.y) - 8
  for i = 0, 7 do
    local o = f.r27puzzle and f.r27puzzle[i]
    if o and not o.deleted and math.floor(o.x) - x0 >= 0 and math.floor(o.x) - x0 < 0x11
       and math.floor(o.y) - y0 >= 0 and math.floor(o.y) - y0 < 0x11 then
      standOn(f, o, off)
      n = n + 1
    end
  end
  local p = f.player
  if p and p.state ~= "dead" and touches(f, p, e) then
    standOn(f, p, off)
    n = n + 1
  end
  local clones = rawget(f, "playerClones")
  if type(clones) == "table" then
    for _, c in ipairs(clones) do
      if not c.deleted and touches(f, { x = c.x, y = c.y, layer = c.layer, minish = false }, e) then
        standOn(f, c, off)
        n = n + 1
      end
    end
  end
  return n
end

function M.update(d, e)
  local f = d.field
  if (e.subtimer or 0) > 0 then
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then
      e.dir = e.animationState
      setAnim(f, e, e.animationState)
    end
  end
  local t = e.form or 0
  if e.action == 1 then
    local w = M.weight(f, e)
    if t + 2 <= w then
      e.action, e.subtimer, e.animationState, e.z = 2, 0, 4, 0
      setAnim(f, e, 4)
      d:set(e.flag, true)
      f:sound(M.SFX.PRESSURE_PLATE)
    else
      if w > e.animationState then
        if t + 1 == w then
          e.subtimer = 4
          setAnim(f, e, w + 1)
        else
          setAnim(f, e, w)
        end
        f:sound(M.SFX.BUTTON_PRESS)
      elseif w < e.animationState then
        setAnim(f, e, w)
      end
      e.animationState = w
    end
  elseif e.action == 2 and (e.canToggle or 0) ~= 0 then
    local w = M.weight(f, e)
    if t + 2 > w then
      e.action, e.animationState = 1, w
      d:set(e.flag, false)
      setAnim(f, e, w)
    end
  end
end

function M.spawnObject(d, e)
  if e.id ~= M.PRESSURE_PLATE then return nil end
  local f = d.field
  local O = f:objects()
  local def = O and O:def(e.id, e.form or 0)
  if def then O:dress(e, def, 0) end
  e.action, e.spritePriority, e.subtimer = 1, 7, 0
  e.hitbox = { x = PLATE_HB.x, y = PLATE_HB.y, w = PLATE_HB.w, h = PLATE_HB.h }
  e.animationState = e.animationState or 0
  e.dir = e.animationState
  e.canToggle = e.flags or 0 -- paramC low half (+$70)
  setAnim(f, e, 0)
  e.extUpdate = function(dd, me) M.update(dd, me) end
  d:track(e)
  return e
end

return M
