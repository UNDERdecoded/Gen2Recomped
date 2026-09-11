-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S HALL OF FAME.
--
-- Reported from play: "make sure the hall of fame and credits work as
-- intended after beating the game".  Neither did: `special 275` GameClear had
-- no handler at all until this round, and the screen the port DID have is the
-- GAME BOY's -- its own music, its own dex-rating boxes, its own player pic --
-- so running it here would have put Kanto's ceremony at the end of Hoenn.
--
-- EVERY PART OF THIS COMES OFF THE CARTRIDGE.  extractHallOfFame finds the
-- mound your six stand on from a single anchor: `LoadPalette(pal, 1, 62)`
-- occurs EXACTLY ONCE in sixteen megabytes, and the two pool loads before it
-- are the tiles and the tilemap -- both checked by decompressing to the sizes
-- a 256-tile sheet and a 32x32 map have.  The words are the same module's
-- own strings, matched out of its literal pools by what they say.
--
-- THE CEREMONY, in the order the cartridge runs it: your party one at a time
-- on the mound, each with its dex number, its species, its nickname and its
-- level; then you, with your name, your id and the time on the clock; then
-- "Welcome to the HALL OF FAME!", and the credits.
--
-- WHAT THIS DOES NOT DO is the cartridge's confetti, its flying-in sprites or
-- its saving screen -- those are animation and a save flow, and the ceremony
-- reads correctly without them.  What it does do is show the right six
-- Pokemon, in the right order, with the cartridge's own words.

local Font = require("src.render.Font")
local Assets = require("src.render.Assets")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local Sprites = require("src.pokemon.Sprites")
local Strings = require("src.core.Strings")

local Gen3HallOfFame = {}
Gen3HallOfFame.__index = Gen3HallOfFame
Gen3HallOfFame.isOpaque = true

local GBA_W, GBA_H = 240, 160
function Gen3HallOfFame:uiSize() return GBA_W, GBA_H end

-- how long each mon holds before the next, and the pause on the last panel
local HOLD_MON = 150
local HOLD_PLAYER = 210
local HOLD_WELCOME = 150

-- WHERE THE MOUND PUTS THINGS.  The platform art is 256 wide and its centre
-- is where the Pokemon stands; the text sits in a box under it, which is the
-- one part of this screen the port draws with its own furniture rather than
-- with ripped art -- Font.drawBox is already the cartridge's window frame.
local MON_CX, MON_CY = 116, 64
local BOX_TX, BOX_TY, BOX_TW, BOX_TH = 1, 12, 28, 6

function Gen3HallOfFame.record(game)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3HallOfFame
  if type(r) ~= "table" or type(r.text) ~= "table" then return nil end
  return r
end

function Gen3HallOfFame.new(game, onDone)
  local record = Gen3HallOfFame.record(game)
  if not record then return nil end
  local self = setmetatable({}, Gen3HallOfFame)
  self.game = game
  self.onDone = onDone
  self.record = record
  self.text = record.text
  -- the party as it stood when the league fell, which is what the cartridge
  -- writes into the Hall of Fame record
  self.party = {}
  for _, mon in ipairs((game.save and game.save.party) or {}) do
    if mon and mon.species then self.party[#self.party + 1] = mon end
  end
  self.index = 0
  self.timer = 0
  self.phase = "mon"
  self.sprites = {}
  self.done = false
  self:advance()
  return self
end

function Gen3HallOfFame:enter()
  pcall(Music.play, self.game.data, "Music_HallOfFame")
end

function Gen3HallOfFame:background()
  local path = self.record and self.record.background
  if type(path) ~= "string" then return nil end
  if self.bg == nil then
    local ok, img = pcall(Assets.image, path)
    self.bg = (ok and img) or false
  end
  return self.bg or nil
end

function Gen3HallOfFame:spriteFor(mon)
  local key = tostring(mon.species)
  if self.sprites[key] == nil then
    local ok, path = pcall(Sprites.path, self.game.data, mon.species, "front",
                           { mon = mon })
    local img = false
    if ok and type(path) == "string" then
      local okI, loaded = pcall(Assets.image, path)
      img = (okI and loaded) or false
    end
    self.sprites[key] = img
  end
  return self.sprites[key] or nil
end

-- ...ONE AT A TIME, AND EACH ONE CRIES.  The cartridge plays the cry as the
-- Pokemon arrives, which is the beat the whole ceremony is paced to.
function Gen3HallOfFame:advance()
  self.timer = 0
  if self.phase == "mon" then
    self.index = self.index + 1
    local mon = self.party[self.index]
    if not mon then
      self.phase = "player"
      return
    end
    pcall(Sound.playCry, self.game.data, mon.species)
    return
  end
  if self.phase == "player" then
    self.phase = "welcome"
    return
  end
  if self.phase == "welcome" then
    return self:finish()
  end
end

function Gen3HallOfFame:finish()
  if self.done then return end
  self.done = true
  local game = self.game
  game.stack:pop()
  -- ...AND THEN THE CREDITS.  Pushed from here rather than from the script,
  -- because on the cartridge the ceremony hands the screen straight to them.
  local okC, Gen3Credits = pcall(require, "src.ui.Gen3Credits")
  local credits = okC and Gen3Credits.new(game, self.onDone) or nil
  if credits then
    game.stack:push(credits)
  elseif self.onDone then
    self.onDone()
  end
end

function Gen3HallOfFame:update()
  self.timer = (self.timer or 0) + 1
  local hold = HOLD_MON
  if self.phase == "player" then hold = HOLD_PLAYER
  elseif self.phase == "welcome" then hold = HOLD_WELCOME end
  local input = self.game.input
  local pressed = input and input.wasPressed
    and (input:wasPressed("a") or input:wasPressed("start"))
  if self.timer >= hold or pressed then self:advance() end
end

function Gen3HallOfFame:keypressed() end

-- ---------------------------------------------------------------------------
-- DRAWING
-- ---------------------------------------------------------------------------

-- WHICH NUMBER, and it is not one field.  SpeciesToPokedexNum answers with
-- the HOENN number until the dex is upgraded and the NATIONAL one after, so
-- the panel has to ask the same two places the dex screen asks: the Hoenn
-- numbering lives in constants.gen3HoennDex.numbers and the national one is
-- `def.dex` on the species row.  Reading a `hoennNumber` field off the
-- species -- which is what this did first -- finds nothing at all, and every
-- panel printed a blank where the number belongs.
local function dexNumber(game, mon)
  local data = game.data or {}
  local def = (data.pokemon or {})[mon.species]
  if not (game.save and game.save.nationalDex) then
    local record = (data.constants or {}).gen3HoennDex
    local numbers = (type(record) == "table") and record.numbers or nil
    local n = numbers and tonumber(numbers[mon.species])
    if n and n >= 1 then return n end
  end
  return def and tonumber(def.dex) or nil
end

local function speciesName(game, mon)
  local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return (def and def.name) or tostring(mon.species)
end

function Gen3HallOfFame:drawMonPanel(mon)
  local game = self.game
  local img = self:spriteFor(mon)
  if img then
    local w, h = img:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, math.floor(MON_CX - w / 2),
                       math.floor(MON_CY - h / 2))
  end
  Font.drawBox(BOX_TX, BOX_TY, BOX_TW, BOX_TH)
  local x, y = BOX_TX * 8 + 6, BOX_TY * 8 + 6
  local line = Font.glyphHeight() + 2
  local number = dexNumber(game, mon)
  local left = number and (tostring(self.text.dexNo or "No. ")
                           .. ("%03d"):format(number)) or ""
  Font.draw(left, x, y)
  Font.draw(speciesName(game, mon), x + 64, y)
  local nickname = mon.nickname or speciesName(game, mon)
  Font.draw(nickname, x, y + line)
  Font.draw(tostring(self.text.level or "Lv. ") .. tostring(mon.level or 0),
            x + 128, y + line)
end

function Gen3HallOfFame:drawPlayerPanel()
  local save = self.game.save or {}
  local player = save.player or {}
  Font.drawBox(BOX_TX, BOX_TY, BOX_TW, BOX_TH)
  local x, y = BOX_TX * 8 + 6, BOX_TY * 8 + 6
  local line = Font.glyphHeight() + 2
  Font.draw(tostring(self.text.name or "NAME"), x, y)
  Font.draw(tostring(player.name or ""), x + 48, y)
  Font.draw(tostring(self.text.idNo or "IDNo."), x, y + line)
  Font.draw(("%05d"):format(math.floor(tonumber(player.id) or 0) % 100000),
            x + 48, y + line)
  -- WHICH INDUCTION THIS IS.  The cartridge heads the ceremony with "HALL OF
  -- FAME No. n" and the number is how many times you have beaten the league,
  -- which special 275 counts.
  local number = math.floor(tonumber(save.hallOfFame) or 1)
  if number < 1 then number = 1 end
  local heading = tostring(self.text.number or "HALL OF FAME No. ")
                  .. ("%d"):format(number)
  Font.draw(heading, math.floor((GBA_W - Font.width(heading)) / 2),
            BOX_TY * 8 - line - 4)
  -- the champion's two lines, which the cartridge prints together
  local champion = tostring(self.text.champion or "")
  local ty = 4
  for piece in (champion .. "\n"):gmatch("([^\n]*)\n") do
    if piece ~= "" then
      Font.draw(piece, math.floor((GBA_W - Font.width(piece)) / 2), ty)
      ty = ty + line
    end
  end
end

function Gen3HallOfFame:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, GBA_W, GBA_H)
  g.setColor(1, 1, 1, 1)
  local bg = self:background()
  if bg then g.draw(bg, 0, 0) end
  local faced = Font.pushFace("small")
  Font.pushStyle(nil)
  if self.phase == "mon" then
    local mon = self.party[self.index]
    if mon then self:drawMonPanel(mon) end
  elseif self.phase == "player" then
    self:drawPlayerPanel()
  else
    local welcome = tostring(self.text.welcome or "")
    Font.drawBox(BOX_TX, BOX_TY, BOX_TW, 4)
    Font.draw(welcome, math.floor((GBA_W - Font.width(welcome)) / 2),
              BOX_TY * 8 + 8)
  end
  Font.popStyle()
  if faced then Font.popFace() end
  local _ = Strings
end

return Gen3HallOfFame
