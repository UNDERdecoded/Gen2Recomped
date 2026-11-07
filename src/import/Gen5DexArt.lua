-- BLACK AND WHITE'S POKEDEX (/a/1/5/9, 113 members, the same in both games;
-- bw_ui_map.md section 8), written as `gen5_dex_art`, drawn by
-- src/ui/Gen5Pokedex.lua. There are no symbols: every pairing below was found
-- by composing the archive's maps against its tilesets and palettes and
-- checking pixel colours and positions against Bulbapedia's two cartridge
-- captures (Pokedex_BW.png -- the list -- and Pokedex_entry_BW.png -- the
-- INFO page), sampled pixel by pixel.
--
-- The archive is four groups, each [palettes][chars][cells][screens][anims]:
--   A  p0-9   g10-25  c26-30  S31-42  a43-47   the entry pages (INFO, ...)
--   B  p48-51 g52-59  c60-61  S62-69  a70-71   the list
--   C  p72-76 g77-82  c83-85  S86-98  a99-101  the search screen
--   D  p102-104 g105-107 S108-112             the area map / size compare
--
-- WHAT IS WRITTEN (all found AND checked against the captures unless noted)
--   list_top        S63 on g57, p49: the top's grid, dark bands 0-23 and 176-191
--   list_header     S69 on g57, p49 (rows 0-47): the >-title strip and the white
--                   SEEN / OBTAINED bar
--   list_touch      S62 on g56, p48: the touch grid, the dark strip (0-15) and the
--                   grey hatched band (16-84) the chosen Pokemon stands in
--   row_<state>     S66 / S67 / S68 (160 x 24) on g58, p48: the list row of a caught
--                   (ball), seen (empty ring) and unseen (one bracket) Pokemon
--   row_<state>_sel the same with palette row 1 replaced by row 2 -- the olive
--                   row of the cursor (the capture's 305810 is row 2 colour 1)
--   info_touch      S40 on g25, p9, drawn 24 pixels up (the capture puts its rows
--                   24 higher than the map does), laid on the grid with the panel's
--                   flat grey (p9 colour 7) flood-filled behind it -- THE BASE
--                   LAYER UNDER S40 WAS NOT FOUND; the grid is S31's own grid tile
--                   shifted to the capture's line phase, the grey is a fill
--   info_header     S37 on g14, p4 with palette row 1 read as row 0 (green: the
--                   capture's stripes are 004030 / 008060, row 0's colours)
--   info_top        S63 on g57, p49 scrolled 8 -- APPROXIMATE: the capture's
--                   band is 168-191 in 383838 / 282828, this one's is 168-183 in
--                   303030 / 181818 and the rest is filled; the right map
--                   was not found
--   ball_hex        g25 tiles 0-4 x 0-2 in p9 row 0, cropped 36 x 18: the white hex
--                   and Poke Ball over S40's green hex when the Pokemon is caught
--   page_<n>        c27 on g13, p3 cells 1-8: INFO / AREA / CRY / FORMS, off/on
--   obj_<n>         c61 on g55, p51: 0 START, 2 scroll thumb, 3 scroll track,
--                   6 the panel's corner brackets and "(A):INFO"
--   button_<n>      /a/0/8/3 g20 / c21 / p19 (the shared touch buttons, as the
--                   bag reads them): 0 (x), 1 back, 2 vv, 3 ^^, 4 <<, 5 >>, 6 box
-- Every OBJ / button entry carries `bx, by` -- its opaque box's corner in the
-- saved image -- so the screen places it by the box the captures measured.
--
--   area_<n>        c28 on g15, p5 (READ: ov208 0x021C0214..0x021C025A loads them
--                   as the AREA page's markers), cell n = the shape ov208 picks by a
--                   place's town-map cursor shape (anim 45: sequence s -> cell
--                   AREA_SEQ_CELL[s])
--   area            the AREA data, /a/1/7/8 (narc 178, READ: ov208 0x021C1F28 reads
--                   member species - 1, 249 bytes): byte 0 nonzero = one block for
--                   every season (0x021C1B08), else four 62-byte blocks at 1 + 62 s
--                   by the season; a block's byte 0 = area unknown (bank 234 #128),
--                   bytes 1..61 = the places in the order of ov208's zone table
--                   0x021C8670 (= the town map's own record order, /a/0/8/6),
--                   value 1..4 (what each value means: NOT READ). Kept as
--                   area[species] = { same = bool, [s] = { unknown = bool,
--                   places = { place = value } } }, s 1..4, place 1..61
--   areaZones       0x021C8670's 61 zones (READ), matched to gen5_town_map's
--                   locations by zone as 0x021C0048 does
-- NOT DONE: the footprint (the box is drawn empty), the English type-label
-- sheet (G18-23 are FR/DE/IT/JP/KR/ES; the screen uses the BW type badges of
-- /a/1/2/4 instead), the CRY / FORMS pages, the search screen (group C),
-- the foot's black gradient (not found in this archive; drawn by the screen
-- from the capture's measured rows).

local A = {}

A.PATH = "/a/1/5/9"
A.AREA_PATH = "/a/1/7/8"
A.AREA_SEQ_CELL = { [0] = 0, 1, 2, 3, 4, 5, 9, 10, 12, 13, 14, 6, 7, 8, 11, 15 }
A.AREA_ZONES = { 389, 397, 6, 16, 28, 62, 96, 107, 113, 120, 136, 406, 412, 418, 0,
  147, 279, 381, 152, 154, 157, 160, 191, 194, 198, 205, 214, 230, 235, 238, 324, 333,
  352, 338, 346, 376, 240, 385, 317, 319, 321, 326, 329, 331, 337, 345, 348, 355, 365,
  368, 370, 374, 378, 383, 423, 387, 249, 253, 254, 255, 263 }

-- the AREA records of /a/1/7/8 (see the header)
function A.areaData(raw)
  local Narc = require("src.import.NarcArchive")
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local out = {}
  for sp = 1, 649 do
    local b = arc:get(sp - 1)
    if b and #b >= 249 then
      local rec = { same = b:byte(1) ~= 0 }
      for s = 1, rec.same and 1 or 4 do
        local base = 1 + 62 * (s - 1)
        local block = { unknown = b:byte(base + 1) ~= 0, places = {} }
        for p = 1, 61 do
          local v = b:byte(base + 1 + p)
          if v ~= 0 then block.places[p] = v end
        end
        rec[s] = block
      end
      out[sp] = rec
    end
  end
  return out
end
A.SHARED = "/a/0/8/3"

local char, byte, floor = string.char, string.byte, math.floor

-- ------------------------------------------------------------ rgba helpers --

local function pixels(img)
  local t = {}
  local s = img.rgba
  for i = 1, img.width * img.height do t[i] = s:sub(i * 4 - 3, i * 4) end
  return t
end

local function pack(w, h, t) return { width = w, height = h, rgba = table.concat(t) } end

local CLEAR = char(0, 0, 0, 0)
local function opaque(p) return byte(p, 4) ~= 0 end

-- a w x h window of `img` from (x, y); outside the image is clear
local function crop(img, x, y, w, h)
  local src = pixels(img)
  local out = {}
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local sx, sy = x + i, y + j
      local p = CLEAR
      if sx >= 0 and sy >= 0 and sx < img.width and sy < img.height then p = src[sy * img.width + sx + 1] end
      out[j * w + i + 1] = p
    end
  end
  return pack(w, h, out)
end

-- `top` over `base` (same size), opaque pixels win
local function over(base, top)
  local b, t = pixels(base), pixels(top)
  for i = 1, #b do if opaque(t[i]) then b[i] = t[i] end end
  return pack(base.width, base.height, b)
end

-- the opaque box of an image
local function bbox(img)
  local p = pixels(img)
  local x0, y0, x1, y1 = math.huge, math.huge, -1, -1
  for y = 0, img.height - 1 do
    for x = 0, img.width - 1 do
      if opaque(p[y * img.width + x + 1]) then
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
      end
    end
  end
  if x1 < 0 then return 0, 0, 0, 0 end
  return x0, y0, x1 - x0 + 1, y1 - y0 + 1
end

local function rgba(c) return char(c[1], c[2], c[3], 255) end

-- a palette with sub-palette `from` copied over sub-palette `to`
local function reRow(pal, from, to)
  local out = {}
  for i, c in pairs(pal) do out[i] = c end
  for k = 1, 16 do out[to * 16 + k] = pal[from * 16 + k] end
  return out
end

-- -------------------------------------------------------------------- build --

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local Narc = require("src.import.NarcArchive")
  local raw = x.rom:read(A.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function unpack(b)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local function m(i) return unpack(arc:get(i)) end
  local index = {
    _source = "ROM:/a/1/5/9 (list S63/S69 on g57 p49, S62 on g56 p48, rows S66-68 on g58 p48; "
      .. "info S40 on g25 p9, S37 on g14 p4; OBJ c27/g13/p3, c61/g55/p51) + /a/0/8/3 buttons",
  }
  local function save(key, image, extra)
    if not image then return end
    extra = extra or {}
    extra.bx, extra.by, extra.bw, extra.bh = bbox(image)
    local entry = x:saveImage("bw_dex/" .. key, image, extra)
    if entry then index[key] = entry end
  end
  local function pal(i)
    local p = G.palette(m(i))
    return p
  end
  local function compose(s, c, p)
    local map, sheet = G.tilemap(m(s)), G.tiles(m(c))
    if not (map and sheet and p) then return nil end
    local img = G.compose(map, sheet, p)
    return img
  end

  -- the list
  local p48, p49 = pal(48), pal(49)
  local top = compose(63, 57, p49)
  if top then save("list_top", crop(top, 0, 0, 256, 192)) end
  local header = compose(69, 57, p49)
  if header then save("list_header", crop(header, 0, 0, 256, 48)) end
  local touch = compose(62, 56, p48)
  if touch then save("list_touch", crop(touch, 0, 0, 256, 192)) end
  local sel = p48 and reRow(p48, 2, 1)
  for s, state in pairs({ [66] = "caught", [67] = "seen", [68] = "unseen" }) do
    save("row_" .. state, compose(s, 58, p48))
    save("row_" .. state .. "_sel", compose(s, 58, sel))
  end

  -- the INFO page
  local p9 = pal(9)
  local info = compose(40, 25, p9)
  local grid = compose(31, 25, p9)
  if info and grid then
    -- S31's grid lines fall at x%8 == 7, y%8 == 7; the capture's at x%8 == 3,
    -- y%8 == 0 (and its top rows are pure grid)
    local g = pixels(grid)
    local base = {}
    for y = 0, 191 do
      for xx = 0, 255 do
        local sx, sy = (xx + 4) % 8 + 8, (y + 7) % 8 + 8
        base[y * 256 + xx + 1] = g[sy * grid.width + sx + 1]
      end
    end
    -- the panel's flat grey behind S40, flood-filled from inside the panel
    local s40 = pixels(info)
    local W, H = info.width, info.height
    local grey = rgba(p9[8] or { 144, 144, 144 })
    local filled = {}
    local stack = { { 60, 70 } }
    while #stack > 0 do
      local pt = table.remove(stack)
      local px, py = pt[1], pt[2]
      if px >= 0 and py >= 24 and px < W and py < 24 + 192 then
        local k = py * W + px + 1
        if not filled[k] and not opaque(s40[k]) then
          filled[k] = true
          stack[#stack + 1] = { px + 1, py }
          stack[#stack + 1] = { px - 1, py }
          stack[#stack + 1] = { px, py + 1 }
          stack[#stack + 1] = { px, py - 1 }
        end
      end
    end
    local out = {}
    for y = 0, 191 do
      for xx = 0, 255 do
        local k = (y + 24) * W + xx + 1
        local p = s40[k]
        if not opaque(p) then p = filled[k] and grey or base[y * 256 + xx + 1] end
        out[y * 256 + xx + 1] = p
      end
    end
    save("info_touch", pack(256, 192, out))
  end
  local p4 = pal(4)
  local ih = p4 and compose(37, 14, reRow(p4, 0, 1))
  if ih then save("info_header", crop(ih, 0, 0, 256, 24)) end
  if top then
    local t = crop(top, 0, 8, 256, 192)
    local px_ = pixels(t)
    local fill = char(48, 48, 48, 255)
    for i = 1, #px_ do if not opaque(px_[i]) then px_[i] = fill end end
    save("info_top", pack(256, 192, px_))
  end
  -- the caught hex: g25's first 5 x 3 tiles, palette row 0
  local sheet25 = G.tiles(m(25))
  if sheet25 and p9 then
    local cells = {}
    for ty = 0, 2 do
      for tx = 0, 4 do cells[#cells + 1] = { tile = ty * 32 + tx, flipX = false, flipY = false, palette = 0 } end
    end
    local hex = G.compose({ width = 40, height = 24, cells = cells }, sheet25, p9)
    if hex then save("ball_hex", crop(hex, 0, 0, 36, 18)) end
  end

  -- objects
  local function obj(prefix, c, b, p, only, getter)
    getter = getter or m
    local sheet, bank = G.tiles(getter(c)), Cells.parse(getter(b), G)
    local palette = G.palette(getter(p))
    if not (sheet and bank and palette) then return end
    for i, cell in ipairs(bank.cells) do
      if not only or only[i - 1] then
        local pic = Cells.assemble(cell, sheet, palette, bank, G)
        if pic then
          local ox, oy = Cells.extent(cell)
          save(("%s_%d"):format(prefix, i - 1), pic, { originX = ox, originY = oy })
        end
      end
    end
  end
  obj("page", 13, 27, 3, { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true })
  obj("obj", 55, 61, 51, { [0] = true, [2] = true, [3] = true, [6] = true })
  obj("area", 15, 28, 5)
  index.area = A.areaData(x.rom:read(A.AREA_PATH))
  index.areaZones = A.AREA_ZONES
  index.areaSeqCell = A.AREA_SEQ_CELL
  local shared = Narc.parse(x.rom:read(A.SHARED) or "")
  if shared then
    obj("button", 20, 21, 19, { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true },
        function(i) return unpack(shared:get(i)) end)
  end
  return index
end

return A
