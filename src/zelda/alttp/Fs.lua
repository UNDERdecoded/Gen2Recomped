-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FOUR SWORDS DATA AND RULES, without LÖVE: floors decoded from the imported
-- cache (FsExtract), collision as the cartridge computes it, and the stage
-- logic shared by every player (rupee layout from a seed, pickups, scores).
--
-- Collision (0x080160F8 / 0x0802BB80): for each 16x16 cell and each of the
-- two layers, coll[ tileType[ metatile ] ]; a cell is blocked when either
-- layer's byte is non-zero. Unused metatiles have tile type 0xFFFF and count
-- as open, like the cartridge's out-of-table read would on an empty slot.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local FE = require("src.zelda.alttp.FsExtract")
local S = require("src.zelda.alttp.Serialize")

local Fs = {}
Fs.__index = Fs

Fs.CELL = 16
Fs.W = 63              -- metatiles per side
Fs.PX = 63 * 16        -- 1008: the cartridge's room size (0x3F0)

local sbyte = string.byte

local function u16(s, o)
  local a, b = sbyte(s, o + 1, o + 2)
  return a + b * 256
end
Fs.u16 = u16

function Fs.load(cache)
  local self = setmetatable({ areas = {} }, Fs)
  local src = cache:read(FE.FILES.info)
  assert(type(src) == "string", "Four Swords data missing -- import the ROM again")
  self.info = assert(S.decode(src))
  self.maps = assert(cache:read(FE.FILES.maps), "Four Swords maps missing")
  self.coll = assert(cache:read(FE.FILES.coll), "Four Swords collision missing")
  self.mapGfx = cache:read(FE.FILES.mapGfx) or ""
  self.cache = cache
  return self
end

function Fs:area(a)
  local hit = self.areas[a]
  if hit then return hit end
  local blob = assert(self.cache:read(FE.areaFile(a)), "Four Swords area missing")
  hit = { blob = blob }
  self.areas[a] = hit
  return hit
end

-- offsets inside an area blob
Fs.VRAM, Fs.MT_A, Fs.MT_B, Fs.TY_A, Fs.TY_B, Fs.PAL = 0, 0x10000, 0x14000, 0x18000, 0x19000, 0x1A000

function Fs:palette(a)
  local blob = self:area(a).blob
  local pal = {}
  for i = 0, 511 do pal[i] = u16(blob, Fs.PAL + i * 2) end
  return pal
end

-- metatile id of layer ("A"|"B") at cell (cx, cy) of map m
function Fs:metatile(m, layer, cx, cy)
  local o = m * FE.MAP_BYTES * 2 + (layer == "B" and FE.MAP_BYTES or 0) + (cy * Fs.W + cx) * 2
  return u16(self.maps, o)
end

-- a floor as runtime state: collision grid and map number
function Fs:floor(fl)
  local m, a = fl.map, fl.area
  local blob = self:area(a).blob
  local grid = {}
  local coll = self.coll
  for cy = 0, Fs.W - 1 do
    for cx = 0, Fs.W - 1 do
      local solid = false
      for _, L in ipairs({ "A", "B" }) do
        local mt = self:metatile(m, L, cx, cy)
        if mt < 2048 then
          local ty = u16(blob, (L == "A" and Fs.TY_A or Fs.TY_B) + mt * 2)
          if ty < #coll then
            if sbyte(coll, ty + 1) ~= 0 then solid = true end
          end
        end
      end
      grid[cy * Fs.W + cx] = solid
    end
  end
  local f = { map = m, area = a, grid = grid, objects = fl.objects }
  -- The floor's type-4 object sits on the wall at the entrance (the
  -- cartridge walks the Links in from there, not ported); players spawn on
  -- the nearest open cells to it instead -- ours.
  local sx, sy = (fl.start or { 504, 504 })[1], (fl.start or { 504, 504 })[2]
  local cx0, cy0 = math.floor(sx / 16), math.floor(sy / 16)
  local cells = {}
  for r = 0, 62 do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local cx, cy = cx0 + dx, cy0 + dy
          if cx >= 1 and cy >= 1 and cx < Fs.W - 1 and cy < Fs.W - 1 and not grid[cy * Fs.W + cx] then
            cells[#cells + 1] = { cx, cy }
          end
        end
      end
    end
    if #cells >= 1 then break end
  end
  local c = cells[1] or { cx0, cy0 }
  f.start = { c[1] * 16 + 8, c[2] * 16 + 8 }
  f.entrance = { sx, sy }
  return f
end

function Fs.blocked(floor, x, y)
  if x < 0 or y < 0 or x >= Fs.PX or y >= Fs.PX then return true end
  return floor.grid[math.floor(y / 16) * Fs.W + math.floor(x / 16)] == true
end

-- decode one layer into 0-based colour indices (1008 x 1008)
-- the area's VRAM with the floor's own tiles laid over it (map groups 51, 72
-- and 93 load extra BG tiles at 0x06004400)
function Fs:vramFor(m, a)
  local blob = self:area(a).blob
  local vram = blob:sub(Fs.VRAM + 1, Fs.VRAM + 0x10000)
  for _, g in ipairs(self.info.mapGfx or {}) do
    if g[1] == m then
      local data = self.mapGfx:sub(g[3] + 1, g[3] + g[4])
      vram = vram:sub(1, g[2]) .. data .. vram:sub(g[2] + #data + 1)
    end
  end
  return vram
end

function Fs:decodeLayer(m, a, layer)
  local blob = self:area(a).blob
  local vram = self:vramFor(m, a)
  local mtBase = layer == "A" and Fs.MT_A or Fs.MT_B
  local tiles = {}
  local function tile(n)
    local t = tiles[n]
    if t then return t end
    t = {}
    local o = n * 32
    for i = 0, 31 do
      local b = sbyte(vram, o + i + 1) or 0
      t[i * 2 + 1] = band(b, 15)
      t[i * 2 + 2] = rshift(b, 4)
    end
    tiles[n] = t
    return t
  end
  local out = {}
  local W = Fs.PX
  -- the padding outside a floor's walls repeats one metatile (the one in the
  -- far corner); its VRAM slot holds unrelated tiles, so it is drawn as the
  -- backdrop here (ours -- the cartridge's camera never shows it)
  local padB = self:metatile(m, "B", Fs.W - 1, Fs.W - 1)
  local padA = self:metatile(m, "A", Fs.W - 1, Fs.W - 1)
  for cy = 0, Fs.W - 1 do
    for cx = 0, Fs.W - 1 do
      local mt = self:metatile(m, layer, cx, cy)
      if self:metatile(m, "B", cx, cy) == padB and self:metatile(m, "A", cx, cy) == padA then mt = 0xFFFF end
      for q = 0, 3 do
        local e = (mt < 2048) and u16(blob, mtBase + mt * 8 + q * 2) or 0
        local px = tile(band(e, 0x3FF) % 2048)
        local hf, vf = band(e, 0x400) ~= 0, band(e, 0x800) ~= 0
        local pal = rshift(e, 12) * 16
        local bx = cx * 16 + (q % 2) * 8
        local by = cy * 16 + math.floor(q / 2) * 8
        for y = 0, 7 do
          local sy = vf and (7 - y) or y
          local row = (by + y) * W + bx
          for x = 0, 7 do
            local c = px[sy * 8 + (hf and (7 - x) or x) + 1]
            out[row + x] = (c ~= 0) and (pal + c) or 0
          end
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- the stage

-- deterministic RNG (same on every player for one seed)
local function rng(seed)
  local s = (seed or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(n)
    s = (s * 48271) % 2147483647
    return n and (s % n) or s
  end
end
Fs.rng = rng

-- Cells reachable on foot from the start, by 16 px steps (4-way).
function Fs.reachable(floor)
  local sx, sy = math.floor((floor.start[1]) / 16), math.floor((floor.start[2]) / 16)
  local seen, list, q = {}, {}, { sy * Fs.W + sx }
  seen[q[1]] = true
  local head = 1
  while q[head] do
    local c = q[head]; head = head + 1
    list[#list + 1] = c
    local cx, cy = c % Fs.W, math.floor(c / Fs.W)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = cx + d[1], cy + d[2]
      if nx >= 0 and ny >= 0 and nx < Fs.W and ny < Fs.W then
        local n = ny * Fs.W + nx
        if not seen[n] and not floor.grid[n] then seen[n] = true; q[#q + 1] = n end
      end
    end
  end
  return list
end

-- Rupees for a stage: green 1, blue 5, red 20 (Four Swords' values), laid out
-- by OUR rule (the cartridge's own drops come from grass, pots and enemies,
-- which are not ported): `count` rupees on reachable cells, from the seed.
Fs.RUPEE_VALUE = { green = 1, blue = 5, red = 20 }
function Fs.layoutRupees(floor, seed, count)
  local r = rng(seed)
  local cells = Fs.reachable(floor)
  local out, used = {}, {}
  count = math.min(count or 30, #cells)
  local guard = 0
  while #out < count and guard < count * 20 do
    guard = guard + 1
    local c = cells[r(#cells) + 1]
    if not used[c] then
      used[c] = true
      local roll = r(100)
      local kind = roll < 70 and "green" or (roll < 93 and "blue" or "red")
      out[#out + 1] = { id = #out + 1, kind = kind, value = Fs.RUPEE_VALUE[kind],
                        x = (c % Fs.W) * 16 + 4, y = math.floor(c / Fs.W) * 16 + 4 }
    end
  end
  return out
end

-- results: players sorted by rupees, ties share a place
function Fs.ranking(scores)
  local list = {}
  for id, v in pairs(scores) do list[#list + 1] = { id = id, rupees = v } end
  table.sort(list, function(a, b)
    if a.rupees ~= b.rupees then return a.rupees > b.rupees end
    return a.id < b.id
  end)
  local place = 0
  for i, e in ipairs(list) do
    if i == 1 or e.rupees ~= list[i - 1].rupees then place = i end
    e.place = place
  end
  return list
end

return Fs
