-- The POKéGEAR (engine/pokegear/pokegear.asm).  Mom hands it over on the
-- way out of New Bark; it is not a bag item in Gen2, it is a START-menu
-- feature gated on EVENT_GOT_POKEGEAR.
--
-- Cards switch with LEFT/RIGHT.  CLOCK and PHONE ship with the unit; MAP
-- arrives with the MAP CARD and RADIO with the RADIO CARD.  EXPN Card
-- (Lavender) unlocks the Poké Flute radio channel.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local PokegearMenu = {}
PokegearMenu.__index = PokegearMenu
PokegearMenu.isOpaque = true

local DAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY",
               "FRIDAY", "SATURDAY" }

local STATIONS = {
  { name = "OAK'S POKéMON TALK",
    lines = { "PROF.OAK: Today's", "sighting is..." } },
  { name = "POKéDEX SHOW",
    lines = { "DJ MARY: Today's", "featured #MON!" } },
  { name = "POKéMON MUSIC",
    lines = { "Now playing the", "#MON MARCH..." } },
  { name = "LUCKY CHANNEL",
    lines = { "REED: Check your", "LOTTO number!" } },
  { name = "BUENA'S PASSWORD",
    lines = { "BUENA: Tonight's", "password is..." } },
  { name = "PLACES & PEOPLE",
    lines = { "A trainer was", "spotted training." } },
}

local function flagOn(flags, names)
  for _, n in ipairs(names) do
    if flags[n] == true then return true end
  end
  return false
end

local function cards(save)
  local flags = save.flags or {}
  local list = { "CLOCK" }
  if flagOn(flags, { "EVENT_GOT_MAP_CARD", "ENGINE_MAP_CARD" }) then
    list[#list + 1] = "MAP"
  end
  if flagOn(flags, { "EVENT_GOT_RADIO_CARD", "ENGINE_RADIO_CARD" }) then
    list[#list + 1] = "RADIO"
  end
  list[#list + 1] = "PHONE"
  return list
end

local function hasExpn(save)
  local flags = save.flags or {}
  local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  local key = ok and Gen2Flags.engineFlag(3) or "ENGINE_EXPN_CARD"
  return flags[key] == true
    or flags.EVENT_GOT_EXPN_CARD == true
    or flags.ENGINE_EXPN_CARD == true
end


-- Gen2 extract writes icons as species_243.png (SPECIES_%03d:lower()).
-- Paths live in data.icons.bySpecies[id].image (NOT always data.pokemon.icon).
local BEAST_SPECIES = {
  RAIKOU = "SPECIES_243",
  ENTEI = "SPECIES_244",
  SUICUNE = "SPECIES_245",
}

local function monIconPath(game, species)
  local key = tostring(species or "")
  local upper = key:upper()
  local speciesId = BEAST_SPECIES[upper] or upper
  if not speciesId:match("^SPECIES_") and tonumber(speciesId) then
    speciesId = string.format("SPECIES_%03d", tonumber(speciesId))
  end
  local data = game and game.data or {}
  -- 1) data.icons.bySpecies (RomExtractorGen2:extractIcons)
  local icons = data.icons or {}
  local by = icons.bySpecies or icons.byDex or {}
  local entry = by[speciesId] or by[speciesId:lower()] or by[upper]
  if type(entry) == "table" and entry.image then return entry.image end
  if type(entry) == "string" then return entry end
  -- 2) data.pokemon[id].icon
  local poke = data.pokemon or {}
  local def = poke[speciesId] or poke[upper] or poke[key]
  if type(def) == "table" and def.icon then return def.icon end
  for id, d in pairs(poke) do
    if type(d) == "table" then
      local n = tostring(d.name or ""):upper():gsub("[^A-Z0-9]", "")
      if n == upper:gsub("[^A-Z0-9]", "") or tostring(id):upper() == speciesId then
        if d.icon then return d.icon end
        local e2 = by[id] or by[tostring(id):upper()]
        if type(e2) == "table" and e2.image then return e2.image end
      end
    end
  end
  -- 3) direct file paths (try several patterns)
  return "assets/generated/icons/" .. speciesId:lower() .. ".png"
end

-- Try several candidate paths until one loads

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

local function loadMonIcon(game, species)
  local primary = monIconPath(game, species)
  local speciesId = BEAST_SPECIES[tostring(species or ""):upper()]
    or tostring(species or "")
  local candidates = {
    primary,
    "assets/generated/icons/" .. tostring(speciesId):lower() .. ".png",
    "assets/generated/icons/species_243.png", -- only used as last resort below
  }
  -- Build candidate list without hardcoding wrong beast
  candidates = { primary }
  local sid = BEAST_SPECIES[tostring(species or ""):upper()] or tostring(species or "")
  if not sid:match("^SPECIES_") and tonumber(sid) then
    sid = string.format("SPECIES_%03d", tonumber(sid))
  end
  candidates[#candidates + 1] = "assets/generated/icons/" .. sid:lower() .. ".png"
  candidates[#candidates + 1] = "assets/generated/icons/" .. tostring(species or ""):lower() .. ".png"
  for _, path in ipairs(candidates) do
    local img = loadImage(path)
    if img then return img, path end
  end
  return nil, primary
end

PokegearMenu.FALLBACK_PAL = {
  { 255, 247, 180 }, { 168, 168, 168 }, { 80, 80, 80 }, { 0, 0, 0 },
}

function PokegearMenu:shellPalette()
  local gear = (self.game.data.field or {}).pokegear
  local pals = gear and gear.palettes
  return (pals and (pals[0] or pals[1])) or PokegearMenu.FALLBACK_PAL
end

function PokegearMenu:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  return { P.whole(self:shellPalette()) }
end

function PokegearMenu.new(game, opts)
  opts = opts or {}
  -- Never spawn beasts here — only refresh landmarks after Burned Tower
  pcall(function()
    require("src.script.Gen2Commands").g2_ensure_roam_landmarks({ save = game.save, game = game })
  end)
  local self = setmetatable({
    game = game,
    onCancel = opts.onCancel,
    cards = cards(game.save),
    index = 1,
    station = 1,
    contact = 1,
    blink = 0,
  }, PokegearMenu)
  return self
end

function PokegearMenu:current()
  return self.cards[self.index]
end

function PokegearMenu:contacts()
  local phone = (self.game.data.field or {}).phone or {}
  local list = phone.contacts or {}
  if #list == 0 then
    list = {
      { name = "MOM", class = "FAMILY" },
      { name = "PROF.ELM", class = "PROF" },
    }
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
  if input:wasPressed("left") then
    self.index = self.index > 1 and self.index - 1 or #self.cards
    Sound.play(self.game.data, "Tink")
  elseif input:wasPressed("right") then
    self.index = self.index < #self.cards and self.index + 1 or 1
    Sound.play(self.game.data, "Tink")
  end
  local card = self:current()
  if card == "RADIO" then
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
  elseif card == "PHONE" then
    local list = self:contacts()
    if input:wasPressed("down") then
      self.contact = self.contact < #list and self.contact + 1 or 1
      Sound.play(self.game.data, "Tink")
    elseif input:wasPressed("up") then
      self.contact = self.contact > 1 and self.contact - 1 or #list
      Sound.play(self.game.data, "Tink")
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
    end
  end
end

-- ── shared chrome ──────────────────────────────────────────────────

local function fillBg()
  -- Cream body matching PokegearPals border colour
  love.graphics.setColor(0.90, 0.97, 0.62, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
end

local function frameBox(x, y, w, h)
  love.graphics.setColor(0.45, 0.45, 0.45, 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  love.graphics.setColor(0.25, 0.25, 0.25, 1)
  love.graphics.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
end

local function textBox(x, y, w, h)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  frameBox(x, y, w, h)
end

function PokegearMenu:drawCardTabs()
  local pal = self:shellPalette()
  local bg = pal[1] or { 255, 247, 180 }
  local mid = pal[2] or { 168, 168, 168 }
  local dark = pal[4] or { 0, 0, 0 }
  -- top strip
  love.graphics.setColor(mid[1]/255, mid[2]/255, mid[3]/255, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 16)
  local x = 2
  for i, card in ipairs(self.cards) do
    local on = i == self.index
    local label = Strings(card)
    local w = Font.width(label) + 8
    if on then
      love.graphics.setColor(bg[1]/255, bg[2]/255, bg[3]/255, 1)
      love.graphics.rectangle("fill", x, 1, w, 14)
      love.graphics.setColor(dark[1]/255, dark[2]/255, dark[3]/255, 1)
    else
      love.graphics.setColor(mid[1]/255 * 0.75, mid[2]/255 * 0.75, mid[3]/255 * 0.75, 1)
      love.graphics.rectangle("fill", x, 1, w, 14)
      love.graphics.setColor(dark[1]/255, dark[2]/255, dark[3]/255, 1)
    end
    Font.draw(label, x + 4, 3)
    x = x + w + 2
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ── CLOCK ──────────────────────────────────────────────────────────

function PokegearMenu:drawClock()
  fillBg()
  self:drawCardTabs()
  -- SWITCH▶ label (original clock tilemap top-right)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("SWITCH▶"), 104, 20)

  -- Day + time panel
  textBox(16, 48, 128, 48)
  local save = self.game.save
  local t = math.floor(save.playTime or 0)
  local hour = math.floor(t / 3600) % 24
  local minute = math.floor(t / 60) % 60
  local ampm = hour < 12 and "AM" or "PM"
  local h12 = hour % 12
  if h12 == 0 then h12 = 12 end
  local sep = self.blink < 0.5 and ":" or " "
  local day = Strings(DAYS[(math.floor(t / 86400) % 7) + 1])
  local clock = Strings("%2d%s%02d %s", h12, sep, minute, ampm)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(day, (160 - Font.width(day)) / 2, 56)
  Font.draw(clock, (160 - Font.width(clock)) / 2, 72)

  -- Bottom textbox
  textBox(8, 112, 144, 24)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("What time is it?"), 16, 120)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ── RADIO ──────────────────────────────────────────────────────────

function PokegearMenu:drawRadio()
  fillBg()
  self:drawCardTabs()

  -- Use extracted pokegear art when present (radio card top has TUNING meter;
  -- tiles sheet is 128x24 with the same strip).
  local gear = (self.game.data.field or {}).pokegear or {}
  local tiles = loadImage(gear.tiles)
  local radioCard = loadImage(gear.cards and gear.cards.RADIO)
  local sprites = loadImage(gear.sprites)
  love.graphics.setColor(1, 1, 1, 1)
  if radioCard then
    local q = love.graphics.newQuad(0, 0, 160, 40, radioCard:getDimensions())
    love.graphics.draw(radioCard, q, 0, 16)
  elseif tiles then
    love.graphics.draw(tiles, 16, 18, 0, 1, 1)
  else
    textBox(16, 20, 128, 24)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("TUNING"), 56, 28)
  end
  -- Cursor arrow from pokegear_sprites (16x40 sheet: arrow + box)
  if sprites then
    love.graphics.setColor(1, 1, 1, 1)
    local q = love.graphics.newQuad(0, 0, 16, 16, sprites:getDimensions())
    love.graphics.draw(sprites, q, 72, 48)
  end

  local stations = self:stationList()
  if self.station > #stations then self.station = 1 end
  local st = stations[self.station] or stations[1]

  textBox(8, 64, 144, 40)
  love.graphics.setColor(0, 0, 0, 1)
  if st then
    Font.draw(Strings(st.name), 16, 72)
    Font.draw(Strings(st.lines[1] or ""), 16, 88)
  end

  textBox(8, 112, 144, 24)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("▲▼ Station  ◀▶ Card"), 16, 120)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ── PHONE ──────────────────────────────────────────────────────────

function PokegearMenu:drawPhone()
  fillBg()
  self:drawCardTabs()

  local list = self:contacts()
  textBox(8, 24, 144, 80)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("Whom do you want"), 16, 32)
  Font.draw(Strings("to call?"), 16, 44)

  local start = math.max(1, self.contact - 2)
  local y = 60
  for i = start, math.min(#list, start + 3) do
    local entry = list[i]
    local name = Strings(entry.name or "?")
    love.graphics.setColor(0, 0, 0, 1)
    if i == self.contact then
      Font.draw("▶", 12, y)
      Font.draw(name, 24, y)
    else
      Font.draw(name, 24, y)
    end
    y = y + 12
  end

  textBox(8, 112, 144, 24)
  love.graphics.setColor(0, 0, 0, 1)
  local cur = list[self.contact]
  Font.draw(Strings(cur and cur.name or ""), 16, 120)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ── MAP ────────────────────────────────────────────────────────────

function PokegearMenu:drawMap()
  local game = self.game
  local town = (game.data.field or {}).townMap or {}
  local gear = (game.data.field or {}).pokegear or {}
  local ow = game.overworld
  local def = ow and ow.map and ow.map.def
  local landmark = def and def.landmark
  local entry = landmark and town.landmarks and (town.landmarks[landmark] or town.landmarks[tostring(landmark)])
  local path = (landmark and landmark >= KANTO_LANDMARK_FIRST and town.kanto) or town.johto
  local image = path and loadImage(path)
  if image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0)
    require("src.render.PaletteFX").markTrueColor(0, 24, 160, 120)

    -- Player icon (solid, GBC-coloured Chris sprite when available)
    local playerIcon = loadImage(gear.playerIcon) or loadImage(town.playerIcon)
    if entry then
      local px = (tonumber(entry.x) or 0) - 8
      local py = (tonumber(entry.y) or 0) - 16
      if playerIcon then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(playerIcon, px, py)
      else
        love.graphics.setColor(0.95, 0.3, 0.2, 1)
        love.graphics.rectangle("fill", px + 4, py + 4, 8, 8)
      end
    end

    -- Roaming legendaries as mon icons (party-icon style, green selection
    -- box like the real G/S pokegear map).
    local roam = game.save.g2RoamReleased and game.save.g2Roam
    if type(roam) == "table" and town.landmarks then
      for species, info in pairs(roam) do
        if info and info ~= false then
          local lm = type(info) == "table" and tonumber(info.landmark) or nil
          local loc = lm and (town.landmarks[lm] or town.landmarks[tostring(lm)])
          if loc then
            local cx = (tonumber(loc.x) or 0) - 4
            local cy = (tonumber(loc.y) or 0) - 12
            local monKey = (type(info) == "table" and (info.speciesId or info.species)) or species
            local monImg = loadMonIcon(game, monKey)
            -- Green box like the real town-map mon marker
            love.graphics.setColor(0.15, 0.85, 0.25, 1)
            love.graphics.rectangle("line", cx - 9, cy - 9, 18, 18)
            love.graphics.rectangle("line", cx - 8, cy - 8, 16, 16)
            if monImg then
              love.graphics.setColor(1, 1, 1, 1)
              local iw, ih = monImg:getDimensions()
              -- Party icons are often 16x32 (two frames); use top frame only
              if ih >= 32 and iw <= 16 then
                local q = love.graphics.newQuad(0, 0, iw, 16, iw, ih)
                love.graphics.draw(monImg, q, cx - 8, cy - 8)
              else
                local scale = math.min(16 / iw, 16 / ih)
                love.graphics.draw(monImg, cx - 8, cy - 8, 0, scale, scale)
              end
            else
              love.graphics.setColor(0.9, 0.5, 0.2, 1)
              love.graphics.rectangle("fill", cx - 6, cy - 6, 12, 12)
            end
          end
        end
      end
    end

    self.mapName = entry and entry.name
      and Strings(entry.name:gsub("[\n\f\v]", " ")) or nil
  else
    self.mapName = nil
    fillBg()
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("JOHTO"), 16, 48)
    Font.draw(Strings("YOU ARE HERE"), 16, 72)
  end
  self:drawMapHeader()
end

function PokegearMenu:drawMapHeader()
  local pal = self:shellPalette()
  local bg = pal[1] or { 255, 247, 180 }
  local mid = pal[2] or { 168, 168, 168 }
  local dark = pal[4] or { 0, 0, 0 }
  love.graphics.setColor(bg[1]/255, bg[2]/255, bg[3]/255, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 16)
  love.graphics.setColor(dark[1]/255, dark[2]/255, dark[3]/255, 1)
  love.graphics.rectangle("fill", 0, 16, 160, 1)
  -- Landmark name on the left (ROM parks it at hlcoord 8, 0)
  if self.mapName then
    love.graphics.setColor(dark[1]/255, dark[2]/255, dark[3]/255, 1)
    Font.draw(self.mapName, 8, 3)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function PokegearMenu:draw()
  local card = self:current()
  if card == "MAP" then
    self:drawMap()
  elseif card == "CLOCK" then
    self:drawClock()
  elseif card == "RADIO" then
    self:drawRadio()
  else
    self:drawPhone()
  end
end

return PokegearMenu
