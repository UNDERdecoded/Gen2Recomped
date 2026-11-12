-- Runtime side of the Minish Cap cache: the manifest, palettes, metatile
-- atlases per area tileset, room layer maps, collision, sprites and text.
--
-- Graphics are decoded the way the GBA's PPU would show them: an area
-- tileset is 48 KiB of 4bpp character memory; a metatile is four 8x8
-- subtiles (tonc screen-entry format: tile 0-9, hflip 10, vflip 11,
-- palette 12-15); the bottom layer reads characters from $06000000 (BG
-- control $1C42, char base 0) and the top layer from $06004000 ($1D45,
-- char base 1).  Each layer becomes one 512x1024 atlas of its 2048
-- metatiles, built on first use.

local bit = require("bit")
local band, rshift, bor, lshift = bit.band, bit.rshift, bit.bor, bit.lshift
local Store = require("src.zelda.tmc.Store")

local Assets = {}
Assets.__index = Assets

local hasFfi, ffi = pcall(require, "ffi")

local function u16(s, o) -- o is 0-based
  local lo, hi = s:byte(o + 1, o + 2)
  return (lo or 0) + (hi or 0) * 256
end

function Assets.new(root)
  local store = Store.new(root)
  local manifest, err = store:readTable("manifest.lua")
  if not manifest then error("Minish Cap cache unreadable: " .. tostring(err)) end
  local self = setmetatable({
    store = store, manifest = manifest,
    atlases = {}, rooms = {}, sprites = {}, spriteImages = {},
  }, Assets)
  self:loadPalettes()
  self:loadCollision()
  return self
end

-- ---------------------------------------------------------------------------
-- palettes
-- ---------------------------------------------------------------------------
local function bgr555(w)
  return band(w, 31) * 255 / 31, band(rshift(w, 5), 31) * 255 / 31, band(rshift(w, 10), 31) * 255 / 31
end

function Assets:loadPalettes()
  self.palRaw = self.store:read("pal.bin") or ""
end

-- palette N (16 colours) from the global bank, as {r,g,b} 0-255
function Assets:paletteColors(id)
  local out = {}
  local raw = self.palRaw
  for i = 0, 15 do
    local o = id * 32 + i * 2 + 1
    local lo, hi = raw:byte(o), raw:byte(o + 1)
    if lo then out[i] = { bgr555(lo + hi * 256) } else out[i] = { 0, 0, 0 } end
  end
  return out
end

-- Run LoadPaletteGroup(g) into a 32-palette buffer (0-15 BG, 16-31 OBJ)
function Assets:applyPaletteGroup(buffer, g)
  local list = self.manifest.paletteGroups[g]
  if not list then return buffer end
  for _, e in ipairs(list) do
    local pal, dest, n = e[1], e[2], e[3]
    for k = 0, n - 1 do
      if dest + k < 32 then buffer[dest + k] = self:paletteColors(pal + k) end
    end
  end
  return buffer
end

function Assets:emptyPalettes()
  local b = {}
  for i = 0, 31 do
    local p = {}
    for c = 0, 15 do p[c] = { 0, 0, 0 } end
    b[i] = p
  end
  return b
end

-- ---------------------------------------------------------------------------
-- collision lookups
-- ---------------------------------------------------------------------------
function Assets:loadCollision()
  local raw = self.store:read("coll.bin") or ""
  local c = self.manifest.collision or { typeCollision = 0, actTile = 0x800, special = 0x1000, count = 0x800 }
  self.typeCollision, self.actTile, self.specialCollision = {}, {}, {}
  for i = 0, c.count - 1 do
    self.typeCollision[i] = raw:byte(c.typeCollision + i + 1) or 0
    self.actTile[i] = raw:byte(c.actTile + i + 1) or 0
  end
  for i = 0, 0x7F do self.specialCollision[i] = raw:byte(c.special + i + 1) or 0 end
  -- partial-tile shapes: masks for shapes 2..9, lookup for collisionType 0
  if c.masks and c.shapeLookup then
    self.shapeMasks, self.shapeLookup = {}, {}
    for s = 0, 7 do
      local rows = {}
      for r = 0, 15 do rows[r] = u16(raw, c.masks + s * 32 + r * 2) end
      self.shapeMasks[s] = rows
    end
    for i = 0, 0x5F do self.shapeLookup[i] = raw:byte(c.shapeLookup + i + 1) or 1 end
  end
  -- round 9: Link's own masks and state tables (Room:isSolidPlayer)
  if c.playerMasks and c.playerShapes then
    self.playerMasks, self.playerShapes = {}, {}
    for s = 0, 39 do
      local rows = {}
      for r = 0, 15 do rows[r] = u16(raw, c.playerMasks + s * 32 + r * 2) end
      self.playerMasks[s] = rows
    end
    for t = 0, 6 do
      local tab = {}
      for i = 0, 0x5F do tab[i] = raw:byte(c.playerShapes + t * 0x60 + i + 1) or 15 end
      self.playerShapes[t] = tab
    end
  end
end

-- ---------------------------------------------------------------------------
-- pixel buffers: an RGBA ImageData we can write fast
-- ---------------------------------------------------------------------------
local function newPixels(w, h)
  local img = love.image.newImageData(w, h)
  local ptr
  if hasFfi and img.getFFIPointer then
    local ok, p = pcall(img.getFFIPointer, img)
    if ok and p then ptr = ffi.cast("uint8_t*", p) end
  end
  return img, ptr
end

local function putPixel(img, ptr, w, x, y, r, g, b, a)
  if ptr then
    local o = (y * w + x) * 4
    ptr[o], ptr[o + 1], ptr[o + 2], ptr[o + 3] = r, g, b, a
  else
    img:setPixel(x, y, r / 255, g / 255, b / 255, a / 255)
  end
end
Assets.newPixels, Assets.putPixel = newPixels, putPixel

-- ---------------------------------------------------------------------------
-- area tileset atlases
-- ---------------------------------------------------------------------------
function Assets:area(area)
  local a = self.manifest.areas[area]
  if not a then return nil end
  return a
end

Assets.u16 = u16

-- BG palettes the area uses: tileset palette groups on top of the global
-- groups the game loads for every field screen (LoadGfxGroups: 11, 12)
function Assets:areaPalettes(area, ts)
  local info = self:area(area)
  local buf = self:emptyPalettes()
  self:applyPaletteGroup(buf, 11)
  self:applyPaletteGroup(buf, 12)
  -- round 15: LoadGfxGroups ends with SetColor(0, 0): the backdrop is
  -- black unless a tileset group loads BG palette 0 again
  do local p0 = {}; for c = 1, 15 do p0[c] = buf[0][c] end; p0[0] = { 0, 0, 0 }; buf[0] = p0 end
  local tsInfo = info and info.tilesets and info.tilesets[ts]
  if tsInfo then
    for _, g in ipairs(tsInfo.paletteGroups or {}) do
      self:applyPaletteGroup(buf, g)
      -- round 13: LoadMapData follows every palette group with
      -- sub_080533CC: OBJ palette 2's colours 0-4 into BG palette 2
      local p2, o2 = {}, buf[18]
      for c = 0, 15 do p2[c] = (c <= 4) and { o2[c][1], o2[c][2], o2[c][3] } or buf[2][c] end
      buf[2] = p2
    end
  end
  -- round 13: LoadRoomTileSet copies BG palette 3 into OBJ palette 5
  -- (MemCopy(&gPaletteBuffer[0x30], &gPaletteBuffer[0x150], 0x20)): the
  -- fixed slot objects with objPaletteId 5 use (statues, ...)
  local p5 = {}
  for c = 0, 15 do p5[c] = { buf[3][c][1], buf[3][c][2], buf[3][c][3] } end
  buf[21] = p5
  self.bgSerial = (self.bgSerial or 0) + 1
  buf.serial = self.bgSerial
  return buf
end

-- `swap` (optional): {key=string, blocks={{vramOffset, bytes}...},
-- paletteGroups={...}} -- a tileset manager's graphics swap
-- (src/manager/*TileSetManager.c) laid over the area tileset
function Assets:atlas(area, ts, swap)
  local key = area * 256 + ts
  if swap and swap.key then key = key .. ":" .. swap.key end
  local cached = self.atlases[key]
  if cached then return cached end
  local info = self:area(area)
  if not (info and info.tilesets and info.tilesets[ts] and info.tiles) then return nil end
  local vram = self.store:read(info.tilesets[ts].file) or ""
  if swap and swap.blocks then
    for _, b in ipairs(swap.blocks) do
      local off, bytes = b[1], b[2]
      if off >= 0 and off + #bytes <= #vram then
        vram = vram:sub(1, off) .. bytes .. vram:sub(off + #bytes + 1)
      end
    end
  end
  local tiles = self.store:read(info.tiles) or ""
  local pals = self:areaPalettes(area, ts)
  if swap and swap.paletteGroups then
    for _, g in ipairs(swap.paletteGroups) do self:applyPaletteGroup(pals, g) end
  end
  local result = { palettes = pals, types = {} }
  -- tile types (metatile -> tileType) for both layers
  for layer = 0, 1 do
    local t = {}
    local base = 0x8000 + layer * 0x1000
    for i = 0, 0x7FF do t[i] = u16(tiles, base + i * 2) end
    result.types[layer == 0 and "bottom" or "top"] = t
  end
  -- palettes flattened for speed: pal[p][c] = r,g,b
  local pr, pg, pb = {}, {}, {}
  for p = 0, 15 do
    for c = 0, 15 do
      local col = pals[p][c]
      pr[p * 16 + c], pg[p * 16 + c], pb[p * 16 + c] = col[1], col[2], col[3]
    end
  end
  local vbytes = {}
  for i = 1, #vram, 4096 do
    local chunk = { vram:byte(i, math.min(#vram, i + 4095)) }
    for k = 1, #chunk do vbytes[i + k - 1] = chunk[k] end
  end
  for layer = 0, 1 do
    local img, ptr = newPixels(512, 1024)
    local subBase = layer * 0x4000
    local charBase = layer * 0x4000
    for m = 0, 2047 do
      local mx, my = (m % 32) * 16, math.floor(m / 32) * 16
      for q = 0, 3 do
        local se = u16(tiles, subBase + (m * 4 + q) * 2)
        local tile = band(se, 0x3FF)
        local hf, vf = band(se, 0x400) ~= 0, band(se, 0x800) ~= 0
        local pal = rshift(se, 12) * 16
        local ox, oy = mx + (q % 2) * 8, my + math.floor(q / 2) * 8
        local tb = charBase + tile * 32 -- 1-based index tb + i + 1
        for py = 0, 7 do
          local sy = vf and (7 - py) or py
          for px = 0, 7 do
            local sx = hf and (7 - px) or px
            local byte = vbytes[tb + sy * 4 + rshift(sx, 1) + 1] or 0
            local ci = (sx % 2 == 0) and band(byte, 15) or rshift(byte, 4)
            if ci ~= 0 then
              local k = pal + ci
              putPixel(img, ptr, 512, ox + px, oy + py, pr[k], pg[k], pb[k], 255)
            end
          end
        end
      end
    end
    local image = love.graphics.newImage(img)
    image:setFilter("nearest", "nearest")
    result[layer == 0 and "bottom" or "top"] = image
  end
  local bd = pals[0][0]
  result.backdrop = { bd[1] / 255, bd[2] / 255, bd[3] / 255 }
  result.anims = self:buildBgAnims(area, vbytes, tiles, pr, pg, pb)
  self.atlases[key] = result
  return result
end

-- BG tile animations (backgroundAnimations.c): for each animation of the
-- area, the metatiles whose characters it rewrites, drawn once per frame
-- into a small packed atlas (slot s at (s % 32, s / 32) * 16)
function Assets:buildBgAnims(area, vbytes, tiles, pr, pg, pb)
  local list = self.manifest.bgAnims and self.manifest.bgAnims[area]
  if not list then return nil end
  self.bgAnimBlob = self.bgAnimBlob or self.store:read("bganim.bin") or ""
  local blob = self.bgAnimBlob
  local out = {}
  for ai, frames in ipairs(list) do
    -- which VRAM bytes this animation touches
    local lo, hi = math.huge, -1
    for _, fr in ipairs(frames) do
      for _, pch in ipairs(fr.patches) do
        lo = math.min(lo, pch[1]); hi = math.max(hi, pch[1] + pch[3])
      end
    end
    -- palette frames (BG_ANIM_PALETTE, LoadPalettes into BG banks 0-15):
    -- the metatiles drawn with those banks are redrawn per frame too
    local banks = {}
    for _, fr in ipairs(frames) do
      for _, pl in ipairs(fr.palettes or {}) do
        for b = pl[1], pl[1] + pl[3] - 1 do if b < 16 then banks[b] = true end end
      end
    end
    if hi > lo or next(banks) then
      local anim = { timers = {}, layers = {}, palette = next(banks) ~= nil }
      for layer = 0, 1 do
        local subBase, charBase = layer * 0x4000, layer * 0x4000
        local slots, order = {}, {}
        for m = 0, 2047 do
          for q = 0, 3 do
            local tile = band(u16(tiles, subBase + (m * 4 + q) * 2), 0x3FF)
            local b = charBase + tile * 32
            if (b + 32 > lo and b < hi) or banks[rshift(u16(tiles, subBase + (m * 4 + q) * 2), 12)] then
              if not slots[m] then order[#order + 1] = m; slots[m] = #order - 1 end
              break
            end
          end
        end
        if #order > 0 then
          local rows = math.ceil(#order / 32)
          local images = {}
          for fi, fr in ipairs(frames) do
            local vb = setmetatable({}, { __index = vbytes })
            for _, pch in ipairs(fr.patches) do
              local bytes = { blob:byte(pch[2] + 1, pch[2] + pch[3]) }
              for k = 1, #bytes do vb[pch[1] + k] = bytes[k] end
            end
            local pr, pg, pb = pr, pg, pb
            if fr.palettes and #fr.palettes > 0 then
              local r2, g2, b2 = setmetatable({}, { __index = pr }), setmetatable({}, { __index = pg }), setmetatable({}, { __index = pb })
              for _, pl in ipairs(fr.palettes) do
                for c = 0, pl[3] * 16 - 1 do
                  local k = pl[1] * 16 + c
                  if k < 256 then
                    local lo8, hi8 = blob:byte(pl[2] + 2 * c + 1), blob:byte(pl[2] + 2 * c + 2)
                    if lo8 and hi8 then r2[k], g2[k], b2[k] = bgr555(lo8 + 256 * hi8) end
                  end
                end
              end
              pr, pg, pb = r2, g2, b2
            end
            local img, ptr = newPixels(512, rows * 16)
            for s, m in ipairs(order) do
              local dx, dy = ((s - 1) % 32) * 16, math.floor((s - 1) / 32) * 16
              for q = 0, 3 do
                local se = u16(tiles, subBase + (m * 4 + q) * 2)
                local tile = band(se, 0x3FF)
                local hf, vf = band(se, 0x400) ~= 0, band(se, 0x800) ~= 0
                local pal = rshift(se, 12) * 16
                local ox, oy = dx + (q % 2) * 8, dy + math.floor(q / 2) * 8
                local tb = charBase + tile * 32
                for py = 0, 7 do
                  local sy = vf and (7 - py) or py
                  for px = 0, 7 do
                    local sx = hf and (7 - px) or px
                    local byte = vb[tb + sy * 4 + rshift(sx, 1) + 1] or 0
                    local ci = (sx % 2 == 0) and band(byte, 15) or rshift(byte, 4)
                    if ci ~= 0 then
                      local k = pal + ci
                      putPixel(img, ptr, 512, ox + px, oy + py, pr[k], pg[k], pb[k], 255)
                    end
                  end
                end
              end
            end
            local image = love.graphics.newImage(img)
            image:setFilter("nearest", "nearest")
            images[fi] = image
          end
          anim.layers[layer == 0 and "bottom" or "top"] = { slots = slots, images = images, h = rows * 16 }
        end
      end
      for fi, fr in ipairs(frames) do anim.timers[fi] = fr.timer end
      if next(anim.layers) then out[#out + 1] = anim end
    end
  end
  return out
end

function Assets:dropAtlases(keepArea, keepKey)
  for key, a in pairs(self.atlases) do
    local k = type(key) == "number" and key or tonumber(tostring(key):match("^(%d+)")) or 0
    if math.floor(k / 256) ~= keepArea or (keepKey and type(key) == "string" and key ~= keepKey) then
      if a.bottom then a.bottom:release() end
      if a.top then a.top:release() end
      self.atlases[key] = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- rooms
-- ---------------------------------------------------------------------------
-- returns { w, h (in 16px tiles), bottom = {[i]=metatile}, top = {...},
-- special = bool } with i = y * w + x (0-based)
function Assets:roomMaps(area, room)
  local key = area * 256 + room
  if self.rooms[key] then return self.rooms[key] end
  local info = self:area(area)
  local r = info and info.rooms and info.rooms[room]
  if not (r and r.file) then return nil end
  local blob = self.store:read(r.file) or ""
  local w, h = math.floor(r.w / 16), math.floor(r.h / 16)
  local out = { w = w, h = h, header = r }
  local function layer(sec)
    local t = {}
    if not sec then return t end
    local at, len = sec[1], sec[2]
    for i = 0, math.min(w * h, math.floor(len / 2)) - 1 do t[i] = u16(blob, at + i * 2) end
    return t
  end
  out.bottom = layer(r.sections.bottom)
  out.top = layer(r.sections.top)
  out.special = out.bottom[0] == 0xFFFF
  if r.sections.collBottom then
    local c, sec = {}, r.sections.collBottom
    for i = 0, math.min(w * h, sec[2]) - 1 do c[i] = blob:byte(sec[1] + i + 1) end
    out.collisionOverride = c
  end
  self.rooms[key] = out
  return out
end

-- ---------------------------------------------------------------------------
-- sprites
-- ---------------------------------------------------------------------------
function Assets:sprite(index)
  local s = self.sprites[index]
  if s ~= nil then return s or nil end
  local name = self.manifest.sprites[index]
  if not name then self.sprites[index] = false; return nil end
  s = self.store:readTable(name)
  if s and s.gfx then s.gfxRaw = self.store:read(s.gfx) end
  self.sprites[index] = s or false
  return s
end

-- One frame of a sprite drawn into an image, with the frame's OAM pieces
-- placed around the entity origin.  Returns image, ox, oy (origin offset).
-- `palette` is a {[0..15]={r,g,b}} table.
local OBJ_SIZES = {
  [0] = { { 8, 8 }, { 16, 16 }, { 32, 32 }, { 64, 64 } },
  [1] = { { 16, 8 }, { 32, 8 }, { 32, 16 }, { 64, 32 } },
  [2] = { { 8, 16 }, { 8, 32 }, { 16, 32 }, { 32, 64 } },
}

-- fixed object graphics block i (src/vram.c LoadFixedGFX), as a string
function Assets:fixedGfx(i)
  self.fixedCache = self.fixedCache or {}
  local c = self.fixedCache[i]
  if c ~= nil then return c or nil end
  local idx = self.manifest.fixedGfx and self.manifest.fixedGfx[i]
  if not idx then self.fixedCache[i] = false; return nil end
  self.fixedRaw = self.fixedRaw or self.store:read("fixed.bin") or ""
  c = self.fixedRaw:sub(idx[1] + 1, idx[1] + idx[2])
  self.fixedCache[i] = c
  return c
end

-- An object palette by id (src/color.c LoadObjPaletteAtIndex): 0-5 are the
-- fixed OBJ palettes the field loads (groups 11/12), 6-0x14 copy a BG
-- palette of the current area (`bg` = that area's palette buffer), 0x16+
-- come from the object palette table.
function Assets:objPalette(id, bg)
  -- round 13: the room's palette buffer when the caller has none (the
  -- field sets curBg with the room); palettes that depend on the room
  -- carry `pkey` so sprite images cached for one area are not reused in
  -- another (Assets:spriteFrame)
  bg = bg or self.curBg
  if id == 5 and bg and bg[21] then
    -- OBJ palette 5 is BG palette 3 (LoadRoomTileSet)
    local p = bg[21]
    p.pkey = p.pkey or ("b5." .. tostring(bg.serial))
    return p
  end
  if id <= 5 then
    if not self.fieldObj then
      local buf = self:emptyPalettes()
      self:applyPaletteGroup(buf, 11)
      self:applyPaletteGroup(buf, 12)
      self.fieldObj = buf
    end
    return self.fieldObj[16 + id]
  elseif id < 0x15 then
    local p = bg and bg[id - 6]
    if not p then return self:emptyPalettes()[0] end
    p.pkey = p.pkey or ("b" .. (id - 6) .. "." .. tostring(bg.serial))
    return p
  elseif id == 0x15 then
    -- MemFill16(gPaletteBuffer[0x3C]): every colour is BG palette 3's 12th
    if not bg then return self:emptyPalettes()[0] end
    if not bg.fill15 then
      local c, p = bg[3][12], { pkey = "f15." .. tostring(bg.serial) }
      for i = 0, 15 do p[i] = { c[1], c[2], c[3] } end
      bg.fill15 = p
    end
    return bg.fill15
  end
  local e = self.manifest.objPalettes and self.manifest.objPalettes[id]
  if not e then return self:emptyPalettes()[0] end
  self.objPalRaw = self.objPalRaw or self.store:read("objpal.bin") or ""
  local function one(at)
    local out = {}
    for i = 0, 15 do
      local o = at + i * 2 + 1
      local lo, hi = self.objPalRaw:byte(o), self.objPalRaw:byte(o + 1)
      out[i] = lo and { bgr555(lo + hi * 256) } or { 0, 0, 0 }
    end
    return out
  end
  local out = one(e[1])
  -- round 7: a multi-slot palette (count in bits 24-27) loads into
  -- consecutive slots; an OAM piece's attr2 high nibble (frame obj byte 4
  -- bits 4-7) adds to the slot, so piece palette +k is the k-th next one
  if (e[2] or 1) > 1 then
    out.next = {}
    for k = 1, e[2] - 1 do out.next[k] = one(e[1] + k * 32) end
  end
  return out
end

-- `gfxSrc`: nil = the sprite's own swap graphics (frame table picks tiles),
-- a number = a fixed graphics block (OAM tiles index it directly), or
-- {vram = tile} = the common OBJ VRAM from that tile on
--
-- Assets.gfxSource(kind, gfx): the source for a definition's gfx field --
-- objects/NPCs give gfxType 0 fixed / 1 swap / 2 common; enemies encode it
-- in the value ($8000 common, $4000 swap, else fixed: LoadEnemySprite)
function Assets.gfxSource(gfxType, gfx)
  if gfxType == "enemy" then
    if gfx == 0 then return nil end
    if bit.band(gfx, 0x8000) ~= 0 then return { vram = bit.band(gfx, 0x3FF) } end
    if bit.band(gfx, 0x4000) ~= 0 then return nil end
    return gfx
  end
  if gfxType == 2 then return { vram = gfx } end
  if gfxType == 1 or gfx == 0 then return nil end
  return gfx
end
function Assets:spriteFrame(index, frame, palette, cacheKey, gfxSrc)
  local srcKey = type(gfxSrc) == "table" and (gfxSrc.raw and ("r" .. tostring(gfxSrc.key)) or gfxSrc.fixed and ("f" .. gfxSrc.fixed .. "+" .. tostring(gfxSrc.first))
    or ("v" .. tostring(gfxSrc.vram))) or tostring(gfxSrc)
  local key = index .. ":" .. frame .. ":" .. tostring(cacheKey or "") .. ":" .. srcKey
  if type(palette) == "table" and palette.pkey then key = key .. ":" .. palette.pkey end -- round 13
  local c = self.spriteImages[key]
  if c ~= nil then
    if c then return c.image, c.ox, c.oy end
    return nil
  end
  local s = self:sprite(index)
  local objs = s and s.objs[frame]
  local first, gfx = 0, nil
  if s and type(gfxSrc) == "table" and gfxSrc.raw then
    -- round 7: tiles the caller assembled (the fusion bubble's two slots)
    gfx, first = gfxSrc.raw, gfxSrc.first or 0
  elseif s and type(gfxSrc) == "table" and gfxSrc.fixed then
    -- round 7: a fixed block from a tile on (an NPC part's tile offset)
    gfx, first = self:fixedGfx(gfxSrc.fixed), gfxSrc.first or 0
  elseif s and type(gfxSrc) == "table" then
    -- common OBJ VRAM (gfx groups 16/23/25/27): tiles start at the
    -- entity's spriteVramOffset
    self.objVram = self.objVram or self.store:read("objvram.bin") or ""
    gfx, first = self.objVram, gfxSrc.vram or 0
  elseif s and gfxSrc then
    gfx = self:fixedGfx(gfxSrc)
  elseif s then
    local fr = s.frames[frame]
    if fr then first, gfx = fr[3], s.gfxRaw end
  end
  if not (objs and gfx and #objs > 0) then
    self.spriteImages[key] = false
    return nil
  end
  -- bounds
  local minx, miny, maxx, maxy = 1e9, 1e9, -1e9, -1e9
  for _, o in ipairs(objs) do
    local shape, size = rshift(o[3], 6), band(rshift(o[3], 4), 3)
    local dims = OBJ_SIZES[shape] and OBJ_SIZES[shape][size + 1] or { 8, 8 }
    minx = math.min(minx, o[1]); miny = math.min(miny, o[2])
    maxx = math.max(maxx, o[1] + dims[1]); maxy = math.max(maxy, o[2] + dims[2])
  end
  local w, h = maxx - minx, maxy - miny
  if w <= 0 or h <= 0 or w > 256 or h > 256 then self.spriteImages[key] = false; return nil end
  local img, ptr = newPixels(w, h)
  -- the pieces go to consecutive OAM slots and a lower slot is drawn on
  -- top (the THOUGHT_BUBBLE's mark is its first piece, over the bubble):
  -- paint them last to first
  for oi = #objs, 1, -1 do
    local o = objs[oi]
    local shape, size = rshift(o[3], 6), band(rshift(o[3], 4), 3)
    local dims = OBJ_SIZES[shape] and OBJ_SIZES[shape][size + 1] or { 8, 8 }
    local hf, vf = band(o[3], 0x04) ~= 0, band(o[3], 0x08) ~= 0
    local tile0 = o[4] + band(o[5], 0x03) * 256
    local pk = rshift(o[5], 4)
    local pal = pk ~= 0 and palette.next and palette.next[pk] or palette
    -- frame obj bitfield bit 0 clears the entity's palette: the piece uses
    -- OBJ slot (hi >> 4) itself, one of the fixed field palettes 0-5
    if band(o[3], 1) ~= 0 and pk <= 5 then pal = self:objPalette(pk) end
    local tw, th = dims[1] / 8, dims[2] / 8
    for ty = 0, th - 1 do
      for tx = 0, tw - 1 do
        local t = tile0 + ty * tw + tx -- 1D mapping
        local tb = (first + t) * 32
        for py = 0, 7 do
          for px = 0, 7 do
            local byte = gfx:byte(tb + py * 4 + rshift(px, 1) + 1) or 0
            local ci = (px % 2 == 0) and band(byte, 15) or rshift(byte, 4)
            if ci ~= 0 then
              local lx, ly = tx * 8 + px, ty * 8 + py
              if hf then lx = dims[1] - 1 - lx end
              if vf then ly = dims[2] - 1 - ly end
              local col = pal[ci] or { 255, 0, 255 }
              putPixel(img, ptr, w, o[1] - minx + lx, o[2] - miny + ly, col[1], col[2], col[3], 255)
            end
          end
        end
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  local entry = { image = image, ox = minx, oy = miny }
  self.spriteImages[key] = entry
  return image, minx, miny
end

-- ---------------------------------------------------------------------------
-- text
-- ---------------------------------------------------------------------------
function Assets:text()
  if not self.textTable then self.textTable = self.store:readTable("text.lua") or {} end
  return self.textTable
end

function Assets:message(index)
  local t = self:text()
  local g = t[rshift(index, 8)]
  return g and g[band(index, 0xFF)]
end

return Assets
