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

-- THE CHARACTER YOU ARE PICKING, ACTUALLY DRAWN.
--
-- The screen used to show the form's ID ("P0", "P4") and a row of "MODEL 1",
-- "MODEL 2" labels, so the player chose a character by reading a number and
-- never saw who it was. `field.playerForms` already carries a pic path per form
-- -- it is what OakSpeech:formPic uses to swap CHRIS and KRIS above the
-- boy/girl question -- and Prism keys it under exactly the p0..p13 ids this
-- screen produces, so nothing new had to be extracted.
--
-- Cached per form: this runs every frame while the cursor moves, and decoding a
-- pic per frame would be felt.
-- The palette the CURRENTLY SELECTED choices make, as a 4-colour OBJ palette.
-- Built off a player sheet's own gen2ObjPal so entry 0 and the outline come
-- from the art rather than being invented here.
function PrismCustomization:previewPalette()
  local ok, PlayerPalette = pcall(require, "src.render.PlayerPalette")
  if not ok then return nil end
  local sprites = self.game.data and self.game.data.sprites or {}
  local field = self.game.data and self.game.data.field
  local form = field and field.playerForms and field.playerForms[self:formId()]
  local walk = form and form.walk
  local base = walk and sprites[walk] and sprites[walk].gen2ObjPal
  if not base then
    -- any player sheet will do for the two entries we are not choosing
    local fallback = sprites.SPRITE_PLAYER0
    base = fallback and fallback.gen2ObjPal
  end
  if not base then return nil end
  -- the LIVE selections, not what is on the save: the whole point of the
  -- preview is to show a choice before it is committed
  local tone = self:tones()[self.skin]
  local pretend = { player = { skinTone = self.skin, clothes = self.clothes } }
  if not tone then pretend.player.skinTone = nil end
  return PlayerPalette.of(self.game.data, pretend, base)
end

function PrismCustomization:formPic(id)
  -- KEYED ON THE COLOURS AS WELL AS THE MODEL.
  --
  -- The cache used to hold one entry per form id, which is right while the
  -- only thing that changes is which character you picked -- and wrong the
  -- moment the picture depends on the skin tone and the outfit too. Dragging a
  -- slider re-entered this, found the id already cached, and handed back the
  -- picture baked with the previous mix, so the preview sat still while the
  -- swatch beside it moved.
  local colors, key = self:previewPalette()
  local cacheKey = id .. "|" .. tostring(key or "-")
  self._pics = self._pics or {}
  local hit = self._pics[cacheKey]
  if hit ~= nil then return hit[1], hit[2] end
  local field = self.game.data and self.game.data.field
  local forms = field and field.playerForms
  local form = forms and forms[id]
  local path = form and (form.intro or form.card or form.front)
  local img = nil
  local trueColor = (form and form.trueColor) and true or false
  if path then
    -- Full-colour art is already the finished picture and cannot be
    -- re-palettised; four-shade art is exactly what the OBP bake is for, and
    -- is what Prism's player pics are.
    if colors and not trueColor then
      local okBake, baked = pcall(function()
        return require("src.render.SpriteRenderer").obpImage(path, colors, "prismcust:" .. cacheKey)
      end)
      img = okBake and baked or nil
      -- a baked pic is full colour, so it must claim its cell out of the
      -- shade-remap pass exactly like trueColor art does
      if img then trueColor = true end
    end
    if not img then
      local ok, loaded = pcall(function()
        return require("src.render.Assets").image(path)
      end)
      img = ok and loaded or nil
      trueColor = (form and form.trueColor) and true or false
    end
  end
  self._pics[cacheKey] = { img, (img and trueColor) and true or false }
  return self._pics[cacheKey][1], self._pics[cacheKey][2]
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

-- EVERY COLOUR ON THIS SCREEN MUST BE MARKED TRUE-COLOUR.
--
-- The whole UI is drawn into the 160x144 Game Boy canvas and then run through
-- the SGB/DMG zone remap, which snaps what it covers to the four GB shades.
-- That is right for Game Boy art and completely wrong for a colour picker: the
-- player mixes an RGB15 value, and the swatch shows them whichever GB shade it
-- happened to land nearest. Marking the rect exempts it from the remap, which
-- is the same thing PicBox, SummaryMenu and the Pokegear do for their
-- full-colour art.
local function trueColorRect(x, y, w, h)
  local ok, P = pcall(require, "src.render.PaletteFX")
  if ok and P and type(P.markTrueColor) == "function" then
    pcall(P.markTrueColor, x, y, w, h)
  end
end

local function swatch(x, y, w, h, r, g, b)
  trueColorRect(x, y, w, h)
  love.graphics.setColor(r / MAX_LEVEL, g / MAX_LEVEL, b / MAX_LEVEL, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x, y, w, h)
end

-- THE PANEL IS AS TALL AS THE SCREEN AND THE LABELS SIT UNDER THE PICTURE.
--
-- It used to be an 8-tile-high box with the character drawn at (12,1) and the
-- three labels drawn at (12,1), (12,3) and (12,5) -- the same column, starting
-- on the same row as the picture. A Prism player pic is 56x56, seven tiles
-- square, so it covered all three of them: the panel showed "Po", "SK" and
-- "SUI" with a trainer standing on top of the rest, which is what the report
-- called overlapping.
--
-- Nothing here can be narrowed to fix that. The picture needs seven interior
-- tiles and "SKIN TONE" needs nine, and seven plus nine plus a cursor column
-- plus four box borders does not fit across twenty. So the two panels SHARE
-- their divider column -- the menu is drawn first and 12 wide, this one starts
-- on its last column and paints over it -- which buys back the tile that made
-- the difference, and the labels move underneath the picture where there is
-- all the room they need.
--
--   menu    tiles 0..11, interior 1..10   -- fits SKIN TONE at column 2
--   divider tile 11, drawn by whichever box paints it last
--   preview tiles 11..19, interior 12..18 -- exactly 56px for the pic
function PrismCustomization:drawPreview()
  -- the chosen character, with the chosen skin and clothes shown below it
  local tone = self:tones()[self.skin]
  Font.drawBox(11, 0, 9, 18)

  local pic, picTrue = self:formPic(self:formId())
  if pic then
    local pw, ph = pic:getWidth(), pic:getHeight()
    local px, py = 12 * 8, 8
    if picTrue then trueColorRect(px, py, pw, ph) end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(pic, px, py)
  end

  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings(self:formId():upper()), 12 * 8, 9 * 8)
  Font.draw(Strings("SKIN"), 12 * 8, 11 * 8)
  Font.draw(Strings("SUIT"), 12 * 8, 13 * 8)
  if tone then swatch(17 * 8, 11 * 8, 16, 8, tone.r, tone.g, tone.b) end
  swatch(17 * 8, 13 * 8, 16, 8, self.clothes.r, self.clothes.g, self.clothes.b)
  love.graphics.setColor(1, 1, 1, 1)
end

function PrismCustomization:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.clear(1, 1, 1, 1)
  self:drawPreview()

  -- One column wider and full height: at 11 the interior stopped at column 9
  -- and "SKIN TONE", drawn from column 2, ran onto the frame itself. Full
  -- height because the MODEL list is up to seven rows and reached row 15.
  Font.drawBox(0, 0, 12, 18)
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
      -- THE BAR WAS ALWAYS BLACK. The fill reused the colour set for the
      -- outline immediately above it and never set its own, so all three
      -- channels drew solid black at every level -- the player was mixing a
      -- colour against three black bars. Fill in the CHANNEL'S own colour at
      -- the level chosen, so R reads as red at the height it is set to.
      trueColorRect(4 * 8, y, 48, 8)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", 4 * 8, y, 48, 8)
      love.graphics.setColor(key == "r" and level / MAX_LEVEL or 0,
                             key == "g" and level / MAX_LEVEL or 0,
                             key == "b" and level / MAX_LEVEL or 0, 1)
      love.graphics.rectangle("fill", 4 * 8, y, 48 * level / MAX_LEVEL, 8)
      love.graphics.setColor(0, 0, 0, 1)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return PrismCustomization
