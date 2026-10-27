-- In-battle HUD tiles, shared by the battle screen and the status
-- screen: pokered overlays the $62-$7F font area with the HP bar /
-- status sheet (font_battle_extra -> $62) and the HUD line tiles
-- (battle_hud_1 -> $6D, battle_hud_2+3 -> $73).
--
-- The two screens do NOT use the same overlay: the status screen scatters
-- hud_2 and hud_3 instead of copying them contiguously, which is what keeps
-- its № and <ID> glyphs alive.  HudTiles.tile draws the battle layout,
-- HudTiles.statusTile the status one -- see STATUS_PAGES below. #280

local Assets = require("src.render.Assets")

local HudTiles = {}

-- The four HUD sheets are glyph pages like any other, so they resolve
-- through the font registry: mod.content.font:register("battle_hud_1",
-- { image = ..., base = 0x6D }) reskins the HP bar.  These are the
-- vanilla pages the importer's cache carries, in the order the asm
-- overlays them ($6D lands on top of font_battle_extra's tail).
local PAGES = {
  { id = "font_battle_extra",
    image = "assets/generated/battle/font_battle_extra.png", base = 0x62 },
  { id = "battle_hud_1",
    image = "assets/generated/battle/battle_hud_1.png", base = 0x6D },
  { id = "battle_hud_2",
    image = "assets/generated/battle/battle_hud_2.png", base = 0x73 },
  { id = "battle_hud_3",
    image = "assets/generated/battle/battle_hud_3.png", base = 0x76 },
  -- Gen2 only (LoadHPBar copies ExpBarGFX to vTiles tile $55).  pokered has
  -- no such sheet, so the page simply fails to resolve there.
  { id = "exp_bar",
    image = "assets/generated/battle/exp_bar.png", base = 0x55 },
}

-- The STATUS SCREEN overlays the SAME sheets differently, and the layout
-- above would break it: engine/pokemon/status_screen.asm:86-97 copies 3
-- tiles of hud_1 to $6D, ONE tile of hud_2 to $78 and 2 tiles of hud_3 to
-- $76, which leaves $70/$73/$74 as font_battle_extra's <to>, <ID> and № --
-- the glyphs the screen prints "№." and "<ID>№/" from
-- (constants/charmap.asm:69-73).  The battle overlay instead copies
-- hud_2+hud_3 contiguously over $73-$78 (engine/battle/core.asm:6520/6532),
-- burying № under a line tile, so the status screen needs its own table.
-- The line glyphs land identically either way -- $76 ─, $77 ┘, $6F the
-- halfarrow -- only the vertical bar moves ($73 in battle, $78 here). #280
local STATUS_PAGES = {
  { id = "font_battle_extra",
    image = "assets/generated/battle/font_battle_extra.png", base = 0x62 },
  { id = "battle_hud_1",
    image = "assets/generated/battle/battle_hud_1.png", base = 0x6D },
  { id = "battle_hud_3",
    image = "assets/generated/battle/battle_hud_3.png", base = 0x76, count = 2 },
  { id = "battle_hud_2",
    image = "assets/generated/battle/battle_hud_2.png", base = 0x78, count = 1 },
  { id = "exp_bar",
    image = "assets/generated/battle/exp_bar.png", base = 0x55 },
}

local tiles, statusTiles

-- HOW WIDE THE BARS ARE ON THIS CARTRIDGE.  Gold and Crystal are the defaults
-- here; a hack that widened them says so in the generated font table (see
-- RomExtractorGen2:gen2HudGeometry), and nothing else changes.
--
-- expBarEmptyTile is the tile that draws ZERO pixels of fill, with +n for n
-- pixels.  Crystal has no such tile in its exp sheet -- it borrows the HP
-- bar's $63 and $6B for the two ends and keeps only the seven partials, which
-- is why the default path below special-cases 0 and 8.
local HUD_DEFAULTS = {
  hpBarTiles = 6,
  -- GetHPPal's thresholds in whole pixels of a six-tile bar
  hpBarGreenPixels = 27,
  hpBarYellowPixels = 10,
  expBarTiles = 8,
}
local GSC_DEFAULTS = {
  hpBarTiles = 6,
  hpBarGreenPixels = 24,
  hpBarYellowPixels = 10,
  expBarTiles = 8,
}

-- ASKED SIX TIMES A ROW.  drawHPBar alone calls this twice per bar, and a
-- party screen draws six of them a frame -- so this built the same nine-field
-- table (and did a package.loaded lookup) about eighteen times a frame for an
-- answer that only changes when the font record is reloaded.  It is memoised
-- on the record it was built from, so a reload rebuilds it and HudTiles.
-- invalidate (already registered with Assets) clears it outright.
local geoCache, geoFrom, geoDefaults
local function hudGeometry()
  local defaults = require('src.core.GameVersion').isGen2() and GSC_DEFAULTS or HUD_DEFAULTS
  local font = require("src.core.Data").font
  local hud = type(font) == "table" and font.hud or nil
  if type(hud) ~= "table" then return defaults end
  if geoCache and geoFrom == hud and geoDefaults == defaults then return geoCache end
  geoFrom, geoDefaults = hud, defaults
  geoCache = {
    hpBarTiles = hud.hpBarTiles or defaults.hpBarTiles,
    hpBarGreenPixels = hud.hpBarGreenPixels or defaults.hpBarGreenPixels,
    hpBarYellowPixels = hud.hpBarYellowPixels or defaults.hpBarYellowPixels,
    expBarTiles = hud.expBarTiles or defaults.expBarTiles,
    expBarEmptyTile = hud.expBarEmptyTile,
    -- the stats screen's page-tile block, and the two tiles in it that close
    -- the exp bar on that screen (RomExtractorGen2:gen2StatsExpCaps)
    statsTilesBase = hud.statsTilesBase,
    statsTilesCount = hud.statsTilesCount,
    statsExpCapLeft = hud.statsExpCapLeft,
    statsExpCapRight = hud.statsExpCapRight,
  }
  return geoCache
end

-- Exposed so the battle screen and the status screen place the bars where
-- this cartridge's own HUD routine places them.
function HudTiles.geometry()
  return hudGeometry()
end

-- Build one code -> {img, quad} map from a page list.  `count` caps a page
-- at the number of tiles the asm actually copies (the extracted sheets all
-- carry 3 tiles; the status overlay uses fewer).  A mod's registered page
-- swaps the image in either table, but only the battle table honors its
-- `base`: the status layout is the asm's own placement, and sliding hud_2
-- there would bury № again.
-- THE STATS SCREEN'S OWN SHEET, wherever this cartridge keeps it.
--
-- LoadStatsScreenPageTilesGFX copies one block into VRAM, and the extractor
-- reads that routine's own `ld de / ld hl / lb bc` for the source, the
-- destination tile and the count (RomExtractorGen2:gen2StatsTilesSheet) -- so
-- the base is not written down here, it arrives with the rest of the HUD
-- geometry.  The exp bar's END CAPS on the summary screen are two tiles of this
-- block and of nothing else, which is why the screen was closing its bar with
-- the HP bar's $62 and $6D instead.
local function statsPage()
  local geo = hudGeometry()
  if not (geo.statsTilesBase and geo.statsTilesCount) then return nil end
  return { id = "stats_tiles", image = "assets/generated/battle/stats_tiles.png",
           base = geo.statsTilesBase, count = geo.statsTilesCount }
end

local function build(pages, fixedBase)
  local out = {}
  local registered = require("src.core.Data").font
  registered = registered and registered.pages or nil
  local all = { statsPage() }        -- nil on a cartridge without one
  for _, page in ipairs(pages) do all[#all + 1] = page end
  pages = all
  for _, page in ipairs(pages) do
    local override = registered and registered[page.id]
    local path, base = page.image, page.base
    if override and override.image then path = override.image end
    if not fixedBase and override and override.base then base = override.base end
    local ok, img = pcall(Assets.image, path)
    if ok then
      local iw, ih = img:getDimensions()
      local per = iw / 8
      local count = page.count or per * (ih / 8)
      for i = 0, count - 1 do
        out[base + i] = {
          img = img,
          -- the page this tile came from, so a bar fill can be drawn from a
          -- REPAINTED copy of the same sheet through the same quad
          path = path,
          quad = love.graphics.newQuad((i % per) * 8,
                                       math.floor(i / per) * 8, 8, 8, iw, ih),
        }
      end
    end
  end
  return out
end

-- THE BAR FILL CANNOT BE TINTED, IT HAS TO BE REPAINTED.
--
-- A bar's fill pixels are DMG SHADE 2 -- 85 of 255 -- and nothing else: decode
-- Crystal's or Prism's own FontBattleExtra $63-$6B and ExpBarGFX and the only
-- values present are shade 0 (transparent paper), shade 2 (the fill) and shade
-- 3 (the black rules).  There is no 170 anywhere, which is what the tint below
-- this used to divide by.
--
-- But the divisor was only half of it.  love.graphics.setColor MULTIPLIES, and
-- 85 * k cannot reach 189 unless k > 1 -- and LOVE clamps k at 1.  A screenshot
-- of Prism's battle HUD measures the fill exactly: the HP bar comes out
-- (0,85,0) where GREENBAR is (0,189,0), and the exp bar (33,85,85) where EXPBAR
-- is (33,140,255) -- red, the one channel whose multiplier was BELOW one
-- (33/85), is the one channel that came out right.  Every HP bar in the port
-- has been at a third of its colour, in battle, in the party menu and on the
-- summary screen; Prism is where it reads as broken rather than as dark,
-- because its bar carries a far heavier black frame (288 black pixels across
-- the fill tiles against Crystal's 72) and the thin band of colour between the
-- rules is all there is to see.
--
-- So the sheet is repainted instead of multiplied: the cartridge's four
-- palette entries replace the four DMG shades, which is what the hardware does
-- and is exact for every colour rather than only for the dark ones.  One image
-- per (sheet, palette name), built on first use and dropped with the pages.
local repainted = {}

local function barImage(path, name, colors)
  if not (path and name and colors) then return nil end
  local key = path .. "|" .. name
  local hit = repainted[key]
  if hit ~= nil then return hit or nil end
  local ok, image = pcall(function()
    local data = Assets.imageData(path)
    local shades = {}
    for shade = 0, 3 do
      local c = colors[shade + 1]
      if c then shades[shade] = { c[1] / 255, c[2] / 255, c[3] / 255 } end
    end
    require("src.import.ImageWriter").recolorShades(data, shades)
    return love.graphics.newImage(data)
  end)
  repainted[key] = ok and image or false
  return ok and image or nil
end

local function put(t, x, y, tint, paint)
  if not t then return end
  local img = (paint and barImage(t.path, paint.name, paint.colors)) or t.img
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(tint or { 1, 1, 1, 1 })
  love.graphics.draw(img, t.quad, x, y)
  love.graphics.setColor(r, g, b, a)
end

-- `paint` is { name = <palette name>, colors = <the four colours> }: the tile
-- is drawn from a repainted copy of its sheet instead of tinted.  Only the bar
-- fills pass one; every other tile keeps the sheet's own greys.
function HudTiles.tile(code, x, y, tint, paint)
  if not tiles then tiles = build(PAGES) end
  put(tiles[code], x, y, tint, paint)
end

-- The same sheets under the status screen's overlay (STATUS_PAGES).  The HP
-- bar codes $62-$6D are identical in both layouts, so drawHPBar below keeps
-- using the battle table. #280
function HudTiles.statusTile(code, x, y, tint)
  if not statusTiles then statusTiles = build(STATUS_PAGES, true) end
  put(statusTiles[code], x, y, tint)
end

-- lazy: the next tile() rebuilds every page from the search path
function HudTiles.invalidate()
  tiles = nil
  statusTiles = nil
  repainted = {}
  geoCache, geoFrom = nil, nil
end

Assets.register(HudTiles.invalidate)

-- The bar's right-end tile follows wHPBarType (DrawHPBar's "Right"
-- branch): only type 1 -- the player's in-battle bar and the status
-- screen -- gets the double-bar $6D; the enemy bar (0) and the party
-- menu (2) close with the near-blank $6C nub.
function HudTiles.capTile(barType)
  return barType == 1 and 0x6D or 0x6C
end

function HudTiles.hpPixels(hp, maximum, segments)
  if maximum <= 0 or hp <= 0 then return 0 end
  segments = segments or hudGeometry().hpBarTiles
  if require('src.core.GameVersion').isGen2() then
    return math.max(1, math.floor(require('src.battle.Gen2HpPresentation').pixels(hp, maximum)
      * segments / 6))
  end
  return math.max(1, math.floor(hp * segments * 8 / maximum))
end

-- Tile HP bar (home/pokemon.asm DrawHPBar): "HP" ($71) + ":[" ($62),
-- six 8px segments ($63 empty, +n partial, $6B full), then the
-- wHPBarType right cap.  A nonzero HP always shows at least a
-- one-pixel sliver.  The fill is tinted with the SGB bar palettes at
-- GetHealthBarColor's thresholds (>= 27 px green, >= 10 yellow, else
-- red).
--
-- segments: how many 8px cells the bar spans (6, the hardware width,
-- unless a caller asks for more -- the widescreen battle layout has room
-- for a longer bar in the same tiles).  The color thresholds scale with
-- it so a wider bar turns yellow and red at the same fractions of full.
--
-- grayFill (#229): when the caller will colorize this bar with an SGB
-- region palette (BattleState's zone pass, BATTLE_ZONES pal 0/1 =
-- GetHealthBarColor), leave the fill as its raw DMG shade-2 gray and skip
-- the per-pixel tint -- the DMG hardware bar is ONE gray shade recolored by
-- the region palette (engine/gfx/palettes.asm SetPal_Battle,
-- data/sgb/sgb_packets.asm BlkPacket_Battle), never a per-pixel repaint.
-- Tinting first would double-apply the color: GREENBAR's fill {0,189,0} has
-- red channel 0, so the tint zeroes the whole bar's red and the zone's
-- red-channel-keyed shade shader then maps every pixel to color 3 = black.
function HudTiles.drawHPBar(data, tx, ty, mon, barType, grayFill, segments, pixels)
  local x, y = tx * 8, ty * 8
  segments = math.max(1, math.floor(segments or hudGeometry().hpBarTiles))
  HudTiles.tile(0x71, x, y)
  HudTiles.tile(0x62, x + 8, y)
  -- A short GSC loop moves pixels while its displayed HP number can repeat.
  -- Recomputing the fill from that number would hide those animation beats.
  local px = pixels ~= nil and math.max(0, math.min(segments * 8, math.floor(pixels)))
    or HudTiles.hpPixels(mon.hp, mon.stats.hp, segments)
  local paint
  if not grayFill then
    local PaletteFX = require("src.render.PaletteFX")
    -- the cartridge's own GetHPPal thresholds, scaled if the caller asked for
    -- a wider bar than the hardware one (the widescreen battle layout does)
    local geo = hudGeometry()
    local green = math.ceil(geo.hpBarGreenPixels * segments / geo.hpBarTiles)
    local yellow = math.ceil(geo.hpBarYellowPixels * segments / geo.hpBarTiles)
    local name = px >= green and "GREENBAR"
                 or px >= yellow and "YELLOWBAR" or "REDBAR"
    local colors = PaletteFX.pal(data, name)
    -- REPAINTED, NOT TINTED -- see the note by barImage above: the fill is the
    -- 1/3 gray and a multiply can only ever darken it
    if colors then paint = { name = name, colors = colors } end
  end
  for i = 0, segments - 1 do
    local seg = math.min(8, math.max(0, px - i * 8))
    HudTiles.tile(seg >= 8 and 0x6B or 0x63 + seg, x + 16 + i * 8, y, nil, paint)
  end
  HudTiles.tile(HudTiles.capTile(barType), x + 16 + segments * 8, y)
end

-- How full the Gen2 exp bar is, in pixels -- out of EXP_BAR_LENGTH * 8, which
-- is 64 on Gold and Crystal and 72 on a cartridge with a wider bar
-- (CalcExpBar's `ld a, EXP_BAR_TILES * 8`).
function HudTiles.expBarPixels(data, mon)
  local def = data.pokemon and data.pokemon[mon.species]
  if not def then return 0 end
  local Growth = require("src.pokemon.Growth")
  local base = Growth.expForLevel(def.growthRate, mon.level, data.growth_rates)
  local next_ = Growth.expForLevel(def.growthRate, mon.level + 1,
                                   data.growth_rates)
  local span = next_ - base
  if span <= 0 then return 0 end
  local into = math.min(span, math.max(0, (mon.exp or 0) - base))
  return math.floor(into * hudGeometry().expBarTiles * 8 / span)
end

-- Gen2's exp bar (PlaceExpBar, engine/battle/core.asm): eight tiles written
-- RIGHT to LEFT off the far end, eight pixels each.  The empty and full
-- extremes are the HP bar's own tiles -- pokered's $63 and $6B, since the
-- Gen2 sheet is remapped into pokered's slots -- and ExpBarGFX at $55
-- supplies the seven partial widths (`add $54`).
function HudTiles.drawExpBar(data, tx, ty, pixels, grayFill)
  local geo = hudGeometry()
  local tileCount = geo.expBarTiles
  pixels = math.max(0, math.min(tileCount * 8, math.floor(pixels or 0)))
  local paint
  if not grayFill then
    -- Only the flat path repaints, exactly like drawHPBar.  Where a zone pass
    -- runs it recolors the DMG shades itself, and a second pass underneath it
    -- moves the fill's luminance into another shade -- which drew the bar
    -- inside out: blue paper with a black fill.
    --
    -- This used to divide the palette colour by the fill's own 85 and hand the
    -- result to setColor.  It does not work, and the screenshot that started
    -- this says so: EXPBAR is (33,140,255) and the bar measured (33,85,85) --
    -- red, whose multiplier was below one, landed exactly, and green and blue,
    -- whose multipliers were 1.6 and 3.0, both clamped to 85.  LOVE clamps.
    local PaletteFX = require("src.render.PaletteFX")
    local colors = PaletteFX.pal(data, "EXPBAR")
    if colors then paint = { name = "EXPBAR", colors = colors } end
  end
  local empty = geo.expBarEmptyTile
  for i = tileCount - 1, 0, -1 do
    local seg = math.min(8, pixels)
    pixels = pixels - seg
    local code
    if empty then
      -- the sheet carries its own ends: empty + n pixels, full at empty + 8
      code = empty + seg
    else
      code = seg >= 8 and 0x6B or (seg == 0 and 0x63 or 0x54 + seg)
    end
    HudTiles.tile(code, (tx + i) * 8, ty * 8, nil, paint)
  end
end

return HudTiles
