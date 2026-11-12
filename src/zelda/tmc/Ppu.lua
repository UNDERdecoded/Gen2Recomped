-- A small GBA picture unit for the cartridge's menus and screens.
--
-- The menu code (src/menu/*.c, fileselect.c, title.c, gameOverTask.c) sets
-- BG controls, loads gfx groups (LoadGfxGroup: tiles into VRAM, tile maps
-- into the EWRAM BG buffers) and palette groups, then draws OAM pieces
-- with DrawDirect.  This module keeps those as the cartridge does --
-- 96 KB of VRAM, the BG buffers in a 256 KB EWRAM, 512 palette entries,
-- an OAM list -- and composes the 240x160 picture the way the GBA does:
-- text-mode BGs and OBJs by priority, BG3 at the back within a priority,
-- OBJs in front of BGs of the same priority, lower OAM slots on top.
--
-- gScreen.bgN.subTileMap -> VRAM: at each `render` a BG flagged `updated`
-- copies its buffer to its screen base (sub_08016CA8; the size follows
-- the control's screen size, gUnk_080B2CD8).

local ffi = require("ffi")
local bit = require("bit")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local Layout = require("src.zelda.tmc.Layout")

local Ppu = {}
Ppu.__index = Ppu

local W, H = 240, 160
Ppu.W, Ppu.H = W, H
local VRAM, EWRAM, PALRAM = 0x06000000, 0x02000000, 0x05000000
local MAP_BYTES = { [0] = 0x800, 0x1000, 0x1000, 0x2000 } -- gUnk_080B2CD8

local OBJ_DIMS = {
  [0] = { { 8, 8 }, { 16, 16 }, { 32, 32 }, { 64, 64 } },
  [1] = { { 16, 8 }, { 32, 8 }, { 32, 16 }, { 64, 32 } },
  [2] = { { 8, 16 }, { 8, 32 }, { 16, 32 }, { 32, 64 } },
}
Ppu.OBJ_DIMS = OBJ_DIMS

function Ppu.new(assets)
  local self = setmetatable({ A = assets }, Ppu)
  self.vram = ffi.new("uint8_t[?]", 0x18000)
  self.ewram = ffi.new("uint8_t[?]", 0x40000)
  self.pal = ffi.new("uint16_t[512]")
  self.idx = ffi.new("uint16_t[?]", W * H)  -- palette index per pixel
  self.prio = ffi.new("uint8_t[?]", W * H)
  self.bg = {}
  local bufs = { [0] = Layout.gBG0Buffer, Layout.gBG1Buffer, Layout.gBG2Buffer, Layout.gBG3Buffer }
  for i = 0, 3 do self.bg[i] = { control = 0, x = 0, y = 0, buf = bufs[i], updated = false } end
  self.dispcnt = 0x1F40
  self.oam = {}
  self.texts = {}
  -- (headless tests: no picture, the state still works)
  if love and love.image and love.graphics then
    self.data = love.image.newImageData(W, H)
    self.image = love.graphics.newImage(self.data)
    self.image:setFilter("nearest", "nearest")
  end
  self.groupBlob = nil
  return self
end

-- ---------------------------------------------------------------------------
-- memory
-- ---------------------------------------------------------------------------
-- copy `len` bytes of string `s` from byte `off` (0-based) to bus address
function Ppu:write(dest, s, off, len)
  off, len = off or 0, len or #s
  local base, size, region
  if dest >= VRAM and dest < VRAM + 0x18000 then
    region, base, size = self.vram, VRAM, 0x18000
  elseif dest >= EWRAM and dest < EWRAM + 0x40000 then
    region, base, size = self.ewram, EWRAM, 0x40000
  elseif dest >= PALRAM and dest < PALRAM + 0x400 then
    local p = ffi.cast("const uint8_t*", s) + off
    for i = 0, math.min(len, 0x400 - (dest - PALRAM)) / 2 - 1 do
      self.pal[(dest - PALRAM) / 2 + i] = p[2 * i] + 256 * p[2 * i + 1]
    end
    return
  else
    return
  end
  local o = dest - base
  len = math.min(len, size - o)
  if len > 0 then ffi.copy(region + o, ffi.cast("const uint8_t*", s) + off, len) end
  if region == self.vram then self.dirty = true end
end

function Ppu:fill(dest, len, v)
  if dest >= VRAM and dest < VRAM + 0x18000 then ffi.fill(self.vram + (dest - VRAM), math.min(len, 0x18000 - (dest - VRAM)), v or 0)
  elseif dest >= EWRAM and dest < EWRAM + 0x40000 then ffi.fill(self.ewram + (dest - EWRAM), math.min(len, 0x40000 - (dest - EWRAM)), v or 0) end
end

function Ppu:u16(addr)
  if addr >= EWRAM and addr < EWRAM + 0x40000 then
    local o = addr - EWRAM
    return self.ewram[o] + 256 * self.ewram[o + 1]
  elseif addr >= VRAM and addr < VRAM + 0x18000 then
    local o = addr - VRAM
    return self.vram[o] + 256 * self.vram[o + 1]
  end
  return 0
end

function Ppu:set16(addr, v)
  local r, o
  if addr >= EWRAM and addr < EWRAM + 0x40000 then r, o = self.ewram, addr - EWRAM
  elseif addr >= VRAM and addr < VRAM + 0x18000 then r, o = self.vram, addr - VRAM
  else return end
  r[o] = band(v, 0xFF); r[o + 1] = band(rshift(v, 8), 0xFF)
  if r == self.vram then self.dirty = true end
end

-- MemClear of the four BG buffers (the menus' first step)
function Ppu:clearBuffers(which)
  for i = 0, 3 do
    if not which or which[i] then
      self:fill(self.bg[i].buf, i == 3 and 0x1000 or 0x800, 0)
    end
  end
end

-- ---------------------------------------------------------------------------
-- LoadGfxGroup / LoadPaletteGroup / LoadPalettes
-- ---------------------------------------------------------------------------
function Ppu:loadGfxGroup(g)
  local A = self.A
  local list = A.manifest.gfxGroups and A.manifest.gfxGroups[g]
  if not list then return false end
  self.groupBlob = self.groupBlob or A.store:read("gfxgroups.bin") or ""
  for _, it in ipairs(list) do self:write(it[1], self.groupBlob, it[2], it[3]) end
  return true
end

-- LoadPalettes(&gGlobalGfxAndPalettes[id * 32], dest, n): dest 0-15 BG
-- banks, 16-31 OBJ banks
function Ppu:loadPalettes(id, dest, n)
  local raw = self.A.palRaw or self.A.store:read("pal.bin") or ""
  self.A.palRaw = raw
  for k = 0, n * 16 - 1 do
    local o = id * 32 + k * 2 + 1
    local lo, hi = raw:byte(o), raw:byte(o + 1)
    if lo and dest * 16 + k < 512 then self.pal[dest * 16 + k] = lo + 256 * hi end
  end
  self.dirty = true
end

function Ppu:loadPaletteGroup(g)
  local list = self.A.manifest.paletteGroups and self.A.manifest.paletteGroups[g]
  if not list then return false end
  for _, e in ipairs(list) do self:loadPalettes(e[1], e[2], e[3]) end
  return true
end

function Ppu:setColor(i, c) self.pal[i] = c; self.dirty = true end

-- a menu data table from menudata.bin (Layout.MENU_DATA): returns a reader
function Ppu:table(name)
  local A = self.A
  local e = A.manifest.menuData and A.manifest.menuData[name]
  if not e then return nil end
  A.menuBlob = A.menuBlob or A.store:read("menudata.bin") or ""
  local blob, base, off = A.menuBlob, e[1], e[2]
  local t = {}
  function t.u8(a) return blob:byte(off + (a - base) + 1) or 0 end
  function t.s8(a) local v = t.u8(a) return v >= 128 and v - 256 or v end
  function t.u16(a) return t.u8(a) + 256 * t.u8(a + 1) end
  function t.s16(a) local v = t.u16(a) return v >= 0x8000 and v - 0x10000 or v end
  function t.u32(a) return t.u16(a) + 65536 * t.u16(a + 2) end
  function t.str(a, n) return blob:sub(off + (a - base) + 1, off + (a - base) + n) end
  t.base, t.size = base, e[3]
  return t
end

-- ---------------------------------------------------------------------------
-- OAM (DrawDirect, arm_sub_080ADA04)
-- ---------------------------------------------------------------------------
function Ppu:flush() self.oam = {}; self.texts = {} end

-- one raw OAM entry
function Ppu:obj(a0, a1, a2) self.oam[#self.oam + 1] = { a0, a1, a2 } end

-- DrawDirect(sprite, frame) with gOamCmd {x, y, _4, _6, _8}: each piece
-- of gFrameObjLists[sprite][frame] (x, y, flags, tile, tile high/palette)
-- placed at cmd.x/y, attr0 |= _4, attr1 |= _6 (flips mirror the pieces),
-- attr2 = _8 + tile (+ high byte; flags bit 0 drops _8's palette)
function Ppu:drawDirect(sprite, frame, cmd)
  if frame == 0xFF then return end
  local s = self.A:sprite(sprite)
  local objs = s and s.objs[frame]
  if not objs then return end
  local a4, a6, a8 = cmd._4 or 0, cmd._6 or 0, cmd._8 or 0
  local hflipCmd, vflipCmd = band(a6, 0x1000) ~= 0, band(a6, 0x2000) ~= 0
  local affine = band(a4, 0x300) ~= 0
  for _, o in ipairs(objs) do
    local b3 = o[3]
    local shape, size = rshift(b3, 6), band(rshift(b3, 4), 3)
    local dims = OBJ_DIMS[shape] and OBJ_DIMS[shape][size + 1] or { 8, 8 }
    local x, y = o[1], o[2]
    if not affine then
      if vflipCmd then y = -y - dims[2] end
      if hflipCmd then x = -x - dims[1] end
    end
    x, y = x + cmd.x, y + cmd.y
    local a0 = bor(band(y, 0xFF), a4, lshift(band(b3, 0xC0), 8))
    local a1 = bor(band(x, 0x1FF), band(a6, 0xFFFF))
    a1 = bxor(a1, lshift(band(b3, 0x3C), 10)) -- flips + size into attr1 bits 12-15
    local a2 = a8 + o[4]
    if band(b3, 1) ~= 0 then a2 = band(a2, 0x0FFF) end
    a2 = band(a2 + lshift(o[5], 8), 0xFFFF)
    self.oam[#self.oam + 1] = { a0, a1, a2 }
  end
end

-- text drawn with the cartridge font into the picture (menus render their
-- strings into BG tiles; this places the same glyphs at the same spot):
-- ink / shadow are palette indexes (0-511)
function Ppu:text(str, x, y, ink, shadow, prio)
  self.texts[#self.texts + 1] = { str = str, x = x, y = y, ink = ink, shadow = shadow, prio = prio or 0 }
end

-- ---------------------------------------------------------------------------
-- compose
-- ---------------------------------------------------------------------------
-- an affine BG (mode 1 BG2, mode 2 BG2 / BG3): 256 colours, one map byte
-- a tile, (128 << size) pixels square, wrap with control bit 13.
-- b.affine = {pa, pb, pc, pd, x, y}: 8.8 steps and the 24.8 origin
-- (BgAffineSet's output, title.c UpdateSwordBgAffineData)
local function affineLayer(self, n, prio)
  local b = self.bg[n]
  local c = b.control
  local charBase = band(rshift(c, 2), 3) * 0x4000
  local screenBase = band(rshift(c, 8), 0x1F) * 0x800
  local size = lshift(128, rshift(c, 14))
  local tilesW = size / 8
  local wrap = band(c, 0x2000) ~= 0
  local af = b.affine or { 256, 0, 0, 256, 0, 0 }
  local pa, pb, pc, pd, ox, oy = af[1], af[2], af[3], af[4], af[5], af[6]
  local vram, idx, pr = self.vram, self.idx, self.prio
  local en, nbit = self.winEn, lshift(1, n)
  local lines = b.affineLines -- round 6: an HBlank DMA of one BgAffineSet a line
  for sy = 0, H - 1 do
    local rx, ry = ox + pb * sy, oy + pd * sy
    local ln = lines and lines[sy]
    if ln then pa, pb, pc, pd, rx, ry = ln[1], ln[2], ln[3], ln[4], ln[5], ln[6] end
    for sx = 0, W - 1 do
      local tx, ty = math.floor((rx + pa * sx) / 256), math.floor((ry + pc * sx) / 256)
      if wrap then tx, ty = tx % size, ty % size end
      if tx >= 0 and tx < size and ty >= 0 and ty < size then
        local tile = vram[screenBase + rshift(ty, 3) * tilesW + rshift(tx, 3)]
        local a = charBase + tile * 64 + band(ty, 7) * 8 + band(tx, 7)
        local ci = a < 0x10000 and vram[a] or 0
        local o = sy * W + sx
        if ci ~= 0 and (not en or band(en[o], nbit) ~= 0) then idx[o] = ci; pr[o] = prio end
      end
    end
  end
end

local function bgLayer(self, n, prio)
  local mode = band(self.dispcnt, 7)
  if (mode == 1 and n == 2) or (mode == 2 and n >= 2) then return affineLayer(self, n, prio) end
  local b = self.bg[n]
  local c = b.control
  local charBase = band(rshift(c, 2), 3) * 0x4000
  local screenBase = band(rshift(c, 8), 0x1F) * 0x800
  local is8 = band(c, 0x80) ~= 0
  local sz = rshift(c, 14)
  local wpx = (sz == 1 or sz == 3) and 512 or 256
  local hpx = (sz == 2 or sz == 3) and 512 or 256
  local vram, idx, pr = self.vram, self.idx, self.prio
  local hofs, vofs = b.x, b.y
  local en, nbit = self.winEn, lshift(1, n) -- OBJ window (WINOUT) enables
  for sy = 0, H - 1 do
    local y = (sy + vofs) % hpx
    local blockY = rshift(y, 8)
    local ty, py = band(rshift(y, 3), 31), band(y, 7)
    for sx = 0, W - 1 do
      local x = (sx + hofs) % wpx
      local blk = rshift(x, 8) + (blockY == 1 and (wpx == 512 and 2 or 1) or 0)
      local mo = screenBase + blk * 0x800 + (ty * 32 + band(rshift(x, 3), 31)) * 2
      local e = vram[mo] + 256 * vram[mo + 1]
      local tile = band(e, 0x3FF)
      local px = band(x, 7)
      local yy = py
      if band(e, 0x400) ~= 0 then px = 7 - px end
      if band(e, 0x800) ~= 0 then yy = 7 - yy end
      local ci
      if is8 then
        local a = charBase + tile * 64 + yy * 8 + px
        ci = a < 0x10000 and vram[a] or 0
        local o = sy * W + sx
        if ci ~= 0 and (not en or band(en[o], nbit) ~= 0) then
          idx[o] = ci; pr[o] = prio
        end
      else
        local a = charBase + tile * 32 + yy * 4 + rshift(px, 1)
        local byte = a < 0x10000 and vram[a] or 0
        ci = band(px, 1) == 0 and band(byte, 15) or rshift(byte, 4)
        local o = sy * W + sx
        if ci ~= 0 and (not en or band(en[o], nbit) ~= 0) then
          idx[o] = rshift(e, 12) * 16 + ci; pr[o] = prio
        end
      end
    end
  end
end

-- the OBJ window (DISPCNT bit 15): OBJs in mode 2 draw nothing, their
-- opaque pixels select WINOUT's high byte of layer enables, every other
-- pixel the low byte.  Returns a per-pixel enable mask (bits 0-3 BG, 4 OBJ).
local function objWindow(self)
  local en = self.winEnBuf or ffi.new("uint8_t[?]", W * H)
  self.winEnBuf = en
  local lo, hi = band(self.winout, 0x3F), band(rshift(self.winout, 8), 0x3F)
  ffi.fill(en, W * H, lo)
  local vram = self.vram
  for _, o in ipairs(self.oam) do
    local a0, a1, a2 = o[1], o[2], o[3]
    if band(a0, 0x300) ~= 0x200 and band(a0, 0xC00) == 0x800 then
      local dims = OBJ_DIMS[rshift(a0, 14)] and OBJ_DIMS[rshift(a0, 14)][rshift(a1, 14) + 1]
      if dims then
        local w, h = dims[1], dims[2]
        local x, y = band(a1, 0x1FF), band(a0, 0xFF)
        if x >= 256 then x = x - 512 end
        if y >= 160 then y = y - 256 end
        local hf = band(a0, 0x100) == 0 and band(a1, 0x1000) ~= 0
        local vf = band(a0, 0x100) == 0 and band(a1, 0x2000) ~= 0
        local tile, tw = band(a2, 0x3FF), w / 8
        for ly = 0, h - 1 do
          local sy = y + ly
          if sy >= 0 and sy < H then
            local ry = vf and (h - 1 - ly) or ly
            for lx = 0, w - 1 do
              local sx = x + lx
              if sx >= 0 and sx < W then
                local rx = hf and (w - 1 - lx) or lx
                local a = 0x10000 + (tile + rshift(ry, 3) * tw + rshift(rx, 3)) * 32 + band(ry, 7) * 4 + rshift(band(rx, 7), 1)
                local byte = a < 0x18000 and vram[a] or 0
                local ci = band(rx, 1) == 0 and band(byte, 15) or rshift(byte, 4)
                if ci ~= 0 then en[sy * W + sx] = hi end
              end
            end
          end
        end
      end
    end
  end
  return en
end

local function objLayer(self, prio)
  local vram, idx = self.vram, self.idx
  local en = self.winEn
  local oam = self.oam
  for i = #oam, 1, -1 do
    local a0, a1, a2 = oam[i][1], oam[i][2], oam[i][3]
    if band(rshift(a2, 10), 3) == prio and band(a0, 0x300) ~= 0x200 and band(a0, 0xC00) ~= 0x800 then
      local shape, size = rshift(a0, 14), rshift(a1, 14)
      local dims = OBJ_DIMS[shape] and OBJ_DIMS[shape][size + 1]
      if dims then
        local w, h = dims[1], dims[2]
        local x, y = band(a1, 0x1FF), band(a0, 0xFF)
        if x >= 256 then x = x - 512 end
        if y >= 160 then y = y - 256 end
        local hf = band(a0, 0x100) == 0 and band(a1, 0x1000) ~= 0
        local vf = band(a0, 0x100) == 0 and band(a1, 0x2000) ~= 0
        local is8 = band(a0, 0x2000) ~= 0
        local tile = band(a2, 0x3FF)
        local bank = rshift(a2, 12)
        -- affine OBJs (attr0 bit 8): matrix (attr1 >> 9) & 31 from
        -- self.affine[n] = {pa, pb, pc, pd} (8.8), about the OBJ's centre
        local aff = band(a0, 0x100) ~= 0 and (self.affine and self.affine[band(rshift(a1, 9), 0x1F)] or { 256, 0, 0, 256 })
        local tw = w / 8
        for ly = 0, h - 1 do
          local sy = y + ly
          if sy >= 0 and sy < H then
            local ry = vf and (h - 1 - ly) or ly
            for lx = 0, w - 1 do
              local sx = x + lx
              local rx = hf and (w - 1 - lx) or lx
              if aff then
                local ry0 = ry
                local dx, dy = lx - w / 2, ly - h / 2
                rx = math.floor((aff[1] * dx + aff[2] * dy) / 256) + w / 2
                ry = math.floor((aff[3] * dx + aff[4] * dy) / 256) + h / 2
                if rx < 0 or rx >= w or ry < 0 or ry >= h then sx = -1 end
                if sx < 0 then ry = ry0 end
              end
              if sx >= 0 and sx < W then
                local t = rshift(ry, 3) * tw + rshift(rx, 3)
                local ci
                if is8 then
                  local a = 0x10000 + (tile + t * 2) * 32 + band(ry, 7) * 8 + band(rx, 7)
                  ci = a < 0x18000 and vram[a] or 0
                  if ci ~= 0 and (not en or band(en[sy * W + sx], 16) ~= 0) then idx[sy * W + sx] = 256 + ci end
                else
                  local a = 0x10000 + (tile + t) * 32 + band(ry, 7) * 4 + rshift(band(rx, 7), 1)
                  local byte = a < 0x18000 and vram[a] or 0
                  ci = band(rx, 1) == 0 and band(byte, 15) or rshift(byte, 4)
                  if ci ~= 0 and (not en or band(en[sy * W + sx], 16) ~= 0) then idx[sy * W + sx] = 256 + bank * 16 + ci end
                end
              end
            end
          end
        end
      end
    end
  end
end

local function textLayer(self, prio)
  local A = self.A
  A.fontRaw = A.fontRaw or A.store:read("font.bin") or ""
  local blob = A.fontRaw
  local Font = require("src.zelda.tmc.Font")
  local idx = self.idx
  for _, t in ipairs(self.texts) do
    if t.prio == prio then
      local x = t.x
      for k = 1, #t.str do
        local c = t.str:byte(k)
        local lead, w = Font.extent(blob, c)
        if c == 0x20 and w == 0 then w = 4 end
        for col = 0, w - 1 do
          for row = 0, 15 do
            local byte = blob:byte(c * 64 + row * 4 + math.floor((lead + col) / 2) + 1) or 0xFF
            local v = (lead + col) % 2 == 0 and byte % 16 or math.floor(byte / 16)
            local sx, sy = x + col, t.y + row
            if sx >= 0 and sx < W and sy >= 0 and sy < H then
              if v == 0xE then idx[sy * W + sx] = t.ink
              elseif v ~= 0 and v ~= 0xF and t.shadow then idx[sy * W + sx] = t.shadow end
            end
          end
        end
        x = x + w + 1
      end
    end
  end
end

-- the VBlank copy of updated BG buffers to their screen blocks
function Ppu:vblank()
  for n = 0, 3 do
    local b = self.bg[n]
    if b.updated and b.buf then
      b.updated = false
      local dest = band(lshift(b.control, 3), 0xF800)
      local len = MAP_BYTES[rshift(b.control, 14)]
      local o = b.buf - EWRAM
      ffi.copy(self.vram + dest, self.ewram + o, math.min(len, 0x40000 - o))
    end
  end
end

-- compose the picture; returns the LÖVE image (240x160)
-- `slot` (optional) renders into a second picture (a blend's other half)
function Ppu:render(slot)
  if slot then
    self.slots = self.slots or {}
    local s = self.slots[slot]
    if not s then
      s = { data = love.image.newImageData(W, H) }
      s.image = love.graphics.newImage(s.data); s.image:setFilter("nearest", "nearest")
      self.slots[slot] = s
    end
    local d, i, k = self.data, self.image, self.lastKey
    self.data, self.image, self.lastKey = s.data, s.image, s.lastKey
    self.dirty = true
    local out = self:render()
    s.lastKey = self.lastKey
    self.data, self.image, self.lastKey = d, i, k
    self.dirty = true
    return out
  end
  local key = {}
  for i, o in ipairs(self.oam) do key[i] = o[1] .. "," .. o[2] .. "," .. o[3] end
  for _, t in ipairs(self.texts) do key[#key + 1] = t.str .. t.x .. "," .. t.y end
  for n = 0, 3 do if self.bg[n].updated then self.dirty = true end end
  key = table.concat(key, ";") .. "|" .. self.dispcnt .. "|" .. tostring(self.winout)
  if self.blend then key = key .. "|b" .. (self.blend.t1 or 0) .. "," .. (self.blend.eva or 0) .. "," .. (self.blend.evb or 0) end
  for n = 2, 3 do
    local af = self.bg[n].affine
    if af then key = key .. "|a" .. n .. ":" .. table.concat(af, ",") end
  end
  if not self.dirty and key == self.lastKey then return self.image end
  self.lastKey, self.dirty = key, false
  self:vblank()
  local idx = self.idx
  local dc = self.dispcnt
  local function composeIdx(d)
    ffi.fill(idx, W * H * 2, 0)
    ffi.fill(self.prio, W * H, 4)
    self.winEn = (self.winout and band(d, 0x8000) ~= 0) and objWindow(self) or nil
    for prio = 3, 0, -1 do
      for n = 3, 0, -1 do
        if band(d, lshift(0x100, n)) ~= 0 and band(self.bg[n].control, 3) == prio then bgLayer(self, n, prio) end
      end
      if prio == 0 then textLayer(self, 0) end
      if band(d, 0x1000) ~= 0 then objLayer(self, prio) end
      if prio ~= 0 then textLayer(self, prio) end
    end
  end
  -- colour special effects (BLDCNT alpha blend): self.blend = {t1 = BG
  -- mask (bit 4 OBJ), eva, evb}.  The first-target layers' pixel, when it
  -- is the top one, mixes eva/16 of itself with evb/16 of what is under it.
  local bl = self.blend
  local topA, under
  if bl then
    local t1 = band(bl.t1 or 0, 0x1F)
    composeIdx(bor(band(dc, 0x80FF), lshift(t1, 8)))
    topA = ffi.new("uint16_t[?]", W * H); ffi.copy(topA, idx, W * H * 2)
    composeIdx(band(dc, bit.bnot(lshift(t1, 8))))
    under = ffi.new("uint16_t[?]", W * H); ffi.copy(under, idx, W * H * 2)
  end
  composeIdx(dc)
  local ptr = ffi.cast("uint8_t*", self.data:getFFIPointer())
  local pal = self.pal
  local clear = self.transparent
  if bl then
    local eva, evb = bl.eva or 16, bl.evb or 0
    for i = 0, W * H - 1 do
      local a = topA[i]
      if a ~= 0 and a == idx[i] then
        local c1, c2 = pal[a], pal[under[i]]
        local r = math.min(31, rshift(band(c1, 31) * eva + band(c2, 31) * evb, 4))
        local g = math.min(31, rshift(band(rshift(c1, 5), 31) * eva + band(rshift(c2, 5), 31) * evb, 4))
        local b = math.min(31, rshift(band(rshift(c1, 10), 31) * eva + band(rshift(c2, 10), 31) * evb, 4))
        ptr[i * 4] = lshift(r, 3) + rshift(r, 2)
        ptr[i * 4 + 1] = lshift(g, 3) + rshift(g, 2)
        ptr[i * 4 + 2] = lshift(b, 3) + rshift(b, 2)
        ptr[i * 4 + 3] = 255
        idx[i] = 0xFFFF -- done
      end
    end
  end
  for i = 0, W * H - 1 do
    if idx[i] == 0xFFFF then goto nextPixel end
    local c = pal[idx[i]]
    if clear and idx[i] == 0 then ptr[i * 4 + 3] = 0 goto nextPixel end
    local r, g, b = band(c, 31), band(rshift(c, 5), 31), band(rshift(c, 10), 31)
    ptr[i * 4] = lshift(r, 3) + rshift(r, 2)
    ptr[i * 4 + 1] = lshift(g, 3) + rshift(g, 2)
    ptr[i * 4 + 2] = lshift(b, 3) + rshift(b, 2)
    ptr[i * 4 + 3] = 255
    ::nextPixel::
  end
  self.image:replacePixels(self.data)
  return self.image
end

-- ---------------------------------------------------------------------------
-- ShowTextBox (text.c): a message drawn into BG tiles as the cartridge does.
-- A Font descriptor {dest (BG buffer entry), gfx_dest (VRAM), buffer, gfx_src
-- (map entry base), width, flags (bit 0 centre, 1 small border, 3 border,
-- 4-7 border type), fill, charColor, line spacing, stylized} places each
-- line as 8x16 cells (two tiles, top then bottom, map rows n and n+1).
-- Glyph nibbles go through gUnk_0810942E[fill][charColor * 2] to colours.
-- ---------------------------------------------------------------------------
local ARGS = { [1] = 1, [2] = 1, [3] = 2, [4] = 1, [5] = 1, [6] = 1, [7] = 2,
               [8] = 1, [9] = 1, [0x0C] = 1, [0x0F] = 1 }

-- a Font descriptor read from a menu data table at `addr`
function Ppu:font(tableName, addr)
  local t = self:table(tableName)
  if not t then return nil end
  local fl = t.u8(addr + 19)
  return { dest = t.u32(addr), gfx_dest = t.u32(addr + 4), buffer = t.u32(addr + 8),
           gfx_src = t.u16(addr + 16), width = t.u8(addr + 18),
           centre = band(fl, 1) ~= 0, sm_border = band(fl, 2) ~= 0,
           draw_border = band(fl, 8) ~= 0, border_type = rshift(fl, 4),
           fill = t.u8(addr + 20), charColor = t.u8(addr + 21), spacing = t.u8(addr + 22),
           stylized = t.u8(addr + 23) }
end

-- the font banks (gUnk_08109248): 0/1 ASCII, 2 the upper half, 3 symbols,
-- 4, and 5-8 double-width glyphs (index << 1)
local FONT_BASE = 0x08692F60
local BANKS = { [0] = 0x08692F60, 0x08692F60, 0x086978E0, 0x08696F60, 0x086AAEE0,
                0x086998E0, 0x086A18E0, 0x086A2A60, 0x086A2EE0 }

local function glyphBlob(self)
  if not self.A.fontBanks then
    local t = self:table("fontBanks")
    self.A.fontBanks = t and t.str(t.base, t.size) or self.A.store:read("font.bin") or ""
  end
  return self.A.fontBanks
end

-- sub_0805F25C: byte offset of glyph `code` ((bank << 8) | index)
local function glyphOffset(code)
  local bank, idx = band(rshift(code, 8), 0xF), band(code, 0xFF)
  if bank <= 1 and idx > 0x7F then idx = idx - 0x80; bank = 2 end
  if bank >= 5 then idx = idx * 2 end
  return (BANKS[bank] or FONT_BASE) - FONT_BASE + idx * 64, bank >= 5
end

-- message bytes -> lines of {code, colour} (GetCharacter): $0A ends a line,
-- $02 c colour, $06 n a variable string (vars[n]), $0B-$0F x a glyph of
-- bank 4 / 7 / 5 / 6 / 3, other control codes skip their arguments
local EXT = { [0x0B] = 0x400, [0x0C] = 0x700, [0x0D] = 0x500, [0x0E] = 0x600, [0x0F] = 0x300 }
local function tokenize(bytes, vars)
  local lines, cur = {}, {}
  local colour = nil
  local function run(s, depth)
    local i = 1
    while i <= #s do
      local c = s:byte(i); i = i + 1
      if c == 0 then break
      elseif c == 0x0A then lines[#lines + 1] = cur; cur = {}
      elseif c == 0x02 then colour = s:byte(i) or 0; i = i + 1
      elseif c == 0x06 then
        local n = s:byte(i) or 0; i = i + 1
        if n == 5 then i = i + 2
        elseif vars and vars[n] and depth < 3 then run(vars[n], depth + 1) end
      elseif EXT[c] then
        cur[#cur + 1] = { EXT[c] + (s:byte(i) or 0), colour }; i = i + 1
      elseif c < 0x20 then
        local n = ARGS[c] or 0
        if c == 4 and s:byte(i) == 0x10 then n = 2 end
        if c == 5 and s:byte(i) ~= 0xFF then n = 2 end
        i = i + n
      else
        cur[#cur + 1] = { c, colour }
      end
    end
  end
  run(bytes, 0)
  lines[#lines + 1] = cur
  return lines
end
Ppu.tokenize = tokenize

-- sub_0805F7A0 on the glyph's first row: leading empty columns and width
local function extentAt(blob, off)
  local function nib(col)
    local b = blob:byte(off + rshift(col, 1) + 1) or 0xFF
    return band(col, 1) == 0 and band(b, 15) or rshift(b, 4)
  end
  local lead = 0
  while lead < 8 and nib(lead) == 0xF do lead = lead + 1 end
  local w = 0
  while lead + w < 8 and nib(lead + w) ~= 0xF do w = w + 1 end
  return lead, w
end

local function glyphWidth(blob, code)
  local off, wide = glyphOffset(code)
  local lead, w = extentAt(blob, off)
  if w == 0 and code == 0x20 then w = 4 end
  if wide then local _, w2 = extentAt(blob, off + 64); w = w + w2 end
  return lead, w
end

-- the fill byte for a fill colour (sub_0805F8F8)
function Ppu:fillByte(idx)
  local colours, fills = self:table("textColors"), self:table("textFill")
  local c = colours.u8(colours.base + idx * 0xC0 + 170)
  return fills.u8(fills.base + c * 4)
end

-- sub_0805F918(type, fill, dest): 7 tiles -- the border glyph's three 8x16
-- cells over the fill, coloured by gUnk_081094CE[fill]
function Ppu:borderTiles(btype, fill, dest)
  local colours = self:table("textColors")
  local borders = self:table("textBorders")
  local fb = self:fillByte(fill)
  local tile = {}
  for k = 0, 0xDF do tile[k] = fb end
  local tab = colours.base + 0xA0 + fill * 0xC0
  for cell = 0, 2 do
    for row = 0, 15 do
      for col = 0, 7 do
        local gb = borders.u8(borders.base + btype * 0xE0 + cell * 0x40 + row * 4 + rshift(col, 1))
        local n = band(col, 1) == 0 and band(gb, 15) or rshift(gb, 4)
        local v = band(colours.u8(tab + n), 15)
        local o = cell * 64 + row * 4 + rshift(col, 1)
        if band(col, 1) == 0 then tile[o] = bor(band(tile[o], 0xF0), v)
        else tile[o] = bor(band(tile[o], 0x0F), lshift(v, 4)) end
      end
    end
  end
  local s = {}
  for k = 0, 0xDF do s[#s + 1] = string.char(tile[k]) end
  self:write(dest, table.concat(s))
end

-- glyphs into an 8x16-cell canvas (sub_0805F820 / sub_080026C4): `chars`
-- is a list of {code, colour or nil}; columns from `col`, at most `limit`
-- columns; returns the next column
-- `fixed` (WStruct.unk1 = 1, sub_0805F820): every glyph 8 columns from
-- its left edge, no proportional width
function Ppu:drawGlyphs(buf, bufLen, chars, col, limit, fill, charColor, stylized, fixed)
  local blob = glyphBlob(self)
  local colours = self:table("textColors")
  for _, ch in ipairs(chars) do
    if ch[2] and ch[2] < 0xE then charColor = ch[2] end
    local lead, w = glyphWidth(blob, ch[1])
    if fixed then lead, w = 0, 8 end
    local goff, wide = glyphOffset(ch[1])
    w = math.min(w, limit - col)
    local tab = colours.base + fill * 0xC0 + charColor * 32
    for j = 0, w - 1 do
      local sc, dc = lead + j, col + j
      local half = goff
      if wide and sc >= 8 then half, sc = goff + 64, sc - 8 end
      local o0 = rshift(dc, 3) * 64 + rshift(band(dc, 7), 1)
      for row = 0, 15 do
        local gb = blob:byte(half + row * 4 + rshift(sc, 1) + 1) or 0xFF
        local n = band(sc, 1) == 0 and band(gb, 15) or rshift(gb, 4)
        local v = band(colours.u8(tab + n), 15)
        local o = o0 + row * 4
        if o < bufLen then
          if band(dc, 1) == 0 then buf[o] = bor(band(buf[o], 0xF0), v)
          else buf[o] = bor(band(buf[o], 0x0F), lshift(v, 4)) end
        end
      end
    end
    if w > 0 then col = col + w end
    if stylized == 1 and col > 1 then col = col - 1 end
  end
  return col
end

function Ppu:showTextBox(bytes, font, vars)
  if type(bytes) == "number" then bytes = self.A:message(bytes) end
  if not bytes or not font then return end
  local f = {}
  for k, v in pairs(font) do f[k] = v end
  local blob = glyphBlob(self)
  local colours = self:table("textColors")
  local fills = self:table("textFill")
  local function fillByte(idx)
    local c = colours.u8(colours.base + idx * 0xC0 + 170)
    return fills.u8(fills.base + c * 4)
  end
  local lines = tokenize(bytes, vars)
  local function lineWidth(l)
    local w = 0
    for _, ch in ipairs(l) do local _, gw = glyphWidth(blob, ch[1]) w = w + gw end
    if f.stylized % 4 == 1 and w > 1 then w = w - #l end
    return w
  end
  local fb = fillByte(f.fill)
  if f.draw_border then
    self:borderTiles(f.border_type, f.fill, f.gfx_dest)
    f.gfx_dest = f.gfx_dest + 0xE0
    local count, blank, maxw = 0, 0, 0
    for _, l in ipairs(lines) do
      local w = lineWidth(l)
      if w > maxw then maxw = w end
      if w ~= 0 then count = count + 1 else blank = blank + 1 end
    end
    local hgt = blank * f.spacing + count * 2
    local cw = math.min(maxw, f.width)
    cw = f.sm_border and band(cw + 7, -8) or f.width
    local frame = f.dest
    f.dest = f.dest + 0x40
    if f.centre then
      cw = band(cw + 15, -16)
      frame = frame - 2 * (rshift(cw, 4) + 1)
    else
      f.dest = f.dest + 2
    end
    cw = rshift(cw, 3)
    self:messageFrame(frame, cw, hgt, f.gfx_src)
    frame = frame + 2
    f.gfx_src = f.gfx_src + 7
    local fillEntry = f.gfx_src - 1
    for _ = 1, hgt do
      frame = frame + 0x40
      for k = 0, cw - 1 do self:set16(frame + 2 * k, fillEntry) end
    end
  end
  local bufLen = lshift(band(f.width + 7, 0x1F8), 3)
  for _, l in ipairs(lines) do
    local buf = ffi.new("uint8_t[?]", bufLen + 64)
    ffi.fill(buf, bufLen, fb)
    local lw = lineWidth(l)
    local col = f.centre and band(8 - rshift(lw + 1, 1), 7) or 0
    local drew = #l > 0
    col = self:drawGlyphs(buf, bufLen, l, col, f.width, f.fill, f.charColor, f.stylized % 4)
    if drew then
      local cells = math.floor((col + 7) / 8)
      local d = f.dest
      if f.centre then d = d - 2 * rshift(cells + 1, 1) end
      for k = 0, cells - 1 do
        self:set16(d + 2 * k, f.gfx_src); f.gfx_src = f.gfx_src + 1
        self:set16(d + 2 * k + 0x40, f.gfx_src); f.gfx_src = f.gfx_src + 1
      end
      f.dest = f.dest + 0x80
      self:write(f.gfx_dest, ffi.string(buf, cells * 64))
      f.gfx_dest = f.gfx_dest + cells * 64
    else
      f.dest = f.dest + f.spacing * 0x40
    end
  end
end

-- DispMessageFrame (message.c): corners `flags`, edges +1/+2, sides +3/+4
function Ppu:messageFrame(buf, width, height, flags)
  local top, bot = buf, buf + lshift(height, 6) + 0x40
  local function put(a, v) self:set16(a, band(v, 0xFFFF)) end
  put(top, flags); put(bot, bor(flags, 0x800)); top = top + 2; bot = bot + 2
  if width > 0 then
    put(top, flags + 1); put(bot, bor(flags + 1, 0x800)); top = top + 2; bot = bot + 2
    for _ = 1, width - 2 do
      put(top, flags + 2); put(bot, bor(flags + 2, 0x800)); top = top + 2; bot = bot + 2
    end
    put(top, bor(flags + 1, 0x400)); put(bot, bor(flags + 1, 0xC00)); top = top + 2; bot = bot + 2
  end
  put(top, bor(flags, 0x400)); put(bot, bor(flags, 0xC00))
  local l, r = buf + 0x40, top + 0x40
  if height > 0 then
    put(l, flags + 3); put(r, bor(flags + 3, 0x400)); l = l + 0x40; r = r + 0x40
    for _ = 1, height - 2 do
      put(l, flags + 4); put(r, bor(flags + 4, 0x400)); l = l + 0x40; r = r + 0x40
    end
    put(l, bor(flags + 3, 0x800)); put(r, bor(flags + 3, 0xC00))
  end
end

return Ppu
