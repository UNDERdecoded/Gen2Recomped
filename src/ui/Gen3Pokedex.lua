-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's Pokedex, the listing screen.
--
-- HOENN HAS ITS OWN NUMBERING and that is the whole reason this screen exists
-- separately from the Game Boy one.  A new Emerald game opens the dex on
-- TREECKO at #001; the national numbers are not shown at all until
-- gSpecials[499] upgrades the dex, and TREECKO's national number is 252.  The
-- Game Boy screen lists by `def.dex`, which IS the national number, so on a
-- Hoenn cache it opened on BULBASAUR -- a Pokemon that does not exist in the
-- region -- and buried the starter two hundred and fifty rows down.
--
-- WHAT COMES OFF THE CARTRIDGE: the listing itself
-- (constants.gen3HoennDex.numbers, read from sSpeciesToHoennPokedexNumber),
-- how many of its entries are natives, every name, and the seen/owned record.
--
-- WHAT IS RECONSTRUCTED: the geometry.  Emerald draws this screen from
-- background art this port has not located yet, so the panels are the
-- cartridge's own window frame at the positions below, and those numbers are
-- the part to correct against a screenshot.  The SHAPE is the cartridge's:
-- the list down the right, the selected Pokemon's picture on the left, and
-- the SEEN/OWN counts under it.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3Pokedex = {}
Gen3Pokedex.__index = Gen3Pokedex
Gen3Pokedex.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED geometry, in tiles where a box is drawn and in pixels where
-- something is placed inside one.  Used only when the dataset carries no
-- ripped screen; everything below MEASURED comes off the art instead.
local LIST = { tx = 12, ty = 0, tw = 18, th = 20 }
local ROW_X = LIST.tx * 8 + 16      -- past the cursor column
local ROW_TOP = 10
local ROW_H = 18
local ROWS = 8
local PIC = { x = 12, y = 16, w = 64, h = 64 }
local COUNTS = { tx = 0, ty = 11, tw = 12, th = 9 }

-- ...AND THE SAME SCREEN LAID OUT ON EMERALD'S OWN ART.
--
-- Reported from play, with a picture: the list was still a blue field with
-- the engine's window frames on it while the entry page behind it had already
-- become the cartridge's.  The import rips this screen now -- the POKeDEX
-- header, the dex's dark display on the left, the yellow list panel down the
-- right -- and the numbers below are measured off that picture: the panel
-- runs x 134..229, its rows are sixteen apart, and the selected one sits on
-- the white bar the art draws at y 70.
--
-- The Pokemon's own place is NOT measured: 48,56 is the cartridge's, out of
-- the task that creates the sprite (0BEC20), and it is the same pair the
-- entry page uses.
local ART = {
  -- WHERE THE LIST SCREEN PUTS THE POKEMON, which is not where the entry page
  -- puts it.
  --
  -- Reported from play: "their image is in the wrong spot when scrolling
  -- through the pokemon".  It was: 48,56 is the ENTRY page's sprite, and the
  -- list screen's own five CreateMonSpriteAtPos calls (0BD310, 0BD342,
  -- 0BD378, 0BD5EE, 0BD64E) every one of them pass 96,80 -- the middle of the
  -- pale panel, not the dark lens on the left.  The lens is where the COUNTS
  -- go, which is the other half of the same mistake.
  pic = { x = 96, y = 80 },
  rows = 8, rowTop = 6, rowHeight = 16,
  numberX = 140, nameX = 172, ballX = 136,
  -- the white bar the art draws is the fifth row down, so the cursor stays
  -- there and the list scrolls under it
  selected = 5,
  counts = { x = 66, y = 96 },
}
-- How far the scrollbar's handle slides: SpriteCB_Scrollbar (0BE62C) sets
-- pos2.y to `selected * 120 / (count - 1)`, so 120 is the whole travel.
local BAR_TRAVEL = 120

-- Emerald prints a row of dashes where a number has never been seen; ten of
-- them is the width of the longest name the cartridge has.
local UNSEEN = "----------"

-- The side of a Pokemon picture's OBJ frame, which is what the cartridge
-- positions rather than the pixels drawn inside it.
local MON_FRAME = 64

function Gen3Pokedex:uiSize() return GBA_W, GBA_H end
function Gen3Pokedex:wantsFillScale() return true end

function Gen3Pokedex:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- THE LISTING, which is not the same list in the two modes the dex has.
--
-- Before the upgrade it is Hoenn's own, #1..#202, and the number shown is the
-- Hoenn number.  Afterwards it is the national dex, and the number shown is
-- `def.dex`.  Both are read: the first out of gen3HoennDex, the second off
-- the species rows.
-- WHICH DEX IS BEING LISTED IS NOT THE SAME QUESTION AS WHICH ONE THE PLAYER
-- HAS.  The cartridge keeps both -- IsNationalPokedexEnabled is the upgrade,
-- sPokedexView->dexMode is the listing the SWITCH DEX row chose -- and a
-- player who owns the national dex and asks for the Hoenn listing has not
-- given the upgrade back.  `national` is that second one; without it the
-- upgrade answers, which is where a freshly opened dex starts.
function Gen3Pokedex.listing(game, national)
  local data = game and game.data or {}
  local constants = data.constants or {}
  local record = constants.gen3HoennDex
  if national == nil then national = game.save and game.save.nationalDex end
  local out = {}
  if record and type(record.numbers) == "table" and not national then
    local native = tonumber(record.native) or 0
    for id, n in pairs(record.numbers) do
      if n >= 1 and n <= native then out[n] = id end
    end
    local last = 0
    for n in pairs(out) do if n > last then last = n end end
    return out, last
  end
  local last = 0
  for id, def in pairs(data.pokemon or {}) do
    local n = tonumber(def.dex)
    if n and n >= 1 then
      out[n] = id
      if n > last then last = n end
    end
  end
  return out, last
end

function Gen3Pokedex.new(game, opts)
  local self = setmetatable({ game = game, opts = opts or {} }, Gen3Pokedex)
  self.dexMode = (game.save and game.save.nationalDex) and 2 or 1
  self.list, self.count = Gen3Pokedex.listing(game, self.dexMode >= 2)
  self.index = 1
  self.scroll = 0
  -- the spinner's angle, in the cartridge's 256ths of a turn
  self.spin = 0
  -- open on the first entry the player has actually seen, which is what the
  -- cartridge's own saved cursor amounts to on a fresh dex
  local dex = game.save and game.save.pokedex
  if dex then
    for n = 1, self.count do
      local id = self.list[n]
      if id and dex.seen[id] then
        self.index = n
        break
      end
    end
  end
  self:clampScroll()
  self:loadPic()
  return self
end

-- WHERE THE LISTING SITS UNDER THE SELECTED ROW.
--
-- Reported from play, with a picture: "the selector is offset ... mudkip is
-- highlighted but its not showing and hitting A does nothing but if i hit
-- down once it appears".  The white bar is NOT drawn by this file.  It is in
-- the art -- sixteen pixels tall at y 72, which is the fifth of the eight
-- rows -- and this was scrolling the list to put the selected entry on the
-- FOURTH.  So everything that followed the index (the picture, A, the arrow)
-- was one row above the row the player could see was chosen.
--
-- CreateMonListEntry fills its eleven rows from `selected - 5` and CLEARS
-- the ones whose number falls outside the dex, which is why there is no
-- clamp on this path: at #001 the cartridge shows four blank rows above it
-- rather than sliding the bar off the entry.
function Gen3Pokedex:clampScroll()
  if self:art() then
    self.scroll = self.index - ART.selected
    return
  end
  local top = self.index - math.floor(ROWS / 2)
  local most = math.max(0, self.count - ROWS)
  if top < 0 then top = 0 end
  if top > most then top = most end
  self.scroll = top
end

function Gen3Pokedex:selected()
  local id = self.list[self.index]
  local dex = self.game.save and self.game.save.pokedex
  local seen = id and dex and dex.seen[id] or false
  return id, seen and true or false
end

function Gen3Pokedex:loadPic()
  local id, seen = self:selected()
  self.pic, self.picTrueColor = nil, false
  self.picSpecies = id
  if not (id and seen) then return end
  local path, trueColor = require("src.pokemon.Sprites").path(
    self.game.data, id, "front", { kind = "dex" })
  if not path then return end
  local ok, img = pcall(love.graphics.newImage, path)
  if ok and img then
    self.pic, self.picTrueColor = img, trueColor and true or false
  end
end

function Gen3Pokedex:counts()
  local dex = self.game.save and self.game.save.pokedex
  local seen, owned = 0, 0
  if not dex then return 0, 0 end
  -- counted over the LISTING, not over the whole species table: the Hoenn dex
  -- counts Hoenn's own, and a caught Kanto Pokemon does not raise it
  for n = 1, self.count do
    local id = self.list[n]
    if id then
      if dex.seen[id] then seen = seen + 1 end
      if dex.owned[id] then owned = owned + 1 end
    end
  end
  return seen, owned
end

function Gen3Pokedex:move(delta)
  if self.count < 1 then return end
  -- the cartridge's list STOPS at both ends; it does not wrap round
  local n = self.index + delta
  if n < 1 then n = 1 elseif n > self.count then n = self.count end
  if n == self.index then return end
  -- the spinner turns by the cartridge's step for every ROW crossed, in the
  -- direction the list moved
  local iface = self:interface()
  local spin = iface and iface.at and iface.at.spinner
  if spin then
    local step = math.floor(tonumber(spin.step) or 16)
    local turn = math.floor(tonumber(spin.turn) or 256)
    self.spin = ((self.spin or 0) + step * (n - self.index)) % turn
  end
  self.index = n
  self:clampScroll()
  self:loadPic()
  Sound.play(self.game.data, "Press_AB")
end

function Gen3Pokedex:update()
  local input = self.game.input
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    if self.opts.onCancel then self.opts.onCancel() end
    return
  end
  if input:wasPressed("up") then
    self:move(-1)
  elseif input:wasPressed("down") then
    self:move(1)
  elseif input:wasPressed("left") then
    self:move(-ROWS)
  elseif input:wasPressed("right") then
    self:move(ROWS)
  elseif input:wasPressed("a") then
    local id, seen = self:selected()
    -- a number that has never been seen is a row of dashes; the cartridge
    -- does not open a page for one
    if id and seen then
      Sound.play(self.game.data, "Press_AB")
      require("src.ui.Screens").push(self.game, "DexEntryMenu", id)
    end
  -- THE TWO KEYS THE SCREEN HAS BEEN DRAWING HINTS FOR.
  --
  -- Reported from play: "for the pokedex in emerald the start and select
  -- buttons arent working for search and menu like they do in the actual
  -- rom/game".  The plates were blitted and the keys did nothing.  START
  -- opens the top bar, SELECT drops straight into the form under its first
  -- row -- which is what the two hints say: SELECT / SEARCH and START / MENU.
  elseif input:wasPressed("start") then
    self:openSearch("topbar")
  elseif input:wasPressed("select") then
    self:openSearch("form")
  end
end

-- Open the search screen, on whichever pane the key that was pressed opens.
-- A dataset without the derivation keeps the key inert rather than opening an
-- empty frame; the hints are drawn off the ripped sheet, so a cache old
-- enough to miss one of the two misses both.
function Gen3Pokedex:openSearch(pane)
  local Search = require("src.ui.Gen3DexSearch")
  if not Search.available(self.game) then
    require("src.core.Logger").warn(
      "gen3 pokedex: this dataset carries no search vocabulary -- %s does "
      .. "nothing", pane == "form" and "SELECT" or "START")
    return
  end
  Sound.play(self.game.data, "Press_AB")
  self.game.stack:push(Search.new(self.game, {
    pane = pane,
    order = self.order,
    mode = self.dexMode,
    onDone = function(result) self:applySearch(result) end,
  }))
end

-- ---------------------------------------------------------------------------
-- WHAT COMES BACK, AND WHAT IT DOES TO THE LIST.
--
-- The search screen answers a question; the listing is this screen's own, so
-- the rebuilding is here.  Three things can change: which dex is being listed
-- (Hoenn or national), what order its rows are in, and which rows survive a
-- filter.
--
-- THE RESTRICTIONS ARE THE CARTRIDGE'S OWN SENTENCES.  "Spotted POKeMON
-- only." is what the name and colour searches say about themselves, and
-- A TO Z with them; "Owned POKeMON only." is the type search and the four
-- size orders.  So the sentence each row carries is READ here rather than the
-- rule being written out again: a listing mode whose sentence says "Owned"
-- drops everything not owned, one that says "Spotted" drops everything not
-- seen, and NUMERICAL, whose sentence says neither, drops nothing.
--
-- AND THE NUMBERS STAY THE DEX'S.  A sorted or filtered list is not
-- renumbered -- row four of a heaviest-first list is still whatever number
-- that Pokemon has -- so the numbers travel beside the list rather than being
-- its index.
-- ---------------------------------------------------------------------------

local function wants(sentence, word)
  return tostring(sentence or ""):find(word, 1, true) ~= nil
end

function Gen3Pokedex:applySearch(result)
  if type(result) ~= "table" then return end
  local data = self.game.data
  local record = (data.constants or {}).gen3PokedexMenu or {}
  local save = self.game.save
  local dex = save and save.pokedex

  -- 1. which dex is LISTED, which does not touch the upgrade: a player who
  -- has the national dex and asks for the Hoenn listing keeps it.
  if result.mode then self.dexMode = result.mode end
  local base, last = Gen3Pokedex.listing(self.game, (self.dexMode or 1) >= 2)

  -- 2. the rows, as a list of {number, species} pairs
  local rows = {}
  for n = 1, last do
    local id = base[n]
    if id then rows[#rows + 1] = { n = n, id = id } end
  end

  -- 3. the filter, when there is one
  local order = (record.orders or {})[result.order or 1]
  local sentence = order and order.description or ""
  local ownedOnly = wants(sentence, "Owned")
  local seenOnly = wants(sentence, "Spotted")
  for _, key in ipairs({ "letter", "colour", "type1", "type2" }) do
    local item = ({ letter = 1, colour = 2, type1 = 3, type2 = 4 })[key]
    if result[key] ~= nil then
      local said = ((record.items or {})[item] or {}).description
      if wants(said, "Owned") then ownedOnly = true end
      if wants(said, "Spotted") then seenOnly = true end
    end
  end

  local kept = {}
  for _, row in ipairs(rows) do
    local def = data.pokemon[row.id]
    local ok = true
    if ownedOnly and not (dex and dex.owned[row.id]) then ok = false end
    if ok and seenOnly and not (dex and dex.seen[row.id]) then ok = false end
    if ok and result.letter then
      local name = tostring((def and def.name) or "")
      ok = name ~= "" and result.letter:find(name:sub(1, 1), 1, true) ~= nil
    end
    if ok and result.colour then
      ok = (def and tonumber(def.bodyColor)) == result.colour
    end
    if ok and (result.type1 or result.type2) then
      local t = (def and def.types) or {}
      local function has(want)
        return want == nil or t[1] == want or t[2] == want
      end
      ok = has(result.type1) and has(result.type2)
    end
    if ok then kept[#kept + 1] = row end
  end

  -- 4. the order.  NUMERICAL is the list as it stands; the other five are the
  -- cartridge's own five keys, and each one is named by its own sentence.
  local key
  if wants(sentence, "alphabetically") then
    key = function(row)
      return tostring((data.pokemon[row.id] or {}).name or "")
    end
  elseif wants(sentence, "heaviest") or wants(sentence, "lightest") then
    key = function(row) return tonumber((data.pokemon[row.id] or {}).weight) or 0 end
  elseif wants(sentence, "tallest") or wants(sentence, "smallest") then
    key = function(row) return tonumber((data.pokemon[row.id] or {}).height) or 0 end
  end
  if key then
    -- "from the heaviest" and "from the tallest" descend; the other two, and
    -- A TO Z, ascend
    local down = wants(sentence, "from the\nheaviest")
                 or wants(sentence, "from the\ntallest")
                 or wants(sentence, "from the heaviest")
                 or wants(sentence, "from the tallest")
    table.sort(kept, function(a, b)
      local ka, kb = key(a), key(b)
      if ka == kb then return a.n < b.n end
      if down then return ka > kb end
      return ka < kb
    end)
  end

  self.list, self.numbers, self.count = {}, {}, #kept
  for i, row in ipairs(kept) do
    self.list[i] = row.id
    self.numbers[i] = row.n
  end
  self.order = result.order
  self.index = math.min(math.max(1, self.index), math.max(1, self.count))
  self:clampScroll()
  self:loadPic()
end

-- ---------------------------------------------------------------------------
-- THE FURNITURE, WHICH IS SPRITES.
--
-- Reported from play: "the black pokeball within the Pokedex ui that spins
-- when a user scrolls through the list of pokemon".  There is one, and this
-- screen could never have drawn it: everything the import had ripped was
-- BACKGROUND, and the whole of the list screen's furniture is OBJECTS --
-- the SEEN and OWN plates and their digits, the two scroll arrows, the
-- scrollbar, the SELECT/SEARCH and START/MENU hints, and the spinner.
--
-- The spinner is two copies of one 32x32 piece at (0, 80) -- half of it off
-- the left edge, inside the ring the background draws -- a quarter turn
-- apart, on matrices 30 and 31.  It turns sixteen 256ths, 22.5 degrees, for
-- every row the list moves: 0BDA18 adds sixteen going down and 0BD9A6 takes
-- sixteen coming back.  That is the whole of "it spins when you scroll".
function Gen3Pokedex:interface()
  if self.ifaceLoaded then return self.iface end
  self.ifaceLoaded = true
  local record = (self.game.data.constants or {}).gen3PokedexScreen
  local iface = (type(record) == "table") and record.interface or nil
  if type(iface) ~= "table" or type(iface.images) ~= "table"
     or type(iface.at) ~= "table" then
    return nil
  end
  self.iface = iface
  return iface
end

function Gen3Pokedex:piece(key)
  local iface = self:interface()
  if not iface then return nil end
  self.pieces = self.pieces or {}
  local held = self.pieces[key]
  if held ~= nil then return held or nil end
  local path = iface.images[key]
  if type(path) ~= "string" then self.pieces[key] = false return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  self.pieces[key] = (ok and img) or false
  return self.pieces[key] or nil
end

-- A GBA sprite's position is its CENTRE, so every one of these is drawn from
-- half its own size.
function Gen3Pokedex:drawPiece(key, at, angle)
  local img = self:piece(key)
  if not (img and at) then return end
  local w, h = img:getDimensions()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, at.x, at.y, angle or 0,
                     1, at.flip and -1 or 1, w / 2, h / 2)
  require("src.render.PaletteFX").markTrueColor(
    math.floor(at.x - w / 2), math.floor(at.y - h / 2), w, h)
end

-- Right-aligned into three digits with the leading zeros left off, which is
-- what CreateInterfaceSprites does by leaving those sprites invisible.
function Gen3Pokedex:drawCount(value, place, set)
  if not place then return end
  local digits = { math.floor(value / 100) % 10,
                   math.floor(value / 10) % 10, value % 10 }
  local started = false
  for i, digit in ipairs(digits) do
    started = started or digit > 0 or i == #digits
    if started then
      self:drawPiece(("%s_%d"):format(set, digit),
                     { x = place.x[i], y = place.y })
    end
  end
end

-- The listing screen's own background, when the import found it.
function Gen3Pokedex:art()
  local record = (self.game.data.constants or {}).gen3PokedexScreen
  local images = type(record) == "table" and record.images or nil
  if type(images) ~= "table" then return nil end
  local national = (self.dexMode or 1) >= 2
  local path = (national and images.list_national) or images.list_hoenn
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  return ok and img or nil
end

-- The caught marker's own bitmap, when the import found it.
function Gen3Pokedex:ballImage()
  if self.ballLoaded then return self.ballPic end
  self.ballLoaded = true
  local record = (self.game.data.constants or {}).gen3PokedexScreen
  local path = type(record) == "table" and type(record.images) == "table"
               and record.images.caught_ball or nil
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  self.ballPic = ok and img or nil
  return self.ballPic
end

function Gen3Pokedex:draw()
  local bg = self:art()
  love.graphics.setColor(1, 1, 1, 1)
  if bg then
    love.graphics.draw(bg, 0, 0)
    require("src.render.PaletteFX").markTrueColor(0, 0, GBA_W, GBA_H)
  else
    love.graphics.setColor(0.30, 0.44, 0.64, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ---- THE SPINNER --------------------------------------------------------
  --
  -- Two copies of one piece at the same place, a quarter turn apart, half of
  -- each off the left edge of the screen -- inside the ring the background
  -- draws there.  Under the Pokemon, because the cartridge gives it
  -- subpriority 2 and the mon priority 0.
  do
    local ifaceSpin = self:interface()
    local spin = ifaceSpin and ifaceSpin.at and ifaceSpin.at.spinner
    if spin then
      local turn = math.floor(tonumber(spin.turn) or 256)
      local apart = math.floor(tonumber(spin.apart) or 64)
      local base = ((self.spin or 0) % turn) * 2 * math.pi / turn
      local step = apart * 2 * math.pi / turn
      self:drawPiece("spinner", spin, base)
      self:drawPiece("spinner", spin, base + step)
    end
  end

  -- ---- the picture well ---------------------------------------------------
  if self.pic then
    local w, h = self.pic:getDimensions()
    local x, y
    if bg then
      -- A GBA SPRITE IS ITS FRAME, NOT ITS PIXELS.
      --
      -- Reported from play: "their image is in the wrong spot when scrolling
      -- through the pokemon".  Centring each picture by its own width moves
      -- the mon every time the art inside the frame sits differently; the
      -- cartridge positions a 64x64 OBJ whose corner is the centre minus
      -- thirty-two and never looks at the art at all.
      local half = (w == MON_FRAME and h == MON_FRAME)
                   and (MON_FRAME / 2) or nil
      x = ART.pic.x - math.floor(half or w / 2)
      y = ART.pic.y - math.floor(half or h / 2)
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

  -- ---- SEEN and OWN -------------------------------------------------------
  --
  -- On the cartridge these are OBJECTS, not text, and they sit on the LEFT --
  -- over the dark ring -- rather than in the pale panel, which is where the
  -- Pokemon goes.  The plates, their digits and the two button hints are all
  -- drawn from the ripped sheet when the import found it; the words below are
  -- the reconstruction a cache without it keeps.
  local seen, owned = self:counts()
  local iface = self:interface()
  local at = iface and iface.at or nil
  if at then
    self:drawPiece("seen", at.seen)
    self:drawPiece("own", at.own)
    self:drawCount(seen, at.seenDigits, "digit")
    self:drawCount(owned, at.ownDigits, "digit")
    self:drawPiece("select", at.select)
    self:drawPiece("search", at.search)
    self:drawPiece("start", at.start)
    self:drawPiece("menu", at.menu)
  else
    love.graphics.setColor(1, 1, 1, 1)
    local cx, cy
    if bg then
      cx, cy = ART.counts.x, ART.counts.y
    else
      Font.drawBox(COUNTS.tx, COUNTS.ty, COUNTS.tw, COUNTS.th)
      cx, cy = (COUNTS.tx + 1) * 8, (COUNTS.ty + 1) * 8 + 8
    end
    Font.draw(Strings("SEEN"), cx, cy)
    Font.draw(("%d"):format(seen), cx + 44, cy)
    Font.draw(Strings("OWN"), cx, cy + 22)
    Font.draw(("%d"):format(owned), cx + 44, cy + 22)
  end

  -- ---- the listing --------------------------------------------------------
  love.graphics.setColor(1, 1, 1, 1)
  if not bg then Font.drawBox(LIST.tx, LIST.ty, LIST.tw, LIST.th) end
  local rows = bg and ART.rows or ROWS
  local top = bg and ART.rowTop or ROW_TOP
  local pitch = bg and ART.rowHeight or ROW_H
  local numX = bg and ART.numberX or ROW_X
  local nameX = bg and ART.nameX or (ROW_X + 32)
  local ballX = bg and ART.ballX or (ROW_X - 8)
  local dex = self.game.save and self.game.save.pokedex
  local digits = math.max(3, #tostring(self.count))
  for slot = 1, rows do
    local n = self.scroll + slot
    -- a row whose number is off either end of the dex is BLANK, not the end
    -- of the drawing: at #001 four of these sit above the selected row
    if n >= 1 and n <= self.count then
      local y = top + (slot - 1) * pitch
      local id = self.list[n]
      local wasSeen = id and dex and dex.seen[id]
      Font.draw(("%0" .. digits .. "d")
                  :format((self.numbers and self.numbers[n]) or n), numX, y)
      if wasSeen then
        local def = self.game.data.pokemon[id]
        Font.draw((def and def.name) or id, nameX, y)
        -- THE CAUGHT MARKER, which is a Poke Ball and was a red dot.
        --
        -- Reported from play: "the side black pokeball in the pokedex is
        -- stupposed to spin".  There was no ball at all -- the import had
        -- never found one, because it is not in this screen's tile sheet:
        -- CreateCaughtBall blits a bare 8x16 bitmap into the list window, so
        -- every graphics pass over the screen's tilemaps went straight past
        -- it.  It is ripped now (sCaughtBall_Gfx, the sixty-four bytes in
        -- front of the row of dashes) and drawn at tile 17, which is the
        -- column the cartridge blits it to.
        if dex.owned[id] then
          local ball = self:ballImage()
          love.graphics.setColor(1, 1, 1, 1)
          if ball then
            love.graphics.draw(ball, ballX - 4, y)
            require("src.render.PaletteFX").markTrueColor(
              ballX - 4, y, ball:getWidth(), ball:getHeight())
          else
            love.graphics.setColor(0.86, 0.24, 0.24, 1)
            love.graphics.circle("fill", ballX, y + 6, 3)
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      else
        Font.draw(UNSEEN, nameX, y)
      end
      -- ON THE ART THERE IS NO ARROW TO DRAW.  The cartridge's selection is
      -- the white bar and the notch cut into the panel's edge, and both are
      -- in the picture already; the arrow this used to put at the notch was
      -- a second cursor drawn over the first.
      if n == self.index and not bg then
        Font.drawCode(Theme.cursor, LIST.tx * 8 + 4, y)
      end
    end
  end

  -- ---- the two arrows and the bar down the right ---------------------------
  --
  -- The down arrow is the up one FLIPPED (0BDBCC sets its vFlip bit), and the
  -- bar's travel is the cartridge's own arithmetic: pos2.y is
  -- `selected * 120 / (count - 1)` (0BE62C), added to a pos1 of twenty -- so
  -- it runs from 20 to 140 over the whole dex.
  do
    local ifaceBar = self:interface()
    local at = ifaceBar and ifaceBar.at or nil
    if at then
      self:drawPiece("arrow", at.arrowUp)
      self:drawPiece("arrow", at.arrowDown)
      local span = math.max(1, self.count - 1)
      local slide = math.floor((self.index - 1) * BAR_TRAVEL / span)
      self:drawPiece("bar", { x = at.bar.x, y = at.bar.y + slide })
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3Pokedex
