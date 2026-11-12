-- Round 16: WARP_POINT ($34) types 0 and 1, the blue dungeon warps
-- (src/object/warpPoint.c), and type 2 (after the boss: TRANSITION_FADE_WHITE_SLOW)
-- when its data names the way out.
--
-- CARTRIDGE BEHAVIOUR:
--   * Init: palette gUnk_08121380[type]; active (sub_0808B830: Action3 and
--     a second WARP_POINT drawn over it, flickering by Link's distance:
--     drawn within $28 px, every other frame within $2E) when its flags
--     ($86) are set or, in a dungeon, IsDungeonWarpActive(type).  Link
--     standing on it at Init (sub_0808B7C8: not Minish, z 0, within 5x5)
--     means he just arrived: Action4 spins him for 96 frames (SFX_112,
--     SFX_114 at $58), then Action3 with timer 1 so he must step off first.
--   * Action1 (inactive): its flags set -> active, EnableDungeonWarp(type),
--     60 frames of blinking (Action2), SFX_112.
--   * Action3: Link on it (timer 0) -> Action5: put away items, Link on its
--     centre facing down, SFX_113, 96 frames of spinning (faster as it
--     goes), then the warp to area unk_7c / room unk_7d (EntityData paramB
--     bytes 0, 1) at tile unk_84 (paramC low: x = (v & $3F) * 16 + 8,
--     y = ((v & $FC0) >> 2) + 8), facing down.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local W = {}
local SFX_112, SFX_113, SFX_114 = 0x112, 0x113, 0x114

local function onIt(e, p)
  return not p.minish and p.state ~= "dead" and (p.z or 0) == 0 and math.abs(p.x - e.x) <= 5 and math.abs(p.y - e.y) <= 5
end

local function warpBits(d)
  local st = d:state()
  st.warps = st.warps or 0
  return st
end

function W.init(d, e)
  local data = e.data or {}
  e.type = e.form or 0
  e.toArea = band(data.paramB or 0, 0xFF)
  e.toRoom = band(rshift(data.paramB or 0, 8), 0xFF)
  local v = band(data.paramC or 0, 0xFFFF)
  e.toX, e.toY = band(v, 0x3F) * 16 + 8, rshift(band(v, 0xFC0), 2) + 8
  e.wflags = rshift(data.paramC or 0, 16)
  e.spritePriority = 6
  local st = warpBits(d)
  local active = d:check(e.wflags) or band(st.warps, bit.lshift(1, e.type)) ~= 0
  e.waction = active and 3 or 1
  e.hidden = not active
  e.wtimer = 0
  local p = d.field.player
  if active and p and onIt(e, p) then
    e.waction, e.wsub = 4, 96
    p.x, p.y, p.animationState = e.x, e.y, 4
    d.field:sound(SFX_112)
    p.state, p.extUpdate = "ext", function(pl) pl.anim:update(1) end
  end
end

-- the spin's turn (Action4 / Action5 switch on subtimer & $60)
local function spinTurn(t, arriving, p)
  local m = band(t, 0x60)
  if arriving then
    if m == 0x40 then return band(t, 1) == 0
    elseif m == 0x20 then return band(t, 3) == 0
    elseif m == 0 then return band(t, 7) == 0 and (p.animationState ~= 4 or t > 0x18) end
  else
    if m == 0x40 then return band(t, 7) == 0
    elseif m == 0x20 then return band(t, 3) == 0
    elseif m == 0 then return t > 0x10 and band(t, 1) == 0 end
  end
  return false
end

function W.update(d, e)
  local f = d.field
  local p = f.player
  local a = e.waction
  if a == 1 then
    if d:check(e.wflags) then
      local st = warpBits(d)
      st.warps = bit.bor(st.warps, bit.lshift(1, e.type)) -- EnableDungeonWarp
      e.waction, e.wsub = 2, 60
      f:sound(SFX_112)
    end
  elseif a == 2 then
    e.wsub = e.wsub - 1
    if e.wsub <= 0 then e.waction, e.hidden = 3, false
    else e.hidden = band(e.wsub, 2) ~= 0 end
  elseif a == 3 then
    -- the flicker of the copy over it: drawn within $28, every other frame to $2E
    local dx, dy = p.x - e.x, p.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    e.glow = dist <= 0x28 or (dist <= 0x2E and not e.glow)
    if onIt(e, p) and p.state == "normal" then
      if e.wtimer ~= 0 then return end
      e.waction, e.wsub = 5, 96
      p.jar = nil
      p.x, p.y, p.animationState = e.x, e.y, 4
      p.state, p.extUpdate = "ext", function(pl) pl.anim:update(1) end
      p:setAnim(p:animFor("idle"), true)
      f:sound(SFX_113)
    elseif not onIt(e, p) then
      e.wtimer = 0
    end
  elseif a == 4 then
    e.wsub = e.wsub - 1
    if e.wsub == 0x58 then f:sound(SFX_114) end
    if e.wsub <= 0 then
      e.waction, e.wtimer = 3, 1
      p.animationState = 4
      p.state, p.extUpdate = "normal", nil
      p.animId = -1
      return
    end
    if spinTurn(e.wsub, true, p) then p.animationState = band(p.animationState + 2, 6); p:setAnim(p:animFor("idle"), true) end
  elseif a == 5 then
    e.wsub = e.wsub - 1
    if e.wsub <= 0 then
      e.waction = 6
      p.state, p.extUpdate = "normal", nil
      f:startTransition({ warpType = 1, area = e.toArea, room = e.toRoom, endX = e.toX, endY = e.toY, facing = 4, kind = 0, layer = 0 })
      if e.type == 2 and f.transition then f.transition.white = true end
      return
    end
    if spinTurn(e.wsub, false, p) then p.animationState = band(p.animationState + 2, 6); p:setAnim(p:animFor("idle"), true) end
  end
end

return W
