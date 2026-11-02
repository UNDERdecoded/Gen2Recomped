-- PLATINUM'S DRESS-UP ART (pokeplatinum overlay022, /graphic/imageclip.narc):
-- the hundred contest accessories and the dressing room's backdrop.
--
--   members 1..100   accessory k's picture is member k + 1 (ov22_0225B5A8):
--                    an NCGR in BITMAP format (characterFmt 1) -- rows of
--                    4bpp pixels, low nibble first, not 8x8 tiles -- of
--                    16/32/64 a side
--   member 0         the accessories' palette, sixteen rows
--   member 235       a byte per accessory: which row of member 0 it uses
--                    (its software sprite's paletteSlot)
--   224 / 225 / 226  the dressing room's BG: tiles, palette, tilemap
--                    (ov22_0225A6E0)
--
-- Colour 0 is clear. The theme each accessory is worth something to, and how
-- much, is contest_data's (Gen4ContestData, `themes`).
--
-- THE PHOTO STUDIO'S ART (pt_photo round, rev platinum-dressup-photo-v1 /
-- hgss-dressup-photo-v1). HGSS keeps the very same archive as /a/0/2/6
-- (NARC_a_0_2_6, loaded by overlay 41 with the same member numbers), so the
-- path falls back to it. READ from ov22 (pokeplatinum src/overlay022):
--   121 / 133 / 122  the dressing room in photo mode (ov22_02256948, 0)
--   123 / 133 / 124  the same after DONE, the stage slid to (72, 56) (1)
--   129 / 133 / 130  the case's Accessories page (ov22_02258354, 0)
--   131 / 133 / 132  the case's Backdrops page (1)
--   134 + 4k / 135 + 4k / 136 + 4k   backdrop k (0..17), a 112 x 128
--                    picture behind the stage (ov22_02257C88)
--   125 / 126 / 128  the photo viewer's frame, dress-up photos (palette
--                    row 1 of 126 = BG slot 4, ov22_0225B85C); 127 with row
--                    0 the contest photos' frame
-- Each is composed whole (Gen4Graphics.compose); the screens are cropped to
-- 256 x 192 and keep palette entry 0 where nothing is drawn.
-- And the sprites (rev *-dressup-photo-v2), each the cell of an animation
-- frame drawn with its OAM palette rows:
--   photo_btn_<b>_<f>  the five touch buttons (ov22_0225A218): button b's
--                    NCGR 107 + 3b, NCER 106 + 3b, NANR 105 + 3b, palette 104;
--                    frame f 0 up, 1 held, 2 chosen (ov22_0225A2D0)
--   photo_slot_<s>     the sub screen's Accessory hearts (ov22_0225A914):
--                    103 / 102 / 101 with the BG palette 225; sequence 0
--                    filled, 1 empty
--   photo_deco_<s>     the viewer's name plate (ov22_0225B964): 233 / 232 /
--                    231 with palette 234; sequence 5 a dress-up photo, 0..4
--                    a contest photo's type
--   photo_bdicon_<k>   backdrop k's 32 x 32 case icon, the bitmap 206 + k in
--                    its backdrop's palette 135 + 4k (ov22_02255B50)
--   photo_sub          the other screen's BG 224 / 225 / 226 (ov22_0225A6E0)

local Gen4DressUp = {}

Gen4DressUp.PATH = "/graphic/imageclip.narc"
Gen4DressUp.HGSS_PATH = "/a/0/2/6"
Gen4DressUp.BACKDROPS = 18
Gen4DressUp.ACCESSORIES = 100
Gen4DressUp.PALETTE = 0
Gen4DressUp.SLOTS = 235
Gen4DressUp.BG_TILES, Gen4DressUp.BG_PALETTE, Gen4DressUp.BG_MAP = 224, 225, 226

local function u16(s, o) return s:byte(o) + s:byte(o + 1) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

-- An NCGR's pixels as indices: { width, height, px = { [y*w+x+1] = index } }.
function Gen4DressUp.bitmap(data)
  if type(data) ~= "string" or data:sub(1, 4) ~= "RGCN" then return nil end
  local b = 17                                    -- the CHAR block, 1-based
  local h, w = u16(data, b + 8) * 8, u16(data, b + 10) * 8
  local depth, fmt = u32(data, b + 12), u32(data, b + 20)
  local size, offset = u32(data, b + 24), u32(data, b + 28)
  if depth ~= 3 then return nil end              -- 4bpp only
  local at = b + 8 + offset
  local px = {}
  if fmt == 1 then
    for i = 0, w * h - 1 do
      local byte = data:byte(at + math.floor(i / 2)) or 0
      px[i + 1] = (i % 2 == 0) and byte % 16 or math.floor(byte / 16)
    end
  else
    -- tiled: 8x8 tiles row-major across the width
    local tw = w / 8
    for t = 0, (w / 8) * (h / 8) - 1 do
      local tx, ty = (t % tw) * 8, math.floor(t / tw) * 8
      for i = 0, 63 do
        local byte = data:byte(at + t * 32 + math.floor(i / 2)) or 0
        local x, y = tx + i % 8, ty + math.floor(i / 8)
        px[y * w + x + 1] = (i % 2 == 0) and byte % 16 or math.floor(byte / 16)
      end
    end
  end
  return { width = w, height = h, px = px, bytes = size }
end

local function rgba(bmp, colours)
  local out = {}
  for i = 1, bmp.width * bmp.height do
    local idx = bmp.px[i]
    local c = idx ~= 0 and colours[idx + 1]
    out[i] = c and string.char(c[1], c[2], c[3], 255) or "\0\0\0\0"
  end
  return { width = bmp.width, height = bmp.height, rgba = table.concat(out) }
end

function Gen4DressUp.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local bytes = rom and rom:read(Gen4DressUp.PATH)
  if not bytes and rom then bytes = rom:read(Gen4DressUp.HGSS_PATH) end
  if not bytes then return nil, "no imageclip.narc" end
  local a = N.parse(bytes)
  local function member(i)
    local b = a:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local palette = G.palette(member(Gen4DressUp.PALETTE))
  local slots = member(Gen4DressUp.SLOTS)
  if not (palette and slots and #slots >= Gen4DressUp.ACCESSORIES) then
    return nil, "imageclip palette or slot table missing"
  end
  local images, record = {}, { accessories = {} }
  for id = 0, Gen4DressUp.ACCESSORIES - 1 do
    local bmp = Gen4DressUp.bitmap(member(id + 1))
    if bmp then
      local slot = slots:byte(id + 1)
      local row = {}
      for i = 1, 16 do row[i] = palette[slot * 16 + i] end
      images["acc_" .. id] = rgba(bmp, row)
      record.accessories[id] = { width = bmp.width, height = bmp.height, slot = slot, key = "acc_" .. id }
    end
  end
  local tiles, map, bgPal = G.tiles(member(Gen4DressUp.BG_TILES)), G.tilemap(member(Gen4DressUp.BG_MAP)),
                            G.palette(member(Gen4DressUp.BG_PALETTE))
  local bg = tiles and map and bgPal and G.compose(map, tiles, bgPal)
  if bg then
    images.room = require("src.import.Gen4ContestArt").backdrop(bg, bgPal[1])
    record.room = "room"
  end
  -- the photo studio's screens and the backdrops (see the header)
  local CA = require("src.import.Gen4ContestArt")
  local function compose(t, p, m)
    local tl, mp, pl = G.tiles(member(t)), G.tilemap(member(m)), G.palette(member(p))
    local pic = tl and mp and pl and G.compose(mp, tl, pl)
    return pic, pl
  end
  local function screen(key, t, p, m, fill)
    local pic, pl = compose(t, p, m)
    if not pic then return end
    if pic.height > 192 then pic = CA.crop(pic, 0, 0, pic.width, 192) end
    if fill then pic = CA.backdrop(pic, pl[1]) end
    images[key] = pic
    record.photo = record.photo or {}
    record.photo[key] = key
  end
  screen("photo_room", 121, 133, 122)
  screen("photo_confirm", 123, 133, 124)
  screen("photo_case_acc", 129, 133, 130)
  screen("photo_case_bd", 131, 133, 132)
  screen("photo_viewer", 125, 126, 128)
  screen("photo_viewer_contest", 125, 126, 127)
  do
    local _, pl = compose(121, 133, 122)
    if pl and pl[1] then record.photoFill = { pl[1][1], pl[1][2], pl[1][3] } end
  end
  -- the sprites (see the header)
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  record.sprites = {}
  local function sprite(key, t, c, an, p, seq, frame)
    local sheet, pal = G.tiles(member(t)), G.palette(member(p))
    local okB, bank = pcall(Cells.parse, member(c), G)
    local okA, anim = pcall(Anim.parse, member(an), G)
    if not (sheet and pal and okB and bank and okA and anim) then return end
    local frames = Anim.frames(anim, seq or 0)
    local fr = frames and frames[(frame or 0) + 1]
    local cell = fr and bank.cells[fr.cell + 1]
    local pic = cell and Cells.assemble(cell, sheet, pal, bank, G)
    if not pic then return end
    local ox, oy = Cells.extent(cell)
    images[key] = pic
    record.sprites[key] = { key = key, originX = ox, originY = oy, width = pic.width, height = pic.height }
  end
  for b = 0, 4 do
    for f = 0, 2 do sprite(("photo_btn_%d_%d"):format(b, f), 107 + 3 * b, 106 + 3 * b, 105 + 3 * b, 104, 0, f) end
  end
  sprite("photo_slot_0", 103, 102, 101, 225, 0, 0)
  sprite("photo_slot_1", 103, 102, 101, 225, 1, 0)
  for q = 0, 5 do sprite("photo_deco_" .. q, 233, 232, 231, 234, q, 0) end
  for k = 0, Gen4DressUp.BACKDROPS - 1 do
    local bmp = Gen4DressUp.bitmap(member(206 + k))
    local pal = G.palette(member(135 + 4 * k))
    if bmp and pal then
      local row = {}
      for i = 1, 16 do row[i] = pal[i] end
      local key = "photo_bdicon_" .. k
      images[key] = rgba(bmp, row)
      record.sprites[key] = { key = key, originX = 0, originY = 0, width = bmp.width, height = bmp.height }
    end
  end
  screen("photo_sub", 224, 225, 226, true)
  record.backdrops = {}
  for k = 0, Gen4DressUp.BACKDROPS - 1 do
    local pic = compose(134 + 4 * k, 135 + 4 * k, 136 + 4 * k)
    if pic then
      images["backdrop_" .. k] = pic
      record.backdrops[k] = { key = "backdrop_" .. k, width = pic.width, height = pic.height }
    end
  end
  return images, record
end

return Gen4DressUp
