-- Round 11: PULLABLE_LEVER ($54).
--
-- CARTRIDGE BEHAVIOUR (src/object/pullableLever.c):
--   * The handle (part 0) starts at its spot plus
--     PullableLever_InitialOffsets[type2] and registers as a carry entity;
--     Link grabs it with R while he faces the lever's side (animationState
--     >> 1 == type2), and is placed at gUnk_081222B8[type2] from it.
--   * Pulling (PL_STATE_PULL, the pull animation's frame flag): Link backs
--     off along gUnk_081222C0[type2] at the handle's speed $60
--     (sub_080044AE), the handle follows him, pullLength = how far it is
--     out; SFX_10F every 16 frames.  When pullLength reaches the required
--     length (paramB >> 16) SFX_BUTTON_PRESS plays and its flag (paramC >>
--     16) is set.
--   * Let go, the handle slides back at $60 toward the wall
--     (HandleAction1); back at 0 the flag is cleared again.
--   * The middle part (part 1) shows the pulled-out chain: hidden under 8 px,
--     then animation (length - 8) >> 4) * 4 + type2 + 8; the socket (part 2)
--     animation type2 + 4.
-- All small tables (the offsets, the pull directions, the hitboxes) are read
-- from the ROM (ExtractR11.lua, manifest.r11.lever).
-- Round 12: the pull steps only on frames where Link's ANIM_PULL keyframe
-- has flag bit 1 (pullableLever.c: PL_STATE_PULL and gPlayerEntity.frame &
-- 2); it used to step every frame the way was held.
local bit = require("bit")
local band = bit.band

local L = {}
local OBJ = 0x54
local SFX_10F, SFX_BUTTON, SFX_19E = 0x10F, 0x10C, 0x19E
local ANIM_GRAB, ANIM_PULL, ANIM_PULL_NOCAP = 0x378, 0x340, 0x944
local KEY = { [0] = "up", [8] = "right", [16] = "down", [24] = "left" }

local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end

local function tables(f)
  local r = f.assets.manifest.r11
  return r and r.lever
end

local function length(e)
  local t = e.type2
  if t == 0 then return math.floor(e.y) - e.iy elseif t == 1 then return e.ix - math.floor(e.x)
  elseif t == 2 then return e.iy - math.floor(e.y) else return math.floor(e.x) - e.ix end
end

local function setFlag(d, e, on)
  if e.pflag and e.pflag ~= 0 then d:set(e.pflag, on) end
end

local function endHold(p)
  p.state = "normal"
  p.extUpdate = nil
  p.holdLever = nil
  p:setAnim(p:animFor("idle"), true)
end

local function hold(p, input)
  local e = p.holdLever
  local f = p.field
  if not e or e.deleted or not input.down("r") then return endHold(p) end
  local dir = e.pullDir
  if input.down(KEY[dir]) then
    p:setAnim(p.hasCap and ANIM_PULL or ANIM_PULL_NOCAP)
    p.anim:update(1)
    if e.len < e.need and band(p.anim.flags or 0, 2) ~= 0 then
      local px, py = p.x, p.y
      local a = (dir * 8) % 256
      p:moveBy(SIN[a] * 0x60 / 65536, -SIN[(a + 64) % 256] * 0x60 / 65536)
      local diff
      if e.type2 == 0 then diff = p.y - py elseif e.type2 == 1 then diff = px - p.x
      elseif e.type2 == 2 then diff = py - p.y else diff = p.x - px end
      if diff ~= 0 then
        e.x = e.x + SIN[a] * diff / 256
        e.y = e.y - SIN[(a + 64) % 256] * diff / 256
        e.len = length(e)
        if e.len >= e.need then
          f:sound(SFX_BUTTON)
          setFlag(f._dungeon, e, true)
        else
          e.sndT = (e.sndT or 2) - 1
          if e.sndT <= 0 then e.sndT = 16; f:sound(SFX_10F) end
        end
        if not e.clicked then e.clicked = true; f:sound(SFX_19E) end
      end
    end
  else
    p:setAnim(ANIM_GRAB)
  end
end

local function update(d, e, input)
  local f = d.field
  local p = f.player
  if p.holdLever == e then return end
  e.clicked = nil
  -- HandleAction1: back toward the wall at $60
  if e.len > 0 then
    local a = (e.type2 * 8 * 8) % 256
    e.x = e.x + SIN[a] * 0x60 / 65536
    e.y = e.y - SIN[(a + 64) % 256] * 0x60 / 65536
    e.len = math.max(0, length(e))
    if e.len == 0 and e.pflag and d:check(e.pflag) then setFlag(d, e, false) end
  end
  -- grab: R facing the lever's side, close to the handle
  if p.state ~= "normal" or p.minish or not input.pressed("r") then return end
  if math.floor(p.animationState / 2) ~= e.type2 then return end
  local T = tables(f)
  local ox, oy = 0, 0
  if T then ox, oy = T.linkOffsets[e.type2][1], T.linkOffsets[e.type2][2] end
  local lx, ly = math.floor(e.x) + ox, math.floor(e.y) + oy
  if math.abs(p.x - lx) > 8 or math.abs(p.y - ly) > 8 then return end
  p.x, p.y = lx, ly
  p.state = "ext"
  p.extUpdate = hold
  p.holdLever = e
  p:setAnim(ANIM_GRAB, true)
end

local function draw(e, f, camX, camY)
  local A = f.assets
  local spr = A:sprite(e.sprite)
  local function frameOf(idx) local k = spr and spr.anims and spr.anims[idx]; return k and k[1] and k[1][1] end
  local function put(frame, x, y)
    if not frame or frame == 0xFF then return end
    local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette, "lever", e.gfx)
    if img then love.graphics.draw(img, math.floor(x - camX) + ox, math.floor(y - camY) + oy) end
  end
  put(frameOf(e.type2 + 4), e.sx, e.sy) -- the socket
  if e.len >= 8 then
    local tmp = (e.len - 8) % 8
    local mx, my = e.x, e.y
    if e.type2 == 0 then my = e.y - tmp - 0x11 elseif e.type2 == 1 then mx = e.x + tmp + 0x11
    elseif e.type2 == 2 then my = e.y + tmp + 0x11 else mx = e.x - tmp - 0x11 end
    put(frameOf(math.floor((e.len - 8) / 16) * 4 + e.type2 + 8), mx, my)
  end
  put(frameOf(e.type2), e.x, e.y) -- the handle
end

function L.spawn(d, e)
  if e.id ~= OBJ then return nil end
  local f = d.field
  local def = f:objects():def(OBJ, e.form or 0)
  if def then f:objects():dress(e, def, 0) end
  local data = e.data or {}
  e.type2 = band(data.paramB or 0, 0xFF) % 4
  e.need = band(bit.rshift(data.paramB or 0, 16), 0xFF)
  e.pflag = bit.rshift(data.paramC or 0, 16)
  local T = tables(f)
  e.sx, e.sy = e.x, e.y
  if T then e.x = e.x + T.initOffsets[e.type2][1]; e.y = e.y + T.initOffsets[e.type2][2] end
  e.ix, e.iy = math.floor(e.x), math.floor(e.y)
  e.pullDir = T and T.pullDirs[e.type2] or ({ [0] = 16, 24, 0, 8 })[e.type2]
  e.len = 0
  e.lever = true
  e.extUpdate = update
  e.drawGhost = draw
  d:track(e)
  return e
end

return L
