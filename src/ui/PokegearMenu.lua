

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local PokegearMenu = {}
PokegearMenu.__index = PokegearMenu
PokegearMenu.isOpaque = true

local SCREEN_W, SCREEN_H = 20, 18
local BLANK_TILE = 0x4F
local SPACE_TILE = 0x7F

local DAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY",
               "FRIDAY", "SATURDAY" }

local STATIONS = {
  { name = "OAK'S POKéMON TALK", lines = { "PROF.OAK: Today's", "sighting is..." } },
  { name = "POKéDEX SHOW", lines = { "DJ MARY: Today's", "featured #MON!" } },
  { name = "POKéMON MUSIC", lines = { "Now playing the", "#MON MARCH..." } },
  { name = "LUCKY CHANNEL", lines = { "REED: Check your", "LOTTO number!" } },
  { name = "BUENA'S PASSWORD", lines = { "BUENA: Tonight's", "password is..." } },
  { name = "PLACES & PEOPLE", lines = { "A trainer was", "spotted training." } },
}

-- Card strip icons (Pokegear_FinishTilemap): 2x2 from tile id
local CARD_DEFS = {
  { id = "CLOCK", icon = 0x46, iconX = 0 },
  { id = "MAP",   icon = 0x40, iconX = 2, flag = "map" },
  { id = "PHONE", icon = 0x44, iconX = 4 },
  { id = "RADIO", icon = 0x42, iconX = 6, flag = "radio" },
}

local BEAST_SPECIES = {
  RAIKOU = "SPECIES_243", ENTEI = "SPECIES_244", SUICUNE = "SPECIES_245",
}

local function flagOn(flags, names)
  for _, n in ipairs(names) do
    if flags[n] == true then return true end
  end
  return false
end

local function hasExpn(save)
  local flags = save.flags or {}
  local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  local key = ok and Gen2Flags.engineFlag(3) or "ENGINE_EXPN_CARD"
  return flags[key] == true or flags.EVENT_GOT_EXPN_CARD == true
    or flags.ENGINE_EXPN_CARD == true
end

local function visibleCards(save)
  local flags = save.flags or {}
  local list = {}
  for _, def in ipairs(CARD_DEFS) do
    if def.flag == "map" then
      if flagOn(flags, { "EVENT_GOT_MAP_CARD", "ENGINE_MAP_CARD" }) then
        list[#list + 1] = def
      end
    elseif def.flag == "radio" then
      if flagOn(flags, { "EVENT_GOT_RADIO_CARD", "ENGINE_RADIO_CARD" }) then
        list[#list + 1] = def
      end
    else
      list[#list + 1] = def
    end
  end
  return list
end

local KANTO_LANDMARK_FIRST = 0x2F
local images = {}

local function loadImage(path)
  if not path then return nil end
  if images[path] == nil then
    local Assets = require("src.render.Assets")
    local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
    images[path] = ok and img or false
  end
  return images[path] or nil
end

local function monIconPath(game, species)
  local key = tostring(species or "")
  local upper = key:upper()
  local speciesId = BEAST_SPECIES[upper] or upper
  if not speciesId:match("^SPECIES_") and tonumber(speciesId) then
    speciesId = string.format("SPECIES_%03d", tonumber(speciesId))
  end
  local data = game and game.data or {}
  local by = (data.icons and data.icons.bySpecies) or {}
  local entry = by[speciesId] or by[speciesId:lower()]
  if type(entry) == "table" and entry.image then return entry.image end
  if type(entry) == "string" then return entry end
  local poke = data.pokemon or {}
  local def = poke[speciesId]
  if type(def) == "table" and def.icon then return def.icon end
  return "assets/generated/icons/" .. speciesId:lower() .. ".png"
end

function PokegearMenu.new(game, opts)
  opts = opts or {}
  pcall(function()
    require("src.script.Gen2Commands").g2_ensure_roam_landmarks({ save = game.save, game = game })
  end)
  local self = setmetatable({
    game = game,
    onCancel = opts.onCancel,
    cards = visibleCards(game.save),
    index = 1,
    station = 1,
    contact = 1,
    phoneSubmenu = nil,
    callText = nil,
    blink = 0,
    sheet = nil,
    quads = {},
  }, PokegearMenu)
  self:loadSheet()
  return self
end

function PokegearMenu:loadSheet()
  local gear = (self.game.data.field or {}).pokegear or {}
  local path = gear.tiles or "assets/generated/ui/pokegear_gear.png"
  local img = loadImage(path)
  -- Fallback to older extract name
  if not img then img = loadImage("assets/generated/ui/pokegear_tiles.png") end
  self.sheet = img
  self.quads = {}
  self.gfx = gear
  if img then
    local iw, ih = img:getDimensions()
    local wide = gear.tilesWide or 16
    local rows = math.floor(ih / 8)
    for row = 0, rows - 1 do
      for col = 0, wide - 1 do
        local id = row * wide + col
        self.quads[id] = love.graphics.newQuad(col * 8, row * 8, 8, 8, iw, ih)
      end
    end
  end
end

-- gfx/pokegear/pokegear.pal entry 0: RGB 28,31,20 / mid greys / black
function PokegearMenu:paperColor()
  local pals = self.gfx and self.gfx.palettes
  local p = pals and (pals[1] or pals[0])
  if type(p) == "table" then
    local c = p[1] or p[0]
    if type(c) == "table" and (c[1] or 0) > 0 then
      -- Accept 0-1 float or 0-255 int
      if (c[1] or 0) <= 1 and (c[2] or 0) <= 1 then
        return {
          math.floor((c[1] or 0) * 255 + 0.5),
          math.floor((c[2] or 0) * 255 + 0.5),
          math.floor((c[3] or 0) * 255 + 0.5),
        }
      end
      return c
    end
  end
  -- Forced cream (PokegearPals RGB 28,31,20) — avoid white from bad extract
  return { 230, 255, 164 }
end

function PokegearMenu:groundColor()
  local pals = self.gfx and self.gfx.palettes
  local p = pals and (pals[1] or pals[0])
  if type(p) == "table" then
    local c = p[4] or p[3]
    if type(c) == "table" then
      if (c[1] or 0) <= 1 and (c[2] or 0) <= 1 then
        return {
          math.floor((c[1] or 0) * 255 + 0.5),
          math.floor((c[2] or 0) * 255 + 0.5),
          math.floor((c[3] or 0) * 255 + 0.5),
        }
      end
      return c
    end
  end
  return { 0, 0, 0 }
end

function PokegearMenu:tile(id, tx, ty)
  local G = love.graphics
  id = tonumber(id) or id
  if id == SPACE_TILE then
    -- Cream paper (never pure white)
    G.setColor(230 / 255, 255 / 255, 164 / 255, 1)
    G.rectangle("fill", tx * 8, ty * 8, 8, 8)
    G.setColor(1, 1, 1, 1)
    return
  end
  if id == BLANK_TILE then
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", tx * 8, ty * 8, 8, 8)
    G.setColor(1, 1, 1, 1)
    return
  end
  if self.sheet and self.quads[id] then
    G.setColor(1, 1, 1, 1)
    G.draw(self.sheet, self.quads[id], tx * 8, ty * 8)
  end
end

function PokegearMenu:drawTilemap(cells)
  if not cells then return end
  for index = 1, SCREEN_W * SCREEN_H do
    local tile = cells[index]
    if tile then
      self:tile(tile, (index - 1) % SCREEN_W, math.floor((index - 1) / SCREEN_W))
    end
  end
end

-- Pokegear_FinishTilemap: 2x2 icons for each owned card
function PokegearMenu:drawStrip()
  for x = 0, SCREEN_W - 1 do
    self:tile(BLANK_TILE, x, 0)
    self:tile(BLANK_TILE, x, 1)
  end
  for _, card in ipairs(self.cards) do
    local n, x = card.icon, card.iconX
    self:tile(n, x, 0)
    self:tile(n + 1, x + 1, 0)
    self:tile(n + 0x10, x, 1)
    self:tile(n + 0x11, x + 1, 1)
  end
end

function PokegearMenu:drawModeArrow()
  local card = self.cards[self.index]
  if not card then return end
  local sprites = loadImage((self.gfx and self.gfx.sprites)
    or "assets/generated/ui/pokegear_sprites.png")
  local iconX = card.iconX * 8
  if sprites then
    local iw, ih = sprites:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    -- 16x16 arrow from first 4 tiles (2x2)
    local q0 = love.graphics.newQuad(0, 0, 8, 8, iw, ih)
    local q1 = love.graphics.newQuad(8, 0, 8, 8, iw, ih)
    local q2 = love.graphics.newQuad(0, 8, 8, 8, iw, ih)
    local q3 = love.graphics.newQuad(8, 8, 8, 8, iw, ih)
    local y = 12
    love.graphics.draw(sprites, q0, iconX, y)
    love.graphics.draw(sprites, q1, iconX + 8, y)
    love.graphics.draw(sprites, q2, iconX, y + 8)
    love.graphics.draw(sprites, q3, iconX + 8, y + 8)
  else
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.polygon("fill",
      iconX + 4, 16, iconX + 12, 16, iconX + 8, 22)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function PokegearMenu:text(str, tx, ty)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings(tostring(str or "")), tx * 8, ty * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Cream plate under a framed textbox (Font.drawBox would force white).
function PokegearMenu:drawPlate(tx, ty, tw, th)
  love.graphics.setColor(230 / 255, 255 / 255, 164 / 255, 1)
  love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Framed dialog box: cream fill + border glyphs (or grey rect fallback).
function PokegearMenu:textbox(tx, ty, interiorW, interiorH)
  local tw, th = interiorW + 2, interiorH + 2
  self:drawPlate(tx, ty, tw, th)
  local G = love.graphics
  local B = Font.BORDER
  if B and B.tl and Font.drawCode then
    G.setColor(0, 0, 0, 1)
    Font.drawCode(B.tl, tx * 8, ty * 8)
    Font.drawCode(B.tr, (tx + tw - 1) * 8, ty * 8)
    Font.drawCode(B.bl, tx * 8, (ty + th - 1) * 8)
    Font.drawCode(B.br, (tx + tw - 1) * 8, (ty + th - 1) * 8)
    for x = 1, tw - 2 do
      Font.drawCode(B.t or B.h or B.tl, (tx + x) * 8, ty * 8)
      Font.drawCode(B.b or B.h or B.bl, (tx + x) * 8, (ty + th - 1) * 8)
    end
    for y = 1, th - 2 do
      Font.drawCode(B.l or B.v or B.tl, tx * 8, (ty + y) * 8)
      Font.drawCode(B.r or B.v or B.tr, (tx + tw - 1) * 8, (ty + y) * 8)
    end
  else
    -- Grey frame fallback when Font.BORDER is unavailable
    G.setColor(0.4, 0.4, 0.4, 1)
    G.setLineWidth(2)
    G.rectangle("line", tx * 8 + 1, ty * 8 + 1, tw * 8 - 2, th * 8 - 2)
    G.setLineWidth(1)
  end
  G.setColor(1, 1, 1, 1)
end

function PokegearMenu:printBoxText(line1, line2)
  self:text(line1 or "", 1, 14)
  if line2 then self:text(line2, 1, 16) end
end

function PokegearMenu:current()
  return self.cards[self.index]
end

function PokegearMenu:contacts()
  local phone = (self.game.data.field or {}).phone or {}
  local list = phone.contacts or {}
  if #list == 0 then
    list = { { name = "MOM" }, { name = "PROF.ELM" } }
  end
  return list
end

function PokegearMenu:stationList()
  local list = {}
  for _, st in ipairs(STATIONS) do list[#list + 1] = st end
  if hasExpn(self.game.save) then
    list[#list + 1] = {
      name = "POKé FLUTE",
      lines = { "Playing the", "POKé FLUTE..." },
      flute = true,
    }
  end
  return list
end

function PokegearMenu:update(dt)
  self.blink = (self.blink + dt) % 1
  local input = self.game.input
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
    return
  end
  if input:wasPressed("left") and not self.phoneSubmenu then
    self.index = self.index > 1 and self.index - 1 or #self.cards
    self.callText = nil
    Sound.play(self.game.data, "Tink")
  elseif input:wasPressed("right") and not self.phoneSubmenu then
    self.index = self.index < #self.cards and self.index + 1 or 1
    self.callText = nil
    Sound.play(self.game.data, "Tink")
  end
  local card = self:current()
  if not card then return end
  if card.id == "RADIO" then
    local n = #self:stationList()
    if input:wasPressed("down") then
      self.station = self.station < n and self.station + 1 or 1
      Sound.play(self.game.data, "Tink")
    elseif input:wasPressed("up") then
      self.station = self.station > 1 and self.station - 1 or n
      Sound.play(self.game.data, "Tink")
    end
    local st = self:stationList()[self.station]
    if st and st.flute then
      self.game.save.g2RadioChannel = "POKE_FLUTE"
      self.game.save.g2MapMusic = "MUSIC_POKE_FLUTE_CHANNEL"
    end
  elseif card.id == "PHONE" then
    local list = self:contacts()
    if self.phoneSubmenu then
      if input:wasPressed("a") then
        local entry = list[self.contact]
        Sound.play(self.game.data, "Press_AB")
        self.phoneSubmenu = nil
        self.callText = nil
        if entry then
          self:startPhoneCall(entry)
        end
      elseif input:wasPressed("b") then
        Sound.play(self.game.data, "Press_AB")
        self.phoneSubmenu = nil
        self.callText = nil
      end
    else
      if input:wasPressed("down") then
        self.contact = self.contact < #list and self.contact + 1 or 1
        Sound.play(self.game.data, "Tink")
      elseif input:wasPressed("up") then
        self.contact = self.contact > 1 and self.contact - 1 or #list
        Sound.play(self.game.data, "Tink")
      elseif input:wasPressed("a") then
        if #list > 0 then
          self.phoneSubmenu = true
          Sound.play(self.game.data, "Press_AB")
        end
      end
    end
  end
end

-- Outgoing phone dialogue (simplified MakePhoneCallFromPokegear).
-- Pushes a TextBox with contact-specific lines so the call is not just a status string.
local PHONE_DIALOG = {
  MOM = {
    "Hello?",
    "Oh, hi, <PLAYER>! Working hard?",
    "Don't forget to rest when you're tired!",
  },
  ["PROF.ELM"] = {
    "Hello, <PLAYER>?",
    "Ah, good to hear from you!",
    "How is your #MON research going?",
  },
  ELM = {
    "Hello, <PLAYER>?",
    "Ah, good to hear from you!",
    "How is your #MON research going?",
  },
  BIKE_SHOP = {
    "Hello? This is the BIKE SHOP.",
    "Have you been riding a lot?",
  },
}

function PokegearMenu:startPhoneCall(entry)
  local name = tostring(entry.name or entry or "?"):upper()
  local save = self.game.save or {}
  local player = (save.player and save.player.name)
    or save.playerName or save.name or "PLAYER"
  local lines = PHONE_DIALOG[name]
  if not lines then
    local key = name:gsub("[^A-Z]", "")
    for k, v in pairs(PHONE_DIALOG) do
      if k:gsub("[^A-Z]", "") == key then lines = v break end
    end
  end
  if not lines then
    lines = {
      "Hello?",
      "This is " .. name .. ".",
      "Thanks for calling!",
    }
  end
  -- \f page breaks so TextBox paginates like other dialogue
  local pages = {}
  for _, line in ipairs(lines) do
    pages[#pages + 1] = line:gsub("<PLAYER>", player):gsub("#MON", "POKéMON")
  end
  local body = table.concat(pages, "\f")
  pcall(function() Sound.play(self.game.data, "Call") end)
  local TextBox = require("src.render.TextBox")
  local game = self.game
  -- TextBox.substitute expands <PLAYER> etc. from the save as well
  game.stack:push(TextBox.new(game, body, function()
    pcall(function() Sound.play(game.data, "Hang_Up") end)
  end))
end

function PokegearMenu:drawClock()
  local cells = self.gfx and self.gfx.cards and self.gfx.cards.clock
  if cells then
    self:drawTilemap(cells)
  else
    local ground = self:groundColor()
    love.graphics.setColor(ground[1]/255, ground[2]/255, ground[3]/255, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  self:drawStrip()
  self:text("SWITCH", 13, 1)

  local save = self.game.save
  local t = math.floor(save.playTime or 0)
  local hour = math.floor(t / 3600) % 24
  local minute = math.floor(t / 60) % 60
  local day = DAYS[(math.floor(t / 86400) % 7) + 1]
  local display = hour % 12
  if display == 0 then display = 12 end
  self:text(day, 6, 6)
  self:text(string.format("%2d", display), 6, 8)
  self:text(self.blink < 0.5 and ":" or " ", 8, 8)
  self:text(string.format("%02d", minute), 9, 8)
  self:text(hour < 12 and "AM" or "PM", 12, 8)

  -- Bottom dialog (lb bc, 4, 18 at row 12) — PokegearPressButtonText
  self:textbox(0, 12, 18, 4)
  self:printBoxText("Press the A Button", "to exit.")
  self:drawModeArrow()
end

function PokegearMenu:drawRadio()
  local cells = self.gfx and self.gfx.cards and self.gfx.cards.radio
  if cells then
    self:drawTilemap(cells)
  else
    local ground = self:groundColor()
    love.graphics.setColor(ground[1]/255, ground[2]/255, ground[3]/255, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  self:drawStrip()
  local stations = self:stationList()
  local st = stations[self.station] or stations[1]
  self:textbox(0, 12, 18, 4)
  if st then
    self:printBoxText(st.name, st.lines and st.lines[1] or "")
  end
  self:drawModeArrow()
end

function PokegearMenu:drawPhone()
  local cells = self.gfx and self.gfx.cards and self.gfx.cards.phone
  if cells then
    self:drawTilemap(cells)
  else
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  self:drawStrip()

  local list = self:contacts()
  if type(list) ~= "table" or #list == 0 then
    list = { { name = "MOM" }, { name = "PROF.ELM" } }
  end
  if self.contact < 1 then self.contact = 1 end
  if self.contact > #list then self.contact = #list end

  local selectedName = nil
  -- One row per contact, starting at tile row 4 (inside the cream plate)
  for i, entry in ipairs(list) do
    local name = tostring(
      (type(entry) == "table" and (entry.name or entry.label)) or entry or "?"
    ):upper()
    local ty = 3 + i   -- MOM at row 4, next at 5, ...
    if ty > 11 then break end

    if i == self.contact then
      selectedName = name
      -- Inverted selection: black row + cream glyphs via Font tint shader
      -- (atlas is black-on-transparent; setColor alone cannot lighten it)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 16, ty * 8, 128, 8)
      love.graphics.setColor(230 / 255, 255 / 255, 164 / 255, 1)
      if Font.beginTint then Font.beginTint() end
      Font.draw(Strings("> " .. name), 18, ty * 8)
      if Font.endTint then Font.endTint() end
      love.graphics.setColor(1, 1, 1, 1)
    else
      self:text(name, 3, ty)
    end
  end

  -- pret _PokegearAskWhoCallText: "Whom do you want" / "to call?"
  self:textbox(0, 12, 18, 4)
  if self.phoneSubmenu and selectedName then
    self:printBoxText("Call " .. selectedName .. "?", "A=Yes  B=No")
  else
    self:printBoxText("Whom do you want", "to call?")
  end
  self:drawModeArrow()
end

function PokegearMenu:drawMap()
  local game = self.game
  local town = (game.data.field or {}).townMap or {}
  local gear = self.gfx or {}
  local ow = game.overworld
  local def = ow and ow.map and ow.map.def
  local landmark = def and def.landmark
  local entry = landmark and town.landmarks
    and (town.landmarks[landmark] or town.landmarks[tostring(landmark)])
  local path = (landmark and landmark >= KANTO_LANDMARK_FIRST and town.kanto)
    or town.johto
  local image = path and loadImage(path)
  if image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0)
    pcall(function()
      require("src.render.PaletteFX").markTrueColor(0, 16, 160, 128)
    end)
  else
    local ground = self:groundColor()
    love.graphics.setColor(ground[1]/255, ground[2]/255, ground[3]/255, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  self:drawStrip()
  if entry and entry.name then
    self:text(tostring(entry.name):gsub("[\n\f\v]", " "), 8, 0)
  end
  -- Player
  local playerIcon = loadImage(gear.playerIcon) or loadImage(town.playerIcon)
  if entry then
    local px = (tonumber(entry.x) or 0) - 8
    local py = (tonumber(entry.y) or 0) - 16
    if playerIcon then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(playerIcon, px, py)
    end
  end
  -- Roam dogs (only after Burned Tower)
  local roam = game.save.g2RoamReleased and game.save.g2Roam
  if type(roam) == "table" and town.landmarks then
    for species, info in pairs(roam) do
      if info and info ~= false then
        local lm = type(info) == "table" and tonumber(info.landmark) or nil
        local loc = lm and (town.landmarks[lm] or town.landmarks[tostring(lm)])
        if loc then
          local cx = (tonumber(loc.x) or 0) - 4
          local cy = (tonumber(loc.y) or 0) - 12
          local monKey = (type(info) == "table" and info.speciesId) or species
          local monImg = loadImage(monIconPath(game, monKey))
          love.graphics.setColor(0.15, 0.85, 0.25, 1)
          love.graphics.rectangle("line", cx - 9, cy - 9, 18, 18)
          if monImg then
            love.graphics.setColor(1, 1, 1, 1)
            local iw, ih = monImg:getDimensions()
            if ih >= 32 and iw <= 16 then
              local q = love.graphics.newQuad(0, 0, iw, 16, iw, ih)
              love.graphics.draw(monImg, q, cx - 8, cy - 8)
            else
              love.graphics.draw(monImg, cx - 8, cy - 8, 0,
                math.min(16/iw, 16/ih), math.min(16/iw, 16/ih))
            end
          end
        end
      end
    end
  end
  self:drawModeArrow()
end

function PokegearMenu:draw()
  -- Skip SGB/GBC shade-remap so the extracted cream/chrome colours stay true
  -- (same path TownMap:drawGen2 uses for the region map).
  pcall(function()
    local P = require("src.render.PaletteFX")
    if P.setPass then P.setPass("ui") end
    P.markTrueColor(0, 0, 160, 144)
  end)

  local card = self:current()
  if not card then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    return
  end
  if card.id == "MAP" then
    self:drawMap()
  elseif card.id == "RADIO" then
    self:drawRadio()
  elseif card.id == "PHONE" then
    self:drawPhone()
  else
    self:drawClock()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return PokegearMenu
