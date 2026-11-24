-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DUNGEON MAP SCREEN (round 31; a stub since round 27A). L in a palace
-- (Module0E_03_DungeonMap; the GBA opens it with L as it opens the world
-- map outside). Its data are the cartridge's, read at import:
--
--   kDungMap_FloorLayout  pointers 0x16FCF4 (14 palaces = cur_palace_index_x2
--                         >> 1), 25 bytes a floor (5 x 5, the room's low byte,
--                         0x0F = none), lowest floor first;
--   kDungMap_Tiles        pointers 0x16FDE8: one room-picture index per
--                         non-empty cell (GetOtherDungmapInfo);
--   kDungMap_Tab23        0x16F132 (744 u16, GBA BG words): the 2 x 2 tiles
--                         of each room picture (0x2200 = nothing);
--   kDungMap_Tab5         0x16F702 (u16): floors below (& 0xF) and above
--                         (>> 4 & 0xF) the ground floor; 0x100 / 0x200 flags;
--   kDungMap_Tab21 / 22   0x16F010 / 0x16F016: rooms drawn as another
--                         (0x89 -> 0xA9, 0xA7 -> 0x77, 0x4F -> 0xBE);
--   kDungMap_Tab25 / 28   0x16F020 / 0x16F03C (s16): the boss's room and its
--                         floor (relative to the ground floor).
--
-- DungeonMap_DrawSingleRowOfRooms: a room shows when Link has the map
-- (link_dungeon_map & the palace's bit) or has seen it (save_dung_info
-- quadrant bits, here progress.dmapSeen[room], set on entering a room);
-- a seen room is bright, a mapped-only room dim. DungeonMap_DrawRoomMarkers:
-- Link's marker at his room cell + ((link_x & 0x1E0) >> 5, (link_y &
-- 0x1E0) >> 5); with the compass the boss's room blinks on its floor.
-- DungeonMap_HandleFloorSelect: up / down change the floor (the cartridge
-- scrolls with 3 floors or more and shows two at once); L / B / START close it.
--
-- OURS: (round 40: the screen is drawn from the cartridge's own chars,
-- frame map, box words and palette, see M.ART; the shaded-block fallback is
-- kept for a cache without them) the BG scroll offsets, the floor list
-- (text) and the markers; the map / compass are "owned" when the item log
-- has them from a room of this palace.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.OFF = { layoutPtrs = 0x16FCF4, tilePtrs = 0x16FDE8, pics = 0x16F132, floors = 0x16F702,
          remapFrom = 0x16F010, remapTo = 0x16F016, bossRoom = 0x16F020, bossFloor = 0x16F03C }
-- r35: a palace's layout is 25 bytes a floor, its floors the two nibbles of
-- its floors word (basements + floors above), read at import
M.FLOOR_BYTES = 25
M.MAP, M.COMPASS = 0x33, 0x25
M.EMPTY = 0x0F

local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { layouts = {}, tiles = {}, floors = rom:bytesU16(O.floors, 14),
              remapFrom = rom:bytesU16(O.remapFrom, 3), remapTo = rom:bytesU16(O.remapTo, 3),
              bossRoom = rom:bytesU16(O.bossRoom, 14), bossFloor = {}, pics = rom:bytesU16(O.pics, 744) }
  for i = 0, 13 do
    local lp = rom:u32(O.layoutPtrs + i * 4) - 0x08000000
    local fw = t.floors[i + 1]
    local lay = rom:bytesU8(lp, M.FLOOR_BYTES * (band(fw, 0xF) + band(rshift(fw, 4), 0xF)))
    local n = 0
    for _, v in ipairs(lay) do if v ~= M.EMPTY then n = n + 1 end end
    t.layouts[i + 1] = lay
    t.tiles[i + 1] = rom:bytesU8(rom:u32(O.tilePtrs + i * 4) - 0x08000000, n)
    t.bossFloor[i + 1] = s16(rom:u16(O.bossFloor + i * 2))
  end
  check(t.layouts[3][44 - 25 + 1] ~= nil and t.floors[5] == 0x70 and t.bossRoom[3] == 200 and t.bossFloor[5] == 6
        and t.remapTo[1] == 0xA9 and t.pics[1] == 0x2261 and #t.tiles[1] > 0, "dungeon map tables")
  t.art = M.extractArt(rom, R, check)
  return t
end

-- r40: the screen's own art, as the GBA's submodules 0 / 1 (0x080B3770 /
-- 0x080B38BC) load it, read at import:
--   BG chars (char base 0x06004000): 0x0812FB90 LZ77s chrA[lang]
--     (0x0822B9C8) to 0x06007000 (chars 0x180-0x1FF: the frame); 0x0812ECDC
--     LZ77s chrB[lang] (0x0822B9AC) to 0x06008000 (0x200-0x23F: grid, floor
--     labels) and the three sheets of sprite set 0x80 | palace (bytes 1-3 of
--     0x0822B624 [set * 4], sheet pointers 0x0822B324) to 0x06008800 /
--     9000 / 9800 (0x240-0x2FF: the room pictures);
--   the frame map: LZ77 0x083BFDC4 -> 0x0600F000 (BG3, 32 x 32 words);
--   palette rows 0-1: 0x08130384 with 0xCAA = 1 copies 8 runs of 4 colours,
--     0x20 bytes apart, from the palette blob 0x3BD758 + 0x610 + 2 *
--     u16 0x0822BC0C [1]; rows 2-7: 0x08133304 copies 96 colours from the
--     blob + 0x1700.
M.ART = { chrA = 0x22B9C8, chrB = 0x22B9AC, sets = 0x22B624, sheets = 0x22B324, frame = 0x3BFDC4,
          palBlob = 0x3BD758, palSel = 0x22BC0C, palRows27 = 0x1700 }
local function hexOf(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
function M.extractArt(rom, R, check)
  local A = M.ART
  local lang = (R and R.ui and R.ui.lang) or 1
  local function lz(p, n, what)
    local d = p and rom:lz77(p)
    check(d and #d == n, "dungeon map art: " .. what)
    return d
  end
  local fr = lz(A.frame, 0x800, "frame map")
  local frame = {}
  for i = 0, 1023 do frame[i + 1] = fr:byte(2 * i + 1) + fr:byte(2 * i + 2) * 256 end
  local art = { frame = frame, chrA = hexOf(lz(rom:ptr(A.chrA + lang * 4), 0x1000, "frame chars")),
                chrB = hexOf(lz(rom:ptr(A.chrB + lang * 4), 0x800, "grid chars")), sets = {}, sheets = {} }
  for d = 0, 13 do
    local set = bit.bor(0x80, d)
    local ids = { rom:u8(A.sets + set * 4 + 1), rom:u8(A.sets + set * 4 + 2), rom:u8(A.sets + set * 4 + 3) }
    art.sets[d + 1] = ids
    for _, id in ipairs(ids) do
      if not art.sheets[id + 1] then art.sheets[id + 1] = hexOf(lz(rom:ptr(A.sheets + id * 4), 0x800, "sheet " .. id)) end
    end
  end
  -- the floor box and label words of 0x080B3E84 / 0x080B4B04: the box's
  -- top row 0x16EFD8 (corner, edge, corner), its sides and inside 0x16EFE0,
  -- the bottom row the top with the v-flip bit (0x800); the labels' digits
  -- 0x16EFE6, 'B' and 'F' from the literal pools at 0x080B42BC / 0x080B4310
  art.boxTop = rom:bytesU16(0x16EFD8, 3)
  art.boxMid = rom:bytesU16(0x16EFE0, 3)
  art.digits = rom:bytesU16(0x16EFE6, 8)
  art.letB, art.letF = rom:u16(0x0B42BC), rom:u16(0x0B4310)
  -- the rooms panel's background grid (BG1, written by submodule 1 from
  -- the literals at 0x080B3E70 / 78 / 7C: a column tile, two edge tiles)
  art.grid = { rom:u16(0x0B3E70), rom:u16(0x0B3E78), rom:u16(0x0B3E7C) }
  check(art.boxTop[2] == art.boxTop[1] + 1 and art.boxMid[2] == 0x200 and art.letF == art.letB + 1
        and art.digits[1] == art.letB + 2 and art.grid[2] == art.grid[1] + 1, "dungeon map box words")
  local pal = {}
  local p01 = A.palBlob + 0x610 + 2 * rom:u16(A.palSel + 2)
  for g = 0, 7 do for k = 0, 3 do pal[#pal + 1] = rom:u16(p01 + g * 0x20 + k * 2) end end
  for k = 0, 95 do pal[#pal + 1] = rom:u16(A.palBlob + A.palRows27 + k * 2) end
  art.pal = pal   -- 128 colours: rows 0-7
  check(#pal == 128 and frame[1] ~= nil, "dungeon map palette")
  return art
end

local function T(game) local t = game.data.t and game.data.t.dmap return t and t.layouts and t end
M.tabs = T

-- ------------------------------------------------------------ state
local function palaceIndex(game)
  local ent = game.interior and game.interior.entrance
  local p = ent and ent.palace or 0xFF
  if p == 0xFF then return nil end
  return rshift(p, 1)
end
M.palaceIndex = palaceIndex

local function floorsOf(tb, d)
  local f = tb.floors[d + 1] or 0
  return band(f, 0xF), band(rshift(f, 4), 0xF)
end

-- the layout floor holding a room's low byte (Tab21 / 22 remap first)
function M.whereIs(tb, d, room)
  local low = band(room, 0xFF)
  for i, r in ipairs(tb.remapFrom) do if r == low then low = tb.remapTo[i] end end
  local lay = tb.layouts[d + 1]
  for k, v in ipairs(lay) do
    if v == low then
      local c = (k - 1) % 25
      return math.floor((k - 1) / 25), c % 5, math.floor(c / 5)
    end
  end
end

local function owned(game, d, id)
  local tb = T(game)
  for _, e in ipairs(game.itemLog or {}) do
    if e.id == id and e.room and M.whereIs(tb, d, e.room) then return true end
  end
  local p = game.progress
  return p.dmapOwned and p.dmapOwned[d .. ":" .. id] or false
end
M.owned = owned

function M.open(game)
  local tb = T(game)
  local d = palaceIndex(game)
  if not (tb and d and tb.layouts[d + 1]) then return false end
  local below, above = floorsOf(tb, d)
  local f = M.whereIs(tb, d, game.interior.room)
  local cur = f or below            -- (layout floor; the ground floor = below)
  game.dmap = { d = d, floor = cur, linkFloor = f, below = below, above = above, t = 0,
                map = owned(game, d, M.MAP), compass = owned(game, d, M.COMPASS) }
  game.dmapOpened = (game.dmapOpened or 0) + 1
  return true
end

function M.update(game)
  local m = game.dmap
  local inp = game.input
  local function pr(b) return inp and inp.wasPressed(b) end
  m.t = m.t + 1
  if pr("l") or pr("b") or pr("start") then game.dmap = nil return end
  -- (the cartridge draws two floors at once and scrolls with 3+; ours shows
  -- one floor, so up / down also switch a 2-floor palace's)
  local n = m.below + m.above
  if n >= 2 then
    if pr("up") and m.floor < n - 1 then m.floor = m.floor + 1 end
    if pr("down") and m.floor > 0 then m.floor = m.floor - 1 end
  end
end

-- a cell's room picture and whether it shows (DungeonMap_DrawSingleRowOfRooms)
function M.cell(game, m, floor, col, row)
  local tb = T(game)
  local lay = tb.layouts[m.d + 1]
  local v = lay[floor * 25 + row * 5 + col + 1]
  if not v or v == M.EMPTY then return nil end
  local count = 0
  for k = 1, #lay do
    if lay[k] == v then break end
    if lay[k] ~= M.EMPTY then count = count + 1 end
  end
  local pic = tb.tiles[m.d + 1][count + 1] or 0
  local seenAll = game.progress.dmapSeen or {}
  local room = v
  local seen = seenAll[tostring(room)]
  return { room = room, pic = pic, seen = seen, show = seen or m.map }
end

-- ------------------------------------------------------------ drawing
local function label(n)
  if n >= 0 then return (n + 1) .. "F" end
  return "B" .. (-n)
end

-- r40: the screen from the cartridge's art (M.ART): BG3 the frame map, BG2
-- the floor boxes with their labels, BG0 the room pictures (kDungMap_Tab23
-- words, 2 x 2 chars a room), two floors at once (the cartridge's view of a
-- palace with 3+ floors scrolls; ours shows the selected floor's pair). The
-- floor list on the left and the markers stay ours (text, blinking boxes).
-- OURS: the BG scroll offsets are not traced -- boxes at tile column 16, the
-- floors 10 rows apart, rooms 2 x 2 tiles from the box's corner.
local function artPixels(game, m)
  local tb = T(game)
  local art = tb.art
  local d = m.d
  M.artCache = M.artCache or {}
  local function bytes(key, hx)
    local c = M.artCache[key]
    if c then return c end
    c = {}
    for i = 1, #hx, 2 do c[#c + 1] = tonumber(hx:sub(i, i + 1), 16) end
    M.artCache[key] = c
    return c
  end
  local ids = art.sets[d + 1]
  local regions = {
    { 0x180, 0x80, bytes("A", art.chrA) }, { 0x200, 0x40, bytes("B", art.chrB) },
    { 0x240, 0x40, bytes("s" .. ids[1], art.sheets[ids[1] + 1]) },
    { 0x280, 0x40, bytes("s" .. ids[2], art.sheets[ids[2] + 1]) },
    { 0x2C0, 0x40, bytes("s" .. ids[3], art.sheets[ids[3] + 1]) },
  }
  local W = 240
  local px = {}
  local function put(word, tx, ty)
    if tx < 0 or ty < 0 or tx >= 30 or ty >= 20 then return end
    local c, hf, vf, pr = band(word, 0x3FF), band(word, 0x400) ~= 0, band(word, 0x800) ~= 0, rshift(word, 12)
    local src, o
    for _, r in ipairs(regions) do if c >= r[1] and c < r[1] + r[2] then src, o = r[3], (c - r[1]) * 32 end end
    if not src then return end
    for y = 0, 7 do
      for x = 0, 7 do
        local sx, sy = hf and 7 - x or x, vf and 7 - y or y
        local b = src[o + sy * 4 + rshift(sx, 1) + 1] or 0
        local n = (sx % 2 == 1) and rshift(b, 4) or band(b, 15)
        if n ~= 0 then px[(ty * 8 + y) * W + tx * 8 + x] = pr * 16 + n end
      end
    end
  end
  -- BG1 (priority 3, under BG0): the rooms panel's grid, 11 columns from
  -- tile 16 (even rows: column, then edge pairs; odd rows: columns)
  if art.grid then
    for ty = 0, 19 do
      for k = 0, 10 do
        local w
        if k % 2 == 0 then w = (ty % 2 == 0 and k > 0) and art.grid[3] or art.grid[1]
        elseif ty % 2 == 0 then w = art.grid[2] end
        if w then put(w, 16 + k, ty) end
      end
    end
  end
  -- BG0 (priority 3): the rooms
  local n = m.below + m.above
  local top = math.min(n - 1, math.max(m.floor, 1))
  local floors = n >= 2 and { top, top - 1 } or { 0 }
  for k, f in ipairs(floors) do
    local by = (k - 1) * 10
    for row = 0, 4 do
      for col = 0, 4 do
        local c = M.cell(game, m, f, col, row)
        if c and c.show then
          for q = 0, 3 do
            local w = tb.pics[(c.pic or 0) * 4 + q + 1] or 0x2200
            -- a room only mapped, not seen: the next palette row (the
            -- cartridge's dim rooms; Tab23's words are row 2)
            if not c.seen then w = w + 0x1000 end
            put(w, 16 + col * 2 + q % 2, by + row * 2 + math.floor(q / 2))
          end
        end
      end
    end
  end
  -- BG2 (priority 2): each floor's box and its label
  for k, f in ipairs(floors) do
    local by = (k - 1) * 10
    for x = 0, 11 do
      local i = (x == 0 and 1) or (x == 11 and 3) or 2
      put(art.boxTop[i], 16 + x, by)
      put(bit.bor(art.boxTop[i], 0x800), 16 + x, by + 9)
      for y = 1, 8 do put(art.boxMid[i], 16 + x, by + y) end
    end
    local rel = f - m.below
    local word
    if rel >= 0 then word = { art.digits[rel + 1], art.letF } else word = { art.letB, art.digits[-rel], art.letF } end
    for j, w in ipairs(word) do if w then put(w, 16 - #word + j - 1, by + 8) end end
  end
  -- BG3 (priority 1): the frame
  for ty = 0, 19 do for tx = 0, 29 do put(art.frame[ty * 32 + tx + 1], tx, ty) end end
  return px, floors
end
M.artPixels = artPixels

local function artImage(game, m)
  local tb = T(game)
  local seen = 0
  for _ in pairs(game.progress.dmapSeen or {}) do seen = seen + 1 end
  local key = table.concat({ m.d, m.floor, tostring(m.map), seen }, ":")
  if M.artKey == key and M.artIm then return M.artIm, M.artFloors end
  local px, floors = artPixels(game, m)
  local pal = tb.art.pal
  local img = love.image.newImageData(240, 160)
  img:mapPixel(function(x, y)
    local i = px[y * 240 + x]
    local c = (i and pal[i + 1]) or pal[1] or 0
    return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31, 1
  end)
  if M.artIm then pcall(M.artIm.release, M.artIm) end
  M.artIm = love.graphics.newImage(img)
  M.artIm:setFilter("nearest", "nearest")
  M.artKey, M.artFloors = key, floors
  return M.artIm, floors
end

function M.drawArt(game)
  local m = game.dmap
  local tb = T(game)
  local g = love.graphics
  local im, floors = artImage(game, m)
  g.push("all")
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  g.draw(im, 0, 0)
  M.font = M.font or g.newFont(8)
  g.setFont(M.font)
  -- the floor list (ours) in the left panel
  local n = m.below + m.above
  for i = 0, n - 1 do
    local fy = 128 - i * 12
    local sel = i == m.floor
    g.setColor(sel and 1 or 0.6, sel and 0.85 or 0.6, sel and 0.3 or 0.6, 1)
    g.print(label(i - m.below), 36, fy)
    if i == m.linkFloor and band(rshift(m.t, 4), 1) == 0 then g.print(">", 26, fy) end
    if m.compass and i == m.below + (tb.bossFloor[m.d + 1] or -256) then
      g.setColor(0.9, 0.2, 0.2, 1); g.print("*", 56, fy)
    end
  end
  -- markers on the shown floors
  for k, f in ipairs(floors) do
    local by = (k - 1) * 80
    if m.compass and f == m.below + (tb.bossFloor[m.d + 1] or -256) and band(rshift(m.t, 3), 1) == 0 then
      for row = 0, 4 do for col = 0, 4 do
        local c = M.cell(game, m, f, col, row)
        if c and c.room == tb.bossRoom[m.d + 1] then
          g.setColor(0.95, 0.2, 0.2, 1); g.rectangle("fill", 128 + col * 16 + 5, by + row * 16 + 5, 6, 6)
        end
      end end
    end
    if f == m.linkFloor and band(rshift(m.t, 3), 3) ~= 0 then
      local _, col, row = M.whereIs(tb, m.d, game.interior.room)
      if col then
        local lk = game.link
        g.setColor(0.2, 1, 0.3, 1)
        g.rectangle("fill", 128 + col * 16 + rshift(band(lk.x, 0x1E0), 5) + 2, by + row * 16 + rshift(band(lk.y, 0x1E0), 5) + 2, 4, 4)
      end
    end
  end
  g.pop()
end

function M.draw(game)
  local m = game.dmap
  local tb = T(game)
  if tb.art and tb.art.frame then return M.drawArt(game) end
  local g = love.graphics
  g.push("all")
  g.clear(0, 0, 0, 1)
  M.font = M.font or g.newFont(8)
  g.setFont(M.font)
  -- the floor list (left), the selected floor's 5 x 5 rooms (right)
  local n = m.below + m.above
  for i = 0, n - 1 do
    local fy = 120 - i * 14
    local sel = i == m.floor
    g.setColor(sel and 1 or 0.55, sel and 0.85 or 0.55, sel and 0.3 or 0.55, 1)
    g.print(label(i - m.below), 20, fy)
    if i == m.linkFloor and band(rshift(m.t, 4), 1) == 0 then g.print(">", 10, fy) end
    if m.compass and i == m.below + (tb.bossFloor[m.d + 1] or -256) then
      g.setColor(0.9, 0.2, 0.2, 1); g.print("*", 44, fy)
    end
  end
  local ox, oy = 92, 24
  g.setColor(0.25, 0.25, 0.35, 1)
  g.rectangle("line", ox - 4.5, oy - 4.5, 5 * 22 + 8, 5 * 22 + 8)
  local pics = tb.pics
  for row = 0, 4 do
    for col = 0, 4 do
      local c = M.cell(game, m, m.floor, col, row)
      if c and c.show then
        local x, y = ox + col * 22, oy + row * 22
        local b = c.seen and 0.75 or 0.4
        for q = 0, 3 do
          local w = pics[(c.pic or 0) * 4 + q + 1] or 0x2200
          if w ~= 0x2200 then
            g.setColor(b * 0.55, b * 0.8, b, 1)
            g.rectangle("fill", x + (q % 2) * 10, y + math.floor(q / 2) * 10, 10, 10)
          end
        end
        g.setColor(b, b, b, 1)
        g.rectangle("line", x + 0.5, y + 0.5, 19, 19)
        -- the boss's room (with the compass)
        if m.compass and m.floor == m.below + (tb.bossFloor[m.d + 1] or -256) and c.room == tb.bossRoom[m.d + 1]
           and band(rshift(m.t, 3), 1) == 0 then
          g.setColor(0.95, 0.2, 0.2, 1)
          g.rectangle("fill", x + 7, y + 7, 6, 6)
        end
      end
    end
  end
  -- Link's marker
  if m.floor == m.linkFloor and band(rshift(m.t, 3), 3) ~= 0 then
    local _, col, row = M.whereIs(tb, m.d, game.interior.room)
    if col then
      local lk = game.link
      local x = ox + col * 22 + rshift(band(lk.x, 0x1E0), 5) + 2
      local y = oy + row * 22 + rshift(band(lk.y, 0x1E0), 5) + 2
      g.setColor(0.2, 1, 0.3, 1)
      g.rectangle("fill", x, y, 4, 4)
    end
  end
  g.setColor(1, 1, 1, 1)
  g.print("LEVEL " .. (m.d >= 2 and (m.d - 1) or 0), 8, 6)
  g.pop()
end

-- ------------------------------------------------------------ install
function M.install(G)
  local A = require("src.zelda.alttp.Actors")
  local er0 = A.enterRoom
  function A:enterRoom(inside, ...)
    local r = er0(self, inside, ...)
    local game = self.game
    if game and inside and inside.room and T(game) then
      local p = game.progress
      p.dmapSeen = p.dmapSeen or {}
      p.dmapSeen[tostring(band(inside.room, 0xFF))] = true
    end
    return r
  end
  -- L in a palace (Game.menuWanted only asks for L outside): the map opens
  -- here, the original update then runs this one frame
  local mw0 = G.menuWanted
  function G:menuWanted()
    local r = mw0(self)
    if r then return r end
    if self.state == "room" and T(self) and palaceIndex(self) and self.input and self.input.wasPressed("l")
       and not (self.roomScroll or self.opening or self.textBox or self.scroll) then
      M.open(self)
    end
    return r
  end
  local upd0 = G.update
  function G:update(dt)
    if self.dmap then return M.update(self) end
    return upd0(self, dt)
  end
  local dr0 = G.draw
  function G:draw(...)
    if self.dmap and not self.headless then return M.draw(self) end
    return dr0(self, ...)
  end
end

return M
