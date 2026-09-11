-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SOOTOPOLIS CUTSCENE.
--
-- Reported from play: "Make sure the cutscene for groudon, kyogre and
-- rayquaza appears after going to the tower and making rayquaza flee and
-- returning to sootopolis ... It shows kyogre and groudon and then rayquaza
-- comes down from the sky".
--
-- WHAT WAS MISSING WAS ONE SPECIAL.  Sootopolis City's two scene scripts were
-- decoded end to end and every command in them lowers and every special they
-- call is implemented except gSpecials[470] = gSpecials[508],
-- Script_DoRayquazaScene -- which is not a script at all.  It takes over the
-- main callback and plays a full-screen cinematic, and this is that
-- cinematic.
--
-- WHAT COMES OFF THE CARTRIDGE (see RomExtractorGen3:extractRayquazaScene):
--
--   * the art.  Five screens' worth of background layers and sprite sheets,
--     composed from the tiles, tilemaps and palettes the scene's own five
--     loader functions bring in.  Groudon comes out 64x64 and Kyogre 32x16
--     because each sheet's frame size is read from the OAM of the sprite
--     template that names its tag.
--   * the ORDER.  The scene's advance step installs the next screen out of a
--     table at $62A6A0, and that table reads
--
--         clouds -> clouds -> storm -> chase -> descent -> light -> end
--
--     which is Groudon and Kyogre first and Rayquaza afterwards, exactly as
--     the report describes it.
--   * WHERE IT STARTS AND WHETHER IT STOPS.  Script_DoRayquazaScene passes
--     two arguments off gSpecialVar_0x8004: the index into that table, and
--     whether the advance exits instead of stepping.  The half the script
--     runs before the Sky Pillar opens on the first screen and stops there;
--     the half after it walks the whole table.
--
-- WHAT DOES NOT: HOW LONG EACH SCREEN HOLDS, and how the Pokemon move across
-- it.  Each step is its own C function counting its own frames, and none of
-- that is data.  So the hold below is this port's, one number for every
-- screen, and the sprites are placed rather than choreographed.  The scene
-- plays the cartridge's pictures in the cartridge's order for the cartridge's
-- two halves; it does not claim to be frame-accurate inside a screen.
local Assets = require("src.render.Assets")

local Gen3Cutscene = {}
Gen3Cutscene.__index = Gen3Cutscene

local GBA_W, GBA_H = 240, 160

-- the port's own numbers, and the only ones here that are
local HOLD = 150               -- frames a screen is up for
local FADE = 20                -- ...of which the first and last are a fade
local SPRITE_HOLD = 8          -- frames per frame of a Pokemon's animation

function Gen3Cutscene:uiSize() return GBA_W, GBA_H end
function Gen3Cutscene:wantsFillScale() return true end
function Gen3Cutscene:isOpaque() return true end

function Gen3Cutscene.record(game)
  local constants = game and game.data and game.data.constants
  local record = constants and constants.gen3RayquazaScene
  if type(record) ~= "table" or type(record.scenes) ~= "table" then
    return nil
  end
  return record
end

-- The screens this half plays, in order.  `part` is the index the cartridge
-- starts at and `earlyStops` is how many steps the early half gets.
function Gen3Cutscene.steps(record, part)
  if not record then return {} end
  local byKey = {}
  for _, scene in ipairs(record.scenes) do byKey[scene.key] = scene end
  local order = record.order
  local out = {}
  if type(order) == "table" and #order > 0 then
    local from = math.max(1, (tonumber(part) or 0) + 1)
    for i = from, #order do
      local key = order[i]
      if key and byKey[key] then out[#out + 1] = byKey[key] end
    end
  else
    -- no order came off the cartridge: play what there is, once each, rather
    -- than nothing at all
    for _, scene in ipairs(record.scenes) do out[#out + 1] = scene end
  end
  -- ...and the early half stops after its first screen, which is what
  -- endEarly does to the advance
  local early = tonumber(record.earlyStops)
  if early and (tonumber(part) or 0) == 0 and #out > early then
    local cut = {}
    for i = 1, early do cut[i] = out[i] end
    out = cut
  end
  return out
end

function Gen3Cutscene.new(game, opts)
  local self = setmetatable({}, Gen3Cutscene)
  self.game = game
  self.onDone = opts and opts.onDone
  self.part = tonumber(opts and opts.part) or 0
  self.record = Gen3Cutscene.record(game)
  self.list = Gen3Cutscene.steps(self.record, self.part)
  self.index = 1
  self.frame = 0
  return self
end

function Gen3Cutscene:current() return self.list[self.index] end

function Gen3Cutscene:finish()
  if self.done then return end
  self.done = true
  if self.game and self.game.stack then
    pcall(self.game.stack.pop, self.game.stack)
  end
  if self.onDone then pcall(self.onDone) end
end

function Gen3Cutscene:update()
  if self.done then return end
  -- nothing to play is not a reason to sit on a black screen: the script
  -- behind this is waiting on it
  if not self:current() then return self:finish() end
  self.frame = self.frame + 1
  if self.frame >= HOLD then
    self.frame = 0
    self.index = self.index + 1
    if not self:current() then return self:finish() end
  end
  -- ...AND IT CAN ALWAYS BE LEFT.  The cartridge's cinematic is not
  -- skippable, but a cinematic this port got wrong and could not be left
  -- would strand the save at the one point in the story it cannot go round.
  local input = self.game and self.game.input
  if input and (input:wasPressed("b") or input:wasPressed("start")) then
    self:finish()
  end
end

-- How far through the current screen the fade is: nothing at the ends, full
-- in the middle.
function Gen3Cutscene:alpha()
  local f = self.frame
  if f < FADE then return f / FADE end
  if f > HOLD - FADE then return math.max(0, (HOLD - f) / FADE) end
  return 1
end

function Gen3Cutscene:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, GBA_W, GBA_H)
  local scene = self:current()
  if not scene then return end
  local alpha = self:alpha()

  -- the layers, back to front.  A higher BG number is further back on the
  -- hardware's usual ordering, and these scenes are built that way: the
  -- cloud tunnel's BG3 is the sky behind everything else it draws.
  local layers = {}
  for _, layer in ipairs(scene.layers or {}) do layers[#layers + 1] = layer end
  table.sort(layers, function(a, b) return (a.bg or 0) > (b.bg or 0) end)
  for _, layer in ipairs(layers) do
    local ok, img = pcall(Assets.image, layer.image)
    if ok and img and img.getWidth then
      g.setColor(1, 1, 1, alpha)
      -- the layer is a 256x256 screen block and the screen is 240x160: it is
      -- centred, which is where the hardware's own scroll leaves it
      g.draw(img, math.floor((GBA_W - img:getWidth()) / 2),
             math.floor((GBA_H - img:getHeight()) / 2))
    end
  end

  -- ...and the Pokemon on it.  Placed, not choreographed -- the biggest sheet
  -- in the middle and anything else beside it -- because where each one flies
  -- is its own C function and not data.
  local sprites = {}
  for _, s in ipairs(scene.sprites or {}) do sprites[#sprites + 1] = s end
  table.sort(sprites, function(a, b)
    return (a.width or 0) * (a.height or 0) > (b.width or 0) * (b.height or 0)
  end)
  local biggest = sprites[1]
  if biggest then
    local ok, img = pcall(Assets.image, biggest.image)
    if ok and img and img.getWidth then
      local w = biggest.width or img:getWidth()
      local h = biggest.height or img:getHeight()
      local frames = math.max(1, biggest.frames or 1)
      local index = math.floor(self.frame / SPRITE_HOLD) % frames
      self.quads = self.quads or {}
      local key = tostring(biggest.image) .. ":" .. index
      local quad = self.quads[key]
      if not quad then
        quad = g.newQuad(index * w, 0, w, h, img:getWidth(), img:getHeight())
        self.quads[key] = quad
      end
      g.setColor(1, 1, 1, alpha)
      g.draw(img, quad, math.floor((GBA_W - w) / 2),
             math.floor((GBA_H - h) / 2))
    end
  end
  g.setColor(1, 1, 1, 1)
end

return Gen3Cutscene
