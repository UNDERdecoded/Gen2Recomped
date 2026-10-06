-- PLATINUM'S SUPER CONTEST ART, composed from the cartridge
-- (/contest/graphic/contest_bg.narc and contest_obj.narc, both shipped
-- prebuilt by pokeplatinum, so no member has a name: every index below is
-- the one overlay017 passes to its loaders, with the file and line noted).
--
-- BACKGROUNDS (contest_bg) -- tiles, tilemap, palette, plus the 16-colour
-- rows the overlay copies over that palette:
--
--   acting_stage      tiles 1, map 2, pal 30   BG3, the audience and stage
--   acting_stage_alt  tiles 1, map 0, pal 30   BG3's other map (ov17_022413D8 1729)
--   acting_window     tiles 3, map 4, pal 30   BG1, the message window
--   acting_panel_<s>  tiles 3, map 5, pal 30   BG2, one contestant's 80x48
--                     score panel, re-coloured to slot s (6/7/10/11 for
--                     contestants 0..3, Unk_ov17_022536B4; ov17_022413E4)
--   sub_logo_<type>   tiles 9, maps 8 + 7, pal 31 with pal 38's row <type>
--                     in slot 2 -- the bottom screen between choices
--                     (ov17_0223F7E4: Unk_ov17_02253558 page 0, ov17_0223FBD4)
--   sub_hearts        tiles 11, map 29, pal 40   the bottom screen's backdrop
--   sub_moves_<type>  tiles 11, map 6, pal 40 with the type's button colours
--                     (Unk_ov17_022534B8, ov17_02240424) in slots 4..7
--   sub_moves_off     the same with pal 40's row 8, a move that cannot be used
--   sub_judges        tiles 11, map 10, pal 40   the judge buttons and EXIT
--   visual_stage      tiles 23, map 22, pal 35 + pal 36 in slot 13 (ov17_0223CB1C)
--   visual_curtain    tiles 24, map 21, pal 35 + pal 37 in slot 12
--   audience          tiles 19, map 20, pal 34   the Visual / results bottom screen
--   results_bg        tiles 27, map 25, pal 39 + pal 36 in slot 13 (ov17_02250744)
--   results_bars      tiles 27, map 26, the same palette
--
-- SPRITES (contest_obj) -- tiles, cells, animation, palette member and row:
--
--   judge_<k>         31/32/30 pal 1, 37/38/36 pal 3, 34/35/33 pal 2 -- the
--                     three seats (ov17_02241720), judge 1 the head judge
--   podium_<k>        39/40/41, pal 0 rows 2/4/5 (ov17_022418A4), 32x64
--   voltage_star      26/25/24, pal 0 row 2 (Unk_ov17_022537EC)
--   flying_star       29/28/27, pal 0 row 0 (Unk_ov17_0225371C)
--   head_heart        20/19/18, pal 0 row 0 (ov17_02241D94)
--   next_<n>          23/22/21 sequences 0..3, "NEXT1".."NEXT4" (ov17_022430AC)
--   reaction_<n>      14/13/12 sequences 0..3 (Unk_ov17_022537B8)
--   small_heart_<n>   17/16/15 sequences 0..3, pal 0 row 0 (ov17_02241E58)
--   sub_heart         45/46/47, pal 4 row 0; sub_heart_minus the same, row 1
--   sub_head_mark     42/43/44, pal 4 row 0 (ov17_022412C0)
--
-- Every picture is written by the importer to
-- assets/generated/gen4/contest/<key>.png and indexed in the cache module
-- `gen4_contest_art`.

local Gen4ContestArt = {}

Gen4ContestArt.BG = "/contest/graphic/contest_bg.narc"
Gen4ContestArt.OBJ = "/contest/graphic/contest_obj.narc"
-- Unk_ov17_022534B8, the move buttons' five colour rows (BGR555)
Gen4ContestArt.BUTTON_SIGNATURE = string.char(0xCD, 0x75, 0xFF, 0x7F, 0xFF, 0x67, 0xFF, 0x4B, 0xFF, 0x2F)
-- ov17_02240424: the row each contest type's buttons take
Gen4ContestArt.BUTTON_ROW = { [0] = 3, 4, 1, 2, 0 }
Gen4ContestArt.PANEL_SLOTS = { [0] = 6, 7, 10, 11 }

local floor = math.floor

local function ch(x) return floor(x * 255 / 31 + 0.5) end
local function bgr555(v) return { ch(v % 32), ch(floor(v / 32) % 32), ch(floor(v / 1024) % 32) } end

-- the five rows of button colours, read from overlay 17 by content
function Gen4ContestArt.buttonRows(ov)
  if type(ov) ~= "string" then return nil end
  local at = ov:find(Gen4ContestArt.BUTTON_SIGNATURE, 1, true)
  if not at then return nil end
  local rows = {}
  for r = 0, 4 do
    local row = {}
    for i = 0, 15 do
      local o = at + (r * 16 + i) * 2
      row[i + 1] = bgr555(ov:byte(o) + ov:byte(o + 1) * 256)
    end
    rows[r] = row
  end
  return rows
end

local function copy(list)
  local out = {}
  for i, v in pairs(list) do out[i] = v end
  return out
end

-- 16 colours into slot `slot`
local function put(palette, slot, colours, from)
  from = from or 0
  for i = 1, 16 do
    local c = colours[from * 16 + i]
    if c then palette[slot * 16 + i] = c end
  end
end

-- a crop of an rgba picture
local function crop(pic, x0, y0, w, h)
  local rows = {}
  for y = 0, h - 1 do
    local at = ((y0 + y) * pic.width + x0) * 4
    rows[#rows + 1] = pic.rgba:sub(at + 1, at + w * 4)
  end
  return { width = w, height = h, rgba = table.concat(rows) }
end

-- `top` drawn over `under` (same size)
local function over(under, top)
  if not under then return top end
  if not top then return under end
  local out = {}
  local a, b = under.rgba, top.rgba
  for p = 0, under.width * under.height - 1 do
    local at = p * 4
    if b:byte(at + 4) ~= 0 then out[p + 1] = b:sub(at + 1, at + 4) else out[p + 1] = a:sub(at + 1, at + 4) end
  end
  return { width = under.width, height = under.height, rgba = table.concat(out) }
end
Gen4ContestArt.over = over
Gen4ContestArt.crop = crop

-- THE BACKDROP: where every layer is transparent the DS shows BG palette
-- entry 0, so a screen's bottom layer is given that colour underneath.
local function backdrop(pic, colour)
  if not (pic and colour) then return pic end
  local fill = string.char(colour[1], colour[2], colour[3], 255)
  local out = {}
  for p = 0, pic.width * pic.height - 1 do
    local at = p * 4
    if pic.rgba:byte(at + 4) == 0 then out[p + 1] = fill else out[p + 1] = pic.rgba:sub(at + 1, at + 4) end
  end
  return { width = pic.width, height = pic.height, rgba = table.concat(out) }
end
Gen4ContestArt.backdrop = backdrop

function Gen4ContestArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local function archive(path) local b = rom:read(path) return b and N.parse(b) end
  local bg, obj = archive(Gen4ContestArt.BG), archive(Gen4ContestArt.OBJ)
  if not (bg and obj) then return nil, "contest graphics missing" end
  local function member(a, i)
    local b = a:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local cache = {}
  local function decoded(a, i, fn)
    local key = tostring(a) .. ":" .. i
    if cache[key] == nil then cache[key] = fn(member(a, i)) or false end
    return cache[key] or nil
  end
  local function tiles(i) return decoded(bg, i, G.tiles) end
  local function map(i) return decoded(bg, i, G.tilemap) end
  local function pal(i) return decoded(bg, i, G.palette) end

  local out = {}
  local function picture(t, m, palette)
    return G.compose(map(m), tiles(t), palette)
  end

  -- the main-screen Acting stage
  local p30 = pal(30)
  out.acting_stage = backdrop(picture(1, 2, p30), p30[1])
  out.acting_stage_alt = backdrop(picture(1, 0, p30), p30[1])
  out.acting_window = picture(3, 4, p30)
  local panelMap = map(5)
  if panelMap then
    for id = 0, 3 do
      local slot = Gen4ContestArt.PANEL_SLOTS[id]
      local cells = {}
      for k, c in ipairs(panelMap.cells) do
        cells[k] = { tile = c.tile, flipX = c.flipX, flipY = c.flipY, palette = slot }
      end
      local full = G.compose({ width = panelMap.width, height = panelMap.height, cells = cells }, tiles(3), p30)
      if full then out["acting_panel_" .. slot] = crop(full, 0, 0, 80, 48) end
    end
  end

  -- the Acting bottom screen
  local p31, p38, p40 = pal(31), pal(38), pal(40)
  for t = 0, 4 do
    local palette = copy(p31)
    put(palette, 2, p38, t)
    out["sub_logo_" .. t] = backdrop(over(picture(9, 8, palette), picture(9, 7, palette)), palette[1])
  end
  out.sub_hearts = backdrop(picture(11, 29, p40), p40[1])
  out.sub_judges = picture(11, 10, p40)
  local rows = Gen4ContestArt.buttonRows(rom.overlay and rom:overlay(17))
  if rows then
    for t = 0, 4 do
      local palette = copy(p40)
      local row = rows[Gen4ContestArt.BUTTON_ROW[t]]
      for slot = 4, 7 do put(palette, slot, row) end
      out["sub_moves_" .. t] = picture(11, 6, palette)
    end
  end
  do
    local palette = copy(p40)
    for slot = 4, 7 do put(palette, slot, p40, 8) end
    out.sub_moves_off = picture(11, 6, palette)
  end

  -- the Visual round and the results
  do
    local palette = copy(pal(35))
    put(palette, 13, pal(36))
    out.visual_stage = backdrop(picture(23, 22, palette), palette[1])
    local curtain = copy(pal(35))
    put(curtain, 12, pal(37))
    out.visual_curtain = picture(24, 21, curtain)
  end
  out.audience = backdrop(picture(19, 20, pal(34)), pal(34)[1])

  -- the Dance competition (ov17_0224A0FC / ov17_022492DC): its stage for each
  -- measure layout (tiles 13, map 14 or 15, pal 32 + pal 36 in slot 13), and
  -- the bottom screen's dance pad (tiles 18, BG2 map 28 under BG0 map 17,
  -- pal 33)
  do
    local palette = copy(pal(32))
    put(palette, 13, pal(36))
    out.dance_stage_0 = backdrop(picture(13, 14, palette), palette[1])
    out.dance_stage_1 = backdrop(picture(13, 15, palette), palette[1])
    local p33 = pal(33)
    out.dance_pad = backdrop(over(picture(18, 28, p33), picture(18, 17, p33)), p33[1])
    -- THE PRESS (ov17_02249DA0): a button's 6 x 12 tiles, at column
    -- {JUMP 0, FRONT 18, LEFT 6, RIGHT 12} of the 32-wide character block,
    -- are overwritten from member 16 (18 tiles wide, three frames side by
    -- side) -- column 12, then 6, then 0, about three frames apart
    -- (Unk_ov17_02254630). One whole pad per button and frame.
    local sheet, press = tiles(18), tiles(16)
    if sheet and press then
      local per = sheet.perTile
      local DST = { 0, 0x12, 6, 0xC }
      for move = 1, 4 do
        for f, src in ipairs({ 12, 6, 0 }) do
          local chunks = {}
          for t = 0, sheet.count - 1 do chunks[t + 1] = sheet.pixels:sub(t * per + 1, (t + 1) * per) end
          for row = 0, 11 do
            for col = 0, 5 do
              local s = row * 18 + src + col
              local d = row * 32 + DST[move] + col
              if d < sheet.count then chunks[d + 1] = press.pixels:sub(s * per + 1, (s + 1) * per) end
            end
          end
          local patched = {}
          for k, v in pairs(sheet) do patched[k] = v end
          patched.pixels = table.concat(chunks)
          local pic = over(G.compose(map(28), patched, p33), G.compose(map(17), patched, p33))
          out[("dance_pad_%d_%d"):format(move, f - 1)] = backdrop(pic, p33[1])
        end
      end
    end
  end
  do
    local palette = copy(pal(39))
    put(palette, 13, pal(36))
    out.results_bg = backdrop(picture(27, 25, palette), palette[1])
    out.results_bars = picture(27, 26, palette)
  end

  -- sprites: the first frame of a sequence, with its origin
  local function sprite(key, t, c, a, palMember, row, sequence)
    local sheet = decoded(obj, t, G.tiles)
    local bank = decoded(obj, c, function(b) return Cells.parse(b, G) end)
    local anim = decoded(obj, a, function(b) return Anim.parse(b, G) end)
    local all = decoded(obj, palMember, G.palette)
    if not (sheet and bank and anim and all) then return end
    local colours = {}
    for i = (row or 0) * 16 + 1, #all do colours[#colours + 1] = all[i] end
    local frames = Anim.frames(anim, sequence or 0)
    local cell = frames and frames[1] and bank.cells[frames[1].cell + 1]
    -- SpriteSystem_NewSprite (sprite_system.c) gives every sprite an
    -- EXPLICIT palette, the resource's base + the template's plttIdx, which
    -- replaces the cell's own OAM palette rather than adding to it: the
    -- podium's cell says palette 2, and the three podiums are rows 2, 4, 5.
    if cell then
      local flat = {}
      for k, v in pairs(cell) do flat[k] = v end
      flat.oam = {}
      for i, o in ipairs(cell.oam) do
        local copyO = {}
        for k, v in pairs(o) do copyO[k] = v end
        copyO.palette = 0
        flat.oam[i] = copyO
      end
      cell = flat
    end
    local pic = cell and Cells.assemble(cell, sheet, colours, bank, G)
    if pic then
      pic.originX, pic.originY = Cells.extent(cell)
      out[key] = pic
    end
  end
  sprite("judge_0", 31, 32, 30, 1, 0)
  sprite("judge_1", 37, 38, 36, 3, 0)
  sprite("judge_2", 34, 35, 33, 2, 0)
  local podiumRow = { [0] = 2, 4, 5 }
  for k = 0, 2 do sprite("podium_" .. k, 39, 40, 41, 0, podiumRow[k]) end
  sprite("voltage_star", 26, 25, 24, 0, 2)
  sprite("flying_star", 29, 28, 27, 0, 0)
  sprite("head_heart", 20, 19, 18, 0, 0)
  for n = 0, 3 do
    sprite("next_" .. (n + 1), 23, 22, 21, 0, 0, n)
    sprite("reaction_" .. n, 14, 13, 12, 0, 0, n)
    sprite("small_heart_" .. n, 17, 16, 15, 0, 0, n)
  end
  sprite("sub_heart", 45, 46, 47, 4, 0)
  sprite("sub_heart_minus", 45, 46, 47, 4, 1)
  sprite("sub_head_mark", 42, 43, 44, 4, 0)
  -- the Dance's sprites, palette member 6 (ov17_0224A0FC's templates): the
  -- note markers by move (58 FRONT, 59 LEFT, 60 JUMP, 61 RIGHT; cell 62,
  -- anim 63 -- sequence 0 yours, 1 another's, 2 the lead's ghost), the
  -- judgement bubbles (Excellent / Good / Miss), the beat ball, the bar's
  -- playhead, the player's arrow and the shadow
  local NOTE = { { 2, 58, 2 }, { 3, 59, 2 }, { 1, 60, 7 }, { 4, 61, 6 } }   -- move, char, row
  for _, n in ipairs(NOTE) do
    for seq = 0, 2 do sprite(("dance_note_%d_%d"):format(n[1], seq), n[2], 62, 63, 6, n[3], seq) end
  end
  for j = 0, 2 do sprite("dance_judge_" .. j, 55, 56, 57, 6, 3, j) end
  sprite("dance_ball", 76, 77, 78, 6, 5)
  sprite("dance_playhead", 99, 98, 97, 6, 2)
  sprite("dance_arrow", 64, 65, 66, 6, 1)
  sprite("dance_shadow", 90, 89, 88, 6, 1)
  return out
end

return Gen4ContestArt
