-- Round 69: FROZEN_OCTOROK ($91, src/object/frozenOctorok.c), the Big Octorok frozen with the Water Element in the
-- Element room ($60:08).  FrozenWaterElement_Init (ToDObjects.spawnFrozenElement) makes it; once the light melts
-- the ice (local flag $37 OUGONTEKI_G, FrozenWaterElement_Action2) it sets this one's subtimer = 1.
--
-- PORTED (decomp):
--   FrozenOctorok_Init: type 0 (body, right half: spriteOffset (+$29, -$20)) and type 6 (left half, (-$29, -$20)) at
--     the room's ($108, $168), scale unk_76 = unk_74 = $A0, unk_7b = -$80, the water element bob unk_7e = 0; type 0
--     makes the four legs (types 1-4: wiggle timer $10, subtimer +-2, scale $100, unk_76 $FF00 (mirrored) for the
--     even types) and the mouth (type 5: scale $100, unk_79 $1C).  Animations gUnk_08123DDC[type * 4]; leg angles
--     gUnk_08123E18 / gUnk_08123E1C (read from the ROM: RomTables FrozenOcto69.*).
--   FrozenOctorok_Action1: legs (sub_0809CB70 at -(body.unk_7b + LEG[t]), radius ((($10000 / body.unk_76) << 13)
--     >> 8) - $2000, halved + $2200 while the mouth's health is not 1; own angle body.unk_7b + LEG2[t] + unk_79; the
--     wiggle sub_0809CBE4 (SFX_19E at each end) while the body walks, step = heap.unk_0); the mouth (at -(body.unk_7b
--     + $80), radius (unk_79 << 8) * ($10000 / body.unk_74) >> 8; unk_79 back to $1C, unk_76 back to $100 unless the
--     body sucks); type 6 copies the body; type 7 holds the camera (gone when the camera leaves it).
--   Type 0, once OUGONTEKI_G: RequestPriorityDuration (Link held); sparkles on the element every 8 frames; its bob
--     (zVelocity -= unk_7e, flipped at +-$3000).  SubActions: 0 the element rises 16 px (0.25 a frame) and bobs; after
--     $F0 frames MessageFromTarget(TEXT_EZLO $43) -> 1: once the message is closed, 8 frames, the camera on a type 7
--     $50 px above; subtimer < 3: 2 (SFX_THUD_HEAVY, $1E frames of x shaking, subtimer + 1, back to 1 after $1E) --
--     two thuds; else 3: $78 frames, then the thawed graphics (LoadFixedGFX $115, palette $EF on every part),
--     SFX_WIND2 -> 4: $3C frames of the mouth throbbing (+-4 every 8) -> 5: $B4 frames of +-8 throbbing (the element
--     jitters), then the element moves at $200 toward the mouth until within $48: hidden, heap.unk_0 = 1, SFX_ED
--     (swallowed) -> 6: the body walks south at $C0 (SFX_TOGGLE_DIVING every 16 frames) past the room's y $1C8: the
--     camera back on Link, local flag $9B, the parts deleted -> 7: CreateEzloHint(TEXT_EZLO $44), gone.
-- SIMPLIFIED: CreateSparkleFx on the element is not shown; OCTOROK_BOSS_OBJECT's steam (type 6, sub-action 3) and suck particles (type 2, sub-action 5) are not
--   drawn; RequestPriorityDuration only holds Link (the others keep running).
local bit = require("bit")
local band, rshift, lshift = bit.band, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local M = {}
M.ID = 0x91
M.ANIM = require("src.zelda.tmc.RomTables").t("FrozenOcto69.ANIM")
M.LEG = require("src.zelda.tmc.RomTables").t("FrozenOcto69.LEG")
M.LEG2 = require("src.zelda.tmc.RomTables").t("FrozenOcto69.LEG2")
M.FLAG_OUGONTEKI, M.FLAG_GONE = 0x37, 0x9B
M.SFX = { THUD = 0xE6, WIND2 = 0xE8, ED = 0xED, DIVE = 0x163, S19E = 0x19E }
M.TEXT_RISE, M.TEXT_HINT = 0x0B43, 0x0B44
M.X, M.Y, M.Y_END = 0x108, 0x168, 0x1C8
M.GFX_THAWED, M.PAL_THAWED = 0x115, 0xEF -- LoadFixedGFX / ChangeObjPalette

local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
local function sin(a) return SIN[band(a, 0xFF)] end
local function cos(a) return SIN[band(a, 0xFF) + 0x40] end
local function u8(v) return band(v, 0xFF) end
local function s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end
local function s16(v) v = band(v, 0xFFFF) if v >= 32768 then return v - 65536 end return v end
local function trunc(v) if v < 0 then return -math.floor(-v) end return math.floor(v) end
local function lflag(f, i) return f:flag("local", i) end

-- sub_0809CB70: the part at `angle` / `radius` (Q8 of a pixel per $100) from its parent
function M.polar(pt, par, angle, radius)
  local tx = trunc(sin(angle) * radius / 256)
  local ty = trunc(cos(angle) * radius / 256)
  pt.x = par.x + tx / 256
  pt.y = par.y - ty / 256
  pt.z = par.z or 0
end

-- the leg radius (FrozenOctorok_Action1 types 1-4)
function M.legRadius(bodyU76, mouthHealth)
  local t = math.floor(0x10000 / bodyU76)
  t = rshift(lshift(t, 13), 8) - 0x2000
  if mouthHealth == 1 then return 0x2200 + t end
  return rshift(t, 1) + 0x2200
end
-- the mouth radius (type 5)
function M.mouthRadius(u79, bodyU74)
  local t = math.floor(0x10000 / bodyU74)
  return rshift(lshift(u79, 8) * t, 8)
end
-- sub_0809CBE4: the leg wiggle (returns true at a turn: SFX_19E)
function M.wiggle(l)
  l.u79 = l.u79 + s8(l.subtimer)
  if s8(l.subtimer) < 0 then
    if l.u79 < -l.timer then l.subtimer = u8(-s8(l.subtimer)) return true end
  elseif l.u79 > l.timer then l.subtimer = u8(-s8(l.subtimer)) return true end
  return false
end

local function part(d, body, t)
  local f = d.field
  local O = f.objects and f:objects()
  local def = O and O:def(M.ID, t)
  local pt = { type = t, x = body and body.x or M.X, y = body and body.y or M.Y, z = 0, u76 = 0x100, u74 = 0x100, u79 = 0,
               u7b = 0, timer = 0, subtimer = 0, anim = Anim.new(), def = def, ox = 0, oy = 0 }
  if def then
    pt.sprite = def.sprite
    pt.palette = f.assets:objPalette(def.palette, f.room.atlas and f.room.atlas.palettes)
    pt.gfx = Assets.gfxSource(def.gfxType, def.gfx)
    local a = M.ANIM[t]
    if pt.sprite and a then pt.anim:set(f.assets:sprite(pt.sprite), a, true) end
  end
  return pt
end

-- FrozenOctorok_Init type 0 (called by ToDObjects.spawnFrozenElement for CreateObject(FROZEN_OCTOROK, 0, 0))
function M.spawn(d, fwe)
  local f = d.field
  if lflag(f, M.FLAG_GONE) then return nil end
  local e = { kind = 6, id = M.ID, form = 0, type = 0, x = M.X, y = M.Y, z = 0, layer = fwe and fwe.layer or 1,
              action = 1, subAction = 0, timer = 1, subtimer = 0, direction = 0x10, u79 = 0xF0, u76 = 0xA0, u74 = 0xA0,
              u7b = 0x80, u7e = 0, ox = 0x29, oy = -0x20, dungeon = true, frozenOcto = true, animationState = 0,
              field80 = 0, field82 = 0, interactType = 0, heap = { unk0 = 0 }, legs = {} }
  local b = part(d, nil, 0)
  e.sprite, e.palette, e.gfx, e.anim, e.def = b.sprite, b.palette, b.gfx, b.anim, b.def
  for i = 1, 4 do
    local l = part(d, e, i)
    l.timer = 0x10
    l.subtimer = band(i, 2) == 0 and 2 or 0xFE
    l.u74 = 0x100
    l.u76 = band(i, 1) == 0 and 0xFF00 or 0x100
    e.legs[i] = l
  end
  local m = part(d, e, 5)
  m.u79, m.health = 0x1C, 0
  e.mouth = m
  local h = part(d, e, 6)
  h.u76, h.u74, h.ox, h.oy = 0xA0, 0xA0, -0x29, -0x20
  e.half = h
  e.drawGhost = function(me, ff, cx, cy) M.draw(me, ff, cx, cy) end
  e.extUpdate = function(dd, me) M.update(dd, me) end
  M.tickParts(e)
  d:track(e)
  return e
end

-- the parts' frame (Action1 types 1-6)
function M.tickParts(e)
  for i, l in ipairs(e.legs) do
    if e.subAction == 6 then
      l.subtimer = s8(l.subtimer) < 0 and u8(-e.heap.unk0) or u8(e.heap.unk0)
      if M.wiggle(l) and e.field then e.field:sound(M.SFX.S19E) end
    end
    M.polar(l, e, u8(-(e.u7b + M.LEG[i])), M.legRadius(e.u76, e.mouth.health))
    l.u7b = u8(e.u7b + M.LEG2[i] + l.u79)
  end
  local m = e.mouth
  if e.subAction ~= 4 and m.health ~= 1 then
    if m.u79 > 0x1C then m.u79 = m.u79 - 1 end
    if m.u76 > 0x100 then m.u76 = m.u76 - 1 else m.u76 = 0x100 end
  end
  M.polar(m, e, u8(-(e.u7b + 0x80)), M.mouthRadius(m.u79, e.u74))
  m.u7b = e.u7b
  e.half.x, e.half.y, e.half.z = e.x, e.y, e.z
end

local function child(e) return e.child or (e.frozenElement and e.frozenElement.water) end -- FWE: (super->child)->child = WATER_ELEMENT

-- FrozenOctorok_Action1 type 0
function M.update(d, e)
  local f = d.field
  e.field = f
  if e.deleted then return end
  local p = f.player
  local w = child(e)
  if lflag(f, M.FLAG_OUGONTEKI) and e.subAction < 7 then p.control = false; e.heldLink = true end -- RequestPriorityDuration
  local sa = e.subAction
  if sa == 0 then
    if e.subtimer ~= 0 then
      if e.u7e == 0 and w then
        if (w.z or 0) < 0x10 then w.z = (w.z or 0) + 0.25
        else w.z = w.z + 0.0625; w.zv = 0x3000; e.u7e = 0x200 end
      end
      e.u79 = e.u79 - 1
      if e.u79 < 0 then
        f:message(M.TEXT_RISE)
        e.subAction, e.u79 = 1, 8
      end
    end
  elseif sa == 1 then
    if not f.textbox then
      e.u79 = e.u79 - 1
      if e.u79 < 0 then
        e.cam = { x = e.x, y = e.y - 0x50, z = 0 }
        f.cameraTarget = e.cam
        if e.subtimer < 3 then e.subAction, e.u79 = 2, 0x1E; f:sound(M.SFX.THUD)
        else e.subAction, e.u79 = 3, 0x78 end
      end
    end
  elseif sa == 2 then
    e.u79 = e.u79 - 1
    if e.u79 < 0 then
      e.subAction, e.u79, e.subtimer = 1, 0x1E, e.subtimer + 1
      e.x = M.X
    else
      local k = band(e.u79, 3)
      local xi = math.floor(e.x)
      if k == 0 or k == 2 then e.x = band(xi, 0xFFF0) + 8
      elseif k == 1 then e.x = band(xi, 0xFFF8) + 4
      else e.x = band(xi, 0xFFF8) - 4 end
    end
  elseif sa == 3 then
    e.u79 = e.u79 - 1
    if e.u79 < 0 then
      e.subAction, e.u79 = 4, 0x3C
      local O = f.objects and f:objects()
      local pal = f.assets:objPalette(M.PAL_THAWED, f.room.atlas and f.room.atlas.palettes)
      for _, pt in ipairs({ e, e.half, e.mouth, e.legs[1], e.legs[2], e.legs[3], e.legs[4] }) do pt.palette = pal; pt.gfx = Assets.gfxSource("enemy", M.GFX_THAWED); pt.thawed = true end
      f:sound(M.SFX.WIND2)
    end
  elseif sa == 4 then
    e.u79 = e.u79 - 1
    if e.u79 < 0 then e.subAction, e.u79, e.type2 = 5, 0xB4, 3
    else e.mouth.u76 = e.mouth.u76 + ((band(f.frame or 0, 8) ~= 0) and -4 or 4) end
  elseif sa == 5 then
    e.mouth.u76 = e.mouth.u76 + ((band(f.frame or 0, 2) ~= 0) and -8 or 8)
    if e.u79 == 0 then
      if w then
        w.spriteOX = 0
        local a = u8(-e.u7b)
        w.x = w.x + sin(a) * 2 / 256
        w.y = w.y - cos(a) * 2 / 256
        if math.abs(w.x - e.x) + math.abs(w.y - e.y) < 0x48 or math.max(math.abs(w.x - e.x), math.abs(w.y - e.y)) < 0x48 then
          e.subAction, e.speed, e.type2, e.subtimer = 6, 0xC0, 0, 0
          w.hidden = true
          e.mouth.u76 = 0x100
          e.heap.unk0 = 1
          f:sound(M.SFX.ED)
        end
      else
        e.subAction, e.speed, e.heap.unk0 = 6, 0xC0, 1
      end
    else
      e.u79 = e.u79 - 1
      if w then local k = band(f.frame or 0, 3) w.spriteOX = (k == 1) and -4 or (k == 3) and 4 or 0 end
    end
  elseif sa == 6 then
    e.y = e.y + (e.speed or 0xC0) / 256 -- LinearMoveUpdate, direction $10
    if e.y > M.Y_END then
      f.cameraTarget = nil
      f:setFlag("local", M.FLAG_GONE, true)
      e.partsGone = true
      e.subAction = 7
    end
    if band(f.frame or 0, 0xF) == 0 then f:sound(M.SFX.DIVE) end
  elseif sa == 7 then
    if not f.scrolling and not f.pan then
      f:message(M.TEXT_HINT)
      e.deleted = true
      if e.heldLink then p.control = true end
      return
    end
  end
  if e.subtimer ~= 0 and w and not w.hidden then
    if e.u7e ~= 0 then
      w.zv = (w.zv or 0) - e.u7e
      w.z = w.z + w.zv / 0x10000
      if w.zv == 0x3000 or w.zv == -0x3000 then e.u7e = -e.u7e end
    end
  end
  if not e.partsGone then M.tickParts(e) end
  for _, pt in ipairs({ e, e.half, e.mouth, e.legs[1], e.legs[2], e.legs[3], e.legs[4] }) do if pt and pt.anim then pt.anim:update(1) end end
end

local function drawAff(f, pt, camX, camY, sx, sy, angle)
  local frame = pt.anim and pt.anim.frame
  if not pt.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = f.assets:spriteFrame(pt.sprite, frame, pt.palette, "fo69" .. tostring(pt.type) .. (pt.thawed and "t" or ""), pt.gfx)
  if not img then return end
  local x = math.floor(pt.x - camX + s8(pt.ox or 0))
  local y = math.floor(pt.y - camY - (pt.z or 0) + (pt.oy or 0))
  local kx, ky = 256 / (sx ~= 0 and sx or 256), 256 / (sy ~= 0 and sy or 256)
  if pt.anim:hflip() then kx = -kx end
  love.graphics.draw(img, x, y, -(angle or 0) / 0x10000 * 2 * math.pi, kx, ky, -ox, -oy)
end

function M.draw(e, f, camX, camY)
  if e.deleted or e.partsGone then return end
  for i = 1, 4 do local l = e.legs[i] drawAff(f, l, camX, camY, s16(l.u76), s16(l.u74), l.u7b * 256) end
  drawAff(f, e.mouth, camX, camY, e.mouth.u76, e.mouth.u74, e.mouth.u7b * 256)
  drawAff(f, e.half, camX, camY, e.u76, e.u74, e.u7b * 256)
  drawAff(f, e, camX, camY, e.u76, e.u74, e.u7b * 256)
end

return M
