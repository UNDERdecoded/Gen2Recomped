-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 62: the exploding wall (door type 0x30) and the room tag that blows
-- it up when a pull switch is pulled (RoomTag_PullSwitchExplodingWall).
--
-- Skull Woods 0x58: the big chest (Fire Rod) sits in the south-west
-- quarter's top, walled off by pits; the north hole (entrance 0x76) lands
-- in the north-east. The way between is the wall under the north-west
-- quarter: the lever (sprite 0x04, Traps27) in the north-west sets
-- dung_flag_statechange_waterpuzzle (+0xBC0) and room tag 0x28 blows the
-- wall open. The port skipped door type 0x30 and tag 0x28.
--
-- GBA, all read at import from the code below:
--   * the tag table (`ldr` at 0x0807B564): the tag whose routine is
--     0x0807B634 (if +0xBC0: bl 0x0807A178) -- tag 0x28 on this cartridge;
--   * 0x0807A178: the first door slot with (type & 0xFE) == 0x30 -> +0xAFE;
--     the blast's spot from the slot's +0x18D0 (= the door's tilemap offset
--     + `adds r1, #n` 0x0807E7D4) plus kTab[(link_y >> 8 & 1) + 1] (tables
--     at the literals 0x0807A180 / 0x0807A182: direction byte / tilemap
--     add) -> x = (d & 0x7E) * 4, y = (d & 0x1F80) >> 4; sound `movs r0,
--     #n` 0x0807A22E; +0xAFC = `movs r0, #n` 0x0807A23A; the tag cleared;
--     AncillaAdd_BlastWall 0x08123B60 (two ancillae 0x33);
--   * Ancilla33_BlastWall 0x08123D00: a running blast (state 1..) steps
--     every `movs r0, #n` 0x08123D78 frames, spawns its explosions while the
--     old state <= `cmp #n` 0x08123D48, stops at `cmp #n` 0x08123D5A; an idle
--     one starts when the other is at state `cmp #n` 0x08123D88 with timer
--     `cmp #n` 0x08123D94, up to `cmp #n` 0x08123DA8 starts; its four spots
--     move `movs r4, #n` 0x08123DEC px apart along the wall (the two first
--     of 0x0818045C's spots (literal 0x08123C24) one way, the two last the
--     other), base + 0x0818047C / 0x08180484 (literals 0x08123BFE /
--     0x08123C0E) by the direction byte; sound `movs r0, #n` 0x08123C7A;
--   * Dungeon (0x080892CC, from the dungeon frame 0x080707DC while +0xAFC):
--     Link held (+0x1770); each frame the first blast is at the start state:
--     the slot's offset -= 2 (0x08089268), the wall drawn (0x08089110: two
--     columns of 12 rows from 0x08167650 (literal 0x08089116), +0xAFC - 1
--     columns of its word 24, two more columns from word 25), +0xAFC +=
--     `adds r0, #n` 0x080892F8; at `cmp r0, #n` 0x08089300 the door is open:
--     +0xBFE |= 0x081676B2[slot] (literal 0x08089308), attributes again;
--   * a room loaded with the wall open (RoomDraw door type 0x30, 0x0807E7B0):
--     its own position table (literal 0x0807E7B4), two pieces of six rows
--     (0x0807E604: two columns, `movs r0, #n` 0x0807E618 columns of word 12,
--     two columns from word 13) from the pointers at the literals 0x0807E842
--     / 0x0807E86C + `adds r0, #n` (0x0807E844 / 0x0807E86E), the second
--     piece `movs r0, #n; lsls` 0x0807E84C bytes further.
--
-- OURS: the blasts are drawn with the bomb's explosion (superFx: no damage),
-- the flying debris (ancilla 0x32, 0x08123F94) is not drawn; the opened
-- state is the room's memory (mem.blast62), the cartridge's door bit.

local M = {}

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

M.TAG_TABLE_LIT = 0x0807B564   -- `ldr r5, =table` in the tag dispatcher 0x0807B54C
M.PULL_TAG_FN = 0x0807B634
M.OPEN_FN = 0x0807A178
M.SITES = {
  doorAdd = 0x0807E7D4, dirLit = 0x0807A180, addLit = 0x0807A182, sndOpen = 0x0807A22E,
  afcStart = 0x0807A23A, timer = 0x08123D78, spawnMax = 0x08123D48, endState = 0x08123D5A,
  startState = 0x08123D88, startTimer = 0x08123D94, starts = 0x08123DA8, step = 0x08123DEC,
  ptsLit = 0x08123C24, offXLit = 0x08123BFE, offYLit = 0x08123C0E, sndSeg = 0x08123C7A,
  liveLit = 0x08089116, afcStep = 0x080892F8, afcEnd = 0x08089300, maskLit = 0x08089308,
  posLit = 0x0807E7B4, loadW = 0x0807E618, pieceALit = 0x0807E842, pieceAAdd = 0x0807E844,
  pieceBLit = 0x0807E86C, pieceBAdd = 0x0807E86E, pieceOff = 0x0807E84C,
}

-- ------------------------------------------------------------ import
function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function imm(at) local v = RT.codeImm(rom, at); return v end
  local function lit(at)
    local v, form = RT.codeImm(rom, at)
    if form ~= "ldr" then return nil end
    return v
  end
  local function u16s(addr, n, signed)
    local out = {}
    if not addr then return out end
    for i = 0, n - 1 do
      local v = rom:u16(addr - 0x08000000 + i * 2)
      if signed and v >= 0x8000 then v = v - 0x10000 end
      out[i] = v
    end
    return out
  end
  local t = {}
  -- the tag whose routine is the pull-switch exploding wall
  local tagTab = lit(M.TAG_TABLE_LIT)
  if tagTab then
    for i = 0, 0x3F do
      if rom:u32(tagTab - 0x08000000 + i * 4) == M.PULL_TAG_FN + 1 then t.tag = i break end
    end
  end
  -- that routine reads +0xBC0 and calls the opener
  local callsOpen = RT.blTarget(rom, M.PULL_TAG_FN + 0x10) == M.OPEN_FN
  t.doorAdd = imm(S.doorAdd)
  t.dirTab = u16s(lit(S.dirLit), 5)
  t.addTab = u16s(lit(S.addLit), 5)
  t.sndOpen = imm(S.sndOpen)
  t.afcStart = imm(S.afcStart)
  t.timer, t.spawnMax, t.endState = imm(S.timer), imm(S.spawnMax), imm(S.endState)
  t.startState, t.startTimer, t.starts = imm(S.startState), imm(S.startTimer), imm(S.starts)
  t.step = imm(S.step)
  t.pts = u16s(lit(S.ptsLit), 16, true)
  t.offX = u16s(lit(S.offXLit), 4, true)
  t.offY = u16s(lit(S.offYLit), 4, true)
  t.sndSeg = imm(S.sndSeg)
  t.live = u16s(lit(S.liveLit), 49)
  t.afcStep, t.afcEnd = imm(S.afcStep), imm(S.afcEnd)
  t.mask = u16s(lit(S.maskLit), 16)
  t.pos = u16s(lit(S.posLit), 12)
  t.loadW = imm(S.loadW)
  local pa, pb = lit(S.pieceALit), lit(S.pieceBLit)
  local aa, ab = imm(S.pieceAAdd), imm(S.pieceBAdd)
  local ptrA = pa and aa and rom:u32(pa + aa - 0x08000000)
  local ptrB = pb and ab and rom:u32(pb + ab - 0x08000000)
  t.pieceA = u16s(ptrA, 25)
  t.pieceB = u16s(ptrB, 25)
  t.pieceOff = imm(S.pieceOff)
  check(t.tag ~= nil and callsOpen and t.doorAdd and t.doorAdd % 2 == 0 and t.afcStart and t.afcStep
        and t.afcEnd and t.afcEnd > t.afcStart and t.timer and t.timer > 0 and t.endState and t.step
        and #t.pos == 11 and t.pieceA[24] ~= nil and t.pieceB[24] ~= nil and t.live[48] ~= nil
        and t.pieceOff and t.pieceOff % 0x80 == 0 and t.loadW and t.mask[0] ~= nil and t.pts[15] ~= nil,
        "exploding wall tables (tag %s)", tostring(t.tag))
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.blast62 end
M.tab = tab

-- the room's exploding wall door: slot (1-based) and its tilemap offset
function M.door(data, room, t)
  local list = data.roomIdx and data.roomIdx.doors and data.roomIdx.doors[room + 1]
  for slot, w in ipairs(list or {}) do
    if band(rshift(w, 8), 0xFE) == 0x30 then
      local pos = band(rshift(w, 4), 15)
      local d = t.pos[pos]
      if d then return slot, d end
    end
  end
  return nil
end

-- ------------------------------------------------------------ drawing
-- the attribute of one cell from its word (Interior.loadRoom's rule)
local function reattr(inside, cells)
  local I = require("src.zelda.alttp.Interior")
  local O = require("src.zelda.alttp.Overworld")
  local idx, data = inside.data.roomIdx, inside.data
  local attr = I.attributes(idx, inside.aux)
  local W = I.WALKABLE
  for c in pairs(cells) do
    local w = inside.patch[c] or (inside.bg2 and data:roomWord(inside.bg2, O.cellIndex(c % 64, math.floor(c / 64)))) or 0
    local v = attr[band(w, 0x3FF)] or 0
    if v >= 0x10 and v < 0x1C then v = bit.bor(v, rshift(band(w, 0xC00), 10)) end
    inside.attrs[c] = v
    inside.grid[c] = not W[v]
    if not inside.bg3 and inside.attrsLo then inside.attrsLo[c] = v; inside.gridLo[c] = not W[v] end
  end
end
M.reattr = reattr

-- RoomDraw_ExplodingWall piece (0x0807E604): 2 + n + 2 columns of `rows`
local function piece(inside, cell, src, n, rows, cells)
  local function put(c, w) inside.patch[c] = w; cells[c] = true end
  for r = 0, rows - 1 do
    put(cell + r * 64, src[r]); put(cell + 1 + r * 64, src[r + rows])
    for k = 0, n - 1 do put(cell + 2 + k + r * 64, src[rows * 2]) end
    put(cell + 2 + n + r * 64, src[rows * 2 + 1 + r]); put(cell + 3 + n + r * 64, src[rows * 3 + 1 + r])
  end
end
M.piece = piece

-- the opened wall as a room load draws it
function M.drawOpen(inside, t)
  local slot, d = M.door(inside.data, inside.room, t)
  if not slot then return false end
  local cells = {}
  local c = rshift(d, 1)
  piece(inside, c, t.pieceA, t.loadW, 6, cells)
  piece(inside, c + rshift(t.pieceOff, 1), t.pieceB, t.loadW, 6, cells)
  M.reattr(inside, cells)
  return true
end

-- ------------------------------------------------------------ the blast
local function startBlast(game, inside, t, slot, d)
  local lk = game.link
  local hi = band(rshift(lk.y, 8), 1)
  local dd = d + t.doorAdd + (t.addTab[(hi + 1) * 2] or 0)
  local dir = t.dirTab[(hi + 1) * 2] or 0
  local bx = band(dd, 0x7E) * 4 + (t.offX[rshift(dir, 1)] or 0)
  local by = rshift(band(dd, 0x1F80), 4) + (t.offY[rshift(dir, 1)] or 0)
  local first = (dir <= 3) and 8 or 0
  local spots = {}
  for j = 0, 3 do spots[j + 1] = { bx + t.pts[first + j * 2], by + t.pts[first + j * 2 + 1], (j < 2) and -1 or 1 } end
  local b = { slot = slot, d = d, off = d + t.doorAdd, afc = t.afcStart, st = { [0] = 1, 0 }, tm = { [0] = t.timer, 0 },
              starts = 0, spots = spots, vertical = dir <= 3, segs = 0 }
  inside.blast62 = b
  game.blastStarted = (game.blastStarted or 0) + 1
  local Sfx = require("src.zelda.alttp.Sfx")
  if t.sndOpen then pcall(Sfx.start, game, t.sndOpen, "blastwall") end
  M.explode(game, inside, b, t)
end

M.startBlast = startBlast   -- r63: PushWall63 (tag 0x20) opens the same wall

-- one segment's four explosions (the bomb's picture, no damage)
function M.explode(game, inside, b, t)
  local IT = game.data.roomIdx and game.data.roomIdx.items
  game.anc = game.anc or {}
  for _, s in ipairs(b.spots) do
    game.anc[#game.anc + 1] = { kind = "bomb", superFx = true, center = false, dir = 0, x = s[1], y = s[2],
                                itl = 1, t = IT and IT.bombTab0 and IT.bombTab0[2] or 4, z = 0,
                                lower = inside.lower }
  end
  b.segs = b.segs + 1
  game.blastSegs = (game.blastSegs or 0) + 1
end

-- one frame: the two blast ancillae, then the wall (0x080892CC)
function M.frame(game, inside, t)
  local b = inside.blast62
  for _, k in ipairs({ 1, 0 }) do
    if b.st[k] ~= 0 then
      b.tm[k] = b.tm[k] - 1
      if b.tm[k] == 0 then
        b.st[k] = b.st[k] + 1
        if b.st[k] == t.endState then b.st[k], b.tm[k] = 0, 0 else b.tm[k] = t.timer end
      end
    else
      local o = 1 - k
      if b.st[o] == t.startState and b.tm[o] == t.startTimer and b.starts + 1 <= t.starts then
        b.starts = b.starts + 1
        b.st[k], b.tm[k] = 1, t.timer
        for _, s in ipairs(b.spots) do
          if b.vertical then s[2] = s[2] + s[3] * t.step else s[1] = s[1] + s[3] * t.step end
        end
        local Sfx = require("src.zelda.alttp.Sfx")
        if t.sndSeg then pcall(Sfx.start, game, t.sndSeg, "blast") end
        M.explode(game, inside, b, t)
      end
    end
  end
  if b.afc then
    game.wallHold = true
    if b.st[0] == t.startState then
      b.off = b.off - 2
      local cells = {}
      piece(inside, rshift(b.off, 1), t.live, b.afc - 1, 12, cells)
      b.cells = b.cells or {}
      for c in pairs(cells) do b.cells[c] = true end
      game.roomImages = nil
      b.afc = b.afc + t.afcStep
      if b.afc == t.afcEnd then
        b.afc = nil
        M.reattr(inside, b.cells)
        inside.mem.blast62 = true
        game.wallHold = nil
        game.blastOpened = (game.blastOpened or 0) + 1
      end
    end
  end
  if not b.afc and b.starts >= t.starts and b.st[0] == 0 and b.st[1] == 0 then inside.blast62 = nil end
end

-- the room tags: the pull switch's flag starts the blast once
function M.roomTags(self, lk)
  local game, inside = self.game, self.inside
  local t = tab(game)
  if not (t and inside and inside.hdr) then return end
  if inside.blast62 then return M.frame(game, inside, t) end
  if inside.mem.blast62 or inside.blast62done then return end
  local hdr = inside.hdr
  if hdr[6] ~= t.tag and hdr[7] ~= t.tag then return end
  local T27 = require("src.zelda.alttp.Traps27")
  if not (T27.stateChange and T27.stateChange(self)) then return end   -- +0xBC0
  local slot, d = M.door(inside.data, inside.room, t)
  if not slot then return end
  inside.blast62done = true   -- the tag byte cleared (0x0807A24C)
  startBlast(game, inside, t, slot, d)
end

-- ------------------------------------------------------------ install
function M.install(G)
  if G.blast62Installed then return end
  G.blast62Installed = true
  local I = require("src.zelda.alttp.Interior")
  local load0 = I.loadRoom
  function I:loadRoom(room, main)
    local r = load0(self, room, main)
    self.blast62, self.blast62done = nil, nil
    if self.mem and self.mem.blast62 and self.data.t and self.data.t.blast62 then M.drawOpen(self, self.data.t.blast62) end
    return r
  end
  local Pm = require("src.zelda.alttp.Palace")
  local rt0 = Pm.roomTags
  function Pm.roomTags(self, lk)
    local r = rt0(self, lk)
    M.roomTags(self, lk)
    return r
  end
end

return M
