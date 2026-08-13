-- Pokémon status screen.
--
-- Gen1 (engine/pokemon/status_screen.asm) is two pages: page 1 = pic, No.,
-- HP bar, STATUS/, the ATTACK/DEFENSE/SPEED/SPECIAL box and TYPE1/TYPE2/
-- IDNo/OT; page 2 = EXP and the moves with PP.  A flips pages, B (or A on
-- page 2) closes.
--
-- Gen2 (engine/pokemon/stats_screen.asm) is THREE pages -- PKMN INFO,
-- SKILLS, MOVES -- kept behind one persistent header (pic, name, level,
-- status) with LEFT/RIGHT paging and a colour accent per page, plus a
-- fourth, separate layout for an EGG (EggStatsScreen, 20:$50ED), which
-- shows no stats at all: just the egg, "?????" where the OT and ID would
-- go, and one of four lines about how close it is to hatching.

local Font = require("src.render.Font")
-- status_screen.asm PrintMonType prints the type's DISPLAY name from the
-- TypeNames table, not the constant: species types are stored as pokered
-- constants (RomExtractor:typesById) and PSYCHIC's is "PSYCHIC_TYPE" (so it
-- won't collide with the PSYCHIC move), which would overflow the TYPE field.
-- TypeChart.displayName maps it back to "PSYCHIC", like HallOfFame and the
-- battle move-type box already do (#214).
local TypeChart = require("src.battle.TypeChart")
local Strings = require("src.core.Strings")
local Stats = require("src.pokemon.Stats")

local SummaryMenu = {}
SummaryMenu.__index = SummaryMenu
SummaryMenu.isOpaque = true

-- StatsScreen_LoadPageIndicators tints one of three 2x2 squares per page;
-- the colours are gfx/stats/pages.pal, copied to BG palettes 3-5 by
-- _CGB_StatsScreenHPPals.  The pages themselves are white on hardware, and
-- they carry no title text -- the squares are the only page indicator.
-- Page order is PINK_PAGE < GREEN_PAGE < BLUE_PAGE.
SummaryMenu.GEN2_PAGE_PALS = {
  { { 255, 255, 255 }, { 255, 156, 255 }, { 255, 123, 255 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 173, 255, 115 }, { 140, 255, 0 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 140, 255, 255 }, { 140, 255, 255 }, { 0, 0, 0 } },
}

-- the shade the remap shader turns into palette color 2
local GEN2_SHADE2 = 0.33

local function isGen2() return require("src.core.GameVersion").isGen2() end

local function eggCycles(mon)
  return math.ceil((mon.eggSteps or 0) / 256)
end

-- EggStatsScreen's `cp 6 / cp $0b / cp $29` ladder over the hatch counter.
local EGG_FALLBACK = {
  soon = "It's making sounds\ninside. It's going\nto hatch soon!",
  close = "It moves around\ninside sometimes.\nIt must be close\nto hatching.",
  more = "Wonder what's\ninside? It needs\nmore time, though.",
  lots = "This EGG needs a\nlot more time to\nhatch.",
}

local function eggHatchText(data, mon)
  local egg = data.field and data.field.egg or {}
  local limits = egg.thresholds or { soon = 6, close = 11, more = 41 }
  local text = egg.hatchText or {}
  local cycles = eggCycles(mon)
  local key = "lots"
  if cycles < (limits.soon or 6) then key = "soon"
  elseif cycles < (limits.close or 11) then key = "close"
  elseif cycles < (limits.more or 41) then key = "more" end
  return text[key] or EGG_FALLBACK[key]
end

-- SGB: SetPal_StatusScreen -- HP-bar palette overall, mon pic zone in
-- the species palette
function SummaryMenu:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local mon = self.mon
  if not mon then return P.wholeNamed(game.data, "MEWMON") end
  if self.isEgg then
    local egg = game.data.field and game.data.field.egg
    local pal = egg and egg.palette
      or { { 255, 255, 255 }, { 247, 214, 90 }, { 189, 132, 0 }, { 0, 0, 0 } }
    -- the icon/pic sheet is already in the egg's own colours
    return { P.whole(pal), P.zone(false, 1, 4, 8, 11) }
  end
  local bar = P.pal(game.data, P.barPalName(mon.hp, mon.stats.hp))
  if not bar then return nil end
  if isGen2() then
    -- _CGB_StatsScreenHPPals: WipeAttrmap leaves the HP palette over the
    -- whole screen, the mon's palette takes the whole upper half (8 rows x
    -- 20), the exp bar row 16 cols 10-19 and the three 2x2 page squares at
    -- (13,5)/(15,5)/(17,5) carry the page palettes.  There is no per-page
    -- wash on hardware -- the pages really are white.
    local pages = SummaryMenu.GEN2_PAGE_PALS
    local out = {
      P.whole(bar),
      -- _CGB_StatsScreen reads the mon's DVs through
      -- GetMonNormalOrShinyPalettePointer, so a shiny wears its alternate
      -- pair here just as it does in battle (and the star sits by the level)
      P.zone(P.monPal(game.data, mon.species, nil,
                      require("src.pokemon.Stats").isShiny(mon.dvs)),
             0, 0, 19, 7),
      P.zone(pages[1], 13, 5, 14, 6),
      P.zone(pages[2], 15, 5, 16, 6),
      P.zone(pages[3], 17, 5, 18, 6),
    }
    local exp = P.pal(game.data, "EXPBAR")
    if exp then out[#out + 1] = P.zone(exp, 10, 16, 19, 16) end
    return out
  end
  local out = { P.whole(bar), P.zone(P.monPal(game.data, mon.species), 1, 0, 7, 6) }
  -- Gen2's exp bar rides its own palette (ExpBarPalette), so the row it
  -- lands on needs its own zone or the HP bar's green swallows it.
  local exp = self.page == 2 and P.pal(game.data, "EXPBAR")
  if exp then
    out[#out + 1] = P.zone(exp, 11, 7, 18, 7)
  end
  return out
end

function SummaryMenu.new(game, mon)
  -- status_screen.asm:66-76: StatusScreen recalculates the stat block before
  -- it draws anything when the mon came from a box or the daycare ("mon is
  -- in a box or daycare" -> CalcStats), because box_struct carries none.
  -- Bill's PC hands us that mon table directly (src/ui/BoxMenu.lua's STATS
  -- submenu entry), and for a .sav imported through
  -- src/save_convert/GenSave.lua it really does arrive with mon.stats nil,
  -- which crashed the HP bar draw below (#233).  Redundant once
  -- SaveData.validate has run over a loaded save, but this is the site the
  -- original recomputes at, and it also covers a mon handed in by a mod.
  Stats.ensure(game.data.pokemon[mon.species], mon)
  local self = setmetatable({ game = game, mon = mon, page = 1 }, SummaryMenu)
  self.isEgg = require("src.pokemon.Party").isEgg(mon) and true or false
  local Sprites = require("src.pokemon.Sprites")
  if self.isEgg then
    -- EggStatsScreen loads EggPic, never the species' -- the whole point of
    -- the screen is that it gives nothing away.
    local egg = game.data.field and game.data.field.egg
    if egg and egg.pic then
      local Assets = require("src.render.Assets")
      local ok, img = pcall(love.graphics.newImage, Assets.resolve(egg.pic))
      self.sprite = ok and img or nil
      self.spriteTrueColor = self.sprite and true or false
    end
    return self
  end
  local path, trueColor = Sprites.path(game.data, mon.species, "front",
    { mon = mon, kind = "summary" })
  if path then
    local ok, img = pcall(love.graphics.newImage, path)
    self.sprite = ok and img or nil
  end
  self.spriteTrueColor = self.sprite and trueColor or false
  -- Crystal animates the pic on this screen: AnimateMon_Menu's PokeAnims
  -- sequence (34:$4058) is stereocry / setup / play.  nil on Gold and
  -- Silver, which ship no animation tables at all.
  self.picAnim = require("src.pokemon.PicAnim").new(game.data, mon.species)
  -- this screen is up the moment it is built, so it runs straight away
  if self.picAnim then self.picAnim:start() end
  require("src.core.Sound").playCry(game.data, mon.species)
  return self
end

function SummaryMenu:update(dt)
  local input = self.game.input
  if self.picAnim then self.picAnim:update(dt) end
  if self.isEgg then
    if input:wasPressed("a") or input:wasPressed("b") then self.game.stack:pop() end
    return
  end
  if isGen2() then
    -- StatsScreen_JoypadAction: LEFT/RIGHT wrap through the three pages, A
    -- steps forward, B leaves.
    if input:wasPressed("b") then
      self.game.stack:pop()
    elseif input:wasPressed("right") or input:wasPressed("a") then
      self.page = self.page % 3 + 1
    elseif input:wasPressed("left") then
      self.page = (self.page + 1) % 3 + 1
    end
    return
  end
  -- both A and B advance the pages (WaitForTextScrollButtonPress)
  if input:wasPressed("a") or input:wasPressed("b") then
    if self.page == 1 then
      self.page = 2
    else
      self.game.stack:pop()
    end
  end
end

-- DrawLineBox (status_screen.asm): a vertical edge down the right,
-- a corner, a horizontal run leftward and the half-arrow ending --
-- drawn from the same HUD tiles the original loads
local function drawLineBox(tx, ty, b, c)
  local HudTiles = require("src.render.HudTiles")
  -- Under the status screen's overlay the vertical is $78 -- DrawLineBox
  -- writes `ld [hl], $78` (status_screen.asm:222), and :90-93 is what puts
  -- hud_2's single bar tile there.  $73 is the <ID> glyph on this screen,
  -- not a line, so the whole box has to come off statusTile (#280).  The
  -- drawn shapes are unchanged: hud_2 tile 0 is the same bar the battle
  -- layout parks at $73.
  for i = 0, b - 1 do HudTiles.statusTile(0x78, tx * 8, (ty + i) * 8) end
  HudTiles.statusTile(0x77, tx * 8, (ty + b) * 8)
  for i = 1, c do HudTiles.statusTile(0x76, (tx - i) * 8, (ty + b) * 8) end
  HudTiles.statusTile(0x6F, (tx - c - 1) * 8, (ty + b) * 8)
end

-- home/pokemon.asm:335-345 PrintLevel: the "<LV>" (":L") tile at (tx,ty)
-- then the level LEFT_ALIGNed after it; at level 100 hl is decremented so
-- the third digit is written back OVER the ":L" tile.  Both status pages
-- print a level this way, and src/ui/PartyMenu.lua models the same rule for
-- its rows. #280
local function printLevel(tx, ty, level)
  local HudTiles = require("src.render.HudTiles")
  local x = tx * 8
  if level < 100 then
    HudTiles.statusTile(0x6E, x, ty * 8)
    x = x + 8
  end
  Font.draw(tostring(level), x, ty * 8)
end

-- The pic in its 7x7-tile well, unmirrored: Gen2 dropped the flipped front
-- pic Gen1's status screen used.
function SummaryMenu:drawGen2Pic(x0, y0)
  if not self.sprite then return end
  -- every animation frame is the pic's own size, so the well placement is
  -- measured off the still and only the texture swaps
  local pw, ph = self.sprite:getDimensions()
  local image = (self.picAnim and self.picAnim:image()) or self.sprite
  local x, y = (x0 or 8) + (56 - pw) / 2, (y0 or 32) + (56 - ph) / 2
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, x, y)
  if self.spriteTrueColor then
    require("src.render.PaletteFX").markTrueColor(x, y, pw, ph)
  end
  love.graphics.setColor(0, 0, 0, 1)
end

local function rightAlign(text, right, y)
  Font.draw(text, right - Font.width(text), y)
end

local function drawLines(text, x, y, step)
  for line in tostring(text or ""):gmatch("[^\n]+") do
    Font.draw(line, x, y)
    y = y + (step or 16)
  end
end

function SummaryMenu:drawEggPage()
  local game = self.game
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, 0, 20, 3)
  Font.draw(Strings("EGG"), 8, 8)
  self:drawGen2Pic()
  local HudTiles = require("src.render.HudTiles")
  -- the ROM literally prints "?????" into both fields (the string that
  -- follows EggString in bank $14)
  Font.draw(Strings("OT/"), 72, 40)
  Font.draw("?????", 72, 56)
  HudTiles.statusTile(0x73, 72, 72) -- <ID>
  HudTiles.statusTile(0x74, 80, 72) -- №
  Font.draw("/", 88, 72)
  Font.draw("?????", 72, 88)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  drawLines(eggHatchText(game.data, self.mon), 8, 112, 10)
  love.graphics.setColor(1, 1, 1, 1)
end

-- StatsScreen_InitUpperHalf: the rows every page keeps, above the row-7
-- divider -- frontpic 7x7 at (0,0), "No." at (8,0), level (14,0), gender
-- (18,0), nickname (8,2) and "/" + species at (9,4).
function SummaryMenu:drawGen2Header()
  local mon, data = self.mon, self.game.data
  local def = data.pokemon[mon.species]
  local HudTiles = require("src.render.HudTiles")
  self:drawGen2Pic(0, 0)
  love.graphics.setColor(0, 0, 0, 1)
  HudTiles.statusTile(0x74, 64, 0) -- №
  Font.drawCode(0xF2, 72, 0)       -- <DOT>
  Font.draw(("%03d"):format(def.dex or 0), 80, 0)
  printLevel(14, 0, mon.level)
  local gender = require("src.pokemon.DayCare").gender(data, mon)
  if gender == "male" or gender == "female" then
    Font.draw(gender == "male" and "♂" or "♀", 144, 0)
  end
  -- StatsScreen_PlaceShinyIcon (14:$4F74): FarCall CheckShininess against
  -- wTempMonDVs, `ret nc`, then `ld [$C3B3], $3F` -- the star tile at
  -- coord (19,0), just right of the gender symbol.  The GB font here has no
  -- star glyph, so it is drawn as a five-pointed shape in the same cell.
  if require("src.pokemon.Stats").isShiny(mon.dvs) then
    local cx, cy, r = 156, 4, 3.5
    local pts = {}
    for i = 0, 9 do
      local rad = (i % 2 == 0) and r or r * 0.42
      local a = -math.pi / 2 + i * math.pi / 5
      pts[#pts + 1] = cx + math.cos(a) * rad
      pts[#pts + 1] = cy + math.sin(a) * rad
    end
    love.graphics.polygon("fill", pts)
  end
  Font.draw(mon.nickname or def.name, 64, 16)
  Font.draw("/", 72, 32)
  Font.draw(def.name, 80, 32)

  -- StatsScreen_PlaceHorizontalDivider fills row 7 with tile $62
  love.graphics.setColor(GEN2_SHADE2, GEN2_SHADE2, GEN2_SHADE2, 1)
  love.graphics.rectangle("fill", 0, 59, 160, 2)
  love.graphics.setColor(0, 0, 0, 1)

  -- the GB font has no side arrows, so StatsScreen_PlacePageSwitchArrows'
  -- (12,6) and (19,6) markers are drawn as triangles
  love.graphics.polygon("fill", 96, 52, 102, 48, 102, 56)
  love.graphics.polygon("fill", 158, 52, 152, 48, 152, 56)

  -- StatsScreen_LoadPageIndicators: 2x2 squares at (13,5)/(15,5)/(17,5),
  -- the current page's drawn from the larger tile set.  Each square is its
  -- own palette zone, so the fill has to be shade 2 to pick the page colour.
  for i = 1, 3 do
    local x, inset = 104 + (i - 1) * 16, i == self.page and 2 or 4
    love.graphics.setColor(GEN2_SHADE2, GEN2_SHADE2, GEN2_SHADE2, 1)
    love.graphics.rectangle("fill", x + inset, 40 + inset,
      16 - inset * 2, 16 - inset * 2)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x + inset + 0.5, 40 + inset + 0.5,
      16 - inset * 2 - 1, 16 - inset * 2 - 1)
  end
end

-- LoadPinkPage: HP, status, types on the left of the column-9 divider, the
-- exp block on its right.
function SummaryMenu:drawGen2PinkPage()
  local mon, game = self.mon, self.game
  local data = game.data
  local def = data.pokemon[mon.species]
  local HudTiles = require("src.render.HudTiles")
  HudTiles.drawHPBar(data, 0, 9, mon, 1)
  rightAlign(("%3d/%3d"):format(mon.hp, mon.stats.hp), 72, 80)
  Font.draw(Strings("STATUS/"), 0, 96)
  Font.draw(mon.status or Strings("OK"), 48, 104)
  Font.draw(Strings("TYPE/"), 0, 112)
  local t1 = def.types[1] and TypeChart.displayName(def.types[1]) or ""
  local t2 = def.types[2] and TypeChart.displayName(def.types[2]) or nil
  Font.draw(t1, 8, 120)
  if t2 and t2 ~= t1 then Font.draw(t2, 8, 136) end

  -- the $31 divider down column 9, rows 8-17
  love.graphics.setColor(GEN2_SHADE2, GEN2_SHADE2, GEN2_SHADE2, 1)
  love.graphics.rectangle("fill", 75, 64, 2, 80)
  love.graphics.setColor(0, 0, 0, 1)

  Font.draw(Strings("EXP POINTS"), 80, 72)
  rightAlign(("%d"):format(mon.exp or 0), 160, 80)
  Font.draw(Strings("LEVEL UP"), 80, 96)
  local Growth = require("src.pokemon.Growth")
  local nextExp = (mon.level or 1) < 100
    and (Growth.expForLevel(def.growthRate, mon.level + 1) - (mon.exp or 0)) or 0
  rightAlign(("%d"):format(math.max(0, nextExp)), 160, 104)
  Font.draw(Strings("TO"), 112, 112)
  printLevel(17, 14, math.min(100, (mon.level or 1) + 1))

  -- FillInExpBar at (11,16), between the $40/$41 end caps at columns 10 and 19
  local zoned = require("src.render.PaletteFX").shader() ~= nil
  HudTiles.tile(0x62, 80, 128)
  HudTiles.drawExpBar(data, 11, 16, HudTiles.expBarPixels(data, mon), zoned)
  HudTiles.tile(HudTiles.capTile(1), 152, 128)
end

-- LoadGreenPage: held item, then the four moves with their PP.
function SummaryMenu:drawGen2GreenPage()
  local mon, data = self.mon, self.game.data
  Font.draw(Strings("ITEM"), 0, 64)
  local item = mon.item and data.items[mon.item]
  Font.draw(item and item.name or mon.item or "---", 48, 64)
  Font.draw(Strings("MOVE"), 0, 80)
  for i = 1, 4 do
    local mv = mon.moves and mon.moves[i]
    local y = 80 + (i - 1) * 16
    local mdef = mv and data.moves[mv.id]
    Font.draw(mv and (mdef and mdef.name or "-") or "-", 64, y)
    if mv then
      Font.draw(Strings("PP"), 96, y + 8)
      rightAlign(("%2d/%2d"):format(mv.pp or 0, (mdef and mdef.pp) or 0),
        160, y + 8)
    else
      Font.draw("--", 136, y + 8)
    end
  end
end

-- LoadBluePage: ID and OT left of the column-10 divider, PrintTempMonStats
-- right of it -- each stat name two rows below the last, its value on the
-- row underneath, right-aligned to column 19.
function SummaryMenu:drawGen2BluePage()
  local mon, game = self.mon, self.game
  local HudTiles = require("src.render.HudTiles")
  HudTiles.statusTile(0x73, 0, 72) -- <ID>
  HudTiles.statusTile(0x74, 8, 72) -- №
  Font.drawCode(0xF2, 16, 72)      -- <DOT>
  Font.draw(("%05d"):format(mon.otId or game.save.player.id or 0), 16, 80)
  Font.draw(Strings("OT/"), 0, 96)
  Font.draw(mon.ot or game.save.player.name or "GOLD", 16, 104)

  love.graphics.setColor(GEN2_SHADE2, GEN2_SHADE2, GEN2_SHADE2, 1)
  love.graphics.rectangle("fill", 83, 64, 2, 80)
  love.graphics.setColor(0, 0, 0, 1)

  -- GSC split SPECIAL in two; the port keeps both halves on the mon
  local stats = mon.stats
  local rows = {
    { "ATTACK", stats.attack },
    { "DEFENSE", stats.defense },
    { "SPCL.ATK", stats.spatk or stats.special },
    { "SPCL.DEF", stats.spdef or stats.special },
    { "SPEED", stats.speed },
  }
  for i, row in ipairs(rows) do
    local y = 64 + (i - 1) * 16
    Font.draw(Strings(row[1]), 88, y)
    rightAlign(("%3d"):format(row[2] or 0), 160, y + 8)
  end
end

function SummaryMenu:drawGen2()
  -- The stats pages are white on hardware: _CGB_StatsScreenHPPals wipes the
  -- attrmap to the HP palette and only the three page squares get a colour.
  -- There is no page title either -- the squares are the whole indicator.
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  self:drawGen2Header()
  if self.page == 1 then
    self:drawGen2PinkPage()
  elseif self.page == 2 then
    self:drawGen2GreenPage()
  else
    self:drawGen2BluePage()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function SummaryMenu:draw()
  if self.isEgg then return self:drawEggPage() end
  if isGen2() then return self:drawGen2() end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local mon = self.mon
  local game = self.game
  local data = game.data
  local def = data.pokemon[mon.species]

  -- shared header: pic (1,0), name (9,1), № + dex number (1,7).  The pic is
  -- MIRRORED -- status_screen.asm:170 draws it through
  -- LoadFlippedFrontSpriteByMonIndex (home/pokemon.asm sets wSpriteFlipped),
  -- the same routine the intro's NIDORINO show-off uses (OakSpeech picFlip:
  -- negative x scale anchored at the pic's right edge). #280
  if self.sprite then
    local pw, ph = self.sprite:getDimensions()
    local py = math.max(0, 56 - ph)
    love.graphics.draw(self.sprite, 8 + pw, py, 0, -1, 1)
    -- a full-color pic has to sit out the SGB monPal recolor, so mark the
    -- rect the mirrored draw covers for the unshaded pass (#430)
    if self.spriteTrueColor then
      require("src.render.PaletteFX").markTrueColor(8, py, pw, ph)
    end
  end
  local HudTiles = require("src.render.HudTiles")
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(mon.nickname or def.name, 72, 8)
  -- status_screen.asm:109-113 backs hl up from DrawLineBox's end to write
  -- the single-tile '№' at (1,7) and '<DOT>' at (2,7); :143-146 then
  -- PrintNumbers the dex number (LEADING_ZEROES, 3 digits) at (3,7).
  -- Spelling "No." out of three letter tiles pushed every digit a column
  -- right of the original. #280
  HudTiles.statusTile(0x74, 8, 56)  -- №
  Font.drawCode(0xF2, 16, 56)       -- <DOT> (charmap.asm:182)
  Font.draw(("%03d"):format(def.dex or 0), 24, 56)

  if self.page == 1 then
    -- HP bar (11,3) + numbers row 4, STATUS/ (9,6), the DrawLineBox
    -- bracket around the name/HP block, and PrintLevel at (14,2).  The
    -- level belongs to page 1 ONLY: StatusScreen2 opens with ClearScreenArea
    -- over (9,2) 5x10 (status_screen.asm:303-305), which wipes it. #280
    printLevel(14, 2, mon.level)
    drawLineBox(19, 1, 6, 10)
    HudTiles.drawHPBar(data, 11, 3, mon, 1) -- wHPBarType 1
    Font.draw(("%3d/%3d"):format(mon.hp, mon.stats.hp), 96, 32)
    Font.draw(Strings("STATUS/"), 72, 48)
    Font.draw(mon.status or "OK", 128, 48)

    -- stats box (0,8) 10x10: names rows 9/11/13/15, values indented
    Font.drawBox(0, 8, 10, 10)
    local stats = {
      { "ATTACK", mon.stats.attack }, { "DEFENSE", mon.stats.defense },
      { "SPEED", mon.stats.speed }, { "SPECIAL", mon.stats.special },
    }
    for i, s in ipairs(stats) do
      local y = 72 + (i - 1) * 16
      Font.draw(Strings(s[1]), 8, y)
      Font.draw(("%3d"):format(s[2]), 48, y + 8)
    end

    -- TYPE1/TYPE2/IDNo/OT column (10,9) with values indented (11,10)
    drawLineBox(19, 9, 8, 6)
    Font.draw(Strings("TYPE1/"), 80, 72)
    Font.draw(def.types[1] and TypeChart.displayName(def.types[1]) or "", 88, 80)
    if def.types[2] then
      Font.draw(Strings("TYPE2/"), 80, 88)
      Font.draw(TypeChart.displayName(def.types[2]), 88, 96)
    end
    -- TypesIDNoOTText's third row is "<ID>№/" (status_screen.asm:205-210):
    -- two single-tile glyphs and a slash, three columns wide, not the five
    -- letter tiles "IDNo/" this used to spell out. #280
    HudTiles.statusTile(0x73, 80, 104) -- <ID>
    HudTiles.statusTile(0x74, 88, 104) -- №
    Font.draw("/", 96, 104)
    -- the trainer ID is rolled at new game (SaveData.newGame) and
    -- backfilled on load for old saves
    Font.draw(("%05d"):format(mon.otId or game.save.player.id or 0), 96, 112)
    Font.draw(Strings("OT/"), 80, 120)
    Font.draw(mon.ot or game.save.player.name or "RED", 96, 128)
  else
    -- page 2: EXP + the moves with PP (StatusScreen2)
    drawLineBox(19, 1, 6, 10)
    Font.draw(Strings("EXP POINTS"), 72, 24)
    -- PrintNumber at (12,4) with 7 columns: the exp is RIGHT-aligned into
    -- cols 12-18 (status_screen.asm:400-403), not left-aligned from col 12.
    -- #280
    Font.draw(("%7d"):format(mon.exp), 96, 32)
    -- StatusScreen2: "LEVEL UP" at (9,5); next-exp PrintNumber 7 cols at
    -- (7,6); the narrow '<to>' tile at (14,6); PrintLevel at (16,6)
    -- (status_screen.asm:393-403).  The old "%d to L%d" string at x=88
    -- overflowed the DrawLineBox edge.
    Font.draw(Strings("LEVEL UP"), 72, 40)
    local Growth = require("src.pokemon.Growth")
    local nextExp = mon.level < 100
      and (Growth.expForLevel(def.growthRate, mon.level + 1) - mon.exp) or 0
    Font.draw(("%7d"):format(math.max(0, nextExp)), 56, 48)
    HudTiles.statusTile(0x70, 112, 48) -- '<to>' at (14,6), was missing (#280)
    printLevel(16, 6, math.min(100, mon.level + 1))
    -- Gen2's stats screen carries the same exp bar the battle HUD does
    -- (stats_screen.asm calls FillInExpBar too).  It lands on DrawLineBox's
    -- bottom run, which is exactly the eight tiles PlaceExpBar writes.
    if require("src.core.GameVersion").isGen2() then
      -- sgbPalettes zones this row to EXPBAR whenever the shader resolves;
      -- with no shader the flat tint is the bar's only color (PartyMenu
      -- reads the same pair of conditions for its own rows).
      local zoned = require("src.render.PaletteFX").shader() ~= nil
      HudTiles.drawExpBar(data, 11, 7, HudTiles.expBarPixels(data, mon), zoned)
    end
    Font.drawBox(0, 8, 20, 10)
    for i = 1, 4 do
      local mv = mon.moves[i]
      local y = 72 + (i - 1) * 16
      if mv then
        local mdef = data.moves[mv.id]
        Font.draw(mdef.name, 16, y)
        Font.draw(Strings("PP"), 88, y + 8)
        Font.draw(("%2d/%2d"):format(mv.pp, mdef.pp), 112, y + 8)
      else
        Font.draw("-", 16, y)
        Font.draw("--", 112, y + 8)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return SummaryMenu
