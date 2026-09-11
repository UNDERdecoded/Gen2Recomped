-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Professor Birch's introduction: Emerald's NEW GAME.
--
-- Not OakSpeech with a different professor.  Oak's is a Game Boy sequence
-- built out of a pic area, a NIDORINO show-off, a shrink animation and a
-- walk-on; Birch's is a man standing on a grass platform who asks two
-- questions and steps aside.  The two share the engine's text box, its menu
-- and its naming screen, and nothing else worth sharing.
--
-- EVERY PART OF THIS COMES OUT OF THE CARTRIDGE.
--
--   * the platform is the scene the intro loads, palettes and all;
--   * Birch is the one sprite in 16 MiB loaded as {palette, then a template
--     whose sheet is a raw 0x800 bytes} -- there is no table he is in;
--   * the boy and the girl are the last two rows of gTrainerFrontPicTable;
--   * and the seven lines are the printable strings the intro code loads,
--     found around the one that splices the player's name in, in the order
--     the code loads them.  They are read here BY POSITION, which is the one
--     thing this file assumes: line 4 asks the boy-or-girl question and line
--     5 asks for a name, because that is the order Birch says them in.
--
-- What it does not have is the fade-and-shrink into the overworld.  The
-- player lands in the truck the same way a warp does.

local Font = require("src.render.Font")
local Gen3Scene = require("src.render.Gen3Scene")
local Logger = require("src.core.Logger")
local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local BirchSpeech = {}
BirchSpeech.__index = BirchSpeech
BirchSpeech.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- THE SURFACE IS THE GBA'S, asked for rather than scaled into.
-- Renderer:setUISize already exists for this (the widescreen battle asks for
-- 304x144) and Game:draw holds it for the whole stack above, so the text box
-- and the naming screen this pushes do not snap the canvas back underneath it.
local WINDOW_X = 0

-- Where he stands.  His sheet is 64x64 but his ink is not centred in it (it
-- runs x 8..49, y 1..63), so the figure is placed by its OWN centre and its
-- own feet rather than by the cell's.
local BIRCH_INK_CENTRE_X, BIRCH_INK_BOTTOM = 29, 63
local STANDING_Y = 88

function BirchSpeech:wantsFillScale() return true end

-- THIS SCREEN COMPOSES ITSELF, so the dialogue box stays inside it.
--
-- Edge docking pulls the box to the WINDOW's bottom edge, which is right for
-- the overworld: the box belongs against the screen, not floating in a
-- letterbox.  It is wrong here.  This screen fills the window at its own
-- scale, and the anchor path blits the box from a different origin than the
-- scene it sits under -- so the box came out wider than the picture above it,
-- hanging off the left with the first few letters of every line cut away.
-- "The intro text is cut off" was that, and it only ever happened while a box
-- was up, because the box is the only thing that anchors.
--
-- Same flag, same reason, as BattleState: a state that draws its own screen
-- keeps every element inside it.
BirchSpeech.holdsUIAnchors = true
function BirchSpeech:uiSize() return GBA_W, GBA_H end

-- colour, not four shades: see the note on Gen3Title:sgbPalettes
function BirchSpeech:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- Which line is which.  The intro says them in this order and the extractor
-- keeps them in it; naming the positions here is what stops the rest of the
-- file counting.
local LINE = {
  welcome = 1, world = 2, andYouAre = 3,
  gender = 4, name = 5, confirm = 6, ready = 7,
}

local function tryImage(path)
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

function BirchSpeech.new(game, onDone)
  local self = setmetatable({}, BirchSpeech)
  self.game = game
  self.onDone = onDone
  local intro = (game.data.constants or {}).gen3Intro or {}
  self.intro = intro
  self.lines = {}
  local text = game.data.text or {}
  for i, key in ipairs(intro.lines or {}) do
    self.lines[i] = text[key]
  end
  if not self.lines[LINE.gender] then
    Logger.warn("gen3 intro: this dataset carries no Birch speech -- the new "
                .. "game asks its questions without his lines")
  end
  self.birchPic = tryImage(intro.birchPic)
  self.boyPic = tryImage(intro.boyPic)
  self.girlPic = tryImage(intro.girlPic)
  self.pic = self.birchPic
  self.step = 0
  self.fade = 0
  self.answers = {}
  return self
end

function BirchSpeech:enter()
  local data = self.game.data
  local song = self.intro.music or "Music_Routes2"
  if data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
  Runtime.emit("intro.birch_speech.started", { speech = self })
  self:advance()
end

-- A line the dataset does not carry is SKIPPED rather than shown as an empty
-- box.  The same reasoning as OakSpeech's sayText: a frame with no text and
-- no way to know whether A does anything is worse than a missing line, and
-- the questions further down are the part that must be reached.
function BirchSpeech:say(index, next)
  local line = self.lines[index]
  if type(line) ~= "string" or line == "" then
    if next then next() end
    return
  end
  self.game.stack:push(TextBox.new(self.game, line, next))
end

function BirchSpeech:askGender(next)
  local Menu = require("src.ui.Menu")
  local game = self.game
  local items = {
    { label = Strings("BOY"), onSelect = function()
      self:chooseGender("boy"); next()
    end },
    { label = Strings("GIRL"), onSelect = function()
      self:chooseGender("girl"); next()
    end },
  }
  game.stack:push(Menu.new(game, items, { tx = 9, ty = 1, tw = 7 }))
end

-- The choice sets three things: the picture the rest of the intro shows, the
-- save's own record of it, and the RIVAL -- who in this game is simply the
-- one the player did not pick.
function BirchSpeech:chooseGender(which)
  self.gender = which
  self.answers.gender = which
  self.pic = (which == "girl") and self.girlPic or self.boyPic
  local player = self.game.save and self.game.save.player
  if player then
    player.gender = which
    player.rival = (which == "girl") and "BRENDAN" or "MAY"
  end

  -- ...AND THE CHARACTER ALREADY STANDING IN THE TRUCK.
  --
  -- New Game pushes the overworld FIRST and this speech on top of it, so by
  -- the time the question is asked the player object exists and has already
  -- picked its sheets -- from field.playerSprites, which is the boy's.
  -- Writing the answer to the save changes what the NEXT Player built would
  -- wear and nothing about the one already there, so answering GIRL and then
  -- stepping out of the truck put Brendan on Route 101.
  --
  -- refreshForm re-reads field.playerForms through the save's gender and
  -- swaps the walking, cycling and surfing sheets. OakSpeech does exactly
  -- this at its own gender step; the Birch speech simply never did.
  local overworld = self.game.overworld
  local avatar = overworld and overworld.player
  if avatar and avatar.refreshForm then
    pcall(function() avatar:refreshForm(self.game.data) end)
  end
end

function BirchSpeech:askName(next)
  local presets = { "BRENDAN", "MAY", "TERRY" }
  local boot = self.game.data.field and self.game.data.field.boot
  if boot and boot.namePresets and boot.namePresets.player then
    presets = boot.namePresets.player
  end
  local constants = self.game.data.constants or {}
  require("src.ui.Screens").push(self.game, "NamingScreen", {
    title = Strings("YOUR NAME?"),
    presets = presets,
    maxLen = constants.playerNameLength or 7,
    onDone = function(name)
      if self.game.save and self.game.save.player then
        self.game.save.player.name = name
      end
      self.answers.name = name
      next()
    end,
  })
end

function BirchSpeech:advance()
  self.step = self.step + 1
  local step = self.step
  local function nextStep() self:advance() end
  if step == 1 then
    self:say(LINE.welcome, nextStep)
  elseif step == 2 then
    self:say(LINE.world, nextStep)
  elseif step == 3 then
    self:say(LINE.andYouAre, nextStep)
  elseif step == 4 then
    self:say(LINE.gender, function() self:askGender(nextStep) end)
  elseif step == 5 then
    self:say(LINE.name, function() self:askName(nextStep) end)
  elseif step == 6 then
    -- the confirmation is the line with the placeholder in it, so it only
    -- reads correctly once the name is set -- which it now is
    self:say(LINE.confirm, nextStep)
  elseif step == 7 then
    self:say(LINE.ready, nextStep)
  else
    self:finish()
  end
end

function BirchSpeech:finish()
  Runtime.emit("intro.birch_speech.finished", {
    speech = self, answers = self.answers,
  })
  local ow = self.game.overworld
  local mapId = (ow and ow.map and ow.map.id)
                or (self.game.save.player and self.game.save.player.map)
  -- pcall: a Gen 3 cache carries songs.lua rather than audio.lua, so the map
  -- theme may have nothing to play -- which must not take the new game down
  -- one frame before the player reaches the world
  if mapId then pcall(Music.playMap, self.game.data, mapId) end
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

-- BIRCH FADES IN WHILE HE IS COVERED, which is the only time he is ever
-- visible: `enter` pushes his first line straight away, so this state is
-- never the top one while there is anything to see. Before StateStack grew
-- `animate` this ran exactly zero times and he was drawn at alpha 0 for the
-- whole introduction -- the platform behind him, his lines, the boy-or-girl
-- menu and the naming screen all correct, and no professor.
function BirchSpeech:animate(dt)
  if self.fade < 1 then self.fade = math.min(1, self.fade + 0.06) end
end

function BirchSpeech:update(dt)
  self:animate(dt)
end

function BirchSpeech:draw()
  local data = self.game.data
  love.graphics.setColor(0.16, 0.27, 0.16, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  Gen3Scene.drawRole(data, "birchSpeech", -WINDOW_X, 0, 1, GBA_W, GBA_H)

  if self.pic then
    local x = math.floor(GBA_W / 2) - BIRCH_INK_CENTRE_X
    local y = STANDING_Y - BIRCH_INK_BOTTOM
    love.graphics.setColor(1, 1, 1, self.fade)
    love.graphics.draw(self.pic, x, y)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if not self.lines[LINE.welcome] then
    -- nothing to say, so at least say why
    love.graphics.setColor(1, 1, 1, 1)
    Font.draw(Strings("NEW GAME"), 8, 8)
  end
end

return BirchSpeech
