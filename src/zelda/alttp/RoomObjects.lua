-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROOM OBJECTS THE GBA DRAWS OVER ITS PRE-RENDERED MAPS (round 16).
--
-- The GBA room loader 0x0807FF10 decompresses three pre-rendered maps and
-- then runs the SNES room drawing for the objects whose look depends on the
-- game's state (found by hooking its object drawer 0x0807FC20, door drawer
-- 0x0807FBC4 and push-block drawer 0x0807D0EC in the scratch interpreter and
-- diffing the maps, r16/py/objtrace.py):
--
--   * subtype-3 0x12 rupee floor (SNES case 0x12: three columns of three
--     rupees, words from ROM 0x16623C; not drawn once a rupee was taken,
--     dung_savegame_state_bits 0x1000);
--   * subtype-3 0x2C large pick-up block (DrawBigGraySegment x 4, 16 words
--     from 0x165382) and 0x47 bomb floor (RoomDraw_BombableFloor, 16 words
--     from 0x164740): manipulable objects 0x70 + n;
--   * subtype-3 0x71 "floor light" (Blind's room): the GBA clears the whole
--     lower map to the blank word while the light is off;
--   * the push blocks of the new-game table (ROM 0x163430, room / tilemap
--     pairs, CpuSet to RAM 0x020029C0 by 0x08078EE2; drawn by 0x0807D0EC
--     with the words 0x2122/0x2123/0x2132/0x2133, read from its literal);
--   * every door (the door pictures, Interior:predrawDoors).
--
-- Pushing a block (SNES InitializePushBlock / Dungeon_PushBlock_Handler /
-- PushBlock_ApplyVelocity / PushBlock_CheckForPit): Link walks into it for
-- 21 frames (gravestone_push_timeout), the block checks the two cells in
-- front (PushBlock_AttemptToPushTheBlock: attribute class T), then slides
-- 16 px at 12/16 px a frame; at the end it is drawn again as a fixed block
-- (attribute 0x27); dung_flag_movable_block_was_pushed toggles (room tags
-- 0x0B-0x13 open the shutters); a pit (attribute 0x20) takes it.
-- Rupee floor (Link_HandleMovingFloor... tiledetect_misc_tiles 0x2200,
-- Dungeon_DeleteRupeeTile): a rupee cell under Link gives 5 rupees, its two
-- cells become the floor word and the room remembers it.

local bit = require("bit")
local band, rshift, bor = bit.band, bit.rshift, bit.bor

local RO = {}

-- ---------------------------------------------------------------- import
function RO.extract(rom, R, check)
  local M = R.roomObj
  local out = { blocks = {} }
  for i = 0, 255 do
    local room = rom:u16(M.blockTable + i * 4)
    if room == 0xFFFF then break end
    local pos = rom:u16(M.blockTable + i * 4 + 2)
    local list = out.blocks[room + 1] or {}
    out.blocks[room + 1] = list
    list[#list + 1] = pos
  end
  out.blockWord = rom:u16(M.blockWordLit)
  out.rupee = rom:bytesU16(M.rupeeWords, 2)
  out.bigBlock = rom:bytesU16(M.bigBlockWords, 16)
  out.bombFloor = rom:bytesU16(M.bombFloorWords, 16)
  -- Dungeon_DeleteRupeeTile's floor word (literal of 0x08087FC4) and the
  -- blank word 0x0808072C fills the lower map with (movs r2, #imm; lsls 1)
  out.floorWord = rom:u16(M.rupeeFloorLit)
  out.blankWord = rom:u8(M.blindBlankImm) * 2
  check(out.floorWord < 0x10000 and band(out.floorWord, 0x3FF) < 0x200 and out.blankWord < 0x400, "rupee floor / blank words")
  check(out.blocks[0x11 + 1] and #out.blocks[0x11 + 1] >= 1, "push block table")
  check(band(out.blockWord, 0x3FF) < 0x200 and out.rupee[2] == out.rupee[1] + 1, "push block / rupee words")
  check(out.bigBlock[2] == out.bigBlock[1] + 0x10 and out.bombFloor[2] == out.bombFloor[1] + 1, "block words")
  return out
end

-- ---------------------------------------------------------------- load
-- patches for the object's map: `lower` = the lower map (our "bg3", the
-- GBA's 0x0201A000)
local function put(self, lower, cell, w)
  if cell < 0 or cell > 4095 then return end
  if lower then self.patch3[cell] = w else self.patch[cell] = w end
end
local function get(self, lower, cell)
  local O = require("src.zelda.alttp.Overworld")
  local p = lower and self.patch3 or self.patch
  local n = lower and (self.bg3 or self.bg2) or self.bg2
  return p[cell] or self.data:roomWord(n, O.cellIndex(cell % 64, math.floor(cell / 64)))
end
RO.get = get

-- SNES RoomDraw_Rightwards2x2: UL, LL, UR, LR
local function draw2x2(self, lower, cell, w1, w2, w3, w4)
  put(self, lower, cell, w1); put(self, lower, cell + 64, w2)
  put(self, lower, cell + 1, w3); put(self, lower, cell + 65, w4)
end

-- called by Interior:loadRoom before the attribute tables are built (the
-- GBA draws these before Dungeon_LoadBasicAttribute)
function RO.load(self)
  local ro = self.data.roomIdx and self.data.roomIdx.roomObj
  self.blocks, self.rupeeCells, self.misc = {}, {}, {}
  if not ro then return end
  local mem = self.mem
  local list = self.data.roomIdx.specials and self.data.roomIdx.specials[self.room + 1] or {}
  for _, o in ipairs(list) do
    if o.s == 3 then
      local lower = o.layer == 3
      local cell = o.y * 64 + o.x
      if o.id == 0x12 and not mem.rupeeTaken then
        -- three columns two cells apart, rows 0/3/6 (src[0]) and 1/4/7 (src[1])
        for i = 0, 2 do
          for _, r in ipairs({ 0, 3, 6 }) do
            put(self, lower, cell + i * 2 + r * 64, ro.rupee[1])
            put(self, lower, cell + i * 2 + (r + 1) * 64, ro.rupee[2])
            self.rupeeCells[cell + i * 2 + r * 64] = true
          end
        end
      elseif o.id == 0x2C or o.id == 0x47 then
        local src = (o.id == 0x2C) and ro.bigBlock or ro.bombFloor
        local offs = { 0, 2, 128, 130 }
        for k = 0, 3 do
          local c = cell + offs[k + 1]
          draw2x2(self, lower, c, src[k * 4 + 1], src[k * 4 + 2], src[k * 4 + 3], src[k * 4 + 4])
          self.misc[#self.misc + 1] = { kind = (o.id == 0x2C) and "big" or "bomb", cell = c, lower = lower, order = o }
        end
      elseif o.id == 0x71 and not (self.memory and self.memory[0x65] and self.memory[0x65].light) then
        -- 0x08080718: save word of room 0x65 bit 0x100 clear -> CpuSet fill
        for c = 0, 4095 do self.patch3[c] = ro.blankWord end
      end
    end
  end
  -- push blocks (the new-game table: dsto_x2 = 2 * cell, 0x2000 = lower map)
  local w = ro.blockWord
  for i, pos in ipairs(ro.blocks[self.room + 1] or {}) do
    local lower = band(pos, 0x2000) ~= 0
    local cell = band(rshift(pos, 1), 0xFFF)
    local b = { cell = cell, lower = lower, index = i,
                under = { get(self, lower, cell), get(self, lower, cell + 64), get(self, lower, cell + 1), get(self, lower, cell + 65) } }
    draw2x2(self, lower, cell, w, w + 0x10, w + 1, w + 0x11)
    self.blocks[#self.blocks + 1] = b
  end
end

-- after the attribute tables: the manipulable objects' attributes 0x70 + n
-- (SNES Dungeon_LoadObjectAttribute: every misc object but the bomb floor
-- segments, 2 x 2 cells; the pots are numbered in the same run, markPots)
function RO.markAttrs(self, first)
  local n = first
  for _, m in ipairs(self.misc) do
    m.attr = 0x70 + band(m.n or 0, 15)
    if m.kind == "big" then
      for _, d in ipairs({ 0, 1, 64, 65 }) do
        local c = m.cell + d
        local t, g = self.attrs, self.grid
        if m.lower then t, g = self.attrsLo, self.gridLo end
        t[c] = m.attr; g[c] = true
      end
    end
  end
  for _, b in ipairs(self.blocks) do
    b.attr = 0x70 + band(n, 15)
    for _, d in ipairs({ 0, 1, 64, 65 }) do
      local c = b.cell + d
      if b.lower then self.attrsLo[c] = b.attr; self.gridLo[c] = true
      else self.attrs[c] = b.attr; self.grid[c] = true end
    end
    n = n + 1
  end
end

-- ---------------------------------------------------------------- play
-- SNES PushBlock_AttemptToPushTheBlock's attribute classes: 0 = the block
-- may move onto it (9 too)
local FREE = {}
for _, a in ipairs({ 0, 5, 6, 7, 8, 9, 0x0A, 0x0C, 0x0D, 0x0E, 0x0F, 0x1C, 0x20, 0x23, 0x24, 0x25,
                     0x3A, 0x3B, 0x40, 0x48, 0x4A, 0x60, 0x61, 0x62, 0x64 }) do FREE[a] = true end
RO.FREE = FREE
local STEP = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- the block in front of Link (his facing), or nil
function RO.blockAhead(self, lx, ly, dir)
  local s = STEP[dir]
  if not s then return nil end
  -- the probe points of kDungeon_QueryIfTileLiftable (in front of his body)
  local px = lx + 8 + s[1] * 12
  local py = ly + 16 + s[2] * 12
  local cell = math.floor(py / 8) * 64 + math.floor(px / 8)
  for _, b in ipairs(self.blocks or {}) do
    if not b.fixed and not b.moving and (b.lower or false) == (self.lower or false) then
      for _, d in ipairs({ 0, 1, 64, 65 }) do
        if b.cell + d == cell then return b end
      end
    end
  end
end

-- can the block move one 16 px step in `dir`? (the two cells it moves onto)
function RO.canPush(self, b, dir)
  local s = STEP[dir]
  local t = b.lower and self.attrsLo or self.attrs
  local c0 = b.cell + s[1] * 2 + s[2] * 128
  for _, d in ipairs({ 0, 1, 64, 65 }) do
    local c = c0 + d
    local a = t[c] or 1
    local inBlock = false
    for _, e in ipairs({ 0, 1, 64, 65 }) do if c == b.cell + e then inBlock = true end end
    if not inBlock and not FREE[a] then return false end
  end
  -- no other block there
  for _, o in ipairs(self.blocks) do
    if o ~= b then
      for _, d in ipairs({ 0, 1, 64, 65 }) do
        for _, e in ipairs({ 0, 1, 64, 65 }) do if o.cell + d == c0 + e then return false end end
      end
    end
  end
  return true
end

-- start a push: the old cells get the words that were under the block, the
-- block becomes a moving picture (RoomDraw_16x16Single + Sprite_Dungeon_
-- DrawSinglePushBlock)
function RO.startPush(self, b, dir)
  local w = b.under
  draw2x2(self, b.lower, b.cell, w[1], w[2], w[3], w[4])
  local t, g = self.attrs, self.grid
  if b.lower then t, g = self.attrsLo, self.gridLo end
  for _, d in ipairs({ 0, 1, 64, 65 }) do t[b.cell + d] = 0; g[b.cell + d] = false end
  local s = STEP[dir]
  b.moving = { dir = dir, sx = s[1], sy = s[2], sub = 0, from = b.cell }
  b.px, b.py = (b.cell % 64) * 8, math.floor(b.cell / 64) * 8
end

-- one frame of a moving block; returns true when it stopped this frame
function RO.stepBlock(self, b)
  local m = b.moving
  if not m then return false end
  m.sub = m.sub + 12 * 16
  local px = math.floor(m.sub / 256)
  b.px = (m.from % 64) * 8 + m.sx * px
  b.py = math.floor(m.from / 64) * 8 + m.sy * px
  -- the moving block stays solid where it is (PushBlock_HandleCollision
  -- holds Link against it: he pushes along at the block's speed)
  local g = b.lower and self.gridLo or self.grid
  for c in pairs(b.solid or {}) do g[c] = false end
  b.solid = {}
  for y = math.floor(b.py / 8), math.floor((b.py + 15) / 8) do
    for x = math.floor(b.px / 8), math.floor((b.px + 15) / 8) do
      local c = y * 64 + x
      if not g[c] then g[c] = true; b.solid[c] = true end
    end
  end
  if px >= 16 then
    for c in pairs(b.solid or {}) do g[c] = false end
    b.solid = nil
    b.moving = nil
    b.cell = m.from + m.sx * 2 + m.sy * 128
    self.blockPushed = not self.blockPushed
    local t, g = self.attrs, self.grid
    if b.lower then t, g = self.attrsLo, self.gridLo end
    if t[b.cell] == 0x20 then
      b.fell = true   -- into a pit: gone (it lands in the room below)
      return true
    end
    b.under = { get(self, b.lower, b.cell), get(self, b.lower, b.cell + 64), get(self, b.lower, b.cell + 1), get(self, b.lower, b.cell + 65) }
    local w = self.data.roomIdx.roomObj.blockWord
    draw2x2(self, b.lower, b.cell, w, w + 0x10, w + 1, w + 0x11)
    b.fixed = true
    for _, d in ipairs({ 0, 1, 64, 65 }) do t[b.cell + d] = 0x27; g[b.cell + d] = true end
    return true
  end
  return false
end

-- Link on a rupee cell (attribute 0x60): the cell and the one below or above
-- become floor, +5 rupees; the room remembers (the whole floor is not drawn
-- again, as dung_savegame_state_bits 0x1000)
function RO.takeRupee(self, x, y)
  local cell = math.floor(y / 8) * 64 + math.floor(x / 8)
  local t = self.lower and self.attrsLo or self.attrs
  if t[cell] ~= 0x60 then return false end
  local top = self.rupeeCells[cell] and cell or (self.rupeeCells[cell - 64] and cell - 64) or nil
  if not top then return false end
  self.rupeeCells[top] = nil
  local floor = self.data.roomIdx.roomObj.floorWord
  for _, c in ipairs({ top, top + 64 }) do
    self.patch[c] = floor
    self.attrs[c] = 0; self.grid[c] = false
  end
  self.mem.rupeeTaken = true
  return true
end

-- one room frame (Escape:escapeRoomFrame, before the key doors): moving
-- blocks, the rupee floor under Link, starting a push. Returns nothing (Link
-- keeps walking: on the cartridge he pushes along with the block).
local DIRS = { [0] = "up", [2] = "down", [4] = "left", [6] = "right" }
RO.PUSH_FRAMES = 21    -- gravestone_push_timeout (player.c 0x87D...: 21)
function RO.frame(game, inp)
  local inside, lk = game.interior, game.link
  if not inside or not inside.blocks then return end
  for _, b in ipairs(inside.blocks) do
    if b.moving then
      if RO.stepBlock(inside, b) then
        game.roomImages = nil
        game.blocksPushed = (game.blocksPushed or 0) + 1
      end
    end
  end
  -- the rupee floor: the cell under Link's feet (SNES tile detection at
  -- y + 16 .. y + 23, x + 8)
  if inside.rupeeCells and next(inside.rupeeCells) then
    for _, p in ipairs({ { 8, 16 }, { 8, 22 } }) do
      if RO.takeRupee(inside, lk.x + p[1], lk.y + p[2]) then
        game.stats.rupees = math.min(999, game.stats.rupees + 5)
        game.roomImages = nil
        game.rupeeFloorTaken = (game.rupeeFloorTaken or 0) + 1
      end
    end
  end
  -- pushing: one direction held, the one Link faces, into a block
  local dir = DIRS[lk.facing]
  local held = 0
  for _, k in ipairs({ "up", "down", "left", "right" }) do if inp[k] then held = held + 1 end end
  local b = (held == 1 and dir and inp[dir]) and RO.blockAhead(inside, lk.x, lk.y, dir) or nil
  if b then
    game.pushT = (game.pushT or 0) + 1
    if game.pushT > RO.PUSH_FRAMES then
      game.pushT = 0
      if RO.canPush(inside, b, dir) then
        RO.startPush(inside, b, dir)
        game.roomImages = nil
      end
    end
  else
    game.pushT = 0
  end
end

-- the moving block's picture (Sprite_Dungeon_DrawSinglePushBlock: an OBJ
-- over the room; OURS: the block's own map words drawn as one 16 x 16 image)
function RO.drawMoving(game, cx, cy)
  local inside = game.interior
  if not inside or not inside.blocks then return end
  for _, b in ipairs(inside.blocks) do
    if b.moving and b.px then
      if not inside.blockImg and game.view then
        local w = inside.data.roomIdx.roomObj.blockWord
        local View = require("src.zelda.alttp.View")
        local id = love.image.newImageData(16, 16)
        View.fill(id, 16, 16, inside:wordsPixels({ w, w + 0x10, w + 1, w + 0x11 }), inside:palette())
        inside.blockImg = love.graphics.newImage(id)
        inside.blockImg:setFilter("nearest", "nearest")
      end
      if inside.blockImg then love.graphics.draw(inside.blockImg, b.px - cx, b.py - cy) end
    end
  end
end

return RO
