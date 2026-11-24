-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE HAMMER PEGS INDOORS AND THE WHOLE BIG BLOCK (round 71). Traced on the
-- GBA (zelda3 names where they fit):
--
--   RoomDraw_HammerPegSingle (subtype-3 object 0x16, 0x0807CF78): the next
--     manipulable slot k (+0xAD2) gets state 0x4040 (+0x195C), the object's
--     map position (+0x199C, | 0x2000 on the upper map) and four replacement
--     words (+0x19BC / 0x19DC / 0x19FC / 0x1A1C = UL, LL, UR, LR: the driven-
--     in peg, the literals of 0x0807D004 / 0E / 18 / 22).
--   Dungeon_LoadAttribute (0x08082360..0x080823CC): every manipulable slot
--     but a bomb floor (state & 0xF0 == 0x30) writes 0x70 + k into its 2 x 2
--     attribute cells. The port marked pots, big blocks and bomb floors but
--     not the pegs: they had the floor's attribute and Link walked through
--     them (0x3F's key block, 0xBE / 0xCE's peg rows).
--   Dungeon_ToolAndTileInteraction (0x08081928), the hammer (link_item_in_
--     hand & 2) at its first step: the cell at the tool point ((y & 0x1F8)
--     << 3 | x >> 3, + 0x1000 on the lower level); attribute 0x70 + k and
--       * state & 0xF0F0 == 0x4040 (a peg): 0x08083AE4 writes the four
--         replacement words and gives the 2 x 2 cells the LR word's tile
--         attribute (0x02002E40[LR & 0x1FF], 0x08083974); sound (the movs at
--         0x080819D0);
--       * == 0x1010 (a pot): RevealPotItem (0x080928F0) on its position, the
--         pot's replacement (the floor), the secret sprite (0x080C34C4) and
--         the pot's debris (0x08116C98): the hammer breaks pots.
--   The big block (state 0x2020): the lift (0x08081740) takes the block's
--     first segment k - (state & 15) and 0x080815E4 runs RevealPotItem on
--     that segment's position and the replacement of ALL FOUR segments: the
--     block comes off whole (the port took one 16 x 16 quarter a lift and
--     revealed nothing, so 0x3F's key and the holes under 0x9E's / 0xCE's
--     blocks never came out). RevealPotItem's case for a secret >= 0x80 but
--     0x88 (0x08092A34): the four segments' replacement words come from the
--     table its literal (0x08092AFC) points to, four words a segment, and
--     the sound of the movs at 0x08092A6A: the hole (attribute 0x20 from
--     the words' tile attribute). A secret < 0x80 is the item the block hid.
--
-- OURS: the lifted block is carried / thrown as the touched 16 x 16 quarter's
-- picture (Lift52.lua); a peg's driven-in picture shows at once (no tile
-- animation); the manipulable numbers 0x70 + k of the pegs are the first
-- ones the room does not use yet (the GBA numbers them in draw order).

local bit = require("bit")
local band, rshift, lshift = bit.band, bit.rshift, bit.lshift

local M = {}

-- GBA code addresses (file offsets)
M.ADDR = {
  pegWordLdr = { 0x07D004, 0x07D00E, 0x07D018, 0x07D022 },   -- UL, LL, UR, LR
  pegStateLdr = 0x07CF8E,      -- RoomDraw_HammerPegSingle: state 0x4040
  toolPegLdr = 0x081996,       -- Dungeon_ToolAndTileInteraction: the peg's state
  toolPotLdr = 0x081A10,       -- the pot's state (0x1010)
  pegSfxMovs = 0x0819D0,       -- movs r0, #sound before the call
  holeTabLdr = 0x092A7C,       -- RevealPotItem: the hole replacement table
  holeSfxMovs = 0x092A6A,
}
M.PEG_OBJ = 0x16               -- subtype-3 object id of the hammer peg

local function lit(rom, ins)
  local h = rom:u16(ins)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return band(ins + 4, bit.bnot(3)) + band(h, 0xFF) * 4
end

local function movsImm(rom, at)
  local h = rom:u16(at)
  if band(h, 0xFF00) ~= 0x2000 then return nil end
  return band(h, 0xFF)
end

-- the room's subtype-3 objects of one id: { x, y (cells), layer 1..3 }
function M.objects(rom, p, id)
  local out, o = {}, p + 2
  for layer = 1, 3 do
    for _ = 1, 400 do
      local b0, b1, b2 = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
      if b0 == 0xF0 and b1 == 0xFF then o = o + 2 break end
      if b0 == 0xFF and b1 == 0xFF then o = o + 2 break end
      o = o + 3
      if band(b0, 0xFC) ~= 0xFC and b2 >= 0xF8 then
        local i = lshift(band(b2, 7), 4) + lshift(band(b1, 3), 2) + band(b0, 3)
        if i == id then out[#out + 1] = { x = rshift(b0, 2), y = rshift(b1, 2), layer = layer } end
      end
    end
    for _ = 1, 64 do
      local w = rom:u16(o)
      o = o + 2
      if w == 0xFFFF then break end
    end
  end
  return out
end

function M.extract(rom, R, check)
  local A = M.ADDR
  local out = { pegWords = {}, pegs = {} }
  for k, a in ipairs(A.pegWordLdr) do
    local l = lit(rom, a)
    check(l, "peg word literal %d", k)
    out.pegWords[k] = band(rom:u32(l), 0xFFFF)
  end
  local w = out.pegWords
  check(w[2] == w[1] + 1 and w[3] == bit.bor(w[1], 0x400) and w[4] == bit.bor(w[2], 0x400), "peg words")
  local sl, tl, pl = lit(rom, A.pegStateLdr), lit(rom, A.toolPegLdr), lit(rom, A.toolPotLdr)
  check(sl and tl and pl, "peg state literals")
  out.pegState = rom:u32(sl)
  check(out.pegState == rom:u32(tl) and band(out.pegState, 0xF0F0) == out.pegState, "peg state")
  out.potState = rom:u32(pl)
  check(out.potState < 0x10000 and out.potState ~= out.pegState, "pot state")
  out.pegSfx = movsImm(rom, A.pegSfxMovs)
  out.holeSfx = movsImm(rom, A.holeSfxMovs)
  check(out.pegSfx and out.holeSfx, "peg / hole sounds")
  local hl = lit(rom, A.holeTabLdr)
  check(hl, "hole table literal")
  local hp = rom:u32(hl) - 0x08000000
  check(hp > 0 and hp < 0x400000, "hole table pointer")
  out.holeWords = rom:bytesU16(hp, 16)
  for r = 0, R.roomCount - 1 do
    local p = rom:ptr(R.roomObjects + r * 4)
    if p then
      local l = M.objects(rom, p, M.PEG_OBJ)
      if #l > 0 then out.pegs[r + 1] = l end
    end
  end
  return out
end

local function tab(inside) return inside and inside.data and inside.data.t and inside.data.t.manip71 end

local CELLS = { 0, 64, 1, 65 }   -- UL, LL, UR, LR

local function put(inside, lower, cell, w)
  if cell < 0 or cell > 4095 then return end
  if lower then inside.patch3[cell] = w else inside.patch[cell] = w end
end

-- 2 x 2 cells get one attribute (both levels, as the pots)
local function setAttr(inside, cell, v)
  local I = require("src.zelda.alttp.Interior")
  for _, d in ipairs(CELLS) do
    local c = cell + d
    inside.attrs[c] = v; inside.grid[c] = not I.WALKABLE[v]
    inside.attrsLo[c] = v; inside.gridLo[c] = not I.WALKABLE[v]
  end
end

-- after the room's pots / blocks: the pegs' manipulable attributes
function M.markPegs(inside)
  inside.pegs71 = {}
  local t = tab(inside)
  local list = t and t.pegs and t.pegs[inside.room + 1]
  if not list then return 0 end
  local used = {}
  for c = 0, 4095 do
    for _, a in ipairs({ inside.attrs[c], inside.attrsLo[c] }) do
      if a and a >= 0x70 and a <= 0x7F then used[a] = true end
    end
  end
  local k = 0
  for _, o in ipairs(list) do
    while used[0x70 + k] and k < 16 do k = k + 1 end
    if k >= 16 then break end
    local p = { cell = o.y * 64 + o.x, attr = 0x70 + k, lower = (o.layer == 3), layer = o.layer }
    used[p.attr] = true
    setAttr(inside, p.cell, p.attr)
    inside.pegs71[#inside.pegs71 + 1] = p
  end
  return #inside.pegs71
end

local function sound(game, id, ev)
  if not id then return end
  local ok, S = pcall(require, "src.zelda.alttp.Sfx")
  if ok and S.start then pcall(S.start, game, id, ev) end
end

-- the hammer's tile action at (x, y); returns "peg" / "pot" / nil
function M.hammerAt(game, x, y)
  local inside = game.interior
  local t = tab(inside)
  if not inside or not t then return nil end
  local cell = band(y, 0x1F8) * 8 + band(rshift(x, 3), 63)
  local a = (inside.lower and inside.attrsLo or inside.attrs)[cell]
  if not a or band(a, 0xF0) ~= 0x70 then return nil end
  for _, p in ipairs(inside.pegs71 or {}) do
    if p.attr == a and not p.down then
      p.down = true
      local I = require("src.zelda.alttp.Interior")
      local at = I.attributes(inside.data.roomIdx, inside.aux)
      local w = t.pegWords
      for k, d in ipairs(CELLS) do put(inside, p.lower, p.cell + d, w[k]) end
      setAttr(inside, p.cell, at[band(w[4], 0x1FF)] or 0)
      game.roomImages = nil
      game.pegsDown71 = (game.pegsDown71 or 0) + 1
      sound(game, t.pegSfx, "peg71")
      return "peg"
    end
  end
  local pot = inside:potAt(x, y)
  if pot then
    local item = inside:liftPot(pot)
    game.roomImages = nil
    game.potsSmashed71 = (game.potsSmashed71 or 0) + 1
    if item and item ~= 0 and game.terrainDrop then
      game:terrainDrop(0, item < 0x80 and item or 0xFF, pot.x * 8, pot.y * 8)
    end
    if game.spawnDebris then game:spawnDebris(0, pot.x * 8, pot.y * 8) end
    return "pot"
  end
  return nil
end

-- the big block's secret (RevealPotItem on its first segment); returns the
-- item (< 0x80) to drop, or nil
function M.revealBlock(inside, segs)
  local t = tab(inside)
  local first = segs[1]
  local pos = first.cell * 2 + (first.lower and 0x2000 or 0)
  local list = inside.data.roomIdx.secrets and inside.data.roomIdx.secrets[inside.room + 1] or {}
  for k, sc in ipairs(list) do
    if sc.pos == pos then
      local d = sc.item or 0
      if d == 0 then return nil end
      if d >= 0x80 and d ~= 0x88 then
        if not t then return nil end
        local I = require("src.zelda.alttp.Interior")
        local at = I.attributes(inside.data.roomIdx, inside.aux)
        for s, m in ipairs(segs) do
          local w = {}
          for j = 1, 4 do w[j] = t.holeWords[(s - 1) * 4 + j] end
          for j, dd in ipairs(CELLS) do put(inside, m.lower, m.cell + dd, w[j]) end
          local v = at[band(w[4], 0x1FF)] or 0
          for _, dd in ipairs(CELLS) do
            local c = m.cell + dd
            if m.lower then inside.attrsLo[c] = v; inside.gridLo[c] = not I.WALKABLE[v]
            else inside.attrs[c] = v; inside.grid[c] = not I.WALKABLE[v] end
          end
        end
        inside.holeRevealed71 = true
        return "hole"
      end
      if d >= 0x80 then return nil end
      -- RevealPotItem's once-per-visit bit (the key is not in those bits)
      if d ~= 8 then
        inside.revealed = inside.revealed or {}
        local bits = inside.revealed[inside.room] or {}
        inside.revealed[inside.room] = bits
        if bits[k] then return nil end
        bits[k] = true
      elseif inside.mem and inside.mem.potKey then
        return nil
      end
      return d
    end
  end
  return nil
end

-- the four segments of the big block a segment belongs to (RoomObjects'
-- misc entries share their object), in draw order
function M.segmentsOf(inside, m)
  local out = {}
  for _, o in ipairs(inside.misc or {}) do
    if o.kind == "big" and o.order == m.order then out[#out + 1] = o end
  end
  if #out == 0 then out[1] = m end
  return out
end

function M.install(G)
  local I = require("src.zelda.alttp.Interior")
  local mark0 = I.markPots
  function I:markPots(...)
    local r = mark0(self, ...)
    M.markPegs(self)
    return r
  end

  local TL = require("src.zelda.alttp.Tools")
  local use0 = TL.useFrame
  function TL.useFrame(game, u)
    local was = (u and u.kind == "hammer") and u.t or nil
    local r = use0(game, u)
    if was == 0 and u.t == 1 and game.state == "room" and game.interior then
      local f = require("src.zelda.alttp.OwSword").tileOffset(game, 3)
      if f then
        local lk = game.link
        M.hammerAt(game, lk.x + f[1], lk.y + f[2])
      end
    end
    return r
  end

  local L52 = require("src.zelda.alttp.Lift52")
  local remove0 = L52.remove
  function L52.remove(inside, m)
    local segs = M.segmentsOf(inside, m)
    for _, s in ipairs(segs) do
      if not s.lifted then remove0(inside, s) end
    end
    local d = M.revealBlock(inside, segs)
    inside.blocksWhole71 = (inside.blocksWhole71 or 0) + 1
    if type(d) == "number" then
      inside.drop71 = { item = d, x = (segs[1].cell % 64) * 8, y = math.floor(segs[1].cell / 64) * 8 }
    end
    inside.reveal71 = d
  end

  local try0 = G.tryLift
  function G:tryLift(...)
    local r = try0(self, ...)
    local inside = self.state == "room" and self.interior
    if inside and inside.reveal71 ~= nil then
      local t = tab(inside)
      if inside.reveal71 == "hole" and t then sound(self, t.holeSfx, "hole71") end
      local dr = inside.drop71
      if dr and self.terrainDrop then self:terrainDrop(0, dr.item, dr.x, dr.y) end
      inside.reveal71, inside.drop71 = nil, nil
    end
    return r
  end
end

return M
