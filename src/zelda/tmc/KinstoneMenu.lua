-- The Kinstone fusion window (src/menu/kinstoneMenu.c) on Ppu.lua, and
-- the fuse-info flow around it (common.c InitializeFuseInfo /
-- PerformFuseAction, Fuse_Action0-3).
--
-- KinstoneMenu_Type0: the pause menu's base gfx (sub_080A4D34), palette
--   group $CB, gfx group $75, Link's name into OBJ tile $80 and the
--   fuser's name into $A0 (KinstoneMenu_080A4494, proportional font,
--   96 px), then gfx group $76 + clamp((width + 7) / 8 - 6, 0, 6) -- the
--   name plate as wide as the name; BG1 $1C01, BG2 $1D02, BG3 $1E0B; the
--   fuser drawn at ($CC, $60); the HUD buttons gUnk_081280DC; a white
--   fade in at speed 8.
-- Type1: the bag on a wheel -- seven pieces at gSineTable positions around
--   ($-10, $4F); the position eases to the chosen index by
--   gUnk_081280EE[...] * $666 a frame; A picks, L / START / B cancel.
-- Type3: the piece slides right 2 px a frame to $46; shapes differ:
--   SFX_ITEM_SHIELD_BOUNCE and Type4 (it slides back 3 px a frame while
--   spinning, SFX_MENU_ERROR); shapes match: WIN0 ($68-$87, $40-$5F)
--   brightens over 15 frames (BLDCNT $3F90), SFX_FA, then Type5.
-- Type5: the fusion is recorded, SFX_TASK_COMPLETE, message $0702; when it
--   closes SFX_147 and 120 frames of spin; the spark, SFX_1CA, 80 frames,
--   then out (Type2) with fusion state 6 (fused) or 5 (cancelled).
-- The target half (gFuseInfo.kinstoneId) spins by gUnk_08128120 through
--   OAM affine matrix 0.

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local Ppu = require("src.zelda.tmc.Ppu")
local Ui = require("src.zelda.tmc.Ui")

local KM = {}
KM.__index = KM

KM.LAYOUT = 0x081280DC   -- gUnk_081280DC (KeyButtonLayout)
KM.SPEEDS = 0x081280EE   -- gUnk_081280EE (6 x u8)
KM.ARROWS = 0x08128110   -- gUnk_08128110 (16 x u8)
KM.SPIN = 0x08128120     -- gUnk_08128120 (28 x s8)

local SFX_CHOICE, SFX_CANCEL, SFX_ERROR = 0x69, 0x6C, 0x6D
local SFX_SHIELD_BOUNCE, SFX_FA, SFX_TASK_COMPLETE, SFX_147, SFX_1CA = 0x118, 0xFA, 0xCD, 0x147, 0x1CA

-- gSineTable entry (sin * 256)
local function sine(i)
  return math.floor(math.sin(band(i, 0xFF) * math.pi / 128) * 256 + 0.5)
end

local function readLayout(t, a)
  local l = {}
  for i = 1, 9 do l[i] = t.u8(a + i - 1) end
  l.elements = {}
  local p = a + 9
  while t.u8(p) ~= 0xFF and #l.elements < 8 do
    l.elements[#l.elements + 1] = { t.u8(p), t.u8(p + 1) }
    p = p + 2
  end
  return l
end

-- opts: target = the half on offer (a kinstone id 1-100, or a piece type
-- for a friend's offer), entity = the fuser drawn on the right, name =
-- the fuser's name text, onPick(piece) (online: the window waits for
-- resolve), onDone(state, piece) (5 cancelled, 6 fused)
function KM.new(field, opts)
  local self = setmetatable({ field = field, A = field.assets, opts = opts or {} }, KM)
  self.target = self.opts.target
  self.menuType, self.overlay = 0, 0
  self.column = 1
  self.pos, self.index, self.shown = 0, 0, 0    -- unk10 (16.16), unk28, unk29
  self.slide, self.spin, self.spinV = 0, 0, 0   -- unk2c, unk18, unk1a
  self.ticks = 0
  self.slots, self.counts, self.slotAge = {}, {}, {}
  self:init()
  return self
end

function KM:sound(id) self.field:sound(id) end

function KM:table()
  self.tbl = self.tbl or Ppu.table({ A = self.A }, "kinstoneMenu")
  return self.tbl
end

-- a name into OBJ VRAM at `tile` (sub_080A44E0: 96 px, $300 bytes)
function KM:nameTiles(text, tile)
  local ffi = require("ffi")
  local p = self.ppu
  if not p:table("textColors") then return 0 end
  local buf = ffi.new("uint8_t[?]", 0x300)
  local chars = {}
  for k = 1, #text do chars[#chars + 1] = { text:byte(k) } end
  local w = p:drawGlyphs(buf, 0x300, chars, 0, 0x60, 5, 0, 0)
  p:write(0x06010000 + tile * 32, ffi.string(buf, 0x300))
  return w
end

-- KinstoneMenu_Type0
function KM:init()
  local f = self.field
  local p = Ppu.new(self.A)
  self.ppu = p
  for _, g in ipairs({ 16, 23 }) do p:loadGfxGroup(g) end
  p:loadGfxGroup(f:inventory(0x08) ~= 0 and 24 or 25)
  p:loadGfxGroup(f:inventory(0x0C) ~= 0 and 28 or 27)
  p:loadPaletteGroup(11); p:loadPaletteGroup(12); p:setColor(0, 0)
  p:loadPaletteGroup(0xCB)
  p:loadGfxGroup(0x75)
  self:nameTiles(tostring(f.save.name or "Link"), 0x80)
  local w = self:nameTiles(tostring(self.opts.name or ""), 0xA0)
  local n = math.floor((w + 7) / 8) - 6
  p:loadGfxGroup(math.max(0, math.min(6, n)) + 0x76)
  p.dispcnt = 0x1F40
  p.bg[0].control = 0x1F0C
  p.bg[1].control, p.bg[2].control, p.bg[3].control = 0x1C01, 0x1D02, 0x1E0B
  for i = 1, 3 do p.bg[i].updated = true end
  self.ui = Ui.new(p)
  local t = self:table()
  if t then self.ui:layout(readLayout(t, KM.LAYOUT)) end
  self.fade = 256
  self.menuType = 1
end

function KM:pieces() return self.field.kinstone:pieces() end

-- KinstoneMenu_Type1
function KM:updateWheel(input)
  local t = self:table()
  self.column = 2
  local target = self.index * 0x10000
  local d = target - self.pos
  if math.abs(d) <= 0x1FFD then
    self.pos = target
  else
    self.column = 1
    local sign = d < 0 and -1 or 1
    local k = math.min(5, math.abs(math.floor(d / 0x20000 + (d < 0 and 1 or 0))))
    local sp = t and t.u8(KM.SPEEDS + k) or 5
    self.pos = self.pos + sp * 0x666 * sign
  end
  local shown = math.floor(self.pos / 0x10000 + (self.pos < 0 and 0.99999 or 0))
  if shown ~= self.shown then self.shown = shown; self:sound(SFX_CHOICE) end
  if self.waiting then return end
  if input.pressed("l") or input.pressed("start") or input.pressed("b") then
    self:sound(SFX_CANCEL)
    return self:exit(5)
  end
  local idx = self.index
  if input.pressed("left") or input.pressed("up") then idx = idx - 1
  elseif input.pressed("right") or input.pressed("down") then idx = idx + 1
  elseif input.pressed("a") and self.column == 2 then
    local list = self:pieces()
    local piece = list[math.floor(self.pos / 0x10000) + 1]
    if piece and (self.target or self.opts.onPick) then
      self.picked = piece
      if self.opts.onPick then
        -- online: the friend's game decides; wait for resolve()
        self.waiting = true
        self.opts.onPick(piece)
        return
      end
      self.menuType, self.overlay = 3, 0
    end
  end
  local n = #self:pieces()
  if idx >= n then idx = n - 1 end
  if n < 2 then idx = 0 end
  if idx < 0 then idx = 0 end
  self.index = idx
end

-- online: the result arrived (ok = the shapes fitted, id = the fusion)
function KM:resolve(ok, id)
  self.waiting = false
  self.forced = ok and "fit" or "nofit"
  if id then self.resultId = id end
  self.menuType, self.overlay = 3, 0
end

function KM:fits()
  if self.forced then return self.forced == "fit" end
  local k = self.field.kinstone
  return k:shape(self.picked) ~= nil and k:shape(self.picked) == k:shape(self.target)
end

function KM:update(input)
  self.ticks = self.ticks + 1
  self.ui.hideFlags = 0
  self.ui:update({ equipped = { a = self.field:equipped("a"), b = self.field:equipped("b") }, health = self.field.save.stats.health })
  -- the slots' ages (KinstoneMenu_080A4054)
  for i = 0, 15 do if (self.slotAge[i] or 0) > 0 then self.slotAge[i] = self.slotAge[i] - 1 end end
  if self.fade then
    self.fade = self.fade - 8
    if self.fade <= 0 then self.fade = nil end
    return
  end
  local mt = self.menuType
  if mt == 1 then return self:updateWheel(input)
  elseif mt == 3 then
    self.column = 3
    if self.overlay == 0 then
      self.spin = 0
      self.slide = self.slide + 2
      if self.slide > 0x45 then self.slide = 0x46; self.overlay = 1 end
    elseif self.overlay == 1 then
      if not self:fits() then
        self:sound(SFX_SHIELD_BOUNCE)
        self.menuType = 4
      else
        self.overlay, self.timer = 2, 20
        self.bright = 0
        self:sound(SFX_FA)
      end
    else
      self.bright = self.bright + 1
      if self.bright > 14 then
        self.bright = nil
        self.menuType, self.overlay = 5, 0
      end
    end
  elseif mt == 4 then
    self.column = 4
    self.slide = self.slide - 3
    self.spin = self.spin + 0x100
    if self.slide < 0 then
      self.spin, self.slide = 0, 0
      self.menuType = 1
      self.forced, self.picked = nil, nil
      self:sound(SFX_ERROR)
      if self.opts.onMismatch then self.opts.onMismatch() end
    end
  elseif mt == 5 then
    if self.overlay == 0 then
      self.column = 5
      self:record()
      self:sound(SFX_TASK_COMPLETE)
      self.field:message(0x0702)
      self.overlay, self.timer = 1, 120
    elseif self.overlay == 1 then
      if not self.field:messageActive() then self.overlay = 2; self:sound(SFX_147) end
    elseif self.overlay == 2 then
      self.timer = self.timer - 1
      if self.timer ~= 0 then
        self.spin = self.spin + self.spinV
        self.spinV = self.spinV + 0x20
      else
        self.column = 6
        self.overlay, self.timer = 3, 79
        self.spark = 0
        self:sound(SFX_1CA)
      end
    else
      self.timer = self.timer - 1
      self.spark = (self.spark or 0) + 1
      if self.timer < 0 then return self:exit(6) end
    end
  end
end

-- Type5 overlay 0: the fused bit, the count, the piece out of the bag
function KM:record()
  local k = self.field.kinstone
  local id = self.resultId or self.target
  self.fusedId = id
  if self.opts.record then self.opts.record(id, self.picked)
  else k:fuse(id, self.picked) end
  local st = self.field.save.kinstones
  st.fusedCount = (st.fusedCount or 0) + 1
end

-- KinstoneMenu_Type2
function KM:exit(state)
  self.done = true
  self.state = state
  if self.opts.onDone then self.opts.onDone(state, self.picked, self.fusedId) end
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------
-- sub_080A43A8 / sub_080A43DC / sub_080A4418: 16 OBJ slots at tile $300 +
-- slot * 16, one per piece art, recycled when unused for 2 frames
function KM:slot(gfx)
  for i = 0, 15 do
    if self.slots[i] == gfx then self.slotAge[i] = 2; return i end
  end
  local pick = 0
  for i = 0, 15 do if (self.slotAge[i] or 0) == 0 then pick = i break end end
  self.slots[pick], self.slotAge[pick], self.counts[pick] = gfx, 2, nil
  local A = self.A
  local e = A.manifest.kinstoneGfx and A.manifest.kinstoneGfx[gfx]
  if e then
    A.kinGfx = A.kinGfx or A.store:read("kinstonegfx.bin") or ""
    self.ppu:write(0x06010000 + (0x300 + pick * 16) * 32, A.kinGfx, e[1], math.min(e[2], 0x200))
  end
  return pick
end

-- sub_080A42E0: a piece (count > 0 draws the count, $FF the whole stone)
function KM:drawPiece(id, count, x, y, _4)
  local p = self.ppu
  local events = self.A.manifest.kinstones and self.A.manifest.kinstones.events or {}
  local ev = events[id] or {}
  local s = self:slot(count == 0xFF and (ev.gfxFull or 0) or (ev.gfxPiece or 0))
  if count ~= 0 and count ~= 0xFF then
    if self.counts[s] ~= count then
      self.counts[s] = count
      local d = p:table("ammoDigits")
      if d then
        local tens = math.min(9, math.floor(count / 10))
        p:write(0x06010000 + (0x2E0 + s * 2) * 32, d.str(d.base + tens * 0x20, 0x20))
        p:write(0x06010000 + (0x2E1 + s * 2) * 32, d.str(d.base + (count % 10 + 10) * 0x20, 0x20))
      end
    end
    local ox, oy = 8, 10
    if self.column == 0 then ox, oy = 0x10, 9 end
    p:drawDirect(0, 5, { x = x + ox, y = y + oy, _4 = 0, _6 = 0, _8 = s * 2 + 0x3AE0 })
  end
  p:drawDirect(0, 3, { x = x, y = y, _4 = _4 or 0, _6 = 0, _8 = bor(lshift(ev.objPalette or 0, 12), 0x800, 0x300 + s * 16) })
end

function KM:draw()
  local p, t = self.ppu, self:table()
  p:flush()
  -- KinstoneMenu_080A422C: the halves in the middle
  local wob = t and t.s8(KM.SPIN + (math.floor(self.spin / 256) % 27)) or 16
  p.affine = p.affine or {}
  p.affine[0] = { lshift(wob, 4), 0, 0, 0x100 }
  local col = self.column
  local tx = 0x180
  if col == 5 then
    self:drawPiece(self.fusedId or self.target, 0xFF, 0x78, 0x4F, 0x100)
  elseif col == 3 or col == 4 then
    if self.picked then self:drawPiece(self.picked, 0, self.slide + 0x32, 0x4F, 0x100) end
    tx = 0x8A - math.floor(self.slide * 0x12 / 0x46)
  elseif col ~= 6 then
    tx = 0x8A
  end
  if self.target and col ~= 5 and col ~= 6 then self:drawPiece(self.target, 0, tx, 0x4F, 0x100) end
  -- KinstoneMenu_080A414C: the wheel
  local list = self:pieces()
  local u = -math.floor(band(self.pos, 0xFFFF) / 0xB21) - 0x45
  for i = -3, 3 do
    local y = math.floor(sine(u) * 0x44 / 0x100) + 0x4F
    local x = math.floor(sine(u + 0x40) * 0x42 / 0x100) - 0x10
    local k = math.floor(self.pos / 0x10000) + i
    if k >= 0 and list[k + 1] then
      local n = self.field.kinstone:count(list[k + 1])
      if i == 0 and (col == 3 or col == 4) then n = n - 1 end
      if n > 0 then self:drawPiece(list[k + 1], n, x, y) end
    end
    u = u + 0x17
  end
  -- KinstoneMenu_080A4080: the header, the two name plates, the arrows
  p:drawDirect(0x1FB, 0, { x = 0x40, y = 0x10, _4 = 0, _6 = 0, _8 = 0x400 })
  p:drawDirect(0x1FA, 0, { x = 0x50, y = 0x94, _4 = 0, _6 = 0, _8 = 0x480 })
  p:drawDirect(0x1FA, 1, { x = 0xB8, y = 0x94, _4 = 0, _6 = 0, _8 = 0x4A0 })
  local a = band(rshift(self.ticks, 2), 0xE)
  local b0, b1 = t and t.u8(KM.ARROWS + a) or 0, t and t.u8(KM.ARROWS + a + 1) or 0
  local last = #list - 1
  if last > 0 then
    local at = math.floor(self.pos / 0x10000)
    if at ~= last then p:drawDirect(0x1FA, 3, { x = 10 - b0, y = b1 + 0x77, _4 = 0, _6 = 0, _8 = 0x4E0 }) end
    if at ~= 0 then p:drawDirect(0x1FA, 2, { x = 10 - b0, y = 0x27 - b1, _4 = 0, _6 = 0, _8 = 0x4E0 }) end
  end
  self.ui:draw()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  g.draw(p:render(), 0, 0)
  -- the fuser (KinstoneMenu_080A4528: its own copy at ($CC, $60))
  local e = self.opts.entity
  if e and e.sprite then
    local frame = e.staticFrame or (e.anim and e.anim.frame)
    if frame and frame ~= 0xFF then
      local img, ox, oy = self.A:spriteFrame(e.sprite, frame, e.palette,
        "e" .. tostring(e.def and e.def.palette) .. ":" .. tostring(e.kind), e.gfx)
      if img then g.draw(img, 0xCC + ox, 0x60 + oy) end
    end
  end
  -- WIN0 brightness (BLDCNT $3F90, BLDY bright): c + (31 - c) * y / 16
  if self.bright then
    g.setColor(1, 1, 1, self.bright / 16)
    g.rectangle("fill", 0x68, 0x40, 0x87 - 0x68, 0x5F - 0x40)
  end
  if self.fade then
    g.setColor(1, 1, 1, math.min(1, self.fade / 256))
    g.rectangle("fill", 0, 0, 240, 160)
  end
  g.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- the fuse-info flow (scripted fusers: ScriptCommand_0807EA4C starts it,
-- UpdateFusion steps it)
-- ---------------------------------------------------------------------------
-- InitializeFuseInfo(entity, text, cancelled, fusing)
function KM.initFuse(field, entity, text, cancelled, fusing)
  field.fuseInfo = { entity = entity, text = text or 0, cancelled = cancelled or 0, fusing = fusing or 0,
                     kinstoneId = entity and entity.fuser or 0, action = 0, state = 0 }
end

local function messageFrom(field, idx, entity)
  if idx and idx ~= 0 then field:message(idx, entity) end
end

-- PerformFuseAction: returns the fusion state (1 cancelled, 2 fused,
-- 3-6 in progress)
function KM.performFuse(field)
  local fi = field.fuseInfo
  if not fi then return 1 end
  if fi.action == 0 then
    messageFrom(field, fi.text, fi.entity)
    fi.state, fi.action = 3, 1
  elseif fi.action == 1 then
    if not field:messageActive() then
      fi.state, fi.action = 4, 2
      field:sound(0x6B)
      local k = field.kinstone
      k.active = true
      k.window = KM.new(field, { target = fi.kinstoneId, entity = fi.entity, name = fi.name,
        onDone = function(state) fi.state = state; k.window = nil; k.active = false end })
    end
  elseif fi.action == 2 then
    local idx
    if fi.state == 5 then idx = fi.cancelled elseif fi.state == 6 then idx = fi.fusing end
    if idx then messageFrom(field, idx, fi.entity); fi.action = 3 end
  elseif fi.action == 3 then
    if not field:messageActive() then
      fi.state = fi.state == 6 and 2 or 1
      fi.action = 4
    end
  end
  local st = fi.state
  if st == 1 or st == 2 then field.fuseInfo = nil end
  return st
end

return KM
