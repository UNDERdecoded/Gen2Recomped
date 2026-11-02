-- BLACK AND WHITE'S MOVING BATTLE SPRITES, from the cartridge's own data.
--
-- A Unova Pokemon's 96 x 96 still (+0 / +9 in /a/0/0/4, see Gen5BattleSprites)
-- is never what the battle draws. The battle draws a MULTI-CELL ANIMATION built
-- out of loose body parts, and every member it needs sits beside the still:
--
--   +2  parts sheet   RGCN, 256 x 128, 4bpp, LINEAR (layout flag 1), 2D-mapped
--   +4  cells         RECN (NCER): one cell per body part, each a few OAMs
--   +5  cell anims    RNAN (NANR): one sequence per animated part
--   +6  multi-cells   RCMN (NMCR): each a list of nodes {sequence, x, y, attr}
--   +7  mc anim       RAMN (NMAR): which multi-cell shows when
--   +8  (untagged)    a motion parameter table -- NOT used for the idle loop
--   +9..+17           the same nine for the back
--   +18 / +19         normal / shiny palette (RLCN, one bank of 16)
--
-- !! NOTHING HERE WAS TAKEN FROM A REFERENCE STRUCT. It was read off species
-- 1, 25, 495 and 643 and checked by rendering; the derivations are recorded
-- next to the code that depends on them.
--
-- THE FORMATS, as measured:
--
-- RECN/KBEC: the usual NCER header, but mappingMode is 4 -- 2D mapping, not one
--   of the 1D boundaries. A tile number t is the 8x8 block at column t % 32,
--   row t / 32 of the 256-pixel-wide sheet, and an OAM of w x h takes the
--   w x h RECTANGLE starting there (not a run of consecutive tiles). The sheet
--   says so itself: tilesX 32, tilesY 16, and its pixels are a plain linear
--   bitmap. Every OAM is authored AFFINE (attr0 bit 8), most DOUBLE-SIZE
--   (bit 9), so attr1 bits 9-13 are an affine slot, not flip bits, and the
--   stored position is the top-left of the doubled box: the object's own
--   centre is (x + w, y + h) when doubled, (x + w/2, y + h/2) when not.
--
-- RNAN/KNBA (NANR) and RAMN/KNBA (NMAR) share one layout:
--   u16 sequenceCount, u16 frameCount, u32 seqOff, u32 frameOff, u32 resOff,
--   8 reserved; offsets relative to the KNBA fields.
--   sequence (16): u16 frames, u16 loopStart, u16 elementType, u16 animType
--     (1 = cell, 2 = multi-cell), u32 playMode (1 once, 2 loop, 3 ping-pong
--     once, 4 ping-pong loop), u32 byte offset into the frame array.
--   frame (8): u32 result offset, u16 duration, u16 0xBEEF.
--   results: elementType 0 = u16 index (2 bytes, padded);
--            1 = SRT: u16 index, u16 rotZ (65536 = a turn), fx32 sx, fx32 sy
--                (0x1000 = 1.0), s16 tx, s16 ty   (16 bytes);
--            2 = T:   u16 index, u16 pad, s16 tx, s16 ty   (8 bytes).
--   Gen4CellAnim reads the same file but calls the animType half "playback
--   mode" and refuses SRT, which Unova's cell anims use constantly.
--
-- RCMN/MCBK (NMCR):
--   u16 multiCellCount, u16 0xBEEF, u32 cellDataOff, u32 nodeOff, u32 0, u32 0
--   (offsets relative to the MCBK fields).
--   multi-cell (8): u16 nodeCount, u16 cellAnimCount, u32 byte offset of its
--     first node, relative to nodeOff.
--   node (8): u16 NANR sequence, s16 x, s16 y, u16 attr. attr's HIGH byte is
--     the cell-animation instance the node draws (nodes may share one); the
--     low byte is 0x20 everywhere measured (a play-mode / visibility flag).
--
-- PLAYBACK. One tick a frame: the NMAR sequence (0, the idle) chooses the
-- multi-cell; every cell-animation instance of that multi-cell advances its
-- own NANR sequence, and each node draws its instance's current cell at
-- node (x, y) + the frame's translation, rotated/scaled about the cell origin
-- by the frame's SRT. When the NMAR moves to a different multi-cell the cell
-- animations restart from frame 0. Node 0 is drawn on top (OAM priority is
-- by order), and inside a cell OAM 0 is on top.
--
-- The multi-cell origin's place in the 96 x 96 still differs per species; bake
-- finds it by matching tick 0 against the still (M.align).

local M = {}

local byte, char, floor, concat = string.byte, string.char, math.floor, table.concat
local sin, cos, pi = math.sin, math.cos, math.pi

M.PATH = "/a/0/0/4"
M.STRIDE = 20
M.SIZE = 96
M.ORIGIN = { 48, 72 }      -- fallback only, when the still cannot be matched
M.RESET_POLICY = "frame"   -- see M.machine
M.ROT_SIGN = 1             -- +1: a positive rotZ turns clockwise on screen
M.SCALE_INVERSE = false    -- true would read sx/sy as the hardware's inverse
M.MAX_TICKS = 1200         -- a loop longer than this is cut (and said so)
M.MEMBER = {
  front = { still = 0, parts = 2, cells = 4, anim = 5, mcells = 6, mcanim = 7, params = 8 },
  back = { still = 9, parts = 11, cells = 13, anim = 14, mcells = 15, mcanim = 16, params = 17 },
  palette = 18, shiny = 19,
}

local function u16(s, at)
  local a, b = byte(s, at, at + 1)
  if not b then return nil end
  return a + b * 256
end
local function s16(s, at)
  local v = u16(s, at)
  if v and v >= 32768 then v = v - 65536 end
  return v
end
local function u32(s, at)
  local a, b, c, d = byte(s, at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end
local function s32(s, at)
  local v = u32(s, at)
  if v and v >= 2147483648 then v = v - 4294967296 end
  return v
end

-- LZ10/LZ11 when it really is: the untagged +8 member can start with 0x10 or
-- 0x11 as an ordinary count, so a failed or nonsensical inflate keeps the raw
-- bytes rather than raising.
local function inflate(data)
  local Lz = require("src.import.Gen5Lz")
  if type(data) ~= "string" or not Lz.isCompressed(data) then return data end
  local ok, out = pcall(Lz.decompress, data)
  if ok and type(out) == "string" and #out > 0 then return out end
  return data
end
M.inflate = inflate

-- Nitro container: { magic, data, sections = { TAG = { body, size } } }.
local function container(data)
  if type(data) ~= "string" then return nil end
  data = inflate(data)
  if #data < 16 then return nil end
  local headerSize, count = u16(data, 13), u16(data, 15)
  if not headerSize or headerSize < 16 then return nil end
  local sections, at = {}, headerSize + 1
  for _ = 1, count or 0 do
    if at + 8 > #data + 1 then break end
    local tag, size = data:sub(at, at + 3), u32(data, at + 4)
    if not size or size < 8 then break end
    sections[tag] = { at = at, size = size, body = at + 8 }
    at = at + size
  end
  return { magic = data:sub(1, 4), data = data, sections = sections }
end
M.container = container

-- ---------------------------------------------------------------------------
-- RECN: cells
-- ---------------------------------------------------------------------------

local DIM = {
  [0] = { [0] = { 8, 8 },  { 16, 16 }, { 32, 32 }, { 64, 64 } },
  [1] = { [0] = { 16, 8 }, { 32, 8 },  { 32, 16 }, { 64, 32 } },
  [2] = { [0] = { 8, 16 }, { 8, 32 },  { 16, 32 }, { 32, 64 } },
}

-- parseCells(data) -> { mappingMode, cells = { [0..n-1] = { oam = {...} } }, count }
--   oam: { cx, cy (object centre, cell space), width, height, tile, palette,
--          flipX, flipY, affine, double }
function M.parseCells(data)
  local c = container(data)
  local sec = c and c.sections.KBEC
  if not sec then return nil, "not a RECN" end
  local d, body = c.data, sec.body
  local count = u16(d, body)
  local attrs = u16(d, body + 2) or 0
  local cellOff = u32(d, body + 4) or 24
  local mapping = u32(d, body + 8) or 0
  local stride = (attrs % 2 == 1) and 16 or 8
  local records = body + cellOff
  local oamBase = records + count * stride
  local out = { count = count, mappingMode = mapping, cells = {} }
  for i = 0, count - 1 do
    local at = records + i * stride
    local n, off = u16(d, at), u32(d, at + 4)
    if not (n and off) then return nil, ("cell %d truncated"):format(i) end
    local cell = { index = i, oam = {} }
    for j = 0, n - 1 do
      local e = oamBase + off + j * 6
      local a0, a1, a2 = u16(d, e), u16(d, e + 2), u16(d, e + 4)
      if not a2 then return nil, ("cell %d oam %d truncated"):format(i, j) end
      local y = a0 % 256; if y >= 128 then y = y - 256 end
      local affine = floor(a0 / 256) % 2 == 1
      local bit9 = floor(a0 / 512) % 2 == 1
      local shape = floor(a0 / 16384) % 4
      local x = a1 % 512; if x >= 256 then x = x - 512 end
      local size = floor(a1 / 16384) % 4
      local dim = DIM[shape] and DIM[shape][size]
      local hidden = (not affine) and bit9
      if dim and not hidden then
        local w, h = dim[1], dim[2]
        local double = affine and bit9
        cell.oam[#cell.oam + 1] = {
          width = w, height = h,
          cx = double and (x + w) or (x + w / 2),
          cy = double and (y + h) or (y + h / 2),
          tile = a2 % 1024, palette = floor(a2 / 4096) % 16,
          flipX = (not affine) and floor(a1 / 4096) % 2 == 1,
          flipY = (not affine) and floor(a1 / 8192) % 2 == 1,
          affine = affine, double = double,
        }
      end
    end
    out.cells[i] = cell
  end
  return out
end

-- ---------------------------------------------------------------------------
-- RNAN / RAMN: animation banks (one parser for both)
-- ---------------------------------------------------------------------------

M.ELEMENT_INDEX, M.ELEMENT_SRT, M.ELEMENT_T = 0, 1, 2
M.PLAY_ONCE, M.PLAY_LOOP, M.PLAY_PINGPONG, M.PLAY_PINGPONG_LOOP = 1, 2, 3, 4

-- parseAnim(data) -> { sequences = { [0..n-1] = { frames = { {index, duration,
--   rot, sx, sy, tx, ty} }, loopStart, elementType, animType, playMode } },
--   sequenceCount, frameCount }
function M.parseAnim(data)
  local c = container(data)
  local sec = c and c.sections.KNBA
  if not sec then return nil, "no KNBA section" end
  local d, f = c.data, sec.body
  local nSeq, nFrames = u16(d, f), u16(d, f + 2)
  local seqOff, frameOff, resOff = u32(d, f + 4), u32(d, f + 8), u32(d, f + 12)
  if not (nSeq and nFrames and seqOff and frameOff and resOff) then
    return nil, "KNBA header truncated"
  end
  local out = { sequences = {}, sequenceCount = nSeq, frameCount = nFrames }
  local seen = 0
  for s = 0, nSeq - 1 do
    local at = f + seqOff + s * 16
    local count, loopStart = u16(d, at), u16(d, at + 2)
    local elementType, animType = u16(d, at + 4), u16(d, at + 6)
    local playMode, within = u32(d, at + 8), u32(d, at + 12)
    if not within then return nil, ("sequence %d truncated"):format(s) end
    if within % 8 ~= 0 then return nil, ("sequence %d is mid-frame"):format(s) end
    local first = within / 8
    if first + count > nFrames then return nil, ("sequence %d overruns"):format(s) end
    local frames = {}
    for k = 0, count - 1 do
      local fa = f + frameOff + (first + k) * 8
      local r, dur, pad = u32(d, fa), u16(d, fa + 4), u16(d, fa + 6)
      if not pad then return nil, "frame truncated" end
      if pad ~= 0xBEEF then
        return nil, ("sequence %d frame %d ends %04X, not BEEF"):format(s, k, pad)
      end
      local ra = f + resOff + r
      local fr = { index = u16(d, ra), duration = dur, rot = 0, sx = 1, sy = 1, tx = 0, ty = 0 }
      if elementType == M.ELEMENT_SRT then
        fr.rot = (u16(d, ra + 2) or 0) / 65536 * 2 * pi
        fr.sx = (s32(d, ra + 4) or 4096) / 4096
        fr.sy = (s32(d, ra + 8) or 4096) / 4096
        fr.tx, fr.ty = s16(d, ra + 12) or 0, s16(d, ra + 14) or 0
      elseif elementType == M.ELEMENT_T then
        fr.tx, fr.ty = s16(d, ra + 4) or 0, s16(d, ra + 6) or 0
      elseif elementType ~= M.ELEMENT_INDEX then
        return nil, ("sequence %d has element type %d"):format(s, elementType)
      end
      if not fr.index then return nil, "result past the end" end
      frames[k + 1] = fr
      seen = seen + 1
    end
    out.sequences[s] = {
      frames = frames, loopStart = loopStart, elementType = elementType,
      animType = animType, playMode = playMode,
    }
  end
  if seen ~= nFrames then
    return nil, ("sequences hold %d frames, header says %d"):format(seen, nFrames)
  end
  return out
end

-- ---------------------------------------------------------------------------
-- RCMN: multi-cells
-- ---------------------------------------------------------------------------

-- parseMultiCells(data) -> { count, multiCells = { [0..n-1] = { cellAnimCount,
--   nodes = { { sequence, x, y, attr, instance } } } } }
function M.parseMultiCells(data)
  local c = container(data)
  local sec = c and c.sections.KBCM
  if not sec then return nil, "no MCBK (KBCM) section" end
  local d, f = c.data, sec.body
  local n = u16(d, f)
  local dataOff, nodeOff = u32(d, f + 4), u32(d, f + 8)
  if not (n and dataOff and nodeOff) then return nil, "MCBK header truncated" end
  local out = { count = n, multiCells = {} }
  for i = 0, n - 1 do
    local at = f + dataOff + i * 8
    local nodes, insts, first = u16(d, at), u16(d, at + 2), u32(d, at + 4)
    if not first then return nil, ("multi-cell %d truncated"):format(i) end
    local mc = { cellAnimCount = insts, nodes = {} }
    for k = 0, nodes - 1 do
      local na = f + nodeOff + first + k * 8
      local seq, x, y, attr = u16(d, na), s16(d, na + 2), s16(d, na + 4), u16(d, na + 6)
      if not attr then return nil, ("multi-cell %d node %d truncated"):format(i, k) end
      mc.nodes[k + 1] = { sequence = seq, x = x, y = y, attr = attr, instance = floor(attr / 256) }
    end
    out.multiCells[i] = mc
  end
  return out
end

-- ---------------------------------------------------------------------------
-- The parts sheet: a linear 4bpp bitmap read as palette indices
-- ---------------------------------------------------------------------------

-- parseSheet(data) -> { width, height, at(x, y) -> 0..15 }
function M.parseSheet(data)
  local c = container(data)
  local sec = c and c.sections.RAHC
  if not sec then return nil, "no RAHC section" end
  local d, b = c.data, sec.body
  local th, tw = u16(d, b), u16(d, b + 2)
  local depth = u32(d, b + 4)
  local layout = (u16(d, b + 12) or 0) % 256
  local size, off = u32(d, b + 16), u32(d, b + 20)
  if depth ~= 3 then return nil, "parts sheet is not 4bpp" end
  if th == 0xFFFF or tw == 0xFFFF then return nil, "parts sheet has no size" end
  local px = d:sub(b + off, b + off + size - 1)
  local W, H = tw * 8, th * 8
  local idx = {}
  if layout == 1 then
    for i = 0, W * H - 1 do
      local v = byte(px, floor(i / 2) + 1) or 0
      idx[i] = (i % 2 == 0) and (v % 16) or floor(v / 16)
    end
  else
    -- tiled: tile k at (k % tw, k / tw)
    for t = 0, tw * th - 1 do
      local ox, oy = (t % tw) * 8, floor(t / tw) * 8
      for y = 0, 7 do for x = 0, 7 do
        local v = byte(px, t * 32 + y * 4 + floor(x / 2) + 1) or 0
        idx[(oy + y) * W + ox + x] = (x % 2 == 0) and (v % 16) or floor(v / 16)
      end end
    end
  end
  return { width = W, height = H, idx = idx, layout = layout }
end

-- ---------------------------------------------------------------------------
-- Cell images (palette-index rasters in cell space)
-- ---------------------------------------------------------------------------

-- rasterCell(cell, sheet, mappingMode) -> { x0, y0, w, h, px = {[i]=index+16*pal} }
-- OAM 0 on top.
function M.rasterCell(cell, sheet, mappingMode)
  if not cell or #cell.oam == 0 then return nil end
  local x0, y0, x1, y1
  for _, o in ipairs(cell.oam) do
    local l, t = floor(o.cx - o.width / 2), floor(o.cy - o.height / 2)
    x0 = (not x0 or l < x0) and l or x0
    y0 = (not y0 or t < y0) and t or y0
    x1 = (not x1 or l + o.width > x1) and (l + o.width) or x1
    y1 = (not y1 or t + o.height > y1) and (t + o.height) or y1
  end
  local w, h = x1 - x0, y1 - y0
  local px = {}
  local SW = sheet.width
  local tilesWide = floor(SW / 8)
  for i = #cell.oam, 1, -1 do
    local o = cell.oam[i]
    local l, t = floor(o.cx - o.width / 2), floor(o.cy - o.height / 2)
    local sx0, sy0
    if mappingMode == 4 then
      -- 2D mapping: the OAM takes a rectangle of the 32-tile-wide sheet
      sx0, sy0 = (o.tile % 32) * 8, floor(o.tile / 32) * 8
    else
      -- 1D mapping: consecutive tiles, boundary 32 << mode bytes
      sx0, sy0 = nil, nil
    end
    local shift = o.palette * 16
    local step = 2 ^ (mappingMode or 0)
    for y = 0, o.height - 1 do
      local ry = o.flipY and (o.height - 1 - y) or y
      for x = 0, o.width - 1 do
        local rx = o.flipX and (o.width - 1 - x) or x
        local v
        if sx0 then
          v = sheet.idx[(sy0 + ry) * SW + sx0 + rx]
        else
          local tileNo = o.tile * step + floor(ry / 8) * (o.width / 8) + floor(rx / 8)
          local ox, oy = (tileNo % tilesWide) * 8, floor(tileNo / tilesWide) * 8
          v = sheet.idx[(oy + ry % 8) * SW + ox + rx % 8]
        end
        if v and v ~= 0 then
          px[(t - y0 + y) * w + (l - x0 + x)] = v + shift
        end
      end
    end
  end
  return { x0 = x0, y0 = y0, w = w, h = h, px = px }
end

-- ---------------------------------------------------------------------------
-- Loading one side of one species
-- ---------------------------------------------------------------------------

local archiveCache = setmetatable({}, { __mode = "k" })

local function archiveOf(rom)
  if type(rom) == "table" and rom.get and rom.count then return rom end
  local hit = archiveCache[rom]
  if hit then return hit end
  local raw = rom and rom.read and rom:read(M.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if arc then archiveCache[rom] = arc end
  return arc
end

local function member(arc, i)
  local b = arc:get(i)
  if not b or #b == 0 then return nil end
  return inflate(b)
end

-- load(rom | archive, species, side, shiny, female) -> set, or nil + why
--   set = { cells, anim, multiCells, mcAnim, sheet, palette, still }
function M.load(rom, species, side, shiny, female)
  local arc = archiveOf(rom)
  if not arc then return nil, "no " .. M.PATH end
  local m = M.MEMBER[side or "front"]
  if not m then return nil, "side must be front or back" end
  local base = species * M.STRIDE
  local parts = female and member(arc, base + m.parts + 1) or nil
  parts = parts or member(arc, base + m.parts)
  local still = female and member(arc, base + m.still + 1) or nil
  still = still or member(arc, base + m.still)
  local set, why = {}, nil
  set.cells, why = M.parseCells(member(arc, base + m.cells)); if not set.cells then return nil, "cells: " .. tostring(why) end
  set.anim, why = M.parseAnim(member(arc, base + m.anim)); if not set.anim then return nil, "cell anim: " .. tostring(why) end
  set.multiCells, why = M.parseMultiCells(member(arc, base + m.mcells)); if not set.multiCells then return nil, "multi-cells: " .. tostring(why) end
  set.mcAnim, why = M.parseAnim(member(arc, base + m.mcanim)); if not set.mcAnim then return nil, "mc anim: " .. tostring(why) end
  set.sheet, why = M.parseSheet(parts); if not set.sheet then return nil, "sheet: " .. tostring(why) end
  local G = require("src.import.Gen4Graphics")
  set.normalPalette = G.palette(member(arc, base + M.MEMBER.palette))
  set.shinyPalette = G.palette(member(arc, base + M.MEMBER.shiny))
  set.palette = shiny and set.shinyPalette or set.normalPalette
  if not set.palette then return nil, "no palette" end
  set.stillBytes = still
  set.params = member(arc, base + m.params)
  return set
end

-- ---------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------

-- A sequence player: { seq, i (1-based frame), left (ticks), dir }
local function player(seq)
  local p = { seq = seq, i = 1, dir = 1, done = false }
  local fr = seq and seq.frames[1]
  p.left = fr and fr.duration or 0
  return p
end

local function current(p)
  return p.seq and p.seq.frames[p.i]
end

-- One tick. Zero-length frames are skipped (bounded, so a sequence of
-- all-zero durations cannot spin).
local function advance(p)
  local seq = p.seq
  if not seq or p.done or #seq.frames == 0 then return end
  p.left = p.left - 1
  local guard = 0
  while p.left <= 0 and not p.done and guard <= #seq.frames * 2 + 2 do
    guard = guard + 1
    local n, mode = #seq.frames, seq.playMode
    local nexti = p.i + p.dir
    if nexti > n or nexti < 1 then
      if mode == M.PLAY_LOOP then
        nexti = (seq.loopStart or 0) + 1
        if nexti > n then nexti = 1 end
      elseif mode == M.PLAY_PINGPONG or mode == M.PLAY_PINGPONG_LOOP then
        if nexti > n then
          p.dir = -1; nexti = math.max(1, n - 1)
        else
          if mode == M.PLAY_PINGPONG_LOOP then p.dir = 1; nexti = math.min(n, 2)
          else p.done = true; nexti = 1 end
        end
      else
        p.done = true; nexti = p.i
      end
    end
    p.i = nexti
    p.left = p.left + (seq.frames[p.i].duration or 0)
  end
end

-- Total ticks in one pass of a sequence (forward), and whether it loops.
local function seqLength(seq)
  local t = 0
  for _, f in ipairs(seq and seq.frames or {}) do t = t + (f.duration or 0) end
  return t
end
M.seqLength = seqLength

-- A machine that steps the whole multi-cell animation one tick at a time and
-- reports the drawable state: a list of { cell, rot, sx, sy, tx, ty } in DRAW
-- ORDER (bottom first), all positions in multi-cell space.
function M.machine(set, sequence, policy)
  local mcSeq = set.mcAnim.sequences[sequence or 0]
  if not mcSeq then return nil, "no NMAR sequence " .. tostring(sequence or 0) end
  policy = policy or M.RESET_POLICY
  local self = { set = set, top = player(mcSeq), clock = 0 }
  local function enter()
    local fr = current(self.top)
    self.mcIndex = fr and fr.index
    self.mcFrame = fr
    local mc = set.multiCells.multiCells[self.mcIndex or -1]
    self.mc = mc
    self.inst = {}
    for _, node in ipairs(mc and mc.nodes or {}) do
      if not self.inst[node.instance] then
        local p = player(set.anim.sequences[node.sequence])
        if policy == "continue" then
          for _ = 1, self.clock do advance(p) end
        end
        self.inst[node.instance] = p
      end
    end
  end
  enter()
  function self.state()
    local out = {}
    local mc = self.mc
    if not mc then return out end
    local top = self.mcFrame or { rot = 0, sx = 1, sy = 1, tx = 0, ty = 0 }
    for k = #mc.nodes, 1, -1 do                  -- node 0 on top
      local node = mc.nodes[k]
      local fr = current(self.inst[node.instance])
      if fr then
        out[#out + 1] = {
          cell = fr.index, rot = fr.rot, sx = fr.sx, sy = fr.sy,
          tx = node.x + fr.tx, ty = node.y + fr.ty,
          top = top,
        }
      end
    end
    return out
  end
  function self.tick()
    local before = self.top.i
    advance(self.top)
    for _, p in pairs(self.inst) do advance(p) end
    self.clock = self.clock + 1
    local fr = current(self.top)
    local moved = self.top.i ~= before
    if moved and fr and (policy == "frame" or fr.index ~= self.mcIndex) then
      enter()                                   -- new multi-cell: restart parts
    else
      self.mcFrame = fr
    end
    self.boundary = moved
  end
  self.loopTicks = seqLength(mcSeq)
  self.loops = mcSeq.playMode == M.PLAY_LOOP or mcSeq.playMode == M.PLAY_PINGPONG_LOOP
  return self
end

-- ---------------------------------------------------------------------------
-- Rendering a state into an index raster
-- ---------------------------------------------------------------------------

local function stateKey(state)
  local parts = {}
  for i, s in ipairs(state) do
    local t = s.top
    parts[i] = ("%d,%.4f,%.4f,%.4f,%d,%d|%.4f,%.4f,%.4f,%d,%d")
      :format(s.cell, s.rot, s.sx, s.sy, s.tx, s.ty, t.rot, t.sx, t.sy, t.tx, t.ty)
  end
  return concat(parts, ";")
end

-- render(set, state, width, height, ox, oy, rasters) -> index table [0..w*h-1]
function M.render(set, state, width, height, ox, oy, rasters)
  local out = {}
  for _, s in ipairs(state) do
    local r = rasters[s.cell]
    if r == nil then
      r = M.rasterCell(set.cells.cells[s.cell], set.sheet, set.cells.mappingMode) or false
      rasters[s.cell] = r
    end
    if r then
      local t = s.top
      local plain = s.rot == 0 and s.sx == 1 and s.sy == 1
        and t.rot == 0 and t.sx == 1 and t.sy == 1
      if plain then
        local bx = ox + t.tx + s.tx + r.x0
        local by = oy + t.ty + s.ty + r.y0
        for y = 0, r.h - 1 do
          local dy = by + y
          if dy >= 0 and dy < height then
            for x = 0, r.w - 1 do
              local v = r.px[y * r.w + x]
              local dx = bx + x
              if v and dx >= 0 and dx < width then out[dy * width + dx] = v end
            end
          end
        end
      else
        -- forward: p_mc = T(top) . [ M(part) . p_cell + t(part) ], where
        -- M = R(rot) S(sx, sy). Invert per destination pixel.
        local function mat(rot, sx, sy)
          rot = rot * M.ROT_SIGN
          if M.SCALE_INVERSE then sx, sy = 1 / sx, 1 / sy end
          local c, sn = cos(rot), sin(rot)
          return c * sx, -sn * sy, sn * sx, c * sy
        end
        local a, b, c, d = mat(s.rot, s.sx, s.sy)
        local A, B, C, D = mat(t.rot, t.sx, t.sy)
        -- combined: p = TOP * (P * q + tp) + tt
        local ma, mb = A * a + B * c, A * b + B * d
        local mc, md = C * a + D * c, C * b + D * d
        local ex = A * s.tx + B * s.ty + t.tx
        local ey = C * s.tx + D * s.ty + t.ty
        local det = ma * md - mb * mc
        if math.abs(det) > 1e-6 then
          local ia, ib, ic, id = md / det, -mb / det, -mc / det, ma / det
          -- destination bounds from the raster's corners
          local minX, minY, maxX, maxY = 1e9, 1e9, -1e9, -1e9
          for _, q in ipairs({ { r.x0, r.y0 }, { r.x0 + r.w, r.y0 },
                               { r.x0, r.y0 + r.h }, { r.x0 + r.w, r.y0 + r.h } }) do
            local px = ma * q[1] + mb * q[2] + ex
            local py = mc * q[1] + md * q[2] + ey
            if px < minX then minX = px end; if px > maxX then maxX = px end
            if py < minY then minY = py end; if py > maxY then maxY = py end
          end
          for dy = math.max(0, floor(oy + minY)), math.min(height - 1, floor(oy + maxY) + 1) do
            for dx = math.max(0, floor(ox + minX)), math.min(width - 1, floor(ox + maxX) + 1) do
              local px = dx + 0.5 - ox - ex
              local py = dy + 0.5 - oy - ey
              local qx = floor(ia * px + ib * py) - r.x0
              local qy = floor(ic * px + id * py) - r.y0
              if qx >= 0 and qy >= 0 and qx < r.w and qy < r.h then
                local v = r.px[qy * r.w + qx]
                if v then out[dy * width + dx] = v end
              end
            end
          end
        end
      end
    end
  end
  return out
end

-- indices -> RGBA string through a flat { {r,g,b}, ... } palette (index 0 and
-- every multiple of 16 transparent)
function M.rgba(indices, width, height, palette)
  local px = {}
  local clear = char(0, 0, 0, 0)
  local cache = {}
  for i = 0, width * height - 1 do
    local v = indices[i]
    if v and v % 16 ~= 0 then
      local s = cache[v]
      if not s then
        local c = palette[v + 1] or palette[(v % 16) + 1] or { 255, 0, 255 }
        s = char(c[1], c[2], c[3], 255)
        cache[v] = s
      end
      px[i + 1] = s
    else
      px[i + 1] = clear
    end
  end
  return concat(px)
end

-- ---------------------------------------------------------------------------
-- Baking
-- ---------------------------------------------------------------------------

-- stillIndices(set) -> the 96 x 96 still as a palette-index raster [0..9215]
-- (the four 1D OAM blocks Gen5BattleSprites lays out), or nil.
M.STILL_BLOCKS = { { 0, 0, 8, 8 }, { 8, 0, 4, 8 }, { 0, 8, 8, 4 }, { 8, 8, 4, 4 } }
function M.stillIndices(set)
  local c = container(set.stillBytes)
  local sec = c and c.sections.RAHC
  if not sec then return nil end
  local d, b = c.data, sec.body
  local px = d:sub(b + (u32(d, b + 20) or 24))
  local out, t = {}, 0
  for _, bl in ipairs(M.STILL_BLOCKS) do
    for ty = 0, bl[4] - 1 do
      for tx = 0, bl[3] - 1 do
        local ox, oy = (bl[1] + tx) * 8, (bl[2] + ty) * 8
        for y = 0, 7 do for x = 0, 7 do
          local v = byte(px, t * 32 + y * 4 + floor(x / 2) + 1) or 0
          v = (x % 2 == 0) and (v % 16) or floor(v / 16)
          if v ~= 0 then out[(oy + y) * M.SIZE + ox + x] = v end
        end end
        t = t + 1
      end
    end
  end
  return out
end

local function bbox(idx, w)
  local x0, y0, x1, y1
  for i, v in pairs(idx) do
    if v and v % 16 ~= 0 then
      local x, y = i % w, floor(i / w)
      if not x0 or x < x0 then x0 = x end
      if not x1 or x > x1 then x1 = x end
      if not y0 or y < y0 then y0 = y end
      if not y1 or y > y1 then y1 = y end
    end
  end
  return x0, y0, x1, y1
end

-- align(set, state) -> ox, oy, same, diff
--
-- WHERE THE MULTI-CELL ORIGIN SITS IN THE STILL IS NOT A CONSTANT: measured
-- (41, 63) for Bulbasaur, (41, 71) for Pikachu, (43, 67) for Snivy. So it is
-- found per species, by drawing tick 0 on a large canvas and sliding the
-- still over it: bounding boxes first, then the best of +-8 pixels around,
-- scored on palette INDICES (equal opaque pixels minus unequal ones).
M.ALIGN_CANVAS = 512
function M.align(set, state, rasters)
  local still = M.stillIndices(set)
  if not still then return nil end
  local S, C = M.SIZE, M.ALIGN_CANVAS
  local half = C / 2
  local big = M.render(set, state, C, C, half, half, rasters or {})
  local bx0, by0 = bbox(big, C)
  local sx0, sy0 = bbox(still, S)
  if not (bx0 and sx0) then return nil end
  -- two first guesses: the bounding boxes, and the centres of mass (which a
  -- stray far-off speck -- Koffing's shrunken gas puffs -- cannot drag)
  local function centroid(idx, w)
    local sx, sy, n = 0, 0, 0
    for i, v in pairs(idx) do
      if v % 16 ~= 0 then sx, sy, n = sx + i % w, sy + floor(i / w), n + 1 end
    end
    return floor(sx / n + 0.5), floor(sy / n + 0.5)
  end
  local bcx, bcy = centroid(big, C)
  local scx, scy = centroid(still, S)
  local guesses = { { bx0 - sx0, by0 - sy0 }, { bcx - scx, bcy - scy } }
  -- THE SAME SCORE, WITHOUT VISITING EVERY PIXEL OF EVERY OFFSET. Walking
  -- all 96 x 96 pixels at each of up to 578 offsets is ~5M steps: instant
  -- compiled, but this runs as a Black / White battle opens (Gen5MonAnimPlayer)
  -- and love-android has the JIT off -- 2.7s interpreted on a desktop per
  -- Pokemon, far longer on a phone. With A = the still's opaque pixels, V =
  -- the big canvas's inside the window (a summed-area table, O(1) each), B =
  -- positions holding both and M = positions holding both equal:
  --   same = M, diff = |A| + |V| - B - M, same - diff = 2M + B - |A| - |V|
  -- so only the still's own pixels are visited, and an offset whose best case
  -- (M = B = min(|A|, |V|)) cannot beat the best so far is skipped. Same
  -- answer, same order, same tie-break.
  local stOff, stVal, nA = {}, {}, 0
  for i, a in pairs(still) do
    nA = nA + 1
    stOff[nA] = floor(i / S) * C + i % S
    stVal[nA] = a
  end
  local x0w, y0w, x1w, y1w
  for _, g in ipairs(guesses) do
    x0w = (not x0w or g[1] - 8 < x0w) and g[1] - 8 or x0w
    y0w = (not y0w or g[2] - 8 < y0w) and g[2] - 8 or y0w
    x1w = (not x1w or g[1] + 8 > x1w) and g[1] + 8 or x1w
    y1w = (not y1w or g[2] + 8 > y1w) and g[2] + 8 or y1w
  end
  -- every window inside the canvas (always, around a centred Pokemon); a
  -- window over an edge reads wrapped rows, which only the plain walk repeats
  local inside = x0w >= 0 and y0w >= 0 and x1w + S <= C and y1w + S <= C
  local RW, RH = x1w + S - x0w, y1w + S - y0w
  local sat
  if inside then
    local occ = {}
    for i in pairs(big) do
      local x, y = i % C - x0w, floor(i / C) - y0w
      if x >= 0 and y >= 0 and x < RW and y < RH then occ[y * RW + x] = 1 end
    end
    sat = {}
    local W1 = RW + 1
    for x = 0, RW do sat[x] = 0 end
    for y = 1, RH do
      local run, row, prev, src = 0, y * W1, (y - 1) * W1, (y - 1) * RW - 1
      sat[row] = 0
      for x = 1, RW do
        run = run + (occ[src + x] or 0)
        sat[row + x] = sat[prev + x] + run
      end
    end
  end
  local tried = {}
  local best, bestX, bestY, bestSame, bestDiff
  for _, g in ipairs(guesses) do
    for dy = -8, 8 do
      for dx = -8, 8 do
        -- the still's top-left on the big canvas
        local wx, wy = g[1] + dx, g[2] + dy
        local key = wx * 4096 + wy
        if not tried[key] then
          tried[key] = true
          local same, diff
          if sat then
            local W1 = RW + 1
            local ax, ay = wx - x0w, wy - y0w
            local nV = sat[(ay + S) * W1 + ax + S] - sat[ay * W1 + ax + S]
              - sat[(ay + S) * W1 + ax] + sat[ay * W1 + ax]
            local lo = nA < nV and nA or nV
            if not best or 3 * lo - nA - nV > best then
              local m, b, base = 0, 0, wy * C + wx
              for k = 1, nA do
                local v = big[base + stOff[k]]
                if v ~= nil then
                  b = b + 1
                  if v == stVal[k] then m = m + 1 end
                end
              end
              same, diff = m, nA + nV - b - m
            end
          else
            same, diff = 0, 0
            for y = 0, S - 1 do
              local row, brow = y * S, (wy + y) * C + wx
              for x = 0, S - 1 do
                local a = still[row + x]
                local v = big[brow + x]
                if a or v then
                  if a == v then same = same + 1 else diff = diff + 1 end
                end
              end
            end
          end
          if same and (not best or same - diff > best) then
            best, bestX, bestY, bestSame, bestDiff = same - diff, wx, wy, same, diff
          end
        end
      end
    end
  end
  return half - bestX, half - bestY, bestSame, bestDiff
end

-- bake(rom | archive, species, side, shiny, opts) -> anim, or nil + why
--
-- anim = {
--   frames = { { width, height, rgba }, ... },  -- distinct images, 1-based
--   play   = { { frame = n, dur = ticks }, ... }, -- one loop, 60 Hz ticks
--   width, height, count, loopTicks, truncated, sequence,
--   indexFrames,         -- the same frames as palette indices (M.recolour)
--   origin = { x, y },   -- multi-cell origin inside a frame
--   stillX, stillY,      -- where the 96 x 96 still's (0, 0) is inside a frame
--   match = { same, diff },  -- tick 0 against the still, in opaque pixels
--   clipped,             -- opaque pixels the crop dropped, over all frames
--   bounds = { x, y, w, h }, -- union of every frame, in still coordinates
-- }
-- frames[1] is always the tick-0 picture (the still's pose).
-- opts: { sequence = 0, maxTicks = M.MAX_TICKS,
--         crop = "still" (default: 96 x 96, aligned to the still, anything
--                outside clipped) | "bounds" (every frame the union bbox),
--         origin = {x, y} (skip alignment; still-window coordinates),
--         female = bool, set = a preloaded M.load result }
M.PAD = 128
function M.bake(rom, species, side, shiny, opts)
  opts = opts or {}
  local set, why = opts.set, nil
  if not set then
    set, why = M.load(rom, species, side or "front", shiny, opts.female)
    if not set then return nil, why end
  end
  local palette = (shiny and set.shinyPalette or set.normalPalette) or set.palette
  local mach, err = M.machine(set, opts.sequence or 0)
  if not mach then return nil, err end
  local rasters = {}
  local S = M.SIZE
  local ox, oy, same, diff
  if opts.origin then
    ox, oy = opts.origin[1], opts.origin[2]
  else
    ox, oy, same, diff = M.align(set, mach.state(), rasters)
    if not ox then ox, oy = M.ORIGIN[1], M.ORIGIN[2] end
  end
  local P = M.PAD
  local CW, CH = S + 2 * P, S + 2 * P
  local maxTicks = opts.maxTicks or M.MAX_TICKS
  local total = mach.loopTicks
  if not mach.loops or total <= 0 then total = maxTicks end
  local truncated = false
  if total > maxTicks then total, truncated = maxTicks, true end

  -- pass 1: every distinct state, on the padded canvas
  local bigs, byState, order = {}, {}, {}
  for tick = 0, total - 1 do
    local state = mach.state()
    local key = stateKey(state)
    local n = byState[key]
    if not n then
      bigs[#bigs + 1] = M.render(set, state, CW, CH, ox + P, oy + P, rasters)
      n = #bigs
      byState[key] = n
    end
    order[tick + 1] = n
    mach.tick()
  end

  -- the window: the still's, or the union of every frame
  local u0, v0, u1, v1
  for _, big in ipairs(bigs) do
    local x0, y0, x1, y1 = bbox(big, CW)
    if x0 then
      u0 = (not u0 or x0 < u0) and x0 or u0; v0 = (not v0 or y0 < v0) and y0 or v0
      u1 = (not u1 or x1 > u1) and x1 or u1; v1 = (not v1 or y1 > v1) and y1 or v1
    end
  end
  u0, v0, u1, v1 = u0 or P, v0 or P, u1 or P, v1 or P
  local wx, wy, W, H
  if opts.crop == "bounds" then
    wx, wy, W, H = u0, v0, u1 - u0 + 1, v1 - v0 + 1
  else
    wx, wy, W, H = P, P, S, S
  end

  -- pass 2: crop, de-duplicate by picture, build the play list
  local clipped = 0
  local frames, indexFrames, byImage, remap = {}, {}, {}, {}
  for n, big in ipairs(bigs) do
    local idx = {}
    for i, v in pairs(big) do
      local x, y = i % CW - wx, floor(i / CW) - wy
      if x >= 0 and y >= 0 and x < W and y < H then idx[y * W + x] = v
      elseif v % 16 ~= 0 then clipped = clipped + 1 end
    end
    local ikey = M.indexKey(idx, W, H)
    local k = byImage[ikey]
    if not k then
      indexFrames[#indexFrames + 1] = idx
      k = #indexFrames
      byImage[ikey] = k
      frames[k] = { width = W, height = H, rgba = M.rgba(idx, W, H, palette) }
    end
    remap[n] = k
  end
  local play = {}
  for _, n in ipairs(order) do
    local k = remap[n]
    local last = play[#play]
    if last and last.frame == k then last.dur = last.dur + 1
    else play[#play + 1] = { frame = k, dur = 1 } end
  end
  return {
    frames = frames, play = play, width = W, height = H, count = #frames,
    indexFrames = indexFrames,
    origin = { ox + P - wx, oy + P - wy },
    stillX = P - wx, stillY = P - wy,
    match = same and { same = same, diff = diff } or nil,
    clipped = clipped,
    bounds = { x = u0 - P, y = v0 - P, w = u1 - u0 + 1, h = v1 - v0 + 1 },
    loopTicks = mach.loopTicks, truncated = truncated, sequence = opts.sequence or 0,
    species = species, side = side or "front", shiny = shiny and true or false,
  }
end

-- indexKey(idx, w, h) -> a string identifying an index raster
function M.indexKey(idx, w, h)
  local t = {}
  for i = 0, w * h - 1 do t[i + 1] = char(idx[i] or 0) end
  return concat(t)
end

-- recolour(anim, palette) -> the same animation (same frame order, same play
-- list) drawn through another palette: how the shiny strip is made, so the
-- normal and shiny strips always line up frame for frame.
function M.recolour(anim, palette)
  local out = {}
  for k, v in pairs(anim) do out[k] = v end
  out.frames = {}
  for i, idx in ipairs(anim.indexFrames) do
    out.frames[i] = { width = anim.width, height = anim.height,
                      rgba = M.rgba(idx, anim.width, anim.height, palette) }
  end
  return out
end

-- strip(anim) -> { width = w * count, height, rgba }: frames side by side, the
-- layout PicAnim.frameImage cuts (frame n at x = (n - 1) * width).
function M.strip(anim)
  local w, h, n = anim.width, anim.height, #anim.frames
  local rows = {}
  for y = 0, h - 1 do
    local row = {}
    for i = 1, n do
      local s = anim.frames[i].rgba
      row[i] = s:sub(y * w * 4 + 1, (y + 1) * w * 4)
    end
    rows[y + 1] = concat(row)
  end
  return { width = w * n, height = h, rgba = concat(rows) }
end

-- picAnim(anim, save, path, shinyPath) -> the def.picAnim record, or nil.
-- `save(path, image)` writes an { width, height, rgba } image and returns the
-- stored path (or an entry with .path) -- e.g. RomExtractor's self:saveImage.
-- `shinyAnim`, when given, should be M.recolour(anim, shinyPalette) so the
-- two strips share one frame order and one play list.
function M.picAnim(anim, save, path, shinyAnim, shinyPath)
  if not (anim and #anim.frames > 0) then return nil end
  local function put(p, a)
    local r = save(p, M.strip(a))
    if type(r) == "table" then r = r.path end
    return r
  end
  local sheet = put(path, anim)
  if not sheet then return nil end
  local rec = {
    sheet = sheet, count = #anim.frames, width = anim.width, height = anim.height,
    play = anim.play, idle = anim.play, loop = true,
    source = ("ROM:%s[%d]"):format(M.PATH, anim.species * M.STRIDE),
  }
  if shinyAnim and #shinyAnim.frames == #anim.frames then
    rec.shinySheet = put(shinyPath, shinyAnim)
  end
  return rec
end

-- Preserve the cartridge resources rather than expanding every idle tick to
-- PNG strips. This also avoids texture-width limits on long NMAR sequences.
function M.pack(arc,species)
  local function word(n)return char(n%256,floor(n/256)%256,floor(n/65536)%256,floor(n/16777216)%256)end
  local out={"G5AN",word(species)}
  for i=0,19 do local data=arc:get(species*20+i) or "";out[#out+1]=word(#data);out[#out+1]=data end
  return concat(out)
end
function M.unpack(bytes)
  if type(bytes)~="string" or bytes:sub(1,4)~="G5AN"then return nil,"invalid animation bundle"end
  local species=u32(bytes,5);if not species then return nil,"truncated header"end
  local members,at={},9
  for i=0,19 do
    local size=u32(bytes,at);at=at+4
    if not size or size>2097152 or at+size-1>#bytes then return nil,"truncated animation member"end
    members[species*20+i]=bytes:sub(at,at+size-1);at=at+size
  end
  if at~=#bytes+1 then return nil,"trailing animation bytes"end
  return {count=(species+1)*20,get=function(_,i)return members[i]end}
end
return M
