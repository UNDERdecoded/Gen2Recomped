-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's Pokedex entry page.
--
-- THE GAME BOY PAGE COULD NOT SHOW THIS DATA AT ALL, and that is a shape
-- difference rather than a styling one.  DexEntryMenu reads `def.dexEntry` as
-- a TABLE -- {kind, heightFt, heightIn, weight, text} -- because that is what
-- the Gen 1 and Gen 2 extractors build.  A Gen 3 species row carries the
-- flavour text itself in `dexEntry`, the species name in `category`, and the
-- height and weight as plain metres and kilograms.  Indexing a string for
-- `.kind` is not an error in Lua, it is nil, so the Hoenn page drew the name,
-- a question mark, and "Data unknown." under it -- for every Pokemon in the
-- game.
--
-- HEIGHT AND WEIGHT ARE IMPERIAL, and the arithmetic is the cartridge's, not
-- a conversion factor picked here.  pokedex.c rounds in a specific way:
--
--     PrintMonHeight:  inches = height * 10000 / 254, round half up on the
--                      last digit, then feet = inches / 120
--     PrintMonWeight:  lbs = weight * 100000 / 4536, rounded the same way
--
-- where `height` is in decimetres and `weight` in hectograms -- which is how
-- the ROM stores them, and what this dataset's metres and kilograms are ten
-- times.  Done with a plain 2.54 and 2.2046 the last digit disagrees with the
-- cartridge on a good fraction of the dex.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3DexEntry = {}
Gen3DexEntry.__index = Gen3DexEntry
Gen3DexEntry.isOpaque = true

-- THE SCREEN THIS PAGE IS DRAWN ON.
--
-- Reported from play: "the pokedex screen that appears is off of the screen".
-- Every number below is a Hoenn one -- a 30-tile entry box, a picture at 6,6,
-- three rows of facts starting 88 pixels across -- and without this the
-- surface it lands on is the Game Boy's 160x144, so the renderer scales a
-- 240-wide page up to fill it and everything right of about tile 20 leaves
-- the screen.  Nineteen other Gen 3 screens say this; four did not, and all
-- four overflowed the same way.
--
-- ...AND THE DECLARATION HAS TO COME FIRST.  Reported from play a second
-- time: "when i select a pokemon its cutting off part of the pokedex entry".
-- It was still cut off, because `local GBA_W, GBA_H` sat BELOW this function
-- -- a local is only in scope after its declaration, so the body read two
-- GLOBALS, got nil twice, and the caller fell straight back to the Game Boy's
-- 160x144.  The fix looked right in the diff and did nothing at all.
local GBA_W, GBA_H = 240, 160

function Gen3DexEntry:uiSize() return GBA_W, GBA_H end

-- RECONSTRUCTED geometry; the shape is the cartridge's -- picture on the
-- left, the four facts beside it, the entry across the bottom.
local PIC = { x = 6, y = 6, w = 64, h = 64 }
local INFO = { tx = 9, ty = 0, tw = 21, th = 9 }
local INFO_X = 88
local INFO_ROW = { 10, 28, 46 }
local TEXT = { tx = 0, ty = 9, tw = 30, th = 9 }
local TEXT_TOP, TEXT_STEP, TEXT_LINES = 78, 14, 4
-- what the entry keeps under itself, because the surface loses its last rows
local DESC_MARGIN = 6

-- The side of a Pokemon picture's OBJ frame.  Every front pic the import
-- writes is this square, because the cartridge's own buffer is.
local MON_FRAME = 64

-- WHAT THE ENTRY IS PRINTED IN.
--
-- Reported from play, with a picture: "i think the pokedex reading on a
-- pokemon isnt supposed to be like this".  The description sits on the dark
-- window in the bottom half of the page, and the page's glyphs are drawn dark
-- with a light shadow -- which reads correctly on the white panel above and
-- upside down on the navy below, where the SHADOW is what you see and the
-- letter disappears into the ground.
--
-- PrintInfoScreenText hands the printer a colour triple of its own for
-- exactly this reason: transparent ground, a light letter, a darker shadow.
-- So the entry -- and only the entry -- is restated in those two tones.
local DESC_INK = { 1, 1, 1 }
local DESC_SHADOW = { 0.22, 0.25, 0.36 }
local MENU_Y = 146

local function resolveSpecies(arg)
  if type(arg) == "table" then
    return arg.species or arg[1], arg.forceOwned and true or false
  end
  return arg, false
end

-- pokedex.c PrintMonHeight, in decimetres.
function Gen3DexEntry.feetInches(decimetres)
  local inches = math.floor((decimetres * 10000) / 254)
  if inches % 10 >= 5 then inches = inches + 10 end
  local feet = math.floor(inches / 120)
  return feet, math.floor((inches - feet * 120) / 10)
end

-- pokedex.c PrintMonWeight, in hectograms.
function Gen3DexEntry.pounds(hectograms)
  local lbs = math.floor((hectograms * 100000) / 4536)
  if lbs % 10 >= 5 then lbs = lbs + 10 end
  return math.floor(lbs / 100), math.floor(lbs / 10) % 10
end

-- The listing number this page shows: Hoenn's before the upgrade, the
-- national one after it, which is the same rule the list screen follows.
function Gen3DexEntry.number(game, species)
  local data = game and game.data or {}
  local def = (data.pokemon or {})[species]
  local record = (data.constants or {}).gen3HoennDex
  local national = game.save and game.save.nationalDex
  if record and type(record.numbers) == "table" and not national then
    local n = record.numbers[species]
    if n and n <= (tonumber(record.native) or 0) then return n end
  end
  return def and tonumber(def.dex) or 0
end

function Gen3DexEntry.new(game, arg)
  local species, forceOwned = resolveSpecies(arg)
  -- the cursor opens on CRY, which is where the cartridge leaves it
  local self = setmetatable({ game = game, species = species,
                              forceOwned = forceOwned, cursor = 2 },
                            Gen3DexEntry)
  self.def = (game.data.pokemon or {})[species]
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, species, "front", { kind = "dex" })
  if path then
    local ok, img = pcall(love.graphics.newImage, path)
    self.pic = ok and img or nil
    self.picTrueColor = self.pic and trueColor and true or false
  end
  Sound.playCry(game.data, species)
  return self
end

function Gen3DexEntry:owned()
  local dex = self.game.save and self.game.save.pokedex
  return self.forceOwned or (dex and dex.owned[self.species]) and true or false
end

-- THE FOUR THINGS THE PAGE CAN DO, which the cartridge draws as ART.
--
-- Reported from play: "the pages of the pokedex listing for area, cry and
-- size arent working".  They were not there to work: the page offered CRY and
-- CANCEL in its own words, and the bar the import now rips across the top of
-- the screen says AREA / CRY / SIZE / CANCEL in tiles.  The words come from
-- the picture; what is added here is the four boxes they sit in -- measured
-- off that picture -- and what each one does.
local BUTTONS = { { key = "area", x = 13 }, { key = "cry", x = 69 },
                  { key = "size", x = 125 }, { key = "cancel", x = 180 } }
local BUTTON = { y = 2, w = 46, h = 13, cancelW = 58 }

function Gen3DexEntry:menu()
  if self:screen() then return BUTTONS end
  return { Strings("CRY"), Strings("CANCEL") }
end

-- WHAT THE POKEMON LOOKS LIKE NEXT TO YOU.
--
-- The SIZE page is not another screen: the cartridge keeps the same
-- background and puts two more sprites on it -- the trainer at 88 and the
-- Pokemon at 152, both on the same line -- each posed by its own scale and
-- offset out of the dex entry.  A GBA affine scale is a DIVISOR, so 256 is
-- life size and a bigger number draws smaller; that is why a WAILORD leaves
-- the trainer at 1352 and stands at 256 himself.
local SIZE_PAGE = { trainer = { x = 88, y = 56 }, mon = { x = 152, y = 56 },
                    lifeSize = 256 }

function Gen3DexEntry:trainerPic()
  if self.sizeTrainer ~= nil then return self.sizeTrainer or nil end
  self.sizeTrainer = false
  local record = (self.game.data.constants or {}).gen3TrainerBack
  local which = record and record.playerFront
  if type(which) ~= "table" then return nil end
  local player = (self.game.save or {}).player or {}
  local index = (player.gender == "girl" and which.girl) or which.boy
  if not index then return nil end
  local ok, img = pcall(require("src.render.Assets").image,
                        ("assets/generated/battle/trainers/%03d.png")
                        :format(index))
  if ok and img then self.sizeTrainer = img end
  return self.sizeTrainer or nil
end

local function posed(img, place, scale, offset)
  if not img then return end
  local w, h = img:getDimensions()
  local s = SIZE_PAGE.lifeSize / math.max(1, tonumber(scale) or 256)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, place.x - w * s / 2,
                     place.y - h * s / 2 + (tonumber(offset) or 0), 0, s, s)
end

function Gen3DexEntry:update()
  local input = self.game.input
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    -- B backs out of the SIZE page first, exactly as it does on the
    -- cartridge: the page is part of this screen, not a screen of its own
    if self.sizePage then self.sizePage = nil return end
    self.game.stack:pop()
    return
  end
  local menu = self:menu()
  if input:wasPressed("left") then
    self.cursor = (self.cursor - 2) % #menu + 1
  elseif input:wasPressed("right") then
    self.cursor = self.cursor % #menu + 1
  elseif input:wasPressed("a") then
    local row = menu[self.cursor]
    local key = (type(row) == "table" and row.key)
                or (self.cursor == 1 and "cry") or "cancel"
    if key == "cry" then
      Sound.playCry(self.game.data, self.species)
    elseif key == "size" then
      -- the same screen with two more sprites on it, which is what the
      -- cartridge does: no page change, no load
      Sound.play(self.game.data, "Press_AB")
      self.sizePage = not self.sizePage
    elseif key == "area" then
      Sound.play(self.game.data, "Press_AB")
      -- WHERE IT LIVES.
      --
      -- Reported from play: "im not seeing any pokemons area in the area
      -- pokedex menu".  The button opened the region map and stopped there,
      -- because nothing had worked out where the Pokemon lives; the map is
      -- now opened in AREA mode, which lights the sections its encounter
      -- rows put it in and names them.
      local ok, Screens = pcall(require, "src.ui.Screens")
      if ok and Screens and Screens.push then
        pcall(Screens.push, self.game, "Gen3RegionMap",
              { area = { species = self.species } })
      end
    else
      Sound.play(self.game.data, "Press_AB")
      self.game.stack:pop()
    end
  end
end

local function lines(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for line in ((text:gsub("\v", "\n"):gsub("\f", "\n")) .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

-- THE SCREEN EMERALD DRAWS THIS ON.
--
-- Reported from play, with a picture: "The pokedex still needs a lot of work
-- before it matches what it looks like in emerald its missing a lot of the
-- emerald art".  It was missing all of it: a flat blue rectangle with the
-- engine's generic window frames on top.  What the cartridge draws is a
-- composed picture -- a green striped ground, a white panel with a grey inner
-- screen, a second panel below it, and a bar across the top reading AREA /
-- CRY / SIZE / CANCEL.  Those four words are TILES, not text, which is why a
-- page that draws only text could never show them.
--
-- The import rips it (extractPokedexScreen) and this draws it.  A cache from
-- before that stage keeps the old reconstruction rather than a blank screen.
function Gen3DexEntry:screen()
  local record = (self.game.data.constants or {}).gen3PokedexScreen
  if type(record) ~= "table" then return nil end
  return record
end

local function screenImage(record, national)
  local images = record and record.images
  if type(images) ~= "table" then return nil end
  -- THE NATIONAL DEX IS A DIFFERENT COLOUR.  LoadPokedexBgPalette branches on
  -- it, which is the whole reason the cartridge carries three palettes for
  -- one picture: finishing Hoenn repaints this screen.
  local path = (national and images.national) or images.hoenn
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  return ok and img or nil
end

function Gen3DexEntry:draw()
  local def = self.def
  local record = self:screen()
  local national = self.game.save and self.game.save.nationalDex
  local bg = screenImage(record, national)
  local place = record and record.text
  love.graphics.setColor(1, 1, 1, 1)
  if bg then
    love.graphics.draw(bg, 0, 0)
    require("src.render.PaletteFX").markTrueColor(0, 0, GBA_W, GBA_H)
  else
    love.graphics.setColor(0.30, 0.44, 0.64, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
  if not def then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- ...AND THE SIZE PAGE, which is this same screen with two more sprites on
  -- it and none of the text.
  if self.sizePage and record then
    local pose = def.dexPose or {}
    posed(self:trainerPic(), SIZE_PAGE.trainer, pose.trainerScale,
          pose.trainerOffset)
    posed(self.pic, SIZE_PAGE.mon, pose.monScale, pose.monOffset)
    self:drawButtons(record)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- ...and the Pokemon itself, where the cartridge puts it: a GBA sprite's
  -- position is its CENTRE, so the picture's corner is that minus half of it.
  if self.pic then
    local w, h = self.pic:getDimensions()
    local x, y
    if record and record.mon then
      -- A GBA SPRITE IS ITS FRAME, NOT ITS PIXELS.
      --
      -- Reported from play: "their image is in the wrong spot when scrolling
      -- through the pokemon".  This centred each picture by ITS OWN width, so
      -- a species whose art sits high or low in the frame landed somewhere
      -- different from the one before it -- and the cartridge does no such
      -- thing.  Every mon pic is a 64x64 OBJ whose centreToCorner is
      -- (-32,-32), so the FRAME's corner is the position minus thirty-two,
      -- whatever the art inside it does.  The half-width fallback is only for
      -- a dataset whose pictures are not the cartridge's own frame.
      local half = (w == MON_FRAME and h == MON_FRAME)
                   and (MON_FRAME / 2) or nil
      x = math.floor(record.mon.x - (half or w / 2))
      y = math.floor(record.mon.y - (half or h / 2))
    else
      x = PIC.x + math.floor((PIC.w - w) / 2)
      y = PIC.y + math.floor((PIC.h - h) / 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.pic, x, y)
    if self.picTrueColor then
      require("src.render.PaletteFX").markTrueColor(x, y, w, h)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  if not place then
    -- the old reconstruction, for a cache with no screen in it
    Font.drawBox(INFO.tx, INFO.ty, INFO.tw, INFO.th)
    Font.drawBox(TEXT.tx, TEXT.ty, TEXT.tw, TEXT.th)
  end
  local at = place or {
    number = { x = INFO_X, y = INFO_ROW[1] },
    name = { x = INFO_X + 64, y = INFO_ROW[1] },
    category = { x = INFO_X, y = INFO_ROW[2] },
    heightLabel = { x = INFO_X, y = INFO_ROW[3] },
    weightLabel = { x = INFO_X + 80, y = INFO_ROW[3] },
    height = { x = INFO_X + 24, y = INFO_ROW[3] },
    weight = { x = INFO_X + 104, y = INFO_ROW[3] },
    description = { y = TEXT_TOP },
  }

  local n = Gen3DexEntry.number(self.game, self.species)
  Font.draw(("No.%03d"):format(n), at.number.x, at.number.y)
  Font.draw(def.name or self.species, at.name.x, at.name.y)
  -- "SEED POKeMON": the category is the cartridge's; the noun after it is the
  -- screen's own word for what is being categorised
  Font.draw((def.category or "") .. " " .. Strings("POKéMON"),
            at.category.x, at.category.y)

  local owned = self:owned()
  Font.draw(Strings("HT"), at.heightLabel.x, at.heightLabel.y)
  Font.draw(Strings("WT"), at.weightLabel.x, at.weightLabel.y)
  if owned then
    local feet, inches = Gen3DexEntry.feetInches(
      math.floor((tonumber(def.height) or 0) * 10 + 0.5))
    local whole, tenth = Gen3DexEntry.pounds(
      math.floor((tonumber(def.weight) or 0) * 10 + 0.5))
    Font.draw(("%d'%02d\""):format(feet, inches), at.height.x, at.height.y)
    Font.draw(("%d.%d lbs"):format(whole, tenth), at.weight.x, at.weight.y)
  else
    -- the cartridge prints its own placeholders rather than nothing, so the
    -- box does not look broken for a Pokemon you have only SEEN
    Font.draw("???'??\"", at.height.x, at.height.y)
    Font.draw("????.? lbs", at.weight.x, at.weight.y)
  end

  -- THE ENTRY, centred line by line, which is what the cartridge does with it
  -- (GetStringCenterAlignXOffset against the whole 240).
  if owned then
    local rows = lines(def.dexEntry)
    while #rows > TEXT_LINES do table.remove(rows) end
    local y = at.description.y
    local step = TEXT_STEP
    if at.description.centred then
      step = math.floor(tonumber(record and record.line) or 16)
      -- ...AND THE LAST LINE HAS TO BE ON THE SCREEN.
      --
      -- Reported from play, with a picture: the fourth line of a four-line
      -- entry was cut in half by the bottom edge.  The cartridge's own y is
      -- 95 and four lines of sixteen from there END exactly at 160 -- there
      -- is no room at all, and this port's surface loses the last few rows to
      -- its own letterbox, so the line that has none to spare is the one that
      -- goes.
      --
      -- So the block keeps a few pixels under it and is lifted only by
      -- however much it needs: a two- or three-line entry never moves, and a
      -- four-line one comes up five.  Deliberately not a different pitch --
      -- the spacing is the cartridge's and stays the cartridge's.
      local bottom = y + #rows * step
      local floor_ = GBA_H - DESC_MARGIN
      if bottom > floor_ then y = y - (bottom - floor_) end
    end
    local toned = at.description.centred
                  and Font.beginTwoTone(DESC_INK, DESC_SHADOW)
    for i, line in ipairs(rows) do
      local x = 8
      if at.description.centred then
        -- GetStringCenterAlignXOffset(1, str, 240): every line is centred
        -- across the whole screen, not left-aligned in a box
        x = math.floor((GBA_W - Font.width(line)) / 2)
      end
      Font.draw(line, x, y + (i - 1) * step)
    end
    if toned then Font.endTwoTone() end
  end

  -- ...and the four things the page can do.  With the cartridge's own bar on
  -- screen the words are already drawn, so only the selection is this page's
  -- to show.
  if place then
    self:drawButtons(record)
  else
    local menu = self:menu()
    local mx = 16
    for i, label in ipairs(menu) do
      if i == self.cursor then Font.drawCode(Theme.cursor, mx - 8, MENU_Y) end
      Font.draw(label, mx, MENU_Y)
      mx = mx + Font.width(label) + 32
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The selection on the ripped bar: an outline round the box the art already
-- draws, because the words in it are tiles and redrawing them as text would
-- put a second copy on top in a different font.
function Gen3DexEntry:drawButtons(record)
  if not record then return end
  local row = BUTTONS[self.cursor]
  if not row then return end
  local w = (row.key == "cancel") and BUTTON.cancelW or BUTTON.w
  love.graphics.setColor(1, 0.92, 0.30, 1)
  love.graphics.rectangle("line", row.x - 1.5, BUTTON.y - 1.5,
                          w + 3, BUTTON.h + 3)
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3DexEntry
