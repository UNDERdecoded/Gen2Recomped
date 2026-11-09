-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- INTERIORS: the cartridge's pre-rendered 512x512 room maps (RomMap.roomBg2 /
-- roomBg1, loader 0x0807FF10), drawn with the tilesets and palette the room
-- header and entrance name (RomMap.roomHeader / entrances, as the SNES
-- Dungeon_LoadHeader), and blocked by the dungeon tile-attribute table
-- (RomMap.dungAttr*, the SNES attributes_for_tile). Pure logic; the game
-- makes images with View.fill.
--
-- Doors (round 4b): the way in is the cartridge's overworld door check
-- (RomMap.owDoorTab*/owEnt*, the GBA's 0x0808BB88): the 16x16 tile in front
-- of Link must show a door tile pair, then its position and area name the
-- entrance. The way out is the SNES TileBehavior_Entrance: tile attribute
-- 0x8E/0x8F under Link while he walks down. STILL OURS (docs/zelda/alttp.md):
-- where Link reappears outside is just below the overworld door he came in
-- by (from the same entrance table); the cartridge's exit table (which also
-- sets the camera) is not read. Room-to-room doors and stairs are not
-- decoded; the walkable set of attribute values (WALKABLE) covers the values
-- met so far; room objects (chests, pots) do nothing yet.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local O = require("src.zelda.alttp.Overworld")

local I = {}
I.__index = I

-- the overworld door (top-left world pixel) of an entrance number, from the
-- cartridge's overworld entrance table; nil when no overworld door names it
function I.doorOf(data, entrance)
  local idx = data.roomIdx
  if not (idx and idx.owEntId) then return nil end
  for i = #idx.owEntId, 1, -1 do
    if idx.owEntId[i] == entrance then
      local area = idx.owEntArea[i]
      local pos = idx.owEntPos[i]
      local q, r = math.floor(pos / 4096), pos % 4096
      local sb, rr = math.floor(r / 1024), r % 1024
      local lx = (q % 2) * 64 + (sb % 2) * 32 + rr % 32
      local ly = math.floor(q / 2) * 64 + math.floor(sb / 2) * 32 + math.floor(rr / 32)
      local ox, oy = O.screenOrigin(area)
      return { world = (area >= 0x40) and "dw" or "lw", x = ox + lx * 8, y = oy + ly * 8,
               area = area, index = i - 1 }
    end
  end
end

-- the overworld door Link is walking up into: the 16x16 tile containing
-- (x, y + 7) as the cartridge's Overworld_UseEntrance computes it. Returns
-- the entrance number or nil.
-- Our Link stops 16-48 px short of the door row the cartridge tests (its
-- door-frame collision is not ported), so `ahead` (0-3) looks that many
-- 16 px rows further up; the door tile pair check guards every row.
function I.owEntrance(data, ow, world, x, y, ahead)
  for k = 0, ahead or 0 do
    local e = I.owEntranceAt(data, ow, world, x, y - 16 * k)
    if e then return e end
  end
end

function I.owEntranceAt(data, ow, world, x, y)
  local idx = data.roomIdx
  if not (idx and idx.owEntId) then return nil end
  local wx, wy = math.floor(x / 16) * 16, math.floor((y + 7) / 16) * 16
  local screen = O.screenAt(world, wx, wy)
  if not screen then return nil end
  local area = ow:area(screen)
  local tx, ty = (wx - area.x) / 8, (wy - area.y) / 8
  -- the door tile pair: the 16x16 tile's bottom two map8 words
  local function word(cx, cy)
    local s = O.screenAt(world, area.x + cx * 8, area.y + cy * 8)
    local lx, ly = (cx % 64), (cy % 64)
    return band(data:mapWord(data:mapNumber("bg2", s), O.cellIndex(lx, ly)), 0x1FF)
  end
  local a, b = word(tx, ty + 1), word(tx + 1, ty + 1)
  local pair = false
  for i = 1, #idx.owDoorTab0 do
    if idx.owDoorTab0[i] == a and idx.owDoorTab1[i] == b then pair = true break end
  end
  if not pair then return nil end
  local q = (tx >= 64 and 1 or 0) + (ty >= 64 and 2 or 0)
  local cx, cy = tx % 64, ty % 64
  local pos = q * 4096 + (math.floor(cy / 32) * 2 + math.floor(cx / 32)) * 1024 + (cy % 32) * 32 + cx % 32
  local areaId = area.parent
  for i = #idx.owEntId, 1, -1 do
    if idx.owEntPos[i] == pos and idx.owEntArea[i] == areaId then return idx.owEntId[i] end
  end
  return nil
end

-- SNES dungeon tile types Link may stand on: 0x00 floor, 0x09 shallow water,
-- 0x0D spikes, 0x1C-0x1F layer/ledge markers, 0x22 stairs, 0x3A/0x3B star
-- tiles, 0x40/0x48 grass, 0x4B warp, 0x80-0xBF door and transition codes.
local WALKABLE = { [0x00] = true, [0x09] = true, [0x0D] = true, [0x1C] = true, [0x1D] = true,
                   [0x1E] = true, [0x1F] = true, [0x22] = true, [0x3A] = true, [0x3B] = true,
                   [0x40] = true, [0x48] = true, [0x4B] = true }
for v = 0x80, 0xBF do WALKABLE[v] = true end
I.WALKABLE = WALKABLE

-- 512-entry attribute table for an aux tileset (SNES attributes_for_tile)
function I.attributes(idx, aux)
  local a = {}
  for i = 1, 0x140 do a[i - 1] = idx.attrBase[i] end
  local mid = idx.attrAux[aux + 1] or idx.attrAux[1]
  for i = 1, 0x80 do a[0x13F + i] = mid[i] end
  for i = 1, 0x40 do a[0x1BF + i] = idx.attrTail[i] end
  return a
end

-- entrance: cartridge entrance number (RomMap.entrances). The way back out
-- is the overworld door of this entrance (or, for an entrance with no door
-- of its own such as Link's bed, of another entrance into the same room).
function I.new(data, entrance)
  local idx = data.roomIdx
  local ent = assert(idx.entrances[entrance + 1], "no such entrance")
  local room = ent.room
  local hdr = idx.headers[room + 1]
  local self = setmetatable({ data = data, room = room, entrance = ent, entranceId = entrance }, I)
  local door = I.doorOf(data, entrance)
  if not door then
    for e = 0, #idx.entrances - 1 do
      if idx.entrances[e + 1].room == room then
        door = I.doorOf(data, e)
        if door then break end
      end
    end
  end
  if door then
    -- Link steps out just below the 16x16 door tile, facing down
    self.outside = { world = door.world, x = door.x, y = door.y + 20 }
  end
  self.main, self.aux = ent.main, hdr[3]
  self.palSet = hdr[2]
  self.palMain = idx.palSets[self.palSet * 4 + 1]
  local t = data.t
  local mt = t.mainTilesets[self.main + 1]
  local at = t.auxTilesets[self.aux + 1]
  self.sheets = { mt[1], mt[2], mt[3] }
  for k = 1, 4 do self.sheets[3 + k] = (at[k] ~= 0xFF) and at[k] or mt[3 + k] end
  self.sheets[8] = mt[8]
  self.bg2 = idx.bg2[room + 1]
  self.bg1 = idx.bg1[room + 1]
  -- Link's spawn from the entrance (world pixels -> room pixels)
  self.spawn = { ent.x % 512, ent.y % 512, 0 }
  -- collision: BG2 tile attributes
  local attr = I.attributes(idx, self.aux)
  local grid, attrs = {}, {}
  for ty = 0, 63 do
    for tx = 0, 63 do
      local w = data:roomWord(self.bg2, O.cellIndex(tx, ty))
      local v = attr[band(w, 0x1FF)] or 0
      attrs[ty * 64 + tx] = v
      grid[ty * 64 + tx] = not WALKABLE[v]
    end
  end
  self.grid, self.attrs = grid, attrs
  self:markExitDoors()
  return self
end

-- The overworld exits of this room, as the SNES door drawers mark them
-- (RomMap.roomDoors): attribute 0x8E over the door's two middle columns.
local ENTRANCE_TYPES = { [4] = true, [10] = true, [12] = true, [14] = true, [16] = true }
function I:markExitDoors()
  local idx = self.data.roomIdx
  local list = idx.doors and idx.doors[self.room + 1]
  if not list then return end
  local function addr(w)
    local dir, pos = band(w, 3), band(rshift(w, 4), 15)
    local tab = (dir == 0) and idx.doorPosUp or ((dir == 1) and idx.doorPosDown or nil)
    return dir, tab and tab[pos + 1]
  end
  local exitAt = {}
  for _, w in ipairs(list) do
    local dir, a = addr(w)
    if a and rshift(w, 8) == 18 then exitAt[a] = true end
  end
  for _, w in ipairs(list) do
    local dir, a = addr(w)
    local t = rshift(w, 8)
    if a and t ~= 18 and (ENTRANCE_TYPES[t] or exitAt[a]) then
      local j = rshift(a, 1)
      local rows
      if dir == 0 then j = band(j, bit.bnot(0x7C0)); rows = { 0, 6 } else rows = { 1, 5 } end
      for r = rows[1], rows[2] do
        for c = 1, 2 do
          local cell = band(j + c + r * 64, 0xFFF)
          self.attrs[cell] = 0x8E
          self.grid[cell] = false
        end
      end
    end
  end
end

function I:attrAt(x, y)
  return self.attrs[math.floor(y / 8) * 64 + math.floor(x / 8)]
end

function I:palette()
  local pal = {}
  for i = 0, 255 do pal[i] = 0 end
  local src = 0x400 + self.data.roomIdx.dungPal[self.palMain + 1]
  for i = 0, 95 do pal[0x20 + i] = self.data:blobColor(src + i) end
  return pal
end

-- TileBehavior_Entrance: the attribute 0x8E/0x8F under (x, y)
function I:isExit(x, y)
  local a = self:attrAt(x, y)
  return a == 0x8E or a == 0x8F
end

-- the camera stays in the 256x256 quadrant the room's spawn is in (the
-- SNES/GBA room quadrant layout)
function I:camera(lx, ly, W, H)
  local qx = math.floor(self.spawn[1] / 256) * 256
  local qy = math.floor(self.spawn[2] / 256) * 256
  local cx = math.max(qx, math.min(qx + 256 - W, lx + 8 - W / 2))
  local cy = math.max(qy, math.min(qy + 256 - H, ly + 12 - H / 2))
  return math.floor(cx), math.floor(cy)
end

function I:blocked(x, y)
  if x < 0 or y < 0 or x >= 512 or y >= 512 then return true end
  return self.grid[math.floor(y / 8) * 64 + math.floor(x / 8)] == true
end

-- 0-based colour indices for "bg2" | "bg1"
function I:decodeLayer(layer)
  local n = layer == "bg1" and self.bg1 or self.bg2
  local tiles = {}
  local data = self.data
  local function tile(t)
    local hit = tiles[t]
    if hit then return hit end
    local slot = math.floor(t / 64)
    hit = {}
    if slot < 8 then
      local raw = data:sheet(self.sheets[slot + 1])
      local o = (t % 64) * 32
      for i = 0, 31 do
        local b = raw:byte(o + i + 1) or 0
        hit[i * 2 + 1] = band(b, 15)
        hit[i * 2 + 2] = rshift(b, 4)
      end
    end
    tiles[t] = hit
    return hit
  end
  local out = {}
  for ty = 0, 63 do
    for tx = 0, 63 do
      local w = data:roomWord(n, O.cellIndex(tx, ty))
      local px = tile(band(w, 0x3FF))
      local hf, vf = band(w, 0x400) ~= 0, band(w, 0x800) ~= 0
      local pal = rshift(w, 12) * 16
      for y = 0, 7 do
        local sy = vf and (7 - y) or y
        local row = (ty * 8 + y) * 512 + tx * 8
        for x = 0, 7 do
          local c = px[sy * 8 + (hf and (7 - x) or x) + 1] or 0
          out[row + x] = (c ~= 0) and (pal + c) or 0
        end
      end
    end
  end
  return out
end

return I
