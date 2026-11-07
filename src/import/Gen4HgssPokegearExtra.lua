-- HEARTGOLD / SOULSILVER POKeGEAR: what the app controllers need beyond the
-- page backgrounds Gen4HgssPokegearArt already writes -- the app buttons'
-- three states, the OBJ sprites, the whole world map, the landmark pictures,
-- the skin-picker frame, the atlas rows the apps copy from, and the map's
-- location table. Merged into `gen4_hgss_pokegear_art` by that module.
-- Drawn by src/ui/HgssPokegear.lua and its apps (HgssGear*.lua).
--
-- SOURCES (pokeheartgold src/application/pokegear):
--   buttons_<skin>     pgear_gra NSCR 54 + skin, all 12 rows over char 48 +
--                      skin: rows 0-3 the bar, 4-7 every button pressed, 8-11
--                      a blank used to mask a missing card
--                      (PokegearApp_DrawAppButtons / _UpdateAppSwitchButtonBGState)
--   obj_gear_<s>_<f>_<skin>  the shell's OBJ: char 6 + skin, palette 0 + skin,
--                      cells 12, anims 13 (PokegearUIManager_LoadInitialSkinGfx);
--                      seq 0 clock digit, 1 colon, 2 weekday, 3 signal, 4-7
--                      the cursor's corners
--   obj_<app>_<s>_<f>  each app's OBJ set from its resdat lists: phone
--                      (pgphone 0/1/2/3), radio (pgradio 0/1/2/3), conf
--                      (pgconf 0/1/2/3), map A/B/C (pgmap 0 + 4/5/6, 1/2/3,
--                      7/8/9: resdat 32-35 entries 0, 1, 2)
--   map_full_<skin>    pgmap NSCR 11 (512 x 512, a linear 64-column map) over
--                      the 8bpp char 10 (ov101_021EAF40 copies 47 x 20 of it)
--   map_ui_<skin>      pgmap NSCR 32 + skin whole (320 rows: the Y / X
--                      buttons' states below the frame), char 26 + skin
--   map_marks_<skin>   pgmap NSCR 38 + skin whole (the markings panel; the
--                      trash can's two states at (14 / 22, 16) 8 x 5, BACK
--                      pressed at (7, 16) 6 x 5), map_marks_bg_<skin> NSCR
--                      44 + skin, both over char 26 + skin
--   map_info_<skin>    pgmap NSCR 56 + skin (top-screen panel + its copy
--                      blocks), char 50 + skin, sub palette 14 + skin
--   map_landmarks      pgmap NSCR 13 over char 12 (SUB_3, 7 x 7 pictures in
--                      a 4-wide grid: tilemapUnk174BlockID - 1)
--   phone_full_<skin>  pgphone NSCR 34 + skin whole (tooltip rows 24-27)
--   radio_full_<skin>  pgradio NSCR 22 + skin whole (channel-button states at
--                      row 24, cols 0 / 4), radio_back_<skin> NSCR 28 + skin
--   config_sel_<skin>  pgconf NSCR 22 + skin (136 x 64: the 9 x 7 current-skin
--                      frame at 0,0 and the 6 x 5 locked face at 6,0)
--   ink                palette rows the apps print in (phone list: MAIN row 2;
--                      radio / map: SUB row 1), per skin
--   locations          sLocationSpecs (overlay 101, 100 x 16 bytes), found by
--                      its first two rows (Sinjoh Ruins 521 at 19,2 then the
--                      S.S. Aqua 307 at 24,16)

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local X = {}

local function archive(rom, path)
  local raw = rom:read(path)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  return function(i)
    local b = arc:get(i)
    return b and (G.isCompressed(b) and G.decompress(b) or b)
  end
end

-- the page palette with the shell's casing over its top slots, as
-- Gen4HgssPokegearArt does (main casing 14-15, sub casing 12-15)
local function paletteWith(core, page, member, skin, sub)
  local pal = G.palette(page(member + skin))
  local casing = G.palette(core((sub and 24 or 30) + skin))
  if not (pal and casing) then return pal end
  local offset = sub and 192 or 224
  for i = offset + 1, 256 do pal[i] = casing[i] or pal[i] end
  return pal
end

local function composeWhole(m, map, char, palette, bpp, linearCols)
  local sheet = G.tiles(m(char))
  local tilemap = G.tilemap(m(map))
  if not (sheet and tilemap and palette) then return nil end
  if bpp then sheet.bpp = bpp; sheet.perTile = bpp == 8 and 64 or 32 end
  if linearCols then
    -- a linear source (64 columns, not 32 x 32 hardware blocks), composed a
    -- 32-column strip at a time (a wider tilemap would be read as blocks)
    local rows = math.floor(#tilemap.cells / linearCols)
    local strips = {}
    for s = 0, linearCols / 32 - 1 do
      local cells = {}
      for y = 0, rows - 1 do
        for x = 0, 31 do
          cells[y * 32 + x + 1] = tilemap.cells[y * linearCols + s * 32 + x + 1] or { tile = 0, palette = 0 }
        end
      end
      strips[#strips + 1] = G.compose({ width = 256, height = rows * 8, cells = cells }, sheet, palette)
      if not strips[#strips] then return nil end
    end
    local lines = {}
    for y = 0, rows * 8 - 1 do
      for _, strip in ipairs(strips) do lines[#lines + 1] = strip.rgba:sub(y * 1024 + 1, y * 1024 + 1024) end
    end
    return { width = #strips * 256, height = rows * 8, rgba = table.concat(lines) }
  end
  return G.compose(tilemap, sheet, palette)
end

-- every frame of every sequence of one OBJ set
local function objSet(out, meta, key, m, palM, charM, cellM, animM)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  local pal, sheet = G.palette(m(palM)), G.tiles(m(charM))
  local bank, anim = Cells.parse(m(cellM), G), CA.parse(m(animM), G)
  if not (pal and sheet and bank and anim) then return end
  local seqs = {}
  for q = 0, #anim.sequences - 1 do
    local frames = CA.frames(anim, q) or {}
    local list = {}
    for f, fr in ipairs(frames) do
      local cell = bank.cells[(fr.cell or 0) + 1]
      local pic = cell and Cells.assemble(cell, sheet, pal, bank, G)
      if pic then
        pic.originX, pic.originY = Cells.extent(cell)
        out[("obj_%s_%d_%d"):format(key, q, f - 1)] = pic
      end
      list[f] = fr.duration or 1
    end
    seqs[q] = list
  end
  meta.objSeq = meta.objSeq or {}
  meta.objSeq[key] = seqs
end

local function rowColours(pal, row)
  local out = {}
  for k = 1, 16 do
    local c = pal and pal[row * 16 + k]
    out[k - 1] = c and { c[1], c[2], c[3] } or { 0, 0, 0 }
  end
  return out
end

-- sLocationSpecs: u16 mapId, u8 x, u8 y, u16 w:4 h:4 ox:4 oy:4, u8 flavour,
-- u8 block, 4 unused, 4 bytes of tilemap copy
function X.locations(rom)
  local ov = rom.overlay and rom:overlay(101)
  if not ov then return nil end
  local first, second = string.char(0x09, 0x02, 19, 2), string.char(0x33, 0x01, 24, 16)
  local at = ov:find(first, 1, true)
  local found
  while at do
    if ov:sub(at + 16, at + 19) == second then
      if found then return nil end -- not unique
      found = at
    end
    at = ov:find(first, at + 1, true)
  end
  if not found then return nil end
  local out = {}
  for i = 0, 99 do
    local o = found + i * 16
    local b = { ov:byte(o, o + 15) }
    if #b < 16 then break end
    local bits = b[5] + b[6] * 256
    out[#out + 1] = {
      mapId = b[1] + b[2] * 256, x = b[3], y = b[4],
      width = bits % 16, height = math.floor(bits / 16) % 16,
      objX = math.floor(bits / 256) % 16, objY = math.floor(bits / 4096) % 16,
      flavour = b[7], block = b[8],
    }
  end
  return out
end

-- images(rom) -> { key -> image }, meta
function X.images(rom)
  local core = archive(rom, "/a/1/4/3")
  local map = archive(rom, "/a/1/4/4")
  local config = archive(rom, "/a/1/4/5")
  local phone = archive(rom, "/a/1/4/6")
  local radio = archive(rom, "/a/1/4/7")
  local out, meta = {}, { ink = {} }
  if not (core and map and config and phone and radio) then return out, meta end
  for skin = 0, 5 do
    local top = paletteWith(core, phone, 10, skin, false)
    out["buttons_" .. skin] = composeWhole(core, 54 + skin, 48 + skin, top)
    local key = "gear"
    local pal = G.palette(core(0 + skin))
    if pal then
      -- the same set per skin: char 6 + skin over palette 0 + skin
      local tmp, m2 = {}, {}
      objSet(tmp, m2, key, core, 0 + skin, 6 + skin, 12, 13)
      for k, v in pairs(tmp) do out[k .. "_" .. skin] = v end
      meta.objSeq = meta.objSeq or {}
      meta.objSeq.gear = (m2.objSeq or {}).gear
    end
    local mapTop = paletteWith(core, map, 20, skin, false)
    out["map_full_" .. skin] = composeWhole(map, 11, 10, mapTop, 8, 64)
    out["map_ui_" .. skin] = composeWhole(map, 32 + skin, 26 + skin, mapTop)
    -- the markings mode's panel (MAIN_2: NSCR 38 + skin, rows 0-13 plus the
    -- trash can / back states it copies from rows 16-20) and its backdrop
    -- (MAIN_3: NSCR 44 + skin), both over char 26 + skin in 16 colours
    -- (PokegearMap_SetBgParam_MarkingsMode; hgss-gear-markings-v1)
    out["map_marks_" .. skin] = composeWhole(map, 38 + skin, 26 + skin, mapTop)
    out["map_marks_bg_" .. skin] = composeWhole(map, 44 + skin, 26 + skin, mapTop)
    local mapSub = paletteWith(core, map, 14, skin, true)
    out["map_info_" .. skin] = composeWhole(map, 56 + skin, 50 + skin, mapSub)
    if skin == 0 then out.map_landmarks = composeWhole(map, 13, 12, mapSub) end
    out["phone_full_" .. skin] = composeWhole(phone, 34 + skin, 28 + skin, top)
    local radioTop = paletteWith(core, radio, 10, skin, false)
    out["radio_full_" .. skin] = composeWhole(radio, 22 + skin, 16 + skin, radioTop)
    out["radio_back_" .. skin] = composeWhole(radio, 28 + skin, 16 + skin, radioTop)
    out["config_sel_" .. skin] = composeWhole(config, 22 + skin, 10 + skin, paletteWith(core, config, 4, skin, false))
    meta.ink[skin] = {
      phoneList = rowColours(top, 2),
      phoneTip = rowColours(top, 10),
      phoneSub = rowColours(paletteWith(core, phone, 4, skin, true), 1),
      radioSub = rowColours(paletteWith(core, radio, 4, skin, true), 0),
      radioMain = rowColours(radioTop, 0),
      mapSub = rowColours(mapSub, 1),
      mapMain = rowColours(mapTop, 10),
    }
  end
  objSet(out, meta, "phone", phone, 0, 1, 2, 3)
  objSet(out, meta, "radio", radio, 0, 1, 2, 3)
  objSet(out, meta, "conf", config, 0, 1, 2, 3)
  objSet(out, meta, "mapA", map, 0, 4, 5, 6)
  objSet(out, meta, "mapB", map, 0, 1, 2, 3)
  objSet(out, meta, "mapC", map, 0, 7, 8, 9)
  meta.locations = X.locations(rom)
  -- THE TOUCH-SCREEN LIST MENU's frame tiles (touchscreen_list_menu.c:
  -- sbox_gra, NARC 165 = /a/1/6/5): 27 tiles, three a row -- top, sides,
  -- between, bottom, then the same four with the selected button's rim (12 on)
  -- and the "between, the button below selected" row (24) -- and its palette
  -- (text 1 / 2 on 3; selected 4 / 5 on 6)
  local sbox = archive(rom, "/a/1/6/5")
  if sbox then
    local pal, sheet = G.palette(sbox(0)), G.tiles(sbox(1))
    if pal and sheet then
      local cells = {}
      for t = 0, 26 do cells[#cells + 1] = { tile = t, palette = 0 } end
      out.sbox = G.compose({ width = 24, height = 72, cells = cells }, sheet, pal)
      meta.sboxInk = rowColours(pal, 0)
    end
  end
  -- THE FLY MAP / TOWN MAP (fly_map.c FlyMap_LoadBGGraphics): its own frame
  -- (MAIN_1 NSCR 67 over char 66, palette 63 -- rows 24-27 the CLOSE button
  -- pressed), the top screen's back (SUB_0 NSCR 65 / char 64) and panel (NSCR
  -- 69 / char 68, palette 62), the map (NSCR 11 / char 10) and the landmark
  -- pictures (NSCR 13 / char 12) on those palettes; the ink of the bottom
  -- windows (MAIN row 10) and the top ones (SUB row 1)
  do
    local p62, p63 = G.palette(map(62), true), G.palette(map(63), true)
    if p62 and p63 then
      out.fly_frame = composeWhole(map, 67, 66, p63)
      out.fly_top = composeWhole(map, 65, 64, p62)
      out.fly_info = composeWhole(map, 69, 68, p62)
      out.fly_map = composeWhole(map, 11, 10, p63, 8, 64)
      out.fly_landmarks = composeWhole(map, 13, 12, p62)
      meta.flyInk = { sub = rowColours(p62, 1), main = rowColours(p63, 10) }
    end
  end
  -- sGenericPhoneCallHeaders (phone_generic_headers.c, overlay 101): 16 per
  -- contact -- 8 for a call the player makes, 8 for one they receive -- of
  -- { u8 type, u8 chance, u16 scriptType, u16 scriptID }. Found by Joey's
  -- outgoing rows (contact 10: FIGHTPOSTROCKETSNOTBUGCONTEST 034,
  -- POSTROCKETWEEKTIME 033, RAND1 type 1 035), the table starting ten
  -- contacts earlier on Mom's empty TERM row (type 0 NIL, chance 100)
  local ov = rom.overlay and rom:overlay(101)
  if ov then
    local joey = string.char(7, 100, 0, 0, 34, 0, 3, 100, 0, 0, 33, 0, 1, 100, 1, 0, 35, 0)
    local hit = ov:find(joey, 1, true)
    local at = hit and hit - 10 * 16 * 6
    if hit and not ov:find(joey, hit + 1, true) and at > 0
        and ov:sub(at, at + 11) == string.char(0, 100, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0) then
      meta.genericHeaders = {}
      for c = 0, 74 do
        local rows = {}
        for k = 0, 15 do
          local o = at + (c * 16 + k) * 6
          local b = { ov:byte(o, o + 5) }
          rows[k] = { type = b[1], chance = b[2], scriptType = b[3] + b[4] * 256, script = b[5] + b[6] * 256 }
        end
        meta.genericHeaders[c] = rows
      end
    end
  end
  -- the phone list's SORT keys: PhoneBookEntry.sortParam[4] (gear_phone.h,
  -- +0x10 of each 20-byte row of /tel/pmtel_book.dat after its u32 count);
  -- PokegearPhone_SortList orders by sortParam[0 title / 1 alphabet / 2
  -- location]
  local book = rom.read and rom:read("/tel/pmtel_book.dat")
  if book and #book >= 4 then
    local n = book:byte(1) + book:byte(2) * 256
    meta.sortParams = {}
    for i = 0, n - 1 do
      local o = 4 + i * 20
      if o + 20 > #book then break end
      meta.sortParams[i] = { book:byte(o + 17, o + 20) }
    end
  end
  -- the contacts' message banks (phonebook_dat.c sPhoneMessageGmm, found the
  -- way Gen4HgssPokegearArt.build finds it), names left to the text cache:
  -- A.build replaces this with its own named copy
  local arm9 = rom.arm9 and rom:arm9()
  local anchor = string.char(152, 2, 204, 2, 154, 2, 150, 2, 151, 2, 131, 2)
  local at = arm9 and arm9:find(anchor, 1, true)
  if at and not arm9:find(anchor, at + 1, true) then
    meta.contacts = {}
    for id = 0, 74 do
      local lo, hi = arm9:byte(at + id * 2, at + id * 2 + 1)
      meta.contacts[id] = { bank = lo + hi * 256 }
    end
  end
  return out, meta
end

return X
