-- Round 37: the parallax backgrounds of the Minish Paths and the Minish
-- rafters (src/manager/verticalMinishPathBackgroundManager.c,
-- horizontalMinishPathBackgroundManager.c, minishRaftersBackgroundManager.c,
-- the room code in src/roomInit.c).  Without them the paths showed the bare
-- BG2 path and the rafters showed the backdrop through the gaps.
--
-- CARTRIDGE BEHAVIOUR:
--   * The room's StateChange code picks the gfx group (LoadGfxGroup: 16 KB
--     of 4bpp characters to $06008000 = char base 2, the BG maps to
--     gMapDataTopSpecial $02002F00..$02006EFF) and switches the room's own
--     BG1 off (gMapTop.bgSettings = 0):
--       $11:00 group 30, $11:01 33, $11:02 31, $11:03 32, $11:04 32
--       ($20 at StateChange, 32 at unk1: the same), $12:00 / $12:01 35
--       (vertical, sub_080575C8; $12:00 also sub_08057688: both BGs at
--       priority 0), $12:02 / $12:03 34 (horizontal, sub_080580B0).
--   * VERTICAL ($02): BG3 control SCREENBASE 29 | PRIORITY 1 | CHARBASE 2,
--     BG1 SCREENBASE 30 | PRIORITY 1 | CHARBASE 2; BLDCNT BG3 blended over
--     BG2 / BG3 / OBJ / backdrop, BLDALPHA (9, 6).  Each frame (sub_0805754C)
--     d = scroll_y - origin_y; BG3 shows the 32-entry-wide strip of the first
--     $2000 bytes of the map from row d + (d >> 3), BG1 the strip of the next
--     $2000 bytes from row d + (d >> 2); x offset 0.
--   * HORIZONTAL ($08): sub_08058034 lays the eight 32x32 blocks of the map
--     side by side in two rows (blocks 0..3 for BG3, 4..7 for BG1, 1024 px
--     wide); sub_08057F20: t = dx + (dx >> 3) + ($400 - width) / 2, BG3 x
--     = t, y = $30 - (($30 - dy) >> 2); BG1 t = dx + (dx >> 2) + ($400 -
--     width) / 2, y = $30 - (($30 - dy) >> 1) (dx / dy = scroll - origin);
--     controls $1D09 / $1E09 (priority 1, char base 2), the same blend.
--   * RAFTERS ($09, type = the room): sub_08058324 LoadPaletteGroup($86 +
--     type), LoadGfxGroup($36 + type) (characters at $06004000, two 32x32
--     map blocks laid side by side: 512 x 256), BG1 control $1D47 (priority
--     3: behind the room); sub_08058244: x = (dx * gUnk_081081EC[type]) /
--     (width - 240), y = origin_y + (dy * $20) / (height - 160).
-- SIMPLIFIED: the BG mosaic bit (the mosaic size register is 0); the blend
--   is the two-pass picture of Cloud34 (below darkened to EVB / 16, BG3 *
--   EVA / 16 added); BG3 reading past its $2000 bytes (rooms are sized so it
--   does not) is not modelled.
local bit = require("bit")
local band, rshift, arshift = bit.band, bit.rshift, bit.arshift

local M = {}
M.VERTICAL, M.HORIZONTAL, M.RAFTERS = 0x02, 0x08, 0x09
-- the room code's sub_080575C8 / sub_080580B0 arguments (src/roomInit.c)
M.GROUP = {
  [0x1100] = 30, [0x1101] = 33, [0x1102] = 31, [0x1103] = 32, [0x1104] = 32,
  [0x1200] = 35, [0x1201] = 35, [0x1202] = 34, [0x1203] = 34,
}
M.PRIO0 = { [0x1200] = true } -- sub_08057688
M.EVA, M.EVB = 9, 6
local SPAN = require("src.zelda.tmc.RomTables").t("PathBg37.RAFTER_SPAN") -- gUnk_081081EC
M.SPAN = SPAN

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

-- the bytes a gfx group writes into [base, base + len)
local function groupBytes(A, g, base, len)
  local list = A.manifest.gfxGroups and A.manifest.gfxGroups[g]
  if not list then return nil end
  A.gfxBlob = A.gfxBlob or A.store:read("gfxgroups.bin") or ""
  local parts, any = {}, false
  local buf = {}
  for _, it in ipairs(list) do
    local d0, off, n = it[1], it[2], it[3]
    if d0 + n > base and d0 < base + len then
      any = true
      parts[#parts + 1] = { d0 - base, A.gfxBlob:sub(off + 1, off + n) }
    end
  end
  if not any then return nil end
  table.sort(parts, function(a, b) return a[1] < b[1] end)
  local out, pos = {}, 0
  for _, pp in ipairs(parts) do
    local at, s = pp[1], pp[2]
    if at > pos then out[#out + 1] = string.rep("\0", at - pos); pos = at end
    if at < pos then s = s:sub(pos - at + 1) end
    out[#out + 1] = s
    pos = pos + #s
  end
  local r = table.concat(out)
  if #r > len then r = r:sub(1, len) end
  return r
end
M.groupBytes = groupBytes

-- a picture of `blocks` 32x32 screen blocks (byte offsets into `map`) laid
-- side by side ("h") or stacked ("v"), 4bpp characters from `chars`
function M.picture(A, chars, map, blocks, dir, pals)
  local nb = #blocks
  local W = dir == "h" and 32 * nb or 32
  local Ht = dir == "h" and 32 or 32 * nb
  local img, ptr = A.newPixels(W * 8, Ht * 8)
  for bi, boff in ipairs(blocks) do
    local bx = dir == "h" and (bi - 1) * 32 or 0
    local by = dir == "h" and 0 or (bi - 1) * 32
    for ty = 0, 31 do
      for tx = 0, 31 do
        local se = u16(map, boff + (ty * 32 + tx) * 2)
        local tile = band(se, 0x3FF)
        local hf, vf = band(se, 0x400) ~= 0, band(se, 0x800) ~= 0
        local pal = pals[rshift(se, 12)]
        local tb = tile * 32
        if pal and tb + 32 <= #chars then
          for py = 0, 7 do
            local sy = vf and (7 - py) or py
            for px = 0, 7 do
              local sx = hf and (7 - px) or px
              local byte = chars:byte(tb + sy * 4 + rshift(sx, 1) + 1) or 0
              local ci = (sx % 2 == 0) and band(byte, 15) or rshift(byte, 4)
              local c = ci ~= 0 and pal[ci]
              if c then A.putPixel(img, ptr, W * 8, (bx + tx) * 8 + px, (by + ty) * 8 + py, c[1], c[2], c[3], 255) end
            end
          end
        end
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  image:setWrap("repeat", "repeat")
  return image
end

local function roomKey(r) return r.area * 256 + r.room end

function M.setup(f, kind, typ)
  local r = f.room
  local A = f.assets
  local key = roomKey(r)
  local s = { kind = kind, room = r, type = typ or 0, prio3 = 1, prio1 = 1 }
  local pals = r.atlas and r.atlas.palettes or (A.areaPalettes and A:areaPalettes(r.area, r.maps.header.ts))
  if not pals then return nil end
  if kind == M.RAFTERS then
    local g = 0x36 + s.type
    local p2 = {}
    for i = 0, 31 do p2[i] = pals[i] end
    A:applyPaletteGroup(p2, 0x86 + s.type)
    local chars = groupBytes(A, g, 0x06004000, 0x8000)
    local map = groupBytes(A, g, 0x02002F00, 0x1000)
    if not (chars and map) then return nil end
    s.bg1 = M.picture(A, chars, map, { 0, 0x800 }, "h", p2)
    s.prio1, s.prio3 = 3, nil
  else
    local g = M.GROUP[key]
    if not g then return nil end
    local chars = groupBytes(A, g, 0x06008000, 0x4000)
    local map = groupBytes(A, g, 0x02002F00, 0x4000)
    if not (chars and map) then return nil end
    s.group, s.map = g, map
    if kind == M.VERTICAL then
      s.bg3 = M.picture(A, chars, map, { 0, 0x800, 0x1000, 0x1800 }, "v", pals)
      s.bg1 = M.picture(A, chars, map, { 0x2000, 0x2800, 0x3000, 0x3800 }, "v", pals)
    else
      s.bg3 = M.picture(A, chars, map, { 0, 0x800, 0x1000, 0x1800 }, "h", pals)
      s.bg1 = M.picture(A, chars, map, { 0x2000, 0x2800, 0x3000, 0x3800 }, "h", pals)
    end
    if M.PRIO0[key] then s.prio1, s.prio3 = 0, 0 end
  end
  r.hideTop = true -- gMapTop.bgSettings = 0
  r.pathBg37 = s
  f.pathBg37 = s
  return s
end

function M.spawnManager(d, m)
  if m.id ~= M.VERTICAL and m.id ~= M.HORIZONTAL and m.id ~= M.RAFTERS then return nil end
  local ok, s = pcall(M.setup, d.field, m.id, m.type)
  if not ok then print("[PathBg37] " .. tostring(s)) end
  return true
end

-- the picture offsets for the cartridge scroll (dx, dy = scroll - origin)
function M.offsets(s, r, dx, dy)
  dx, dy = math.floor(dx), math.floor(dy)
  if s.kind == M.VERTICAL then
    return 0, dy + arshift(dy, 3), 0, dy + arshift(dy, 2)
  elseif s.kind == M.HORIZONTAL then
    local c = math.floor((0x400 - r.width) / 2)
    return dx + arshift(dx, 3) + c, 0x30 - arshift(0x30 - dy, 2),
           dx + arshift(dx, 2) + c, 0x30 - arshift(0x30 - dy, 1)
  else
    local sw, sh = r.width - 240, r.height - 160
    local x = sw > 0 and math.floor(dx * (SPAN[s.type] or 0x30) / sw) or 0
    local y = sh > 0 and math.floor(dy * 0x20 / sh) or 0
    return nil, nil, x, (r.y or 0) + y
  end
end

-- the BG1 screen entry shown at room pixel (x, y) (waterDrop.c reads
-- gBG3Buffer + $400, the horizontal manager's BG1 window); 0 = empty
function M.bg1At(f, x, y)
  local r = f.room
  local s = r and r.pathBg37
  if not s or not s.map or s.kind == M.RAFTERS then return 0 end
  local cx, cy = f.camX or 0, f.camY or 0
  if f._realCam then cx, cy = f._realCam[1], f._realCam[2] end
  local _, _, x1, y1 = M.offsets(s, r, cx, cy)
  local col = math.floor((x1 + math.floor(x) - math.floor(cx)) / 8)
  local row = math.floor((y1 + math.floor(y) - math.floor(cy)) / 8)
  local off
  if s.kind == M.HORIZONTAL then
    local blk = 4 + math.floor(col / 32)
    if blk < 4 or blk > 7 then return 0 end
    off = blk * 0x800 + ((row % 32) * 32 + col % 32) * 2
  else
    if row < 0 or row >= 128 then return 0 end
    off = 0x2000 + (row * 32 + col % 32) * 2
  end
  return u16(s.map, off)
end

local function drawPic(img, ox, oy, cx, cy, camX, camY, wrapY, blend)
  local g = love.graphics
  -- screen pixel (sx, sy) = room (cx + sx, cy + sy) shows picture (ox + sx, oy + sy)
  local x = math.floor(cx) - ox - math.floor(camX)
  local y = math.floor(cy) - oy - math.floor(camY)
  local iw, ih = img:getDimensions()
  local function one()
    if wrapY then
      -- the BG wraps every 256 rows: screen row sy shows (oy + sy) mod ih
      M.quads = M.quads or setmetatable({}, { __mode = "k" })
      local q = M.quads[img]
      if not q then q = g.newQuad(0, 0, iw, ih * 3, iw, ih); M.quads[img] = q end
      local y0 = (math.floor(cy) - math.floor(camY)) - ((oy % ih) + ih)
      g.draw(img, q, x, y0)
    else
      g.draw(img, x, y)
    end
  end
  if blend then
    g.push("all")
    g.setColor(0, 0, 0, (16 - M.EVB) / 16)
    one()
    g.setBlendMode("add")
    g.setColor(M.EVA / 16, M.EVA / 16, M.EVA / 16, 1)
    one()
    g.pop()
  else
    one()
  end
end

-- Priority.compose (through R37.bgPass): BG3 then BG1 of priority p
function M.bgPass(f, r, p, camX, camY)
  local s = r.pathBg37
  if not s then return end
  local cx, cy = camX, camY
  if f._realCam then cx, cy = f._realCam[1], f._realCam[2] end
  local g = love.graphics
  local x3, y3, x1, y1 = M.offsets(s, r, cx, cy)
  local wrap = s.kind ~= M.VERTICAL
  g.push("all")
  -- the BGs cover the 240 x 160 screen (zoomed out: the screen's window)
  local sx0, sy0 = g.transformPoint(math.floor(cx) - math.floor(camX), math.floor(cy) - math.floor(camY))
  local sx1, sy1 = g.transformPoint(math.floor(cx) - math.floor(camX) + 240, math.floor(cy) - math.floor(camY) + 160)
  if require("src.zelda.tmc.View").wide(f) and f.room == r then -- widescreen: the whole field wide
    local vw = require("src.zelda.tmc.View").screen(f)
    sx0 = g.transformPoint(0, 0); sx1 = g.transformPoint(vw, 0)
  end
  g.intersectScissor(math.floor(sx0), math.floor(sy0), math.max(0, math.ceil(sx1 - sx0)), math.max(0, math.ceil(sy1 - sy0)))
  if s.bg3 and s.prio3 == p then drawPic(s.bg3, x3, y3, cx, cy, camX, camY, wrap, true) end
  if s.bg1 and s.prio1 == p then drawPic(s.bg1, x1, y1, cx, cy, camX, camY, wrap, false) end
  g.pop()
end

return M
