-- Round 12: pulling a PUSHABLE_STATUE (pushableStatue.c registers itself as
-- a carry entity, carryFlags 1: R grabs it, ITEM_TRY_PICKUP_OBJECT).
--
-- CARTRIDGE BEHAVIOUR (ported from itemTryPickupObject.c / pushableStatue.c):
--   * R facing the statue (in front, close) grabs it: ANIM_GRAB.
--   * Holding R and the direction away from it plays ANIM_PULL
--     (PL_STATE_PULL); on a keyframe with flag bit 1 (frame & 2, as the
--     lever's pull reads it) the statue starts
--     sliding one tile toward Link (pushableStatue's move: speed $80 for
--     $20 frames, SFX_10F) when the tile behind Link is free; Link backs
--     off with it.
--   * Letting go of R ends the grab.
-- SIMPLIFIED: the hold item's own sub-states (PlayerTryDropObject, the
-- iframes check) are not modelled.
local bit = require("bit")
local band = bit.band

local SP = {}
local ANIM_GRAB, ANIM_PULL, ANIM_PULL_NOCAP = 0x378, 0x340, 0x944
local SFX_10F = 0x10F
local KEY = { [0] = "up", [2] = "right", [4] = "down", [6] = "left" }
local AWAY = { [0] = "down", [2] = "left", [4] = "up", [6] = "right" }
local DV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }

local function endHold(p)
  p.state = "normal"
  p.extUpdate = nil
  p.holdStatue = nil
  p:setAnim(p:animFor("idle"), true)
end

local function hold(p, input)
  local e = p.holdStatue
  local f = p.field
  local d = f._dungeon
  if e.moving then
    -- Link backs off with it
    p:moveBy(-DV[p.animationState][1] * 0.5, -DV[p.animationState][2] * 0.5)
    p.anim:update(1)
    return
  end
  if not e or e.deleted or not input.down("r") then return endHold(p) end
  local s = p.animationState
  if input.down(AWAY[s]) then
    p:setAnim(p.hasCap and ANIM_PULL or ANIM_PULL_NOCAP)
    p.anim:update(1)
    if band(p.anim.flags or 0, 2) ~= 0 then
      local v = DV[s]
      -- the tile behind Link must be free for him, and the statue's way is his
      local bx, by = p.x - v[1] * 16, p.y - v[2] * 16
      if not p:blocked(bx, by) then
        d:block(e.tx, e.ty, e.layer, false)
        local r11 = f.assets.manifest.r11
        e.mdx, e.mdy, e.moving = -v[1], -v[2], (r11 and r11.statueHitbox) and 32 or 16
        f:sound(SFX_10F)
      end
    end
  else
    p:setAnim(ANIM_GRAB)
  end
end

-- each frame from Dungeon:updateStatue (not while it moves)
function SP.update(d, e, input)
  local f = d.field
  local p = f.player
  if p.holdStatue == e then return true end
  if p.state ~= "normal" or p.minish or not input.pressed("r") then return false end
  local fx, fy = p:frontPoint(8)
  if math.floor(fx / 16) ~= e.tx or math.floor(fy / 16) ~= e.ty then return false end
  p.state = "ext"
  p.extUpdate = hold
  p.holdStatue = e
  p:setAnim(ANIM_GRAB, true)
  return true
end

return SP
