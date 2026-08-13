-- A framed picture pop-up over the map.
--
-- Gen1 used this as DisplayMonFrontSpriteInBox: show a pic, any button
-- closes it, then the optional text plays.  Gen2 reaches it through the
-- `pokepic` script command (Script_pokepic -> Pokepic, 09:$44E3), which is
-- what puts CYNDAQUIL/TOTODILE/CHIKORITA on screen at Elm's table before the
-- "do you want this one?" prompt.  That flavour is a four-command sequence
-- in the ROM --
--
--     pokepic CYNDAQUIL / cry CYNDAQUIL / waitbutton / closepokepic
--
-- so the box has to stay up while the script keeps running (the cry sounds
-- under it) and only wait for the button when `closepokepic` arrives.  That
-- is the same shape as Commands.fade's FadeOverlay: an overlay state that
-- ticks the overworld's script runner from its own update, because
-- StateStack only updates the top state.
--
-- Geometry is PokepicMenuHeader (09:$4547) = `40 04 06 0d 0e`: flags
-- MENU_BACKUP_TILES, then menu_coords y1 4, x1 6, y2 13, x2 14 -- a 9x10
-- tile frame whose interior is exactly the 7 columns a Gen2 front pic
-- occupies.  Pokepic itself loads the pic with `ld bc, $0707`.

local Font = require("src.render.Font")

-- the frame, and the 7x7 pic cell inside it
local BOX_X, BOX_Y, BOX_W, BOX_H = 6, 4, 9, 10
local PIC_X, PIC_Y, PIC_TILES = (BOX_X + 1) * 8, (BOX_Y + 1) * 8, 7

local PicBox = {}
PicBox.__index = PicBox
PicBox.isOpaque = false

-- A mon pic is stored in the four DMG shades and gets its colour from
-- whatever palette the surface it lands on carries.  In battle that is
-- BattleState's own getImage, which bakes the species palette in; over the
-- MAP there is no such thing, so the pic came out wearing the overworld's
-- BG palette -- the green wash the user saw.  Bake the species colours the
-- same way BattleState does and mark the rect so the zone pass leaves it be.
--
-- _CGB_Pokepic (02:$5499) does exactly this on hardware: it loads the mon's
-- own palette into the pic's attribute block rather than reusing the map's.
local function coloredImage(path, colors)
  local Assets = require("src.render.Assets")
  if not colors then
    local plain, image = pcall(love.graphics.newImage, Assets.resolve(path))
    return plain and image or nil
  end
  local ok, image = pcall(function()
    local id = Assets.imageData(path)
    id:mapPixel(function(_, _, r, g, b, a)
      if a == 0 then return r, g, b, a end
      local c = r > 0.83 and colors[1] or r > 0.5 and colors[2]
                or r > 0.17 and colors[3] or colors[4]
      return c[1] / 255, c[2] / 255, c[3] / 255, a
    end)
    return love.graphics.newImage(id)
  end)
  return ok and image or nil
end

-- opts: a plain image path (the old Gen1 call), or
--   { path =, colors =, trueColor =, text =, passive =, overworld = }
-- passive means "draw only": input is ignored until arm() is called.
function PicBox.new(game, opts, text)
  local self = setmetatable({}, PicBox)
  self.game = game
  local path, colors = opts, nil
  if type(opts) == "table" then
    path = opts.path
    colors = opts.colors
    self.trueColor = opts.trueColor and true or false
    self.text = opts.text
    self.passive = opts.passive and true or false
    self.overworld = opts.overworld
  end
  self.image = coloredImage(path, colors)
  -- a baked pic carries its own colours, so the zone pass has to skip it
  if colors and self.image then self.trueColor = true end
  self.text = self.text or text
  return self
end

-- From here A or B dismisses the box; onDone fires once it is gone.
-- armedDelay skips the frame we were armed on, so the button press that
-- advanced the script into `closepokepic` cannot also close this.
function PicBox:arm(onDone)
  self.passive = false
  self.armedDelay = 1
  self.onDone = onDone
end

-- A text box may sit above this overlay, so unwind in place rather than
-- popping the top of the stack (the same reason FadeOverlay does).
function PicBox:remove()
  local states = self.game.stack.states
  for i = #states, 1, -1 do
    if states[i] == self then table.remove(states, i) break end
  end
  if self.overworld and self.overworld.pokepicBox == self then
    self.overworld.pokepicBox = nil
  end
end

function PicBox:update(dt)
  -- StateStack only updates the top state, so while this box is up nothing
  -- else advances the script that opened it.
  local ow = self.overworld
  if ow and ow.runner then ow.runner:update() end
  if self.passive then return end
  if self.armedDelay and self.armedDelay > 0 then
    self.armedDelay = self.armedDelay - 1
    return
  end
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self:remove()
    local onDone = self.onDone
    self.onDone = nil
    if self.text then
      local TextBox = require("src.render.TextBox")
      self.game.stack:push(TextBox.new(self.game, self.text))
    end
    if onDone then onDone() end
  end
end

function PicBox:draw()
  Font.drawBox(BOX_X, BOX_Y, BOX_W, BOX_H)
  if not self.image then return end
  love.graphics.setColor(1, 1, 1, 1)
  local w, h = self.image:getDimensions()
  -- Gen2 pads a short pic into the 7x7 buffer the way the sprite loader
  -- does: centred across, sitting on the bottom row.
  local x = PIC_X + math.floor((PIC_TILES - w / 8) / 2) * 8
  local y = PIC_Y + (PIC_TILES - h / 8) * 8
  love.graphics.draw(self.image, x, y)
  if self.trueColor then
    require("src.render.PaletteFX").markTrueColor(x, y, w, h)
  end
end

return PicBox
