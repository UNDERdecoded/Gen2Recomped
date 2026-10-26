-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE IN-GAME TRADE SEQUENCE'S ART, OUT OF THE PLAYER'S OWN CARTRIDGE.
--
-- Reported from play: "Test all in game trades as well ensure the art for
-- trading also properly displayed with rom parity" and "Ensure it works for
-- emerald and firered as well".  Special 257 (DoInGameTradeScene) swapped the
-- two Pokemon and showed nothing at all; the cartridge plays a full minute of
-- animation there -- the Pokemon on its platform, the ball, the GBA zooming
-- out and sending a signal, the two Pokemon crossing in a column of light,
-- the GBA receiving, the new Pokemon released.  src/ui/Gen3TradeAnim.lua is
-- that sequence; this is the art and the tables it is drawn with.
--
-- WHICH PATH.  pokeemerald CB2_InitInGameTrade (src/trade.c) allocates the
-- trade state with AllocZeroed and never sets `isCableTrade`, so DoTradeAnim
-- runs DoTradeAnim_Wireless for every in-game trade -- the wireless-adapter
-- GBA, the concentric signal rings, the white crossing column -- not the
-- cable sequence a link-cable trade uses.  pokefirered's trade_scene.c is the
-- same code with the same omission, so both games are served by one table of
-- WIRELESS assets below; the cable-only ones (gba_map_cable, the cable end
-- sprite, crossing_highlight_cable) are never shown by an in-game trade and
-- are not extracted.
--
-- WHERE THE ADDRESSES COME FROM.  A retail GBA ROM carries no symbols, and
-- the rest of this importer finds its tables structurally.  These are taken
-- from the symbol files pret publishes for the ROM-matching builds
-- (pokeemerald.sym for BPEE rev 0, pokefirered.sym for BPRE rev 0) and keyed
-- by game code and revision, so a cartridge this table does not name is
-- skipped rather than read at the wrong offsets.  EVERY BLOB IS THEN VERIFIED
-- against the shape the decomp gives it before anything is written:
--
--   * an LZ77 blob must carry the 0x10 header and decompress to exactly the
--     size the code copies (gBattleTextboxTiles 0x2000, the closeup map 0x800,
--     the signal tiles 0x1800, the battle ball 384 bytes = three 16x16
--     frames, ...);
--   * a palette must be BGR555 with bit 15 clear in every entry;
--   * a tilemap must only name tiles its char block holds and only palette
--     banks SetTradeSequenceBgGpuRegs loaded (0 for the text box, 0-3 for the
--     GBA art), and the affine map must index the 160 8bpp tiles DMA'd for it;
--   * the four sentences must decode and carry their {VARn} placeholders;
--   * the ball's bounce table must be 108 bytes in -4..4, the signal's
--     animation table must end on its 0xFF sentinel, and gSineTable must read
--     0 / 256 / 0 at 0, 64 and 128.
--
-- Anything that fails is logged and the whole stage is skipped: the screen
-- falls back to the bare swap the port always did, which is better than a
-- trade drawn out of the wrong bytes.
--
-- HOW IT IS STORED.  The trade screen fades, blends and cycles PALETTES --
-- BeginNormalPaletteFade, BlendPalettes, the wireless signal's sixteen-step
-- palette walk, the glow core's colour 4 -- so the pictures are written as
-- INDEX images: red = the colour index (bank * 16 + pixel for a 4bpp layer,
-- the 8bpp index for the affine one), alpha 0 for the transparent pixel 0.
-- The palettes themselves are kept as BGR555 words in the data module, which
-- is what lets the screen do the cartridge's own 5-bit fade arithmetic
-- (BlendPalette, util.c) rather than an approximation of it.

local RomGba = require("src.import.RomGba")
local ImageWriter = require("src.import.ImageWriter")
local Logger = require("src.core.Logger")

local Gen3TradeArt = {}

-- ---------------------------------------------------------------------------
-- The addresses, per cartridge.  `lz` = LZ77 (decompressed size = `size`),
-- otherwise raw bytes of `size`.  File offsets (ROM address - 0x08000000).
-- ---------------------------------------------------------------------------
Gen3TradeArt.ROMS = {
  -- pokeemerald.sym, Emerald (USA, Europe) BPEE rev 0
  BPEE0 = {
    version = "emerald",
    textboxTiles   = { at = 0xC00000, size = 0x2000, lz = true },  -- gBattleTextboxTiles
    textboxPal     = { at = 0xC004E0, size = 0x40,   lz = true },  -- gBattleTextboxPalette
    textboxMap     = { at = 0xC00524, size = 0x1000, lz = true },  -- gBattleTextboxTilemap
    gba2Pal        = { at = 0xDD7300, size = 0x60 },               -- gTradeGba2_Pal
    gbaGfx         = { at = 0xDD7360, size = 0x1400 },             -- gTradeGba_Gfx
    platformMap    = { at = 0x331F60, size = 0x1000 },             -- gTradePlatform_Tilemap
    affineGfx      = { at = 0x332F60, size = 0x2800 },             -- sGbaAffine_Gfx
    affineMap      = { at = 0x3358A0, size = 0x100 },              -- sGbaAffineMapWireless
    gbaMap         = { at = 0x3359A0, size = 0x1000 },             -- sGbaMapWireless
    closeupMap     = { at = 0x3379A0, size = 0x800,  lz = true },  -- sWirelessCloseup_Map
    signalSendPal  = { at = 0x337AA0, size = 0x200 },              -- sWirelessSignalSend_Pal
    signalRecvPal  = { at = 0x337CA0, size = 0x200 },              -- sWirelessSignalRecv_Pal
    signalNonePal  = { at = 0x337EA0, size = 0x20 },               -- sWirelessSignalNone_Pal
    signalGfx      = { at = 0x337EC0, size = 0x1800, lz = true },  -- sWirelessSignal_Gfx
    signalMap      = { at = 0x338550, size = 0x800,  lz = true },  -- sWirelessSignal_Tilemap
    pokeballPal    = { at = 0x32DFA0, size = 0x20 },               -- sPokeball_Pal
    pokeballGfx    = { at = 0x32DFC0, size = 0x600 },              -- sPokeball_Gfx
    gbaPal         = { at = 0x3308E0, size = 0x20 },               -- sGba_Pal
    linkMonPal     = { at = 0x330940, size = 0x20 },               -- sLinkMon_Pal
    glowGfx        = { at = 0x330960, size = 0x200 },              -- sLinkMonGlow_Gfx
    shadowGfx      = { at = 0x330B60, size = 0x200 },              -- sLinkMonShadow_Gfx
    gbaScreenGfx   = { at = 0x330F60, size = 0x1000 },             -- sGbaScreen_Gfx
    shadowCycle    = { at = 0x338EA4, size = 0x18 },               -- sLinkMonShadow_Pal
    velocity       = { at = 0x339024, size = 0x6C },               -- sTradeBallVerticalVelocityTable
    signalParams   = { at = 0x339090, size = 0x44 },               -- sWirelessSignalAnimParams
    ballGfx        = { at = 0xC0173C, size = 384,    lz = true },  -- gBallGfx_Poke
    ballPal        = { at = 0xC017F8, size = 0x20,   lz = true },  -- gBallPal_Poke
    particleGfx    = { at = 0xC1A490, size = 0x100,  lz = true },  -- gBattleAnimSpriteGfx_Particles
    particlePal    = { at = 0xC1A564, size = 0x20,   lz = true },  -- gBattleAnimSpritePal_CircleImpact
    ballFadeColors = { at = 0x5E5310, size = 0x18 },               -- gBallOpenFadeColors
    sine           = { at = 0x329F40, size = 0x280 },              -- gSineTable
    speciesInfo    = 0x3203CC,                                     -- gSpeciesInfo
    text = {                                                       -- strings.c
      sending  = 0x5EE942,   -- gText_XWillBeSentToY
      goodbye  = 0x5EE959,   -- gText_ByeByeVar1
      arrived  = 0x5EE966,   -- gText_XSentOverY
      takeCare = 0x5EE977,   -- gText_TakeGoodCareOfX
    },
    -- DrawTextOnTradeWindow: AddTextPrinterParameterized4(win, FONT_NORMAL,
    -- 0, 2, 0, 0, ...) -- x 0, y 2, no extra line spacing; a new line moves
    -- down FONT_NORMAL's maxLetterHeight (sFontInfos, 16) plus that spacing
    textLayout = { x = 0, y = 2, letterSpacing = 0, lineSpacing = 0,
                   maxLetterHeight = 16 },
    -- include/constants/songs.h
    sounds = { BALL_OPEN = 15, WARP_IN = 45, WARP_OUT = 46,
               BALL_BOUNCE_1 = 56, BALL_BOUNCE_2 = 57, BALL_BOUNCE_3 = 58,
               BALL_BOUNCE_4 = 59, BALL_TRADE = 60, M_MEGA_KICK = 140,
               M_SAND_ATTACK = 159, M_SWAGGER2 = 194, M_HEAL_BELL = 195,
               M_MINIMIZE = 204 },
    -- Emerald's CreatePokeballSpriteToReleaseMon takes the species and
    -- SpriteCB_ReleasedMonFlyOut runs DoMonFrontSpriteAnimation, which plays
    -- the cry and the species' own front animation; FireRed has neither and
    -- plays the cry from the trade state machine instead
    releaseAnimates = true,
  },
  -- pokefirered.sym, FireRed (USA, Europe) BPRE rev 0
  BPRE0 = {
    version = "firered",
    textboxTiles   = { at = 0xD00000, size = 0x2000, lz = true },  -- gBattleInterface_Textbox_Gfx
    textboxPal     = { at = 0xD004D8, size = 0x40,   lz = true },  -- gBattleInterface_Textbox_Pal
    textboxMap     = { at = 0xD0051C, size = 0x1000, lz = true },  -- gBattleInterface_Textbox_Tilemap
    gba2Pal        = { at = 0xEAEA20, size = 0x60 },               -- gTradeGba2_Pal
    gbaGfx         = { at = 0xEAEA80, size = 0x1400 },             -- gTradeGba_Gfx
    platformMap    = { at = 0x26601C, size = 0x1000 },             -- gTradeOrHatchMonShadowTilemap
    affineGfx      = { at = 0x26701C, size = 0x2800 },             -- sGbaAffine_Gfx
    affineMap      = { at = 0x26995C, size = 0x100 },              -- sGbaAffineMapWireless
    gbaMap         = { at = 0x269A5C, size = 0x1000 },             -- sGbaMapWireless
    closeupMap     = { at = 0x26BA5C, size = 0x800,  lz = true },  -- sWirelessCloseup_Map
    signalSendPal  = { at = 0x26BB5C, size = 0x200 },              -- sWirelessSignalAnimPals_Outbound
    signalRecvPal  = { at = 0x26BD5C, size = 0x200 },              -- sWirelessSignalAnimPals_Inbound
    signalNonePal  = { at = 0x26BF5C, size = 0x20 },               -- sWirelessSignalAnimPals_Off
    signalGfx      = { at = 0x26BF7C, size = 0x1800, lz = true },  -- sWirelessSignal4bpp
    signalMap      = { at = 0x26C60C, size = 0x800,  lz = true },  -- sWirelessSignalTilemap
    pokeballPal    = { at = 0x26205C, size = 0x20 },               -- sPokeball_Pal
    pokeballGfx    = { at = 0x26207C, size = 0x600 },              -- sPokeball_Gfx
    gbaPal         = { at = 0x26499C, size = 0x20 },               -- sGba_Pal
    linkMonPal     = { at = 0x2649FC, size = 0x20 },               -- sLinkMon_Pal
    glowGfx        = { at = 0x264A1C, size = 0x200 },              -- sLinkMonGlow_Gfx
    shadowGfx      = { at = 0x264C1C, size = 0x200 },              -- sLinkMonShadow_Gfx
    gbaScreenGfx   = { at = 0x26501C, size = 0x1000 },             -- sGbaScreen_Gfx
    shadowCycle    = { at = 0x26CF60, size = 0x18 },               -- sLinkMonShadow_Pal
    velocity       = { at = 0x26D1E4, size = 0x6C },               -- sTradeBallVerticalVelocityTable
    signalParams   = { at = 0x26D250, size = 0x42 },               -- sWirelessSignalAnimParams
    ballGfx        = { at = 0xD01724, size = 384,    lz = true },  -- gBallGfx_Poke
    ballPal        = { at = 0xD017E0, size = 0x20,   lz = true },  -- gBallPal_Poke
    particleGfx    = { at = 0xD1A608, size = 0x100,  lz = true },  -- gBattleAnimSpriteGfx_Particles
    particlePal    = { at = 0xD1A6DC, size = 0x20,   lz = true },  -- gBattleAnimSpritePal_CircleImpact
    ballFadeColors = { at = 0x40C1C4, size = 0x18 },               -- sBallOpenFadeColors
    sine           = { at = 0x25E074, size = 0x280 },              -- gSineTable
    speciesInfo    = 0x254784,                                     -- gSpeciesInfo
    text = {
      sending  = 0x41E1E9,
      goodbye  = 0x41E200,
      arrived  = 0x41E20D,
      takeCare = 0x41E21E,
    },
    -- trade_scene.c DrawTextOnTradeWindow: (..., 0, 2, 0, 2, ...) -- the
    -- same origin as Emerald's and two more pixels between the lines, over
    -- FireRed's shorter FONT_NORMAL (new_menu_helpers.c: 14 tall), which
    -- lands the second line on the same row Emerald's does
    textLayout = { x = 0, y = 2, letterSpacing = 0, lineSpacing = 2,
                   maxLetterHeight = 14 },
    sounds = { BALL_OPEN = 15, WARP_IN = 39, WARP_OUT = 40,
               BALL_BOUNCE_1 = 49, BALL_BOUNCE_2 = 50, BALL_BOUNCE_3 = 51,
               BALL_BOUNCE_4 = 52, BALL_TRADE = 53, M_MEGA_KICK = 133,
               M_SAND_ATTACK = 152, M_SWAGGER2 = 187, M_HEAL_BELL = 188,
               M_MINIMIZE = 197 },
    releaseAnimates = false,
  },
}

-- the cartridge's own header: game code at 0xAC, software version at 0xBC
function Gen3TradeArt.romKey(rom)
  local ok, key = pcall(function()
    local code = {}
    for i = 0, 3 do code[#code + 1] = string.char(rom:u8(0xAC + i)) end
    return table.concat(code) .. tostring(rom:u8(0xBC))
  end)
  return ok and key or nil
end

-- ---------------------------------------------------------------------------
-- reading, with the checks the header comment promises
-- ---------------------------------------------------------------------------

local function blob(rom, spec, name)
  if spec.lz then
    local ok, data, err = pcall(rom.lz77, rom, spec.at)
    if not ok or type(data) ~= "table" then
      return nil, ("%s at %07X is not LZ77 (%s)"):format(name, spec.at,
                                                          tostring(err or data))
    end
    if #data ~= spec.size then
      return nil, ("%s at %07X decompresses to %d bytes, expected %d")
        :format(name, spec.at, #data, spec.size)
    end
    return data
  end
  local ok, data = pcall(rom.bytes, rom, spec.at, spec.size)
  if not ok or type(data) ~= "table" or #data ~= spec.size then
    return nil, ("%s at %07X is past the end of the ROM"):format(name, spec.at)
  end
  return data
end

-- BGR555 words, every one with bit 15 clear
local function words(bytes, name)
  local out = {}
  for i = 1, #bytes - 1, 2 do
    local w = bytes[i] + bytes[i + 1] * 256
    if w >= 0x8000 then
      return nil, ("%s: entry %d is %04X, not a BGR555 colour"):format(
        name, (i - 1) / 2, w)
    end
    out[#out + 1] = w
  end
  return out
end

local function signed16(lo, hi)
  local v = lo + hi * 256
  return v >= 0x8000 and v - 0x10000 or v
end

-- A text-mode tilemap: every entry must name a tile the char block holds
-- and a palette bank that is loaded.  Returns the highest bank used.
local function checkTextMap(map, tileCount, maxBank, name)
  local top = 0
  for i = 1, #map - 1, 2 do
    local e = map[i] + map[i + 1] * 256
    local tile, bank = e % 1024, math.floor(e / 4096)
    if tile >= tileCount then
      return nil, ("%s: entry %d names tile %d of %d"):format(
        name, (i - 1) / 2, tile, tileCount)
    end
    if tile ~= 0 and bank > maxBank then
      return nil, ("%s: entry %d uses palette bank %d (only 0-%d are loaded)")
        :format(name, (i - 1) / 2, bank, maxBank)
    end
    if tile ~= 0 and bank > top then top = bank end
  end
  return top
end

-- ---------------------------------------------------------------------------
-- index images
-- ---------------------------------------------------------------------------

local function setIndex(img, x, y, index, opaque)
  if opaque then
    img:setPixel(x, y, index / 255, 0, 0, 1)
  else
    img:setPixel(x, y, 0, 0, 0, 0)
  end
end

-- A 4bpp text background, GBA screenblock order: a 512-wide map is two
-- 32x32 blocks side by side, a 512-tall one two stacked -- which is the same
-- formula: block = floor(tx/32) + floor(ty/32) * (width/32).
local function textLayer(map, tiles, cols, rows)
  local img = ImageWriter.blank(cols * 8, rows * 8)
  local across = math.floor(cols / 32)
  for ty = 0, rows - 1 do
    for tx = 0, cols - 1 do
      local block = math.floor(tx / 32) + math.floor(ty / 32) * across
      local cell = block * 1024 + (ty % 32) * 32 + (tx % 32)
      local lo, hi = map[cell * 2 + 1], map[cell * 2 + 2]
      if lo and hi then
        local e = lo + hi * 256
        local tile = e % 1024
        local hflip = math.floor(e / 1024) % 2 == 1
        local vflip = math.floor(e / 2048) % 2 == 1
        local bank = math.floor(e / 4096)
        for y = 0, 7 do
          for x = 0, 7 do
            local sx = hflip and (7 - x) or x
            local sy = vflip and (7 - y) or y
            local b = tiles[tile * 32 + sy * 4 + math.floor(sx / 2) + 1] or 0
            local pix = (sx % 2 == 0) and (b % 16) or math.floor(b / 16)
            setIndex(img, tx * 8 + x, ty * 8 + y, bank * 16 + pix, pix ~= 0)
          end
        end
      end
    end
  end
  return img
end

-- The affine GBA: a 16x16 byte map of 8bpp tiles, 128x128 pixels
local function affineLayer(map, tiles)
  local img = ImageWriter.blank(128, 128)
  for ty = 0, 15 do
    for tx = 0, 15 do
      local tile = map[ty * 16 + tx + 1]
      for y = 0, 7 do
        for x = 0, 7 do
          local v = tiles[tile * 64 + y * 8 + x + 1] or 0
          setIndex(img, tx * 8 + x, ty * 8 + y, v, v ~= 0)
        end
      end
    end
  end
  return img
end

-- A 4bpp OBJ sheet in 1D mapping: `frames` frames of w x h, each made of
-- (w/8)*(h/8) consecutive tiles starting at frame * tilesPerFrame, stacked
-- down the image.  Pixel = 0..15, alpha 0 for colour 0.
local function objSheet(tiles, w, h, frames, firstTiles)
  local tw, th = w / 8, h / 8
  local img = ImageWriter.blank(w, h * frames)
  for f = 0, frames - 1 do
    local first = firstTiles and firstTiles[f + 1] or f * tw * th
    for t = 0, tw * th - 1 do
      local tile = first + t
      local ox, oy = (t % tw) * 8, f * h + math.floor(t / tw) * 8
      for y = 0, 7 do
        for x = 0, 7 do
          local b = tiles[tile * 32 + y * 4 + math.floor(x / 2) + 1] or 0
          local pix = (x % 2 == 0) and (b % 16) or math.floor(b / 16)
          setIndex(img, ox + x, oy + y, pix, pix ~= 0)
        end
      end
    end
  end
  return img
end

-- ---------------------------------------------------------------------------
-- THE STAGE.  `x` is a RomExtractorGen3; it supplies the ROM, the text
-- decoder, the species table and the two writers.
-- ---------------------------------------------------------------------------
function Gen3TradeArt.extract(x)
  local rom = x.rom
  local key = Gen3TradeArt.romKey(rom)
  local mapped = x.manifest and x.manifest.tradeArt
  local T = mapped and mapped.romKey == key and mapped or key and Gen3TradeArt.ROMS[key]
  if not T then
    Logger.warn("gen3 trade art: no address table for cartridge %s -- in-game "
                  .. "trades keep the bare swap", tostring(key))
    return nil
  end
  local function fail(why)
    Logger.warn("gen3 trade art (%s): %s -- skipped, in-game trades keep the "
                  .. "bare swap", key, tostring(why))
    return nil
  end

  -- ---- read every blob ---------------------------------------------------
  local B = {}
  for _, name in ipairs({ "textboxTiles", "textboxPal", "textboxMap",
                          "gba2Pal", "gbaGfx", "platformMap", "affineGfx",
                          "affineMap", "gbaMap", "closeupMap",
                          "signalSendPal", "signalRecvPal", "signalNonePal",
                          "signalGfx", "signalMap", "pokeballPal",
                          "pokeballGfx", "gbaPal", "linkMonPal", "glowGfx",
                          "shadowGfx", "gbaScreenGfx", "shadowCycle",
                          "velocity", "signalParams", "ballGfx", "ballPal",
                          "particleGfx", "particlePal", "ballFadeColors",
                          "sine" }) do
    local data, err = blob(rom, T[name], name)
    if not data then return fail(err) end
    B[name] = data
  end

  -- ---- palettes ------------------------------------------------------------
  local P = {}
  for _, name in ipairs({ "textboxPal", "gba2Pal", "signalSendPal",
                          "signalRecvPal", "signalNonePal", "pokeballPal",
                          "gbaPal", "linkMonPal", "shadowCycle", "ballPal",
                          "particlePal", "ballFadeColors" }) do
    local w, err = words(B[name], name)
    if not w then return fail(err) end
    P[name] = w
  end
  -- LoadCompressedPalette(gBattleTextboxPalette, BG_PLTT_ID(0),
  -- PLTT_SIZE_4BPP): only the first bank of the two the blob holds
  local textboxPal = {}
  for i = 1, 16 do textboxPal[i] = P.textboxPal[i] end

  -- ---- tilemaps ------------------------------------------------------------
  local textboxTiles = #B.textboxTiles / 32
  local gbaTiles = #B.gbaGfx / 32
  local signalTiles = #B.signalGfx / 32
  -- only the 32x32 BG0 shows (CopyToBgTilemapBuffer(0, ..., BG_SCREEN_SIZE)):
  -- the action and move panels further down use bank 1 and never appear
  local shownBox = {}
  for i = 1, 0x800 do shownBox[i] = B.textboxMap[i] end
  local ok, err = checkTextMap(shownBox, textboxTiles, 0, "textbox map")
  if not ok then return fail(err) end
  for _, row in ipairs({ { "platformMap", gbaTiles }, { "gbaMap", gbaTiles },
                         { "closeupMap", gbaTiles },
                         { "signalMap", signalTiles } }) do
    ok, err = checkTextMap(B[row[1]], row[2], 3, row[1])
    if not ok then return fail(err) end
  end
  local affineTiles = #B.affineGfx / 64
  for i, t in ipairs(B.affineMap) do
    if t >= affineTiles then
      return fail(("affine map cell %d names tile %d of %d"):format(
        i - 1, t, affineTiles))
    end
  end

  -- ---- tables --------------------------------------------------------------
  local velocity = {}
  for i, b in ipairs(B.velocity) do
    local v = b >= 128 and b - 256 or b
    if v < -4 or v > 4 then
      return fail(("bounce table entry %d is %d"):format(i - 1, v))
    end
    velocity[i] = v
  end
  -- sWirelessSignalAnimParams: { palette step, frames } pairs ending on a
  -- 0xFF frame count -- the sentinel Task_AnimateWirelessSignal stops on
  local params, ended = {}, false
  for i = 1, #B.signalParams - 1, 2 do
    local step, frames = B.signalParams[i], B.signalParams[i + 1]
    params[#params + 1] = { step, frames }
    if frames == 0xFF then ended = true break end
    if step > 16 then
      return fail(("signal step %d names palette %d"):format(#params, step))
    end
  end
  if not ended then return fail("the signal table has no 0xFF sentinel") end
  local sine = {}
  for i = 1, #B.sine - 1, 2 do
    sine[#sine + 1] = signed16(B.sine[i], B.sine[i + 1])
  end
  if not (sine[1] == 0 and sine[65] == 256 and sine[129] == 0
          and sine[193] == -256) then
    return fail("gSineTable does not read 0/256/0/-256 at 0/64/128/192")
  end

  -- ---- the four sentences --------------------------------------------------
  local text = {}
  for role, at in pairs(T.text) do
    local okT, s = pcall(x.readText, x, at, 64)
    if not (okT and type(s) == "string" and s:find("{VAR%d}")) then
      return fail(("the %s line at %07X does not decode with a placeholder")
        :format(role, at))
    end
    text[role] = s
  end

  -- ---- noFlip, out of gSpeciesInfo -------------------------------------------
  -- SpeciesInfo is 28 bytes; byte 0x19 is bodyColor:7 / noFlip:1.  The
  -- manifest's own structurally found gBaseStats has to be the same table.
  local manifestBase = x.symbol and x:symbol("gBaseStats")
  if manifestBase and manifestBase ~= T.speciesInfo then
    return fail(("gSpeciesInfo %07X is not the manifest's gBaseStats %07X")
      :format(T.speciesInfo, manifestBase))
  end
  local noFlip, flipped = {}, 0
  for id, def in pairs(x._pokemon or {}) do
    local idx = type(def) == "table" and tonumber(def.index)
    if idx and idx > 0 then
      local okB, b = pcall(rom.u8, rom, T.speciesInfo + idx * 28 + 0x19)
      if okB and b >= 128 then noFlip[id] = true; flipped = flipped + 1 end
    end
  end

  -- ---- the pictures ----------------------------------------------------------
  local images = {}
  local okImg, imgErr = pcall(function()
    local function save(name, img)
      x:saveImage(img, "trade/" .. name .. ".png")
      images[name] = "assets/generated/trade/" .. name .. ".png"
    end
    -- BG0: the battle text box's 32x32 map (BG_SCREEN_SIZE of the 32x64)
    save("bg_textbox", textLayer(shownBox, B.textboxTiles, 32, 32))
    -- BG2 text 512x256: the platform
    save("bg_platform", textLayer(B.platformMap, B.gbaGfx, 64, 32))
    -- BG1 256x512: the wireless GBA strip
    save("bg_gba", textLayer(B.gbaMap, B.gbaGfx, 32, 64))
    -- BG1 after SetTradeSequenceBgGpuRegs(2): the closeup LZ77s over the
    -- first screenblock only, the second keeps the GBA strip's bottom half
    local close = {}
    for i = 1, 0x1000 do close[i] = B.closeupMap[i] or B.gbaMap[i] end
    save("bg_closeup", textLayer(close, B.gbaGfx, 32, 64))
    -- BG2 256x512 after (3): the signal rings
    save("bg_signal", textLayer(B.signalMap, B.signalGfx, 32, 64))
    -- BG2 affine 128x128, 8bpp
    save("bg_affine", affineLayer(B.affineMap, B.affineGfx))
    -- OBJ sheets
    save("obj_pokeball", objSheet(B.pokeballGfx, 16, 16, 12))
    save("obj_glow", objSheet(B.glowGfx, 32, 32, 1))
    -- sAnims_LinkMonShadow: tile 0 (big) and tile 8 (small)
    save("obj_shadow", objSheet(B.shadowGfx, 16, 32, 2, { 0, 8 }))
    -- sAnim_GbaScreen_*: tiles 0, 32, 64, 96
    save("obj_gbascreen", objSheet(B.gbaScreenGfx, 64, 32, 4))
    -- gBallGfx_Poke: three 16x16 frames at tiles 0, 4, 8 -- the third is
    -- left as the cartridge ships it (see Gen3TradeAnim on the open ball)
    save("obj_ball", objSheet(B.ballGfx, 16, 16, 3))
    -- the eight 8x8 particles
    save("obj_particles", objSheet(B.particleGfx, 8, 8, 8))
  end)
  if not okImg then return fail(imgErr) end

  local record = {
    key = key,
    version = T.version,
    images = images,
    palettes = {
      textbox = textboxPal,
      gba2 = P.gba2Pal,
      signalSend = P.signalSendPal,
      signalRecv = P.signalRecvPal,
      signalNone = P.signalNonePal,
      pokeball = P.pokeballPal,
      gba = P.gbaPal,
      linkMon = P.linkMonPal,
      linkMonShadow = P.shadowCycle,
      ball = P.ballPal,
      particles = P.particlePal,
    },
    -- BALL_POKE's colour, the first of gBallOpenFadeColors
    ballFadeColor = P.ballFadeColors[1],
    velocity = velocity,
    signalParams = params,
    sine = sine,
    noFlip = noFlip,
    text = text,
    textLayout = T.textLayout,
    sounds = T.sounds,
    releaseAnimates = T.releaseAnimates,
    source = ("ROM %s: trade.c / trade_scene.c wireless assets at %07X.., "
              .. "battle text box %07X, ball %07X; %d noFlip species")
             :format(key, T.platformMap.at, T.textboxTiles.at, T.ballGfx.at,
                     flipped),
  }
  x:write("gen3_trade_art", record)
  Logger.info("Gen3 trade art: %s -- %d pictures, %d palettes, %d bounce "
                .. "steps, %d signal steps, %d species never flipped",
              key, 12, 11, #velocity, #params, flipped)
  return record
end

return Gen3TradeArt
