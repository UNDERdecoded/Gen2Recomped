-- Prism's character customisation (event/customization.asm PlayerCustomization).
--
-- Prism does not ask "are you a boy or a girl?".  It asks three questions, and
-- the answers pack into wPlayerCharacteristics:
--
--   byte 0  bit 0    gender          } together, the `& $f` index GetPlayerSprite
--           bits 1-3 character model } uses -- the p0..p13 keys field.playerForms
--           bits 4-6 skin tone         is already keyed under
--   bytes 1-2        clothes colour, a 15-bit RGB the player mixes themselves
--
-- so the screen writes save.player.gender = "p<N>", .skinTone and .clothes, and
-- every existing consumer (Sprites.playerForm, Player:refreshForm, the trainer
-- card) picks the character up from gender exactly as it does for Crystal's
-- BOY/GIRL.
--
-- The three categories, their sizes and the order they appear in are the ROM's
-- (PlayerCust_CategoryMenuItems.InitialMenu: Model, SkinTone, Outfit, Restart,
-- Done); the outfit really is three 0-31 sliders, which is why the ROM draws
-- three slider cursors at x = 14, 16 and 18.

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")
local Sound = require("src.core.Sound")

local PrismCustomization = {}
PrismCustomization.__index = PrismCustomization
PrismCustomization.isOpaque = true

local CATEGORIES = { "model", "skin", "outfit", "restart", "done" }
local CATEGORY_LABEL = {
  model = "MODEL", skin = "SKIN TONE", outfit = "OUTFIT",
  restart = "RESTART", done = "DONE",
}
local CHANNELS = { "r", "g", "b" }
local CHANNEL_LABEL = { r = "R", g = "G", b = "B" }
-- RGB15: the ROM's own range for both the skin swatches and the sliders
local MAX_LEVEL = 31

local function spec(game)
  local field = game.data and game.data.field
  return field and field.playerCustomization or nil
end

-- Is this dataset one that customises?  Only Prism ships the table, so this is
-- also the test the new-game speech uses to decide which question to ask.
function PrismCustomization.available(game)
  local s = spec(game)
  return s ~= nil and type(s.skinTones) == "table" and (s.models or 0) >= 1
end

function PrismCustomization.new(game, onDone)
  local self = setmetatable({}, PrismCustomization)
  self.game = game
  self.onDone = onDone
  self.spec = spec(game)
  local d = (self.spec and self.spec.default) or {}
  local player = game.save and game.save.player or {}
  -- resume whatever is already on the save, so re-entering the screen (the
  -- Oxalis Salon does exactly this) starts on the current character
  self.model = 0
  self.female = false
  local form = tostring(player.gender or d.form or "p0"):match("^p(%d+)$")
  if form then
    local index = tonumber(form) or 0
    self.model = math.floor(index / 2)
    self.female = index % 2 == 1
  end
  self.skin = player.skinTone or d.skinTone or 1
  local c = player.clothes or d.clothes or { r = 31, g = 31, b = 31 }
  self.clothes = { r = c.r or 31, g = c.g or 31, b = c.b or 31 }
  self.category = 1
  self.mode = "category"
  self.channel = 1
  return self
end

function PrismCustomization:formId()
  return string.format("p%d", self.model * 2 + (self.female and 1 or 0))
end

function PrismCustomization:models()
  return (self.spec and self.spec.models) or 1
end

function PrismCustomization:tones()
  return (self.spec and self.spec.skinTones) or {}
end

local function beep(self)
  Sound.play(self.game.data, "Press_AB")
end

function PrismCustomization:commit()
  local save = self.game.save
  if not save then return end
  save.player = save.player or {}
  save.player.gender = self:formId()
  save.player.skinTone = self.skin
  save.player.clothes = { r = self.clothes.r, g = self.clothes.g, b = self.clothes.b }
  -- the overworld player may already exist (the salon path); re-pick its sheet
  local ow = self.game.overworld
  if ow and ow.player and ow.player.refreshForm then
    pcall(function() ow.player:refreshForm(self.game.data) end)
  end
end

function PrismCustomization:finish()
  self:commit()
  self.game.stack:pop()
  if self.onDone then self.onDone(self:formId()) end
end

function PrismCustomization:updateCategory(input)
  if input:wasPressed("up") then
    self.category = self.category > 1 and self.category - 1 or #CATEGORIES
  elseif input:wasPressed("down") then
    self.category = self.category < #CATEGORIES and self.category + 1 or 1
  elseif input:wasPressed("a") then
    beep(self)
    local id = CATEGORIES[self.category]
    if id == "done" then
      self:finish()
    elseif id == "restart" then
      local d = (self.spec and self.spec.default) or {}
      self.model, self.female = 0, false
      self.skin = d.skinTone or 1
      self.clothes = { r = 31, g = 31, b = 31 }
    else
      self.mode = id
      self.channel = 1
    end
  end
end

function PrismCustomization:updateModel(input)
  local n = self:models()
  if input:wasPressed("up") then
    self.model = self.model > 0 and self.model - 1 or n - 1
  elseif input:wasPressed("down") then
    self.model = self.model < n - 1 and self.model + 1 or 0
  elseif input:wasPressed("left") or input:wasPressed("right") then
    self.female = not self.female
  elseif input:wasPressed("a") or input:wasPressed("b") then
    beep(self)
    self.mode = "category"
  end
end

function PrismCustomization:updateSkin(input)
  local n = #self:tones()
  if n < 1 then self.mode = "category" return end
  if input:wasPressed("up") then
    self.skin = self.skin > 1 and self.skin - 1 or n
  elseif input:wasPressed("down") then
    self.skin = self.skin < n and self.skin + 1 or 1
  elseif input:wasPressed("a") or input:wasPressed("b") then
    beep(self)
    self.mode = "category"
  end
end

function PrismCustomization:updateOutfit(input)
  local key = CHANNELS[self.channel]
  if input:wasPressed("up") then
    self.channel = self.channel > 1 and self.channel - 1 or #CHANNELS
  elseif input:wasPressed("down") then
    self.channel = self.channel < #CHANNELS and self.channel + 1 or 1
  elseif input:isDown("left") then
    self.clothes[key] = math.max(0, self.clothes[key] - 1)
  elseif input:isDown("right") then
    self.clothes[key] = math.min(MAX_LEVEL, self.clothes[key] + 1)
  elseif input:wasPressed("a") or input:wasPressed("b") then
    beep(self)
    self.mode = "category"
  end
end

function PrismCustomization:update()
  local input = self.game.input
  if self.mode == "category" then self:updateCategory(input)
  elseif self.mode == "model" then self:updateModel(input)
  elseif self.mode == "skin" then self:updateSkin(input)
  elseif self.mode == "outfit" then self:updateOutfit(input)
  end
end

function PrismCustomization:keypressed() end

local function swatch(x, y, w, h, r, g, b)
  love.graphics.setColor(r / MAX_LEVEL, g / MAX_LEVEL, b / MAX_LEVEL, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x, y, w, h)
end

function PrismCustomization:drawPreview()
  -- the chosen character, with the chosen skin and clothes shown beside it
  local tone = self:tones()[self.skin]
  Font.drawBox(11, 0, 9, 8)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings(self:formId():upper()), 12 * 8, 8)
  Font.draw(Strings("SKIN"), 12 * 8, 3 * 8)
  Font.draw(Strings("SUIT"), 12 * 8, 5 * 8)
  if tone then swatch(17 * 8, 3 * 8, 16, 8, tone.r, tone.g, tone.b) end
  swatch(17 * 8, 5 * 8, 16, 8, self.clothes.r, self.clothes.g, self.clothes.b)
  love.graphics.setColor(1, 1, 1, 1)
end

function PrismCustomization:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.clear(1, 1, 1, 1)
  self:drawPreview()

  Font.drawBox(0, 0, 11, 12)
  love.graphics.setColor(0, 0, 0, 1)
  if self.mode == "category" then
    for i, id in ipairs(CATEGORIES) do
      Font.draw(Strings(CATEGORY_LABEL[id]), 2 * 8, i * 16 - 8)
      if i == self.category then Font.drawCode(Theme.cursor, 8, i * 16 - 8) end
    end
  elseif self.mode == "model" then
    Font.draw(Strings(self.female and "GIRL" or "BOY"), 2 * 8, 8)
    for i = 0, self:models() - 1 do
      Font.draw(Strings(string.format("MODEL %d", i + 1)), 2 * 8, (i + 2) * 16 - 8)
      if i == self.model then Font.drawCode(Theme.cursor, 8, (i + 2) * 16 - 8) end
    end
  elseif self.mode == "skin" then
    for i, tone in ipairs(self:tones()) do
      Font.draw(Strings(string.format("TONE %d", i)), 2 * 8, i * 12 - 4)
      swatch(9 * 8, i * 12 - 4, 8, 8, tone.r, tone.g, tone.b)
      if i == self.skin then Font.drawCode(Theme.cursor, 8, i * 12 - 4) end
      love.graphics.setColor(0, 0, 0, 1)
    end
  elseif self.mode == "outfit" then
    for i, key in ipairs(CHANNELS) do
      local y = i * 24 - 8
      Font.draw(Strings(CHANNEL_LABEL[key]), 2 * 8, y)
      if i == self.channel then Font.drawCode(Theme.cursor, 8, y) end
      local level = self.clothes[key]
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", 4 * 8, y, 48, 8)
      love.graphics.rectangle("fill", 4 * 8, y, 48 * level / MAX_LEVEL, 8)
      love.graphics.setColor(0, 0, 0, 1)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return PrismCustomization
