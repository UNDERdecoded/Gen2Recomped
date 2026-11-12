-- Multi-part NPC sprites (round 7): townspeople, kids, guards, shopkeepers...
--
-- The cartridge draws these NPCs from up to four sprite parts instead of the
-- entity's own frame (src/physics.c LoadExtraSpriteData / SetExtraSpriteFrame
-- / SetSpriteSubEntryOffsetData1/2 / sub_0807000C, drawn by the ARM entity
-- drawer at $080B2718: when spriteAnimation[2] is set it skips the entity's
-- frame and draws each part's frame of its own sprite, with its own palette,
-- at the part's offset, the part's flip byte XORed into the entity's flip).
--
-- Each NPC's `_Head` function (gNPCFunctions[id][1]) picks the part frames
-- from the entity's animation bytes every frame: frameIndex (keyframe byte
-- 0), frameSpriteSettings (byte 2) and frame (byte 3). They are ported here
-- by NPC id. Every table they read (the SpriteLoadData lists, the per-type
-- frame bases, gExtraFrameOffsets) is read from the player's ROM: the
-- `npcData` and `extraFrameOffsets` ranges of menudata.bin (Layout.MENU_DATA).
local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local NpcParts = {}

-- ---------------------------------------------------------------------------
-- ROM readers
-- ---------------------------------------------------------------------------
local function reader(A, name)
  local e = A.manifest and A.manifest.menuData and A.manifest.menuData[name]
  if not e then return nil end
  A.menuBlob = A.menuBlob or (A.store and A.store:read("menudata.bin")) or ""
  local blob, base, off, size = A.menuBlob, e[1], e[2], e[3]
  local t = { base = base, size = size }
  function t.u8(a)
    local o = a - base
    if o < 0 or o >= size then return 0 end
    return blob:byte(off + o + 1) or 0
  end
  function t.u16(a) return t.u8(a) + 256 * t.u8(a + 1) end
  function t.u32(a) return t.u16(a) + 65536 * t.u16(a + 2) end
  return t
end

function NpcParts.readers(A)
  if A._npcParts == nil then
    local d, x = reader(A, "npcData"), reader(A, "extraFrameOffsets")
    A._npcParts = (d and x) and { d = d, x = x } or false
  end
  return A._npcParts or nil
end

-- GetSpriteSubEntryOffsetDataPointer(sprite, frame): the 4 offset bytes
local EFO = 0x089FB770
local function offsetData(X, sprite, frame)
  local v = X.u16(EFO + 0x10 + 2 * sprite) + EFO
  local idx = X.u8(v + band(frame, 0xFF)) * 4
  return EFO + X.u32(EFO) + idx
end

-- ---------------------------------------------------------------------------
-- part state (struct_gUnk_020000C0_1)
-- ---------------------------------------------------------------------------
-- LoadExtraSpriteData: up to four 4-byte entries, stopping at a zero sprite
-- (bits 16-25); bits 0-9 palette, 10-15 tile offset, 26 per-frame graphics
function NpcParts.load(R, addr)
  local parts = {}
  for i = 0, 3 do
    local w = R.d.u32(addr + i * 4)
    local sprite = band(rshift(w, 16), 0x3FF)
    if sprite == 0 then break end
    parts[i + 1] = {
      pal = band(w, 0x3FF), tile = band(rshift(w, 10), 0x3F), sprite = sprite,
      swap = band(rshift(w, 26), 1) == 1,
      frame = 0xFF, flip = 0, ox = 0, oy = 0,
    }
  end
  return parts
end

local function setFrame(e, i, f)
  local p = e.parts[i + 1]
  if p then p.frame = band(f, 0xFF) end
end

-- SetSpriteSubEntryOffsetData1 / 2 (bytes 0-1 / 2-3 of the anchor's data)
local function offset(e, R, a, b, second)
  local pa, pb = e.parts[a + 1], e.parts[b + 1]
  if not (pa and pb) then return end
  local p = offsetData(R.x, pa.sprite, pa.frame) + (second and 2 or 0)
  pb.ox = band(pa.ox + R.x.u8(p), 0xFF)
  pb.oy = band(pa.oy + R.x.u8(p + 1), 0xFF)
end
local function off1(e, R, a, b) offset(e, R, a, b, false) end
local function off2(e, R, a, b) offset(e, R, a, b, true) end

-- the entity's animation bytes
local function bytes(e)
  local an = e.anim
  return an.frame or 0xFF, an.flip or 0, an.flags or 0
end

-- ---------------------------------------------------------------------------
-- per NPC: which SpriteLoadData list, and the _Head function
-- ---------------------------------------------------------------------------
local function typ(e) return e.form or 0 end
local function ptrAt(R, tbl, i) return R.d.u32(tbl + i * 4) end

-- a plain head over a body: part 0 = f(frame), part 1 = frameIndex
local function headBody(fn)
  return function(e, R)
    local fi, fss, fr = bytes(e)
    setFrame(e, 0, fn(fr, fss, e, R))
    setFrame(e, 1, fi)
    off1(e, R, 1, 0)
  end
end

local SPEC = {}
NpcParts.SPEC = SPEC

-- TOWNSPERSON: gUnk_0810B6EC[type]; gUnk_0810B680 {frame1, frame2, hold}
SPEC[0x06] = {
  load = function(e, R) return ptrAt(R, 0x0810B6EC, typ(e)) end,
  head = function(e, R)
    local fi = bytes(e)
    local t = 0x0810B680 + typ(e) * 4
    setFrame(e, 0, R.d.u8(0x0810B78C + band(e.animIndex or 0, 3)) + R.d.u8(t))
    setFrame(e, 1, fi + R.d.u8(t + 1))
    off1(e, R, 1, 0)
  end,
  -- sub_08061CB4: a held keyframe ($FF) lasts gUnk_0810B680[type].unk2
  hold = function(e, R) return R.d.u8(0x0810B680 + typ(e) * 4 + 2) end,
}
-- KID: gUnk_0810BDC4[type]; gUnk_0810C0A0 {frame, frameIndex} x 2 per type
SPEC[0x07] = {
  load = function(e, R) return ptrAt(R, 0x0810BDC4, typ(e)) end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    local t = typ(e)
    local p = 0x0810C0A0 + t * 4
    local u3 = band(fr, 0x1F) + R.d.u8(p)
    local u4 = band(fi, 0x1F) + R.d.u8(p + 1)
    if t <= 5 then
      local u2 = rshift(band(fss, 0x30), 4)
      if u2 ~= 0 then u2 = u2 + 0x50 end
      setFrame(e, 0, u3); setFrame(e, 1, u4); setFrame(e, 2, u2 - 1)
      off1(e, R, 1, 0); off2(e, R, 1, 2)
    elseif t == 6 then
      local u5 = band(fss, 0xF)
      if u5 ~= 0 then u5 = u5 + 0x93 end
      setFrame(e, 0, u5 - 1); setFrame(e, 1, u3); setFrame(e, 2, u4)
      off1(e, R, 2, 1); off2(e, R, 1, 0)
    elseif t <= 8 then
      setFrame(e, 0, u3); setFrame(e, 1, u4)
      off1(e, R, 1, 0)
    end
  end,
}
-- GUARD ($08) / GUARD_1 ($15): &gUnk_0810F524[(id ^ $15) ? 4 : 0]
local function guardHead(e, R)
  local fi, fss, fr = bytes(e)
  local u2, p5, u4 = band(fr, 0x3F), band(fi, 0x3F), band(fss, 0x3F)
  local p3
  if e.id == 0x15 then
    if band(fi, 0x40) ~= 0 then
      p5 = p5 + 0x21; p3 = -1; u4 = 0
    else
      p3 = u2 + 0x19
      if band(fss, 0x3F) ~= 0 then u4 = u4 + 0x1F end
    end
  else
    p3 = u2 + 0x46; p5 = p5 + 0x2D
    if band(fss, 0x3F) ~= 0 then u4 = u4 + 0x4C end
  end
  setFrame(e, 0, p3); setFrame(e, 1, p5); setFrame(e, 2, u4 - 1)
  off1(e, R, 1, 0); off2(e, R, 1, 2)
end
local function guardLoad(e) return 0x0810F524 + (e.id == 0x15 and 0 or 16) end
SPEC[0x08] = { load = guardLoad, head = guardHead }
SPEC[0x15] = { load = guardLoad, head = guardHead }
-- MAID ($0B) / MAID_1 ($16): &gUnk_0810F874[(id ^ $16) ? 3 : 0]
local function maidHead(e, R)
  local fi, _, fr = bytes(e)
  local u2, u3 = band(fr, 0x7F), fi
  if e.id == 0x16 then
    if u2 ~= 0 then u2 = u2 + 10 end
  else
    if u2 ~= 0 then u2 = u2 + 0x1A end
    u3 = u3 + 0x10
  end
  setFrame(e, 0, u2 - 1); setFrame(e, 1, u3)
  off1(e, R, 1, 0)
end
local function maidLoad(e) return 0x0810F874 + (e.id == 0x16 and 0 or 12) end
SPEC[0x0B] = { load = maidLoad, head = maidHead }
SPEC[0x16] = { load = maidLoad, head = maidHead }
-- FOREST_MINISH: gUnk_0810A348
SPEC[0x03] = {
  load = function() return 0x0810A348 end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    local f = fr
    if fr ~= 0xFF then f = band(fr, 0x7F) end
    if band(fss, 1) == 0 then f = 0xFF end
    setFrame(e, 0, f); setFrame(e, 1, fi)
    off1(e, R, 1, 0)
  end,
}
-- MINISH_EZLO: gUnk_0810C48C (the palette switch of sub_0806FF10 is kept)
SPEC[0x0F] = {
  load = function() return 0x0810C48C end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    local a, b = 0, 1
    if band(fss, 4) ~= 0 then a, b = 1, 0 end
    setFrame(e, a, band(fr, 0x7F) - 1); setFrame(e, b, fi)
    local p = e.parts[b + 1]
    if p then p.pal = band(fss, 8) ~= 0 and 0x16 or 0x11C end
    off1(e, R, b, a)
  end,
}
-- BEEDLE: gUnk_0810C8D4
SPEC[0x11] = { load = function() return 0x0810C8D4 end, head = headBody(function(fr) return band(fr, 0x3F) end) }
-- SITTING_PERSON: &gUnk_0810CB78[type * 3]; gUnk_0810CBC0, gUnk_0810CD88[type][4]
SPEC[0x13] = {
  load = function(e) return 0x0810CB78 + typ(e) * 12 end,
  head = function(e, R)
    local fi, _, fr = bytes(e)
    local p = 0x0810CBC0 + typ(e) * 4
    setFrame(e, 0, R.d.u8(p) + band(fr, 0xF))
    setFrame(e, 1, R.d.u8(0x0810CD88 + typ(e) * 4 + band(fi, 3)) + R.d.u8(p + 1))
    off1(e, R, 1, 0)
  end,
}
-- STURGEON / TALON / MUTOH / GORMAN / HURDY_GURDY_MAN / FARMERS / MAMA
SPEC[0x1A] = { load = function() return 0x0810FA38 end, head = headBody(function(fr) return band(fr, 0x3F) end) }
SPEC[0x1D] = { load = function() return 0x0810FEB0 end, head = headBody(function(fr) return band(fr, 7) + 0xB end) }
SPEC[0x29] = { load = function() return 0x08110C00 end, head = headBody(function(fr) return band(fr, 0x7F) end) }
SPEC[0x34] = { load = function() return 0x08111C3C end, head = headBody(function(fr) return band(fr, 7) + 0xF end) }
SPEC[0x53] = { load = function() return 0x081144F0 end, head = headBody(function(fr) return band(fr, 0x7F) + 8 end) }
SPEC[0x3E] = { load = function(e) return 0x08113140 + typ(e) * 12 end, head = headBody(function(fr) return band(fr, 0x7F) end) }
SPEC[0x46] = { load = function() return 0x08113754 end, head = headBody(function(fr) return band(fr, 0x7F) end) }
-- SMITH: gUnk_08110354 (part 1 is the hammer: frame $16 while frame bit $40)
SPEC[0x22] = {
  load = function() return 0x08110354 end,
  head = function(e, R)
    local fi, _, fr = bytes(e)
    setFrame(e, 0, fi)
    setFrame(e, 1, band(fr, 0x40) ~= 0 and 0x16 or 0xFF)
    off1(e, R, 0, 1)
  end,
}
-- CARPENTER: &gUnk_08110CA8[type * 4]
SPEC[0x2A] = {
  load = function(e) return 0x08110CA8 + typ(e) * 16 end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    setFrame(e, 0, band(fr, 0x7F)); setFrame(e, 1, fi)
    if typ(e) < 2 then
      setFrame(e, 2, band(fss, 0x3F))
      off1(e, R, 1, 0); off2(e, R, 1, 2)
    else
      off1(e, R, 1, 0)
    end
  end,
}
-- MOUNTAIN_MINISH: gUnk_08111358
SPEC[0x2D] = {
  load = function() return 0x08111358 end,
  head = function(e, R)
    local fi, _, fr = bytes(e)
    local b = band(fr, 0x7F)
    setFrame(e, 1, fi)
    if band(b, 0x40) ~= 0 then
      setFrame(e, 0, band(b, 0x1F) + 4); setFrame(e, 2, 0xFF)
      off1(e, R, 1, 0)
    elseif band(b, 0x20) ~= 0 then
      setFrame(e, 0, 0xFF); setFrame(e, 2, band(b, 0x1F))
      off1(e, R, 1, 2)
    else
      setFrame(e, 0, 0xFF); setFrame(e, 2, 0xFF)
    end
  end,
}
-- MELARI: gUnk_08111520
SPEC[0x2F] = {
  load = function() return 0x08111520 end,
  head = function(e, R)
    local fi, _, fr = bytes(e)
    local b = band(fr, 0x3F)
    setFrame(e, 1, fi)
    if band(b, 0x20) ~= 0 then
      setFrame(e, 0, band(b, 0x1F)); setFrame(e, 2, 0xFF)
      off1(e, R, 1, 0)
    else
      setFrame(e, 0, 0xFF); setFrame(e, 2, band(b, 0x1F))
      off2(e, R, 1, 2)
    end
  end,
}
-- DOG: &gUnk_08111D58[type * 3]; head base gUnk_08111E30[type]
SPEC[0x35] = {
  load = function(e) return 0x08111D58 + typ(e) * 12 end,
  head = function(e, R)
    local fi, _, fr = bytes(e)
    local f = band(fr, 0x7F)
    if f ~= 0 then f = f + R.d.u8(0x08111E30 + typ(e)) end
    setFrame(e, 0, f - 1); setFrame(e, 1, fi)
    off1(e, R, 1, 0)
  end,
}
-- SYRUP: type 0 gUnk_081121B4, else gUnk_081121C4
SPEC[0x36] = {
  load = function(e) return typ(e) == 0 and 0x081121B4 or 0x081121C4 end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    local s = rshift(e.animationState or 0, 1)
    setFrame(e, 0, R.d.u8(0x081121E4 + s + fi * 4) + 0x10)
    if e.parts[1] then e.parts[1].flip = R.d.u8(0x08112204 + s) end
    setFrame(e, 1, band(rshift(fr, 4), 7))
    setFrame(e, 2, band(fr, 7) + 0x1C)
    setFrame(e, 3, band(fss, 1) + 0x1A)
    off1(e, R, 1, 0); off2(e, R, 1, 3)
  end,
}
-- TOWN_MINISH: gUnk_08112674[type]
SPEC[0x38] = {
  load = function(e, R) return ptrAt(R, 0x08112674, typ(e)) end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    local f
    if e.script then
      f = fr
      if f ~= 0xFF then f = band(f, 0x7F) end
      if band(fss, 1) == 0 then f = 0xFF end
    else
      f = band(fss, 1) ~= 0 and (rshift(e.unk69 or 0, 1) + 0x1C) or 0xFF
    end
    setFrame(e, 0, f); setFrame(e, 1, fi)
    off1(e, R, 1, 0)
  end,
}
-- PERCY: gUnk_08112E1C
SPEC[0x3A] = {
  load = function() return 0x08112E1C end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    setFrame(e, 0, band(fss, 0x3F) + 0x13)
    setFrame(e, 1, band(fr, 0x7F) + 0xB)
    setFrame(e, 2, fi)
    off1(e, R, 2, 1); off2(e, R, 2, 0)
  end,
}
-- TEACHERS: &gUnk_08113910[type * 4]
SPEC[0x48] = {
  load = function(e) return 0x08113910 + typ(e) * 16 end,
  head = function(e, R)
    local fi, fss, fr = bytes(e)
    local u3 = band(fr, 0x7F)
    if typ(e) == 0 then
      setFrame(e, 0, u3 + 3); setFrame(e, 1, fi)
      off1(e, R, 1, 0)
    else
      setFrame(e, 0, u3 + 6); setFrame(e, 1, band(fss, 0x3F) + 3); setFrame(e, 2, fi)
      off1(e, R, 2, 1); off2(e, R, 2, 0)
    end
  end,
}
-- WIND_TRIBESPEOPLE: &gUnk_08113A1C[type * 4]
SPEC[0x49] = {
  load = function(e) return 0x08113A1C + typ(e) * 16 end,
  head = function(e, R)
    local fi, _, fr = bytes(e)
    local b = band(fr, 0x3F)
    if typ(e) == 4 then
      setFrame(e, 0, 9); setFrame(e, 1, b); setFrame(e, 2, fi)
      off2(e, R, 2, 0); off1(e, R, 2, 1)
    else
      local a, c = 0, 1
      if band(fr, 0x40) ~= 0 then a, c = 1, 0 end
      setFrame(e, a, b); setFrame(e, c, fi)
      off1(e, R, c, a)
    end
  end,
}
-- NPC_UNK_58 (the figurine / shell counters): gUnk_081146D0
SPEC[0x58] = {
  load = function() return 0x081146D0 end,
  head = function(e, R)
    setFrame(e, 0, e.unk68 or 0); setFrame(e, 1, e.unk6a or 0); setFrame(e, 2, e.unk6c or 0); setFrame(e, 3, 10)
    for i, x in ipairs({ -12, -4, 12 }) do
      local p = e.parts[i]
      if p then p.ox, p.oy = band(x, 0xFF), 0 end
    end
  end,
}

-- ---------------------------------------------------------------------------
-- entity hooks
-- ---------------------------------------------------------------------------
-- at spawn: give the entity its parts when its NPC id is multi-part
function NpcParts.attach(field, e)
  local spec = SPEC[e.id]
  if not spec or e.kind ~= 7 then return end
  local R = NpcParts.readers(field.assets)
  if not R then return end
  local addr = spec.load(e, R)
  if not addr or addr < 0x08000000 then return end
  local parts = NpcParts.load(R, addr)
  if #parts == 0 then return end
  e.parts = parts
  e.partSpec = spec
end

-- every frame after the animation steps (NPCUpdate: the _Head call)
function NpcParts.update(field, e)
  local spec = e.partSpec
  if not spec then return end
  local R = NpcParts.readers(field.assets)
  if not R then return end
  if spec.hold and e.anim and e.anim.timer == 0xFF then e.anim.timer = spec.hold(e, R) end
  spec.head(e, R)
end

local function s8(v) return v >= 128 and v - 256 or v end

-- the drawer ($080B2718): parts 3..0 so part 0 lands on top (lower OAM slot)
function NpcParts.draw(field, e, x, y, hflip)
  local A = field.assets
  local Assets = require("src.zelda.tmc.Assets")
  local bgPal = field.room and field.room.atlas and field.room.atlas.palettes
  for i = #e.parts, 1, -1 do
    local p = e.parts[i]
    if p.frame ~= 0xFF then
      local flip = hflip
      if band(p.flip, 1) ~= 0 then flip = not flip end
      local ox, oy = s8(p.ox), s8(p.oy)
      local px = flip and (x - ox) or (x + ox)
      local py = y + oy
      p.palette = p.palette and p.palId == p.pal and p.palette or A:objPalette(p.pal, bgPal)
      p.palId = p.pal
      local src = (not p.swap) and e.def and e.def.gfx and e.def.gfx ~= 0
        and { fixed = e.def.gfx, first = p.tile } or nil
      local img, iox, ioy = A:spriteFrame(p.sprite, p.frame, p.palette, "np" .. p.pal, src)
      if img then
        if flip then love.graphics.draw(img, px - iox, py + ioy, 0, -1, 1)
        else love.graphics.draw(img, px + iox, py + ioy) end
      end
    end
  end
end

return NpcParts
