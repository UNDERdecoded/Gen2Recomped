-- HEARTGOLD / SOULSILVER'S FIELD MENU (pokeheartgold src/start_menu.c and
-- overlay 27), over Platinum's (src/ui/Gen4StartMenu.lua), whose row actions,
-- safari / contest handling and save flow it keeps. What is HGSS's:
--
-- THE PANEL IS ON THE TOUCH SCREEN: /a/0/1/4's green panel (Gen4HgssMenuArt)
-- with an icon button per entry and its word under it. Drawn on the second
-- screen when it is shown, else on the game screen over the world.
--
-- THE ENTRIES AND THEIR ORDER, `StartMenu_BuildActionLists`: RETIRE (in a
-- contest or the Safari), POKeDEX, POKeMON, BAG, POKeGEAR, the player's name
-- (the card), SAVE, OPTIONS -- each shown only once its flag is set
-- (`FieldSystem_ShouldDrawStartMenuIcon`: FLAG_GOT_POKEDEX 0x6B, STARTER 0x6A,
-- POKEGEAR 0x9C, BAG 0x11B, TRAINER_CARD 0x11C, SAVE 0x11D, OPTIONS 0x11E). A
-- save that carries none of those flags (one made before the port kept them)
-- shows every entry rather than none. No EXIT: B, X, START or the header
-- close the menu (SEQ_SE_GS_GEARCANCEL).
--
-- THE GEOMETRY, overlay 27: icons at `ov27_0225D038` -- (24, 22 + 40 i) down
-- the first column, (104, 22 + 40 i) down the second -- the words in 9 x 2-tile
-- windows at tile (1 / 11, 6 + 5 i) (`ov27_0225D074`), centred; touch
-- rectangles `ov27_0225CF68`, 60 x 32 per button and the header strip
-- {y 0..16, x 8..160} to close. The selected icon wears palette row 1 (its rim
-- turns red). The words are bank 196.
--
-- MEASURED, not read: the header's (x) mark and "MENU" positions, off
-- Bulbapedia's capture of the cartridge.

local Gen4StartMenu = require("src.ui.Gen4StartMenu")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Screens = require("src.ui.Screens")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")

local HgssStartMenu = setmetatable({}, { __index = Gen4StartMenu })
HgssStartMenu.__index = HgssStartMenu
HgssStartMenu.isOpaque = false

local W, H = 256, 192
local floor = math.floor
local BANK = 196

-- id -> { icon NCGR, bank 196 entry, flag }
local ENTRY = {
  retire = { 42, 8 },
  pokedex = { 18, 0, 0x6B },
  pokemon = { 21, 1, 0x6A },
  bag = { 24, 2, 0x11B },
  pokegear = { 30, 14, 0x9C },
  trainerCase = { 33, 3, 0x11C },
  save = { 36, 4, 0x11D },
  options = { 39, 5, 0x11E },
}
local ORDER = { "retire", "pokedex", "pokemon", "bag", "pokegear", "trainerCase", "save", "options" }
local FEMALE_BAG = 27

local SLOTS = {
  { 24, 22 }, { 24, 62 }, { 24, 102 }, { 24, 142 },
  { 104, 22 }, { 104, 62 }, { 104, 102 }, { 104, 142 },
}
local LABELS = {
  { 8, 48 }, { 8, 88 }, { 8, 128 }, { 8, 168 },
  { 88, 48 }, { 88, 88 }, { 88, 128 }, { 88, 168 },
}
local LABEL_W = 72
local BUTTON_RECTS = { -- top, bottom, left, right
  { 22, 54, 16, 76 }, { 62, 94, 16, 76 }, { 102, 134, 16, 76 }, { 142, 174, 16, 76 },
  { 22, 54, 96, 156 }, { 62, 94, 96, 156 }, { 102, 134, 96, 156 }, { 142, 174, 96, 156 },
}
local CLOSE_RECT = { 0, 16, 8, 160 }
local CLOSE_AT, MENU_AT = { 44, 2 }, { 61, 2 }
-- the green panel alone (x 0..168), for the game screen: the grey column is
-- the touch screen's and would hide the world
local PANEL_W = 168
local COLUMN = 4

local function se(self, name)
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then pcall(Sound.playSe, data, name) end
end

function HgssStartMenu.new(game, opts)
  local self = Gen4StartMenu.new(game, opts)
  setmetatable(self, HgssStartMenu)
  self.menuArt = (game.data or {}).gen4_hgss_menu_art or {}
  local keep = {}
  for _, row in ipairs(self.rows) do keep[row.id] = true end
  -- the rows Platinum's menu decided are allowed, plus POKeGEAR, in HGSS order
  keep.pokegear = true
  -- PAL PARK HAS NO RETIRE HERE (FieldSystem_GetStartMenuButtonInhibitFlags_
  -- PalPark: BAG and SAVE off; RETIRE is the Safari's and the contest's) --
  -- the worker by the gate is how the Catching Show is left
  if self.palPark then keep.retire = nil end
  local flags = (game.save or {}).flags or {}
  local anyFlag = false
  for _, def in pairs(ENTRY) do
    if def[3] and flags[("FLAG_G4_%04X"):format(def[3])] then anyFlag = true end
  end
  -- EVERY FLAGGED ENTRY ANSWERS TO ITS OWN FLAG, POKeDEX AND POKeMON TOO
  -- (FieldSystem_ShouldDrawStartMenuIcon: CheckGotPokedex, CheckGotStarter).
  -- They had been left to Platinum's stand-ins -- "a species has been seen"
  -- and "the party is not empty" -- which opened the POKeDEX as soon as the
  -- starter was in the party, a route before Oak gives it at Mr. Pokemon's
  -- house (R30R0201: GivePokedex, SetFlag FLAG_GOT_POKEDEX). A new game has
  -- none of these flags and an empty panel, as the cartridge's bedroom does
  -- until Mom hands over the BAG, card, SAVE and OPTIONS (T20R0201).
  -- Only a save with a party and none of the flags (one made before the port
  -- kept them) falls back to the old answer, so it is not left with nothing.
  local legacy = not anyFlag and #((game.save or {}).party or {}) > 0
  local rows = {}
  for _, id in ipairs(ORDER) do
    local def = ENTRY[id]
    local shown = keep[id]
    if shown and not legacy and def[3] then
      shown = flags[("FLAG_G4_%04X"):format(def[3])] == true
    end
    if shown then
      local icon = def[1]
      if id == "bag" and self:isFemale() then icon = FEMALE_BAG end
      rows[#rows + 1] = { id = id, label = self:word(def[2], id), hgssIcon = icon }
    end
  end
  -- MODS (the port's, see Gen4StartMenu.modsRow) takes the next free button.
  -- An ordinary field menu has seven entries and eight buttons; with RETIRE
  -- up (Safari, Bug-Catching Contest) all eight are the cartridge's and MODS
  -- waits until the game is over.
  -- LINK (the port's, Gen4StartMenu.linkRow: a party, and not in the
  -- Safari, the contest or Pal Park) takes the next free button as well.
  -- When LINK and MODS will not both fit, they share one PORT button that
  -- opens a two-row list (docs/online-design.md 2.6).
  local mods = Gen4StartMenu.modsRow(game)
  local link = Gen4StartMenu.linkRow(game, self)
  local extras = {}
  if link then extras[#extras + 1] = link end
  if mods then extras[#extras + 1] = mods end
  if #rows + #extras <= #SLOTS then
    for _, row in ipairs(extras) do rows[#rows + 1] = row end
  elseif #extras > 1 and #rows < #SLOTS then
    rows[#rows + 1] = { id = "port", label = Strings("PORT"), sub = extras }
  end
  self.rows = rows
  self.index = 1
  for i, row in ipairs(rows) do if row.id == game.gen4StartMenuCursor then self.index = i end end
  return self
end

function HgssStartMenu:isFemale()
  local g = ((self.game.save or {}).player or {}).gender
  return g == "girl" or g == "female" or g == 1
end

function HgssStartMenu:word(n, fallback)
  if n == 3 then
    return tostring((((self.game.save or {}).player or {}).name) or fallback)
  end
  local T = require("src.import.Gen4Text")
  local s = T.resolve(self.game.data, BANK, n, self.game)
  if type(s) ~= "string" or s == "" then return tostring(fallback):upper() end
  return s
end

-- ----------------------------------------------------------------- input --

function HgssStartMenu:close()
  se(self, "SEQ_SE_GS_GEARCANCEL")
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function HgssStartMenu:select()
  local row = self.rows[self.index]
  if row and row.id == "port" then
    -- LINK and MODS behind one button: a two-row list over the panel
    self.portIndex = 1
    return
  end
  if row and row.id == "link" then
    self.game.stack:pop()
    Gen4StartMenu.openLink(self.game)
    return
  end
  if row and row.id == "pokegear" then
    -- the Pokegear (src/ui/HgssPokegear.lua) once its art is in the cache;
    -- until then the button says so and stays put
    local okP = (self.game.data or {}).gen4_hgss_pokegear_art and pcall(require, "src.ui.HgssPokegear")
    if okP then
      local reopen = self:reopen()
      self.game.stack:pop()
      local P = require("src.ui.HgssPokegear")
      self.game.stack:push(P.new(self.game, { onCancel = reopen }))
      return
    end
    Logger.warn("hgss start menu: the Pokegear app is not ported yet")
    se(self, "SEQ_SE_GS_GEARCANCEL")
    return
  end
  return Gen4StartMenu.select(self)
end

-- the PORT list (LINK / MODS) while it is open
function HgssStartMenu:updatePort(input)
  local row = self.rows[self.index]
  local sub = row and row.sub or {}
  if not input or #sub == 0 then self.portIndex = nil return end
  if input:wasPressed("up") or input:wasPressed("down") then
    self.portIndex = self.portIndex % #sub + 1
    se(self, "SEQ_SE_DP_SELECT")
  elseif input:wasPressed("a") then
    se(self, "SEQ_SE_DP_SELECT")
    local pick = sub[self.portIndex]
    self.portIndex = nil
    if pick.id == "link" then
      self.game.stack:pop()
      Gen4StartMenu.openLink(self.game)
    else
      Screens.push(self.game, "ManagerState")
    end
  elseif input:wasPressed("b") or input:wasPressed("x") then
    se(self, "SEQ_SE_GS_GEARCANCEL")
    self.portIndex = nil
  end
end

function HgssStartMenu:update()
  local input = self.game.input
  if self.portIndex then return self:updatePort(input) end
  local count = #self.rows
  -- an empty panel (a new game before Mom's gifts) still opens and closes
  -- like the cartridge's: the header, B, X or START
  if count == 0 then
    local tap0 = self.tapAt
    self.tapAt = nil
    local i0 = self.game.input
    if (tap0 and self:inRect(tap0, CLOSE_RECT))
        or (i0 and (i0:wasPressed("b") or i0:wasPressed("start") or i0:wasPressed("x"))) then
      return self:close()
    end
    return
  end
  self.frame = (self.frame or 0) + 1
  local tap = self.tapAt
  self.tapAt = nil
  if tap then
    if self:inRect(tap, CLOSE_RECT) then return self:close() end
    for i = 1, count do
      if self:inRect(tap, BUTTON_RECTS[i]) then
        self.index = i
        self.game.gen4StartMenuCursor = self.rows[i].id
        se(self, "SEQ_SE_DP_SELECT")
        return self:select()
      end
    end
  end
  if not input then return end
  local before = self.index
  local i = self.index - 1
  local col, r = floor(i / COLUMN), i % COLUMN
  if input:wasPressed("up") then
    self.index = (i - 1) % count + 1
  elseif input:wasPressed("down") then
    self.index = (i + 1) % count + 1
  elseif input:wasPressed("left") or input:wasPressed("right") then
    local other = (1 - col) * COLUMN + r
    if other >= count then other = count - 1 end
    self.index = other + 1
  elseif input:wasPressed("a") then
    se(self, "SEQ_SE_DP_SELECT")
    return self:select()
  elseif input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("x") then
    return self:close()
  end
  if self.index ~= before then
    se(self, "SEQ_SE_DP_SELECT")
    self.game.gen4StartMenuCursor = self.rows[self.index].id
  end
end

function HgssStartMenu:inRect(p, rc)
  return p.y >= rc[1] and p.y <= rc[2] and p.x >= rc[3] and p.x <= rc[4]
end

function HgssStartMenu:onSecondScreen()
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

function HgssStartMenu:touchpressed(id, px, py)
  local x, y
  if self:onSecondScreen() and SecondScreen.toLocal then
    x, y = SecondScreen.toLocal(self.game, px, py)
  else
    local rect = require("src.render.Renderer").uiPresentation
    x, y = px, py
    if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
  end
  if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
  self.tapAt = { x = floor(x), y = floor(y) }
  return true
end

-- ------------------------------------------------------------------ draw --

function HgssStartMenu:menuImg(key)
  local rec = self.menuArt[key]
  if type(rec) ~= "table" then return nil end
  return self:imgAt(rec.path), rec
end

-- THE MODS BUTTON, out of the cartridge's own button art: the SAVE button's
-- frame (grey rim, red when selected) with its picture covered by its own
-- blank face -- a 6-pixel strip from left of the picture, stretched across --
-- and four small tiles in the picture's ink where the picture was.
function HgssStartMenu:drawModsButton(slot, selected, glyph)
  local g = love.graphics
  local icon, rec = self:menuImg(("icon_36_%d"):format(selected and 1 or 0))
  local x, y = slot[1] + ((rec or {}).originX or 0), slot[2] + ((rec or {}).originY or 0)
  if not icon then
    g.setColor(selected and 0.78 or 0.2, 0.2, 0.2, 1)
    g.rectangle("fill", x, y, 40, 26)
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", x + 2, y + 2, 36, 22)
    return
  end
  g.draw(icon, x, y)
  local iw, ih = icon:getDimensions()
  self.modsFaceQuad = self.modsFaceQuad or g.newQuad(4, 2, 6, 22, iw, ih)
  g.draw(icon, self.modsFaceQuad, x + 8, y + 2, 0, 26 / 6, 1)
  g.setColor(0.33, 0.33, 0.33, 1)
  if glyph == "link" then
    -- two linked rings: the cable
    g.setLineWidth(2)
    g.rectangle("line", x + 11, y + 8, 10, 8)
    g.rectangle("line", x + 18, y + 11, 10, 8)
    g.setLineWidth(1)
  elseif glyph == "port" then
    -- the LINK rings beside two of the MODS tiles
    g.setLineWidth(2)
    g.rectangle("line", x + 10, y + 6, 8, 6)
    g.rectangle("line", x + 14, y + 10, 8, 6)
    g.setLineWidth(1)
    g.rectangle("fill", x + 25, y + 6, 5, 5)
    g.rectangle("fill", x + 25, y + 13, 5, 5)
  else
    for k = 0, 3 do
      g.rectangle("fill", x + 13 + (k % 2) * 8, y + 5 + floor(k / 2) * 8, 6, 6)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function HgssStartMenu:drawPanel(whole)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local panel = self:menuImg("panel")
  if panel and whole then
    g.draw(panel, 0, 0)
  elseif panel then
    self.panelQuad = self.panelQuad or love.graphics.newQuad(0, 0, PANEL_W, H, panel:getDimensions())
    g.draw(panel, self.panelQuad, 0, 0)
  else
    Font.drawBox(0, 0, 21, 23)
  end
  local close, crec = self:menuImg("close")
  if close then g.draw(close, CLOSE_AT[1] + (crec.originX or 0), CLOSE_AT[2] + (crec.originY or 0)) end
  local ink = self.menuArt.ink or {}
  local letter = ink.letter or { 1, 1, 1 }
  local shadow = ink.shadow or { 0, 0, 0 }
  Font.pushStyle({ text = letter, shadow = shadow })
  Font.draw(self:word(12, "MENU"), MENU_AT[1], MENU_AT[2])
  for i, row in ipairs(self.rows) do
    local slot, lab = SLOTS[i], LABELS[i]
    if slot then
      g.setColor(1, 1, 1, 1)
      if row.id == "mods" or row.id == "link" or row.id == "port" then
        self:drawModsButton(slot, i == self.index, row.id)
      else
        local icon, rec = self:menuImg(("icon_%d_%d"):format(row.hgssIcon, i == self.index and 1 or 0))
        if icon then g.draw(icon, slot[1] + (rec.originX or 0), slot[2] + (rec.originY or 0)) end
      end
      local label = row.label or ""
      Font.draw(label, lab[1] + floor((LABEL_W - Font.width(label)) / 2), lab[2])
    end
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
  -- the PORT list, in the game's own window beside its button
  local row = self.rows[self.index]
  if self.portIndex and row and row.sub then
    local slot = SLOTS[self.index] or SLOTS[#SLOTS]
    local tx = floor(slot[1] / 8) + (slot[1] < 80 and 8 or -1)
    local ty = math.max(0, math.min(floor(slot[2] / 8), 24 - (#row.sub * 2 + 2)))
    if tx + 9 > 32 then tx = 32 - 9 end
    Font.drawBox(tx, ty, 9, #row.sub * 2 + 2)
    g.setColor(0, 0, 0, 1)
    for k, r in ipairs(row.sub) do
      local y = (ty + 1) * 8 + (k - 1) * 16
      Font.draw(r.label, (tx + 1) * 8 + 8, y)
      if k == self.portIndex then
        local okT, Theme = pcall(require, "src.ui.Theme")
        Font.drawCode((okT and Theme.cursor) or 0xED, (tx + 1) * 8, y)
      end
    end
    g.setColor(1, 1, 1, 1)
  end
end

function HgssStartMenu:draw()
  if self:onSecondScreen() then
    return SecondScreen.draw(self.game, function() self:drawPanel(true) end)
  end
  self:drawPanel()
  self:drawBallCount()
end

return HgssStartMenu
