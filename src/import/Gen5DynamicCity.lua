-- BLACK CITY AND WHITE FOREST: THE "RD" CHUNKS AND THEIR PIECES.
--
-- Black City (zones 0 / 294, matrix 226) and White Forest (zones 424 / 295,
-- matrix 225) are each a 2 x 2 matrix of the only "RD" chunks in /a/0/0/8
-- (members 228..235). Neither the zone headers nor the chunks differ between
-- the two cartridges; what differs is which of the two a save shows.
--
-- AN RD CHUNK (ov21's chunk-format table at 0x21D3E0C: magic, loaders
-- 0x2193629 / 0x2193791) has three sections -- the model, the permissions
-- and the building placements -- like a WB chunk, but its permission tile is
-- 24 BYTES, not 8: two constant 8-byte records (0000 FE0F 0000 0000 and
-- FE0F 0000 0000 0000 on every tile) and then the 8-byte record a WB tile
-- holds (byte 4 the behaviour, bit 0 of byte 6 the collision). Read as a WB
-- chunk the section matched nothing and every tile fell back to "blocked":
-- the cache held no floor for either place.
--
-- THE PIECES. The chunk is only the streets. The loader (0x2193628) then
-- walks the chunk's 4 x 4 blocks of 8 x 8 tiles; each block's entry in an
-- 8 x 8 grid over the whole matrix (grid x = (cell % 2) * 4 + block x) names
-- a PIECE, /a/1/5/6[id] (arc 0x9C, 0x21C939C):
--   u16 offset of its permissions: u16 width, u16 height, then 24-byte tiles
--   u16 offset of its buildings:   u32 count, 16-byte placements as a chunk's
-- and 0x21C93E4 copies the block's 8 x 8 tiles of the piece over the chunk's
-- (a piece two or four blocks wide covers its blocks from its own columns),
-- while the piece's building -- an id in the area's building pack -- is
-- placed once, at the piece's first block (0x21C9450, offset by that block's
-- tile x / z * 16 units).
--
-- THE GRID is built by 0x2194128 from a TEMPLATE, /a/1/5/4[30] for Black City
-- and [31] for White Forest (0x21D3F58, indexed by the save's city byte):
--   +0x00  8 x 8 entries of two bytes -- the low / high nibbles of the first
--          step back to the piece's first block, and the piece TYPE (0xFF
--          none)
--   +0x80  per type, 64 bytes: two variants x eight levels of u32 piece ids
-- At a piece's first block the id is table[type][variant][level], where
--   level   = residents * 8 / 10 + rand(n), at most 7
--   variant = ((sum of the residents' byte 9 + x + y) / (x + y + 4)) & 1
-- from the residents (the save's ten 0x18-byte slots, counted by ov20
-- 0x2186278) and the field's 64-bit LCG seeded from the save. A NEW GAME
-- FILLS ALL TEN (ov20 0x21860D4, called from the new-game set-up 0x2183C58,
-- draws each at random), so level = 80 / 10 + rand >= 8, held at 7: every
-- piece stands at its last level whatever the draw, and that is what is
-- imported here. The variant depends on which residents were drawn (their
-- byte 9); the import takes a byte sum of 0 for it. The city changing as
-- residents come and go is not modelled.
--
-- WHICH ONE A CARTRIDGE SHOWS: zone lookups pass through ARM9 0x2013A94,
-- which swaps zone 0 for 424 and 294 for 295 (the pairs at 0x20A72A8) while
-- the save's city byte is 1 (ov10 0x2161D64). Black shows Black City and
-- White shows White Forest: `M.remap` says which zones a White import sends
-- its warps to instead.

local M = {}

M.TEMPLATE_ARC, M.PIECE_ARC = "/a/1/5/4", "/a/1/5/6"
M.TEMPLATES = { 30, 31 }
M.TILE_RD, M.TILE_WB, M.SUB = 24, 8, 16
M.CHUNK = 32

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end
local function s32(s, o)
  local v = u32(s, o)
  return v >= 2147483648 and v - 4294967296 or v
end

-- rdPermissions(raw RD section) -> the WB-shaped section (4-byte header and
-- 8 bytes a tile), or nil when this is not a 32 x 32 RD section
function M.rdPermissions(raw)
  if type(raw) ~= "string" or #raw < 4 then return nil end
  local w, h = u16(raw, 0), u16(raw, 2)
  if w < 1 or h < 1 or #raw < 4 + w * h * M.TILE_RD then return nil end
  local out = { raw:sub(1, 4) }
  for t = 0, w * h - 1 do
    local at = 4 + t * M.TILE_RD + M.SUB
    out[#out + 1] = raw:sub(at + 1, at + M.TILE_WB)
  end
  return table.concat(out)
end

-- piece(bytes) -> { width, height, tiles = raw 24-byte tiles, buildings = raw }
function M.piece(bytes)
  if type(bytes) ~= "string" or #bytes < 8 then return nil end
  local po, bo = u16(bytes, 0), u16(bytes, 2)
  local w, h = u16(bytes, po), u16(bytes, po + 2)
  if w < 1 or h < 1 or #bytes < po + 4 + w * h * M.TILE_RD then return nil end
  return { width = w, height = h, tiles = bytes:sub(po + 5, po + 4 + w * h * M.TILE_RD),
           buildings = bytes:sub(bo + 1) }
end

-- layout(template, residents) -> grid[gy][gx] = { lo, hi, type, piece } for
-- the 8 x 8 blocks (nil where the template has no piece). `residents` is
-- { count, byteSum } and defaults to a new game's ten.
M.NEW_GAME_RESIDENTS = 10
function M.layout(tpl, residents)
  if type(tpl) ~= "string" or #tpl < 0x80 then return nil end
  local count = residents and residents.count or M.NEW_GAME_RESIDENTS
  local sum = residents and residents.byteSum or 0
  local grid = {}
  for gy = 0, 7 do
    grid[gy] = {}
    for gx = 0, 7 do
      local nib, ty = tpl:byte(gy * 16 + gx * 2 + 1), tpl:byte(gy * 16 + gx * 2 + 2)
      if ty ~= 0xFF then
        local lo, hi = nib % 16, math.floor(nib / 16)
        local entry = { lo = lo, hi = hi, type = ty }
        if lo == 0 and hi == 0 then
          local variant = math.floor(((sum + gx + gy) % 256) / (gx + gy + 4)) % 2
          -- + rand(n): n is 1 with no residents (adding 0); with residents
          -- the cartridge's LCG adds 0..n-1 here (not modelled -- with the
          -- new game's ten the level is held at 7 whatever it adds)
          local level = math.min(math.floor(count * 8 / 10), 7)
          local at = 0x80 + ty * 64 + (variant * 8 + level) * 4
          entry.piece = #tpl >= at + 4 and u16(tpl, at) or nil
        else
          local origin = grid[gy - hi] and grid[gy - hi][gx - lo]
          entry.piece = origin and origin.piece
        end
        grid[gy][gx] = entry
      end
    end
  end
  return grid
end

-- the building placements a piece adds, as Gen5Field.placements returns
-- them, moved to the block at chunk tile (tx, tz)
local function piecePlacements(buildings, tx, tz)
  local out = {}
  if type(buildings) ~= "string" or #buildings < 4 then return out end
  local n = u32(buildings, 0)
  for i = 0, n - 1 do
    local o = 4 + i * 16
    if #buildings < o + 16 then break end
    local rot = u16(buildings, o + 12)
    out[#out + 1] = { model = buildings:byte(o + 15) * 256 + buildings:byte(o + 16), x = s32(buildings, o) / 4096 + tx * 16,
      y = s32(buildings, o + 4) / 4096, z = -s32(buildings, o + 8) / 4096 + tz * 16,
      rotY = rot / 65536 * 360, gen5 = true, gen5Piece = true }
  end
  return out
end

-- stamp(perms, piece, lo, hi, tx, tz) -> the WB-shaped permissions with the
-- block's 8 x 8 tiles of the piece written at chunk tile (tx, tz)
local function stamp(perms, pc, lo, hi, tx, tz)
  local cw = u16(perms, 0)
  local parts, last = {}, 0
  local rows = {}
  for r = 0, 7 do
    local src = {}
    for c = 0, 7 do
      local px, py = lo * 8 + c, hi * 8 + r
      if px < pc.width and py < pc.height then
        local at = (py * pc.width + px) * M.TILE_RD + M.SUB
        src[#src + 1] = pc.tiles:sub(at + 1, at + M.TILE_WB)
      end
    end
    if #src == 8 then rows[#rows + 1] = { at = 4 + ((tz + r) * cw + tx) * M.TILE_WB, bytes = table.concat(src) } end
  end
  table.sort(rows, function(a, b) return a.at < b.at end)
  for _, row in ipairs(rows) do
    parts[#parts + 1] = perms:sub(last + 1, row.at)
    parts[#parts + 1] = row.bytes
    last = row.at + #row.bytes
  end
  parts[#parts + 1] = perms:sub(last + 1)
  return table.concat(parts)
end

-- build(rom, opts) -> { [chunk id] = { permissions = WB-shaped, objects = { ... } } }
-- for every matrix made of RD chunks. opts:
--   matrices  { [id] = Gen5Maps.matrix(...) } (all of /a/0/0/9)
--   rdChunks  { [chunk id] = raw RD permission section } (WB-shaped already)
--   packIds   function(matrix id) -> set of building ids its zone's pack holds
function M.build(rom, opts)
  local Narc = require("src.import.NarcArchive")
  local tb, pb = rom:read(M.TEMPLATE_ARC), rom:read(M.PIECE_ARC)
  local tArc, pArc = tb and Narc.parse(tb), pb and Narc.parse(pb)
  if not (tArc and pArc) then return {}, {} end
  local pieces = {}
  local function pieceOf(id)
    if pieces[id] == nil then pieces[id] = (id < pArc.count and M.piece(pArc:get(id))) or false end
    return pieces[id] or nil
  end
  local layouts = {}
  for _, t in ipairs(M.TEMPLATES) do layouts[t] = t < tArc.count and M.layout(tArc:get(t)) or nil end
  -- which template is the matrix's: the one whose pieces' buildings its
  -- area's building pack holds (template 30's are Black City's pack 18,
  -- 31's White Forest's pack 47)
  local function fits(grid, ids)
    if not (grid and ids) then return false end
    local any = false
    for gy = 0, 7 do
      for gx = 0, 7 do
        local e = grid[gy][gx]
        local pc = e and e.piece and pieceOf(e.piece)
        for _, o in ipairs(pc and piecePlacements(pc.buildings, 0, 0) or {}) do
          any = true
          if not ids[o.model] then return false end
        end
      end
    end
    return any
  end
  local out, report = {}, {}
  for mid, m in pairs(opts.matrices or {}) do
    local cells, rd = m.width * m.height, true
    for i = 1, cells do if not (m.chunks[i] and opts.rdChunks[m.chunks[i]]) then rd = false end end
    if rd and cells > 0 then
      local ids = opts.packIds and opts.packIds(mid)
      local tpl
      for _, t in ipairs(M.TEMPLATES) do if not tpl and fits(layouts[t], ids) then tpl = t end end
      local grid = tpl and layouts[tpl]
      report[#report + 1] = ("matrix %d: template %s"):format(mid, tostring(tpl))
      for i = 1, cells do
        local c = m.chunks[i]
        local cx, cz = (i - 1) % m.width, math.floor((i - 1) / m.width)
        local perms, objects = opts.rdChunks[c], {}
        for bz = 0, 3 do
          for bx = 0, 3 do
            local e = grid and grid[cz * 4 + bz] and grid[cz * 4 + bz][cx * 4 + bx]
            local pc = e and e.piece and pieceOf(e.piece)
            if pc then
              perms = stamp(perms, pc, e.lo, e.hi, bx * 8, bz * 8)
              if e.lo == 0 and e.hi == 0 then
                for _, o in ipairs(piecePlacements(pc.buildings, bx * 8, bz * 8)) do objects[#objects + 1] = o end
              end
            end
          end
        end
        out[c] = { permissions = perms, objects = objects, template = tpl }
      end
    end
  end
  return out, report
end

-- the zone pairs a cartridge swaps while its city byte is 1 (White): read
-- from the ARM9 table 0x20A72A8 by its bytes, two u16 pairs
function M.remap(rom)
  local arm9 = rom and rom.arm9 and rom:arm9()
  local key = string.char(0x00, 0x00, 0xA8, 0x01, 0x26, 0x01, 0x27, 0x01)
  local at = arm9 and arm9:find(key, 1, true)
  if not at then return { [0] = 424, [294] = 295 } end
  local out = {}
  for k = 0, 1 do out[u16(arm9, at - 1 + k * 4)] = u16(arm9, at - 1 + k * 4 + 2) end
  return out
end

return M
