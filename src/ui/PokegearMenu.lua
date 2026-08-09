-- The POKéGEAR (engine/pokegear/pokegear.asm).  Mom hands it over on the
-- way out of New Bark; it is not a bag item in Gen2, it is a START-menu
-- feature gated on EVENT_GOT_POKEGEAR.
--
-- Four cards, switched with LEFT/RIGHT along the top row exactly like the
-- original's card icons.  CLOCK and PHONE ship with the unit; MAP arrives
-- with the MAP CARD (Elm's aide on Route 30) and RADIO with the RADIO CARD
-- (Radio Tower 2F), so an un-carded slot is skipped rather than drawn
-- empty -- PokegearCard_CheckHasMapCard / .CheckHasRadioCard.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local PokegearMenu = {}
PokegearMenu.__index = PokegearMenu
PokegearMenu.isOpaque = true

-- Gen2's clock runs off the cartridge RTC; this port has no battery, so
-- the play clock stands in for it (the same seconds SaveData persists).
local DAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY",
               "FRIDAY", "SATURDAY" }

-- RadioChannels: the station list, in the order the tuner sweeps them.
local STATIONS = {
  { name = "OAK'S POKéMON TALK",
    lines = { "PROF.OAK: Today's", "sighting is...", "", "A wild #MON was",
              "spotted nearby!" } },
  { name = "POKéDEX SHOW",
    lines = { "DJ MARY: Today's", "featured #MON", "is a real charmer!" } },
  { name = "POKéMON MUSIC",
    lines = { "Now playing the", "#MON MARCH..." } },
  { name = "LUCKY CHANNEL",
    lines = { "REED: Check your", "LOTTO number", "at any #MON CENTER!" } },
  { name = "BUENA'S PASSWORD",
    lines = { "BUENA: Tonight's", "password is a", "secret!" } },
  { name = "PLACES & PEOPLE",
    lines = { "A trainer was", "spotted training", "hard today." } },
}

local function cards(save)
  local flags = save.flags or {}
  local list = { "CLOCK" }
  if flags.EVENT_GOT_MAP_CARD then list[#list + 1] = "MAP" end
  if flags.EVENT_GOT_RADIO_CARD then list[#list + 1] = "RADIO" end
  list[#list + 1] = "PHONE"
  return list
end

-- Landmarks 0..$2E are Johto, everything above is Kanto (TownMap_
-- GetKantoLandmarkLimits); landmark pixel coords are screen-absolute.
local KANTO_LANDMARK_FIRST = 0x2F

local images = {}
local function loadImage(path)
  if images[path] == nil then
    local Assets = require("src.render.Assets")
    local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
    images[path] = ok and img or false
  end
  return images[path] or nil
end

-- PalPacket_Pokegear (02:60E5) loads PokegearPals, the same six-palette CGB
-- pack the town map rides on; palette 0 is the unit's own shell.  Without
-- this the screen had no palette entry at all and came out as a flat Gen1
-- black-on-white box.
PokegearMenu.FALLBACK_PAL = {
  { 255, 255, 255 }, { 123, 189, 255 }, { 41, 90, 181 }, { 0, 0, 0 },
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

function PokegearMenu:current() return self.cards[self.index] end

-- Registered numbers.  save.phone is a list of { name, class, text }; the
-- unit ships with MOM already in it (Mom_PokegearScript), and Elm calls
-- once his errand is running.
--
-- Gen 2 keeps its book somewhere else: wPhoneList is a set of the PHONE_*
-- ids that addcellnum / askforphonenumber register, mirrored into
-- save.g2Phone.  Resolve those through PhoneContacts so a number the story
-- hands over actually appears on the card instead of leaving MOM alone.
function PokegearMenu:contacts()
  local save = self.game.save
  local list = {}
  for _, entry in ipairs(save.phone or {}) do
    if type(entry) == "table" and entry.name then list[#list + 1] = entry end
  end
  if type(save.g2Phone) == "table" then
    local Gen2Commands = require("src.script.Gen2Commands")
    local ids = {}
    for id, registered in pairs(save.g2Phone) do
      if registered and type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local name, class = Gen2Commands.phoneName(self.game.data, id)
      if name then list[#list + 1] = { name = name, class = class, g2 = id } end
    end
  end
  if #list == 0 then
    list[1] = { name = "MOM", text = "Take care of\nyourself out there!" }
  end
  return list
end

function PokegearMenu:update(dt)
  local input = self.game.input
  self.blink = (self.blink + (dt or 0)) % 1

  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
    return
  end

  if input:wasPressed("right") then
    self.index = self.index < #self.cards and self.index + 1 or 1
  elseif input:wasPressed("left") then
    self.index = self.index > 1 and self.index - 1 or #self.cards
  end

  local card = self:current()
  if card == "RADIO" then
    if input:wasPressed("down") then
      self.station = self.station < #STATIONS and self.station + 1 or 1
    elseif input:wasPressed("up") then
      self.station = self.station > 1 and self.station - 1 or #STATIONS
    end
  elseif card == "PHONE" then
    local Gen2Commands = require("src.script.Gen2Commands")
    local list = self:contacts()
    if input:wasPressed("down") then
      self.contact = self.contact < #list and self.contact + 1 or 1
    elseif input:wasPressed("up") then
      self.contact = self.contact > 1 and self.contact - 1 or #list
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      local entry = list[self.contact]
      -- PhoneCall (36:$4298) runs the contact's second `dba` -- the script for
      -- a call YOU place -- through the normal script engine, which is how
      -- Mom's money talk and Elm's five-way progress report get their
      -- dialogue.  The extractor walks those scripts into map_scripts.scripts
      -- and hangs the label off the contact, so hand it to the overworld's
      -- pending-script FIFO and close the unit; the runner picks it up on the
      -- next idle frame.  Anything without a script (the Gen1 phone list)
      -- still falls back to its baked line.
      local script = entry.g2 and Gen2Commands.phoneCallScript(self.game.data,
        entry.g2) or nil
      local ow = script and self.game.overworld
      if ow and ow.queueScript then
        ow:queueScript(script)
        -- straight back to the map, NOT through onCancel: that re-opens the
        -- START menu, and the overworld cannot drain its pending scripts
        -- while a menu owns the top of the stack, so the call would sit there
        -- until the player closed everything by hand
        self.game.stack:pop()
        return
      end
      local TextBox = require("src.render.TextBox")
      self.game.stack:push(TextBox.new(self.game,
        Strings("%s: %s", entry.name, entry.text or "...")))
    end
  end
end

function PokegearMenu:drawClock()
  local save = self.game.save
  local t = math.floor(save.playTime or 0)
  local hour = math.floor(t / 3600) % 24
  local minute = math.floor(t / 60) % 60
  -- the original prints a 12-hour clock with the colon blinking each second
  local ampm = hour < 12 and "AM" or "PM"
  local h12 = hour % 12
  if h12 == 0 then h12 = 12 end
  local sep = self.blink < 0.5 and ":" or " "
  local day = Strings(DAYS[(math.floor(t / 86400) % 7) + 1])
  local clock = Strings("%2d%s%02d %s", h12, sep, minute, ampm)
  Font.draw(day, (160 - Font.width(day)) / 2, 62)
  Font.draw(clock, (160 - Font.width(clock)) / 2, 82)
end

function PokegearMenu:drawMap()
  local game = self.game
  local town = (game.data.field or {}).townMap or {}
  local ow = game.overworld
  local def = ow and ow.map and ow.map.def
  local landmark = def and def.landmark
  local entry = landmark and town.landmarks and town.landmarks[landmark]
  -- Kanto landmarks start where the Johto table ends (Landmarks/JohtoMap
  -- share one id space); the Kanto sheet is drawn for those.
  local path = (landmark and landmark >= KANTO_LANDMARK_FIRST and town.kanto)
    or town.johto
  local image = path and loadImage(path)
  if image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0)
    -- the sheet is real GBC color; keep it out of the shade-remap pass.
    -- Not the top 24px: the shell strip is drawn over that and wants the
    -- unit's own palette.
    require("src.render.PaletteFX").markTrueColor(0, 24, 160, 120)
    if entry and self.blink < 0.5 then
      -- Landmarks holds raw OAM bytes, so the icon's screen CENTRE is
      -- (x - 8 + 4, y - 16 + 4) once the GB sprite origin is taken off --
      -- the same correction TownMap's gen2Locations makes.  Drawn straight,
      -- the dot sat 4px right and 12px below the town it marks.
      love.graphics.setColor(1, 0.2, 0.2, 1)
      love.graphics.rectangle("fill", (entry.x or 0) - 7, (entry.y or 0) - 15,
        6, 6)
    end
    -- PokegearMap_UpdateLandmarkName writes the name at hlcoord 8, 0 --
    -- inside the top strip, next to the mode icons.  The map card has NO
    -- bottom textbox (only .Clock/.Radio/.Phone run Textbox at 0,12), so the
    -- three-row box drawn here used to hide the bottom of Johto (#0).  The
    -- header draws it instead; see drawMapHeader.
    self.mapName = entry and entry.name
      and Strings(entry.name:gsub("[\n\f\v]", " ")) or nil
    return
  end
  self.mapName = nil
  local name = (def and (def.name or def.label))
    or (ow and ow.map and ow.map.id) or "?"
  Font.draw(Strings("JOHTO"), 16, 48)
  Font.draw(Strings("YOU ARE HERE"), 16, 72)
  Font.draw(tostring(name):gsub("_", " "), 16, 88)
end

function PokegearMenu:drawRadio()
  local station = STATIONS[self.station]
  Font.draw(Strings("CH.%d %s", self.station, station.name), 16, 40)
  for i, line in ipairs(station.lines) do
    Font.draw(Strings(line), 16, 56 + (i - 1) * 12)
  end
end

function PokegearMenu:drawPhone()
  local list = self:contacts()
  for i, entry in ipairs(list) do
    if i > 6 then break end
    Font.draw(Strings(entry.name), 24, 40 + (i - 1) * 14)
  end
  local row = math.min(self.contact, 6)
  Font.drawCode(0xED, 12, 40 + (row - 1) * 14)  -- the "|>" cursor glyph
end

-- The unit's shell: a coloured strip along the top holding one plate per
-- fitted card with the mode-indicator arrow under the active one
-- (Pokegear_FinishTilemap.PlaceMapIcon/.PlacePhoneIcon/.PlaceRadioIcon and
-- AnimatePokegearModeIndicatorArrow), then the card's own panel below.
-- The fills are chosen by RED CHANNEL, because that is what PaletteFX's
-- shade-remap shader keys on: 1.0 -> shell colour 0, 0.66 -> 1, 0.3 -> 2,
-- 0 -> 3.
function PokegearMenu:drawShell(overMap)
  love.graphics.setColor(1, 1, 1, 1)
  -- the map card fills the whole face, so the shell must not repaint over it
  if not overMap then love.graphics.rectangle("fill", 0, 0, 160, 144) end
  love.graphics.setColor(0.66, 0.66, 0.66, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 26)
  love.graphics.setColor(0.3, 0.3, 0.3, 1)
  love.graphics.rectangle("fill", 0, 26, 160, 2)

  local slots = #self.cards
  local w = 160 / slots
  for i, card in ipairs(self.cards) do
    local x = (i - 1) * w
    local on = i == self.index
    love.graphics.setColor(on and 0.3 or 1, on and 0.3 or 1, on and 0.3 or 1, 1)
    love.graphics.rectangle("fill", x + 1, 4, w - 2, 16)
    love.graphics.setColor(on and 1 or 0, on and 1 or 0, on and 1 or 0, 1)
    local label = Strings(card)
    Font.draw(label, x + math.max(0, (w - Font.width(label)) / 2), 8)
    if on then
      love.graphics.setColor(0.3, 0.3, 0.3, 1)
      love.graphics.polygon("fill", x + w / 2 - 3, 21, x + w / 2 + 3, 21,
                            x + w / 2, 25)
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
end

-- The MAP card's own shell.  InitMapNameSign's .Map branch rules row 2 off
-- with $06/$07/$17 and PokegearMap_UpdateLandmarkName parks the landmark
-- name at hlcoord 8, 0, so only rows 0-2 (y 0..23) ever sit over the map --
-- everything below is the picture.  The port labels its mode plates with
-- text rather than the ROM's 8x8 icons, so the plates take the first row
-- and the name the second, which keeps the same 24px footprint.
function PokegearMenu:drawMapHeader()
  love.graphics.setColor(0.66, 0.66, 0.66, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 22)
  love.graphics.setColor(0.3, 0.3, 0.3, 1)
  love.graphics.rectangle("fill", 0, 22, 160, 2)

  local w = 160 / #self.cards
  for i, card in ipairs(self.cards) do
    local x = (i - 1) * w
    local on = i == self.index
    love.graphics.setColor(on and 0.3 or 1, on and 0.3 or 1, on and 0.3 or 1, 1)
    love.graphics.rectangle("fill", x + 1, 1, w - 2, 10)
    love.graphics.setColor(on and 1 or 0, on and 1 or 0, on and 1 or 0, 1)
    local label = Strings(card)
    Font.draw(label, x + math.max(0, (w - Font.width(label)) / 2), 2)
  end

  if self.mapName then
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.mapName,
      math.max(0, (160 - Font.width(self.mapName)) / 2), 13)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function PokegearMenu:draw()
  local card = self:current()
  if card == "MAP" then
    -- the map card fills the whole face; the header strip rides on top
    self:drawMap()
    self:drawMapHeader()
    return
  end
  self:drawShell()
  -- the card's own panel, inset in the shell
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 4, 32, 152, 108)
  love.graphics.setColor(0.3, 0.3, 0.3, 1)
  love.graphics.rectangle("line", 4.5, 32.5, 151, 107)
  love.graphics.setColor(0, 0, 0, 1)
  if card == "CLOCK" then
    self:drawClock()
  elseif card == "RADIO" then
    self:drawRadio()
  else
    self:drawPhone()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return PokegearMenu
