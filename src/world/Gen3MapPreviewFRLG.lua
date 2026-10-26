-- FIRERED'S DUNGEON PREVIEW (map_preview_screen.c, fldeff_flash.c).
--
-- Walking into Viridian Forest, Mt. Moon, Rock Tunnel and the rest shows a
-- picture of the place with its name in a white bar before the map appears.
-- The picture fades in from black, holds for 120 frames the first time
-- (the WORLD_MAP flag is not yet set) and 40 after, B cuts it short, and it
-- fades out to white.  The records come from RomExtractorGen3:
-- extractFireRedMapPreviews.

local Flags = require("src.script.Flags")
local Font = require("src.render.Font")

local Preview = {}
Preview.__index = Preview
Preview.isOpaque = true

local FADE_IN, FADE_OUT = 16, 16

function Preview.record(game, section)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3FRLGMapPreviews
  return r and r.bySection and r.bySection[section] or nil
end

function Preview.new(game, section, name, onDone)
  local rec = Preview.record(game, section)
  if not rec then return nil end
  local seen = rec.flag and Flags.get(game.save, rec.flag)
  if rec.flag then Flags.set(game.save, rec.flag) end
  local ok, img = pcall(require("src.render.Assets").image, rec.image)
  if not (ok and img) then return nil end
  return setmetatable({
    game = game, section = section, image = img, name = name or "", onDone = onDone,
    hold = seen and 40 or 120, t = 0, phase = "in",
  }, Preview)
end

function Preview:uiSize() return 240, 160 end

function Preview:update()
  self.t = self.t + 1
  if self.phase == "in" and self.t >= FADE_IN then
    self.phase, self.t = "hold", 0
  elseif self.phase == "hold" then
    local input = self.game.input
    if self.t > self.hold or (input and input.isDown and input:isDown("b")) then
      self.phase, self.t = "out", 0
    end
  elseif self.phase == "out" and self.t >= FADE_OUT then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function Preview:draw()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  g.draw(self.image, 0, 0)
  -- sMapNameWindow: (0,0) 13x2, white, the name centred in 104 pixels
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", 0, 0, 104, 16)
  local ink, shadow = { 98 / 255, 98 / 255, 98 / 255, 1 }, { 214 / 255, 214 / 255, 206 / 255, 1 }
  local two = Font.beginTwoTone(ink, shadow)
  if not two then g.setColor(ink) end
  Font.draw(self.name, math.max(0, math.floor((104 - Font.width(self.name)) / 2)), 2)
  if two then Font.endTwoTone() end
  if self.phase == "in" then
    g.setColor(0, 0, 0, 1 - self.t / FADE_IN)
    g.rectangle("fill", 0, 0, 240, 160)
  elseif self.phase == "out" then
    g.setColor(1, 1, 1, self.t / FADE_OUT)
    g.rectangle("fill", 0, 0, 240, 160)
  end
  g.setColor(1, 1, 1, 1)
end

return Preview
