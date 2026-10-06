-- PLATINUM'S BATTLE SPRITES THAT THE GENERIC pl_batt_obj PASS GETS WRONG
-- (src/import/Gen4Battle.lua extracts every family cell-by-cell on the first
-- row of its palette; these three are animations whose palette ROW and
-- SEQUENCE matter, so they are assembled here the way the cartridge shows
-- them).  Everything below is /battle/graphic/pl_batt_obj.narc, by member
-- index, because `interface/stock_anim.NANR` is in the archive twice.
--
--   cursor_<s>_<f>     interface/cursor (250 char, 251 cell, 252 anim) over
--                      interface/cursor.NCLR (80) row 0 -- cursor_renderer.c.
--                      Sequences 0..3 are the four corners (top-left,
--                      top-right, bottom-left, bottom-right:
--                      BattleSystem_DrawCursorSprites sets anim 0..3 on
--                      sprites placed at (x1,y1) (x2,y1) (x1,y2) (x2,y2));
--                      4.. are the split anchors.
--   stock_player_<s>   the bottom screen's party balls, battle_subscreen.c
--                      BattleSubscreen_LoadSprites: char 208 / cell 207 /
--                      anim 209, interface/shared.NCLR (72) ROW 0
--                      (sPlayerPartyBallTemplate.plttIdx 0; a SpriteSystem
--                      sprite, so the template's row replaces the cell's).
--   stock_enemy_<s>    char 205 / cell 204 / anim 206, shared.NCLR ROW 1
--                      (sOpponentPartyBallTemplate.plttIdx 1).
--                      Sequence = GetBallStatusAnimID: 0 no Pokemon, 1
--                      healthy, 2 status condition, 3 fainted.
--   gauge_<s>_<f>      the top screen's party gauge, party_gauge.c: char 340
--                      / cell 341 / anim 342 over interface/top_stock.NCLR
--                      (110) row 0.  Sequences (enum PartyGaugeAnimIndex):
--                      0..2 theirs healthy/statused/fainted, 3..5 ours, 6
--                      empty slot, 7 the arrow THEIRS, 8 the arrow OURS.
--
-- Every image carries originX/originY: the cell's top-left relative to the
-- sprite's position, so a caller places it exactly where the OAM would.
-- `data(rom)` is each sequence's frame durations, written as the cache
-- module `gen4_battle_anims` ({ cursor = { [seq] = { d, d, ... } }, ... }),
-- plus `healthboxInk.name` = the healthbox nickname's ink/shadow colours.
--
-- Written to assets/generated/gen4/battle_art/<key>.png and indexed in the
-- cache module `gen4_battle_art`.

local Gen4BattleArt = {}

Gen4BattleArt.PATH = "/battle/graphic/pl_batt_obj.narc"

Gen4BattleArt.SETS = {
  { prefix = "cursor",       char = 250, cell = 251, anim = 252, pal = 80,  row = 0, allFrames = true },
  { prefix = "stock_player", char = 208, cell = 207, anim = 209, pal = 72,  row = 0 },
  { prefix = "stock_enemy",  char = 205, cell = 204, anim = 206, pal = 72,  row = 1 },
  { prefix = "gauge",        char = 340, cell = 341, anim = 342, pal = 110, row = 0, allFrames = true },
}

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom:read(path)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function row(colours, r)
  local out = {}
  for i = 1, 16 do out[i] = colours[r * 16 + i] or { 0, 0, 0 } end
  return out
end

-- one cell with every OAM entry forced onto palette 0 (the row passed in)
local function assembleCell(cell, sheet, colours, bank)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  if not cell then return nil end
  local flat = {}
  for k, v in pairs(cell) do flat[k] = v end
  flat.oam = {}
  for i, o in ipairs(cell.oam) do
    local c = {}
    for k, v in pairs(o) do c[k] = v end
    c.palette = 0
    flat.oam[i] = c
  end
  local pic = Cells.assemble(flat, sheet, colours, bank, G)
  if pic then pic.originX, pic.originY = Cells.extent(flat) end
  return pic
end

local function walk(rom, visit)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom, Gen4BattleArt.PATH)
  if not member then return nil, "pl_batt_obj missing" end
  for _, set in ipairs(Gen4BattleArt.SETS) do
    local sheet = G.tiles(member(set.char))
    local bank = Cells.parse(member(set.cell), G)
    local anim = Anim.parse(member(set.anim), G)
    local pal = G.palette(member(set.pal))
    if sheet and bank and anim and pal then
      visit(set, sheet, bank, anim, row(pal, set.row))
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- THE BATTLE PARTY LIST (src/battle_sub_menus/battle_party*.c), the bottom
-- screen POKeMON opens in a battle.  /battle/graphic/pl_b_plist_gra.narc:
-- tiles 22, palette 23 (sixteen rows, used as stored -- the moves screen's
-- row-12 swap is not on these two screens).
--
--   bparty_bg / bparty_fg        the party screen's BG3 (member 0) and BG2
--                                (member 1), 256x192
--   bselect_bg / bselect_fg      the select screen's (members 18 and 19)
--   bparty_panel_<a>_<s>[_fnt|_egg]
--                                a party button out of member 20: a = 0 the
--                                panel of the Pokemon IN battle, 1 the
--                                others (ALT, x offset 16 tiles); s = 0
--                                unpressed, 3 disabled (an empty slot).
--                                `_fnt` forces every cell onto palette 2
--                                (RetrieveButtonData's fainted rule), `_egg`
--                                writes column 5 over columns 6..14 of rows
--                                2-3 (an egg has no HP bar).  16x6 tiles.
--   bparty_cancel_<s>            CANCEL, member 20 at (26, 24 + 5s), 5x5
--   bparty_small_<s>             SUMMARY / CHECK MOVES, member 20 (0, 39)
--                                unpressed and (13, 44) disabled, 13x5
--   bparty_shift                 SHIFT, member 21 (0, 0), 30x17
--   bparty_digits                font_special_chars tiles 0..12 (0-9, "/",
--                                "Lv") in the windows' TEXT_COLOR(15, 14, 0)
--                                of row 9 (FontSpecialChars_Init(15, 14, 0))
--   bparty_status_<n>            pl_pst_gra's status icons, sequence n
--                                (SummaryStatus: 0 PKRS .. 5 BRN, 6 FNT)
--   bparty_held_item / _mail     pl_plist_gra icons cells 0 / 1
-- ---------------------------------------------------------------------------
Gen4BattleArt.PARTY_PATH = "/battle/graphic/pl_b_plist_gra.narc"
Gen4BattleArt.PARTY_TILES, Gen4BattleArt.PARTY_PALETTE = 22, 23

local function partyImages(rom, out)
  local G = require("src.import.Gen4Graphics")
  local member = opener(rom, Gen4BattleArt.PARTY_PATH)
  if not member then return end
  local sheet = G.tiles(member(Gen4BattleArt.PARTY_TILES))
  local pal = G.palette(member(Gen4BattleArt.PARTY_PALETTE))
  if not (sheet and pal) then return end
  local function screen(i)
    local map = G.tilemap(member(i))
    if not map then return nil end
    local cols = math.floor((map.width or 256) / 8)
    local cells = {}
    for r = 0, 23 do
      for c = 0, 31 do cells[#cells + 1] = map.cells[r * cols + c + 1] or { tile = 0, palette = 0 } end
    end
    return G.compose({ width = 256, height = 192, cells = cells }, sheet, pal)
  end
  out.bparty_bg, out.bparty_fg = screen(0), screen(1)
  out.bselect_bg, out.bselect_fg = screen(18), screen(19)
  -- a w x h block of a button map, as a picture
  local function block(mapIndex, x0, y0, w, h, edit)
    local map = G.tilemap(member(mapIndex))
    if not map then return nil end
    local cols = math.floor((map.width or 256) / 8)
    local cells = {}
    for r = 0, h - 1 do
      for c = 0, w - 1 do
        local src = map.cells[(y0 + r) * cols + x0 + c + 1] or { tile = 0, palette = 0 }
        cells[#cells + 1] = { tile = src.tile, flipX = src.flipX, flipY = src.flipY, palette = src.palette }
      end
    end
    if edit then edit(cells, w) end
    return G.compose({ width = w * 8, height = h * 8, cells = cells }, sheet, pal)
  end
  local function fainted(cells) for _, c in ipairs(cells) do c.palette = 2 end end
  local function egg(cells, w)
    for r = 2, 3 do
      local keep = cells[r * w + 5 + 1]
      for l = 0, 8 do
        cells[r * w + 6 + l + 1] = { tile = keep.tile, flipX = keep.flipX, flipY = keep.flipY, palette = keep.palette }
      end
    end
  end
  for a = 0, 1 do
    for _, s in ipairs({ 0, 3 }) do
      local base = ("bparty_panel_%d_%d"):format(a, s)
      out[base] = block(20, a * 16, s * 6, 16, 6)
      if s == 0 then
        out[base .. "_fnt"] = block(20, a * 16, 0, 16, 6, fainted)
        out[base .. "_egg"] = block(20, a * 16, 0, 16, 6, egg)
      end
    end
  end
  for s = 0, 3 do out["bparty_cancel_" .. s] = block(20, 26, 24 + 5 * s, 5, 5) end
  out.bparty_small_0 = block(20, 0, 39, 13, 5)
  out.bparty_small_3 = block(20, 13, 44, 13, 5)
  out.bparty_shift = block(21, 0, 0, 30, 17)

  -- the digits, in row 9's 15 / 14 over transparent
  local font = opener(rom, "/graphic/pl_font.narc")
  local special = font and G.tiles(font(require("src.import.Gen4SpecialChars").MEMBER))
  if special then
    local cells = {}
    for t = 0, 12 do cells[t + 1] = { tile = t, palette = 0 } end
    local c15, c14 = pal[9 * 16 + 16], pal[9 * 16 + 15]
    out.bparty_digits = G.compose({ width = 13 * 8, height = 8, cells = cells }, special,
      { { 0, 0, 0 }, c15 or { 255, 255, 255 }, c14 or { 0, 0, 0 } })
  end

  -- the status icons and the held item / mail icons
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local A = require("src.import.Gen4Archives")
  local function named(path)
    local bytes = rom:read(path)
    if not bytes then return nil end
    local narc = require("src.import.NarcArchive").parse(bytes)
    return function(name)
      local i = A.find(path, name)
      local b = i and narc:get(i)
      if b and G.isCompressed(b) then b = G.decompress(b) end
      return b
    end
  end
  local pst = named("/graphic/pl_pst_gra.narc")
  if pst then
    local s = G.tiles(pst("status_icons.NCGR"))
    local bank = Cells.parse(pst("status_icons_cell.NCER"), G)
    local anim = Anim.parse(pst("status_icons_anim.NANR"), G)
    local spal = G.palette(pst("status_icons.NCLR"))
    if s and bank and anim and spal then
      for seq = 0, 6 do
        local frames = Anim.frames(anim, seq)
        local cell = frames and frames[1] and bank.cells[frames[1].cell + 1]
        out["bparty_status_" .. seq] = assembleCell(cell, s, row(spal, 0), bank)
      end
    end
  end
  local plist = named("/graphic/pl_plist_gra.narc")
  if plist then
    local s = G.tiles(plist("icons.NCGR"))
    local bank = Cells.parse(plist("icons_cell.NCER"), G)
    local ipal = G.palette(plist("icons.NCLR"))
    if s and bank and ipal then
      out.bparty_held_item = assembleCell(bank.cells[1], s, row(ipal, 0), bank)
      out.bparty_held_mail = assembleCell(bank.cells[2], s, row(ipal, 0), bank)
    end
  end
end

-- the windows' palette (row 9 of member 23), 0-based index -> { r, g, b }
local function partyInk(rom)
  local G = require("src.import.Gen4Graphics")
  local member = opener(rom, Gen4BattleArt.PARTY_PATH)
  local pal = member and G.palette(member(Gen4BattleArt.PARTY_PALETTE))
  if not pal then return nil end
  local r9 = {}
  for i = 0, 15 do
    local c = pal[9 * 16 + i + 1]
    r9[i] = c and { c[1], c[2], c[3] } or { 0, 0, 0 }
  end
  return r9
end

function Gen4BattleArt.images(rom)
  local out = {}
  local okP, errP = pcall(partyImages, rom, out)
  if not okP then print("gen4 battle art: the battle party list did not extract: " .. tostring(errP)) end
  local ok, err = walk(rom, function(set, sheet, bank, anim, colours)
    for s, seq in ipairs(anim.sequences or {}) do
      local frames = seq.frames or {}
      local last = set.allFrames and #frames or math.min(1, #frames)
      for f = 1, last do
        local cell = bank.cells[frames[f].cell + 1]
        local key = set.allFrames and ("%s_%d_%d"):format(set.prefix, s - 1, f - 1)
                    or ("%s_%d"):format(set.prefix, s - 1)
        local pic = assembleCell(cell, sheet, colours, bank)
        if pic then
          -- a translated frame moves the cell; carry it into the origin
          pic.originX = (pic.originX or 0) + (frames[f].x or 0)
          pic.originY = (pic.originY or 0) + (frames[f].y or 0)
          out[key] = pic
        end
      end
    end
  end)
  if not ok then return nil, err end
  return out
end

-- { [prefix] = { [seq] = { duration, duration, ... } } }
function Gen4BattleArt.data(rom)
  local out = {}
  walk(rom, function(set, _, _, anim)
    local t = {}
    for s, seq in ipairs(anim.sequences or {}) do
      local d = {}
      for f, fr in ipairs(seq.frames or {}) do d[f] = fr.duration or 1 end
      t[s - 1] = d
    end
    out[set.prefix] = t
  end)
  -- THE HEALTHBOX NAME'S INK: HealthBox_DrawBattlerName prints FONT_SYSTEM in
  -- HEALTHBOX_NAME_TEXT_COLOR = TEXT_COLOR(14, 2, 15) over healthbox/
  -- primary.NCLR (member 71) row 0, the boxes' own palette.
  local member = opener(rom, Gen4BattleArt.PATH)
  local G = require("src.import.Gen4Graphics")
  local pal = member and G.palette(member(71))
  if pal then
    local function at(i) local c = pal[i + 1] return c and { c[1], c[2], c[3] } end
    out.healthboxInk = { name = { ink = at(14), shadow = at(2), background = at(15) } }
  end
  -- THE TARGET SELECT'S NAMES: BattleSubscreen_DrawTargetSelectMenu prints
  -- them on sub OBJ palette offset 6 of interface/shared.NCLR (member 72),
  -- TEXT_COLOR(1, 2, 3) on the odd slots and (4, 5, 6) on the even ones;
  -- the whole row is kept, 0-based index -> { r, g, b }.
  local shared = member and G.palette(member(72))
  if shared then
    local r6 = {}
    for i = 0, 15 do
      local c = shared[6 * 16 + i + 1]
      r6[i] = c and { c[1], c[2], c[3] } or { 0, 0, 0 }
    end
    out.subscreenInk = { target = r6 }
  end
  local okP, r9 = pcall(partyInk, rom)
  if okP and r9 then out.partyInk = r9 end
  return out
end

return Gen4BattleArt
