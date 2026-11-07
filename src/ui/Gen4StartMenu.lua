-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's START MENU, and the second half of the original brief:
--
--   "instead of showing the start menu on the bottom screen have a start menu
--    on the main screen like the other games have the choice to switch between
--    the two styles."
--
-- BOTH STYLES, and the switch is a row on the OPTIONS screen rather than a boot
-- flag, so it can be changed mid-game:
--
--   MAIN    the menu is on the main screen, which is where Red through Emerald
--           put theirs.  Default, because it makes Platinum continuous with the
--           rest of this launcher's library and muscle memory carries over.
--   BOTTOM  the authentic arrangement.  It goes through `SecondScreen`, so on
--           the inset mode it appears in the corner panel and is clickable
--           there, and on swap it takes the window.
--
-- WHAT IS THE CARTRIDGE'S:
--
--   * THE ROWS AND THEIR ORDER, from `StartMenu_MakeOptionList` rather than
--     from the enum -- the two differ.  The list is built RETIRE, CHAT,
--     POKEDEX, POKEMON, BAG, TRAINER CASE, SAVE, OPTIONS, EXIT, each added only
--     if its hide flag is clear, so an ordinary field menu is the last seven.
--   * THE WORDS, bank 367.  TRAINER CASE's entry is a TEMPLATE and not a word
--     -- `{STRVAR_1 3, 0, 0}`, filled with the player's name -- so printing it
--     raw would put a control code on the menu.
--   * THE ICONS.  `animIdx = option * ICON_ANIM_COUNT` is the mapping, and a
--     FEMALE player's BAG is group 9, which is why the sheet has ten cells for
--     nine options.
--   * THE GEOMETRY: the panel at tile (20, 1), eleven tiles wide and three per
--     row; the icons centred at x = 174 and the cursor at x = 204, both at
--     y = 20 + 24 * i.
--
-- WHAT IS NOT: which rows are AVAILABLE.  Platinum hides a row behind a save
-- flag this port's Gen 4 save does not carry yet, so the Pokedex and party rows
-- are gated on the same conditions the engine's own start menu uses -- the dex
-- being handed over, and the party not being empty -- rather than on a flag
-- that would always read false and hide them forever.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Screens = require("src.ui.Screens")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")

local Gen4StartMenu = {}
Gen4StartMenu.__index = Gen4StartMenu

local W, H = 256, 192

-- Used when the cache carries no `startMenu` record: the same seven rows in the
-- same order, so a pre-`menus` cache gets a working menu with the engine's
-- words rather than an empty panel.
local FALLBACK_ROWS = {
  { id = "pokedex", label = "POKéDEX" },
  { id = "pokemon", label = "POKéMON" },
  { id = "bag", label = "BAG" },
  { id = "trainerCase", label = "", playerName = true },
  { id = "save", label = "SAVE" },
  { id = "options", label = "OPTIONS" },
  { id = "exit", label = "EXIT" },
}

local FALLBACK_LAYOUT = {
  panelX = 160, panelY = 8, panelW = 88, rowTiles = 3,
  pitch = 24, iconX = 174, cursorX = 204, firstY = 20,
}

-- The cartridge's effects: SE_CONFIRM_sseq_3 is the ROM's SEQ_SE_DP_SELECT.
local function se(self, name, opts)
  local data = self.game and self.game.data or self.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then return Sound.playSe(data, name, opts) end
end

function Gen4StartMenu:uiSize() return W, H end
function Gen4StartMenu:wantsFillScale() return true end
function Gen4StartMenu:wantsEdgeBleed() return false end

-- NOT opaque: the start menu sits over the world on every other version in this
-- launcher and it does here too, in both styles -- on `bottom` the world is
-- what the main screen is still showing.
Gen4StartMenu.isOpaque = false

function Gen4StartMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4StartMenu)
  self.game = game
  self.onCancel = opts.onCancel
  self.cache = {}

  local menus = (game.data or {}).gen4_menus or {}
  local record = menus.startMenu or {}
  self.layout = record.layout or FALLBACK_LAYOUT
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}

  local source = record.rows
  if not source or #source == 0 then
    Logger.warn("gen4 start menu: this cache carries no start-menu record -- "
                .. "falling back to the engine's own words")
    source = FALLBACK_ROWS
  end

  self.rows = {}
  -- DURING A SAFARI GAME the cartridge swaps its hide flags for
  -- `StartMenu_GetSafariHiddenOptions` -- SAVE and CHAT only -- so RETIRE,
  -- which the record marks hidden for the ordinary field, appears, and SAVE
  -- goes.
  self.safari = (game.save or {}).safari ~= nil
  -- ...AND DURING HEARTGOLD / SOULSILVER'S BUG-CATCHING CONTEST (flag 0x996):
  -- BAG and SAVE are off and RETIRE runs std 10404 (start_menu.c 220-315)
  self.bugContest = require("src.world.HgssBugContest").running(game.save)
  -- ...AND IN PAL PARK'S CATCHING SHOW (`StartMenu_GetPalParkHiddenOptions`):
  -- SAVE, CHAT and BAG off; RETIRE runs the park's own script 4
  self.palPark = not self.safari and require("src.world.Gen4PalPark").inPark(game.save)
  for _, row in ipairs(source) do
    local hidden = row.hidden
    if self.palPark then
      hidden = (row.id == "save" or row.id == "chat" or row.id == "bag")
    elseif self.safari then
      hidden = (row.id == "save" or row.id == "chat")
    elseif self.bugContest then
      hidden = (row.id == "save" or row.id == "chat" or row.id == "bag")
    end
    if not hidden and self:available(row.id) then
      self.rows[#self.rows + 1] = {
        id = row.id,
        label = self:labelFor(row),
        icon = self:iconFor(row),
      }
    end
  end
  -- a contest's RETIRE when the record behind this menu has no such row
  -- (HeartGold / SoulSilver's cache carries no start-menu record)
  if self.bugContest then
    local has = false
    for _, r in ipairs(self.rows) do if r.id == "retire" then has = true end end
    if not has then
      local text = (game.data or {}).text or {}
      local label = text["TEXT_B0196_00008"] or "RETIRE"
      table.insert(self.rows, math.max(1, #self.rows), { id = "retire", label = label })
    end
  end
  -- MODS, the port's own row and not the cartridge's: the only way into the
  -- mod manager once a game is running, on the same terms as the Game Boy and
  -- GBA menus (src/ui/StartMenu.lua, Gen3StartMenu:buildRows) -- shown only
  -- when at least one mod is installed, and placed before EXIT so the
  -- cartridge's rows keep their order.  No icon: the panel draws the word.
  -- LINK, the port's too (docs/online-design.md 2.6): the same terms, the
  -- same place, drawn as a word like MODS -- and never during the Safari
  -- Game, the Bug-Catching Contest or Pal Park's Catching Show
  local link = Gen4StartMenu.linkRow(game, self)
  if link then
    local at = #self.rows + 1
    if self.rows[#self.rows] and self.rows[#self.rows].id == "exit" then at = #self.rows end
    table.insert(self.rows, at, link)
  end
  local mods = Gen4StartMenu.modsRow(game)
  if mods then
    local at = #self.rows + 1
    if self.rows[#self.rows] and self.rows[#self.rows].id == "exit" then at = #self.rows end
    table.insert(self.rows, at, mods)
  end
  -- FieldSystem.menuCursorPos: the menu opens on the option it was left on
  self.index = 1
  for i, row in ipairs(self.rows) do
    if row.id == game.gen4StartMenuCursor then self.index = i end
  end
  self.frame, self.swellFrom = 0, nil
  -- field_control.c:332 (and StartMenu_OpenFromScript, start_menu.c:329):
  -- the field plays SEQ_SE_DP_WIN_OPEN as it opens the menu. Coming back
  -- from a row's screen the cartridge's menu task simply resumes, silently.
  if game.gen4StartMenuReturning then
    game.gen4StartMenuReturning = nil
  else
    se(self, "SEQ_SE_DP_WIN_OPEN")
  end
  return self
end

-- ------------------------------------------------------------------ rows --

-- The MODS row, or nil when no mod is installed (a vanilla install's menu is
-- the cartridge's and nothing else).  Shared with HgssStartMenu and
-- Gen5StartMenu, which build their own row lists.
function Gen4StartMenu.modsRow(game)
  local status = game and game.modStatus
  if not (status and #(status.available or {}) > 0) then return nil end
  return { id = "mods", label = Strings("MODS") }
end

-- The LINK row, or nil: link play needs a party, and the cartridge's
-- minigames (`menu` carries safari / bugContest / palPark as new() worked
-- them out) keep their own menus.  Shared with HgssStartMenu and
-- Gen5StartMenu.
function Gen4StartMenu.linkRow(game, menu)
  if #((game and game.save or {}).party or {}) == 0 then return nil end
  if menu and (menu.safari or menu.bugContest or menu.palPark) then return nil end
  return { id = "link", label = Strings("LINK") }
end

-- the link screen is a state of its own (it owns the socket and outlives
-- the menu); shared with the HGSS and BW menus
function Gen4StartMenu.openLink(game)
  local ok, LinkState = pcall(require, "src.link.LinkState")
  if not ok then
    Logger.warn("start menu: link play is not available (%s)", tostring(LinkState))
    return false
  end
  game.stack:push(LinkState.new(game))
  return true
end

-- Whether a row belongs on the menu at all.  See the header: Platinum's own
-- hide flags are not in this port's Gen 4 save, so these are the engine's
-- conditions, which answer the same questions.
function Gen4StartMenu:available(id)
  if id == "pokedex" then
    local ok, Flags = pcall(require, "src.script.Flags")
    if ok and Flags.hasPokedex then return Flags.hasPokedex(self.game.save) end
    return true
  end
  if id == "pokemon" then
    return #((self.game.save or {}).party or {}) > 0
  end
  return true
end

function Gen4StartMenu:labelFor(row)
  if row.playerName then
    local player = ((self.game.save or {}).player or {})
    return tostring(player.name or Strings("PLAYER"))
  end
  local label = row.label
  if type(label) ~= "string" or label == "" then return row.id:upper() end
  -- A leftover control code would print as braces; the only template on this
  -- menu is handled above, so anything still carrying one is a row this port
  -- does not know how to fill and its own name is the honest stand-in.
  if label:find("{") then return row.id:upper() end
  return label
end

-- THE FEMALE BAG IS A DIFFERENT ICON, which is one line in the cartridge and
-- would be a silently wrong picture here.
function Gen4StartMenu:iconFor(row)
  local index = row.icon
  if index == nil then return nil end
  if row.femaleIcon then
    local gender = ((self.game.save or {}).player or {}).gender
    if gender == "girl" or gender == "female" then index = row.femaleIcon end
  end
  return index
end

-- ---------------------------------------------------------------- pictures --

function Gen4StartMenu:img(key)
  local rec = self.art[key]
  return self:imgAt((type(rec) == "table" and rec.path) or rec)
end

function Gen4StartMenu:imgAt(path)
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4StartMenu:icon(index)
  if index == nil then return nil end
  return self:img(("menu/icons_%02d"):format(index))
end

-- ------------------------------------------------------------------ input --

function Gen4StartMenu:style()
  local options = (self.game.save or {}).options or {}
  return (options.gen4StartMenuStyle == "bottom") and "bottom" or "main"
end

function Gen4StartMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4StartMenu:reopen()
  return function()
    self.game.gen4StartMenuReturning = true
    Screens.push(self.game, "StartMenu")
    -- if the push landed on another version's menu, do not leave the mark
    self.game.gen4StartMenuReturning = nil
  end
end

function Gen4StartMenu:select()
  local row = self.rows[self.index]
  if not row then return end
  local reopen = self:reopen()
  local id = row.id
  if id == "exit" then return self:close() end
  if id == "mods" then
    -- the manager goes ON TOP of the menu, as the Game Boy menu's does:
    -- ManagerState pops itself when backed out of, which leaves the player
    -- on this menu, on this row
    return Screens.push(self.game, "ManagerState")
  end
  self.game.stack:pop()
  if id == "link" then
    Gen4StartMenu.openLink(self.game)
    return
  end
  if id == "retire" and self.bugContest then
    require("src.world.HgssBugContest").runStd(self.game.overworld, 10404)
    if self.onCancel then self.onCancel() end
    return
  end
  if id == "retire" and self.palPark then
    -- `StartMenu_SelectRetire` outside a Safari Game: the map's script 4
    -- (Pal Park's "Would you like to retire?")
    local ow = self.game.overworld
    if ow then require("src.world.Gen4PalPark").runMapScript(ow, 4) end
    if self.onCancel then self.onCancel() end
    return
  end
  if id == "retire" then
    -- `StartMenu_SelectRetire`: SCRIPT_ID(SAFARI_GAME, 21) -- "Would you like
    -- to retire from the Safari Game?" and, on yes, back to the gate
    local ow = self.game.overworld
    local rows = require("src.world.Gen4TileScripts").compile(self.game.data, "safari_game", 21)
    if ow and rows then ow:queueScript(rows, { mapId = ow.map and ow.map.id }) end
    if self.onCancel then self.onCancel() end
    return
  end
  if id == "pokedex" then
    Screens.push(self.game, "PokedexMenu", { onCancel = reopen })
  elseif id == "pokemon" then
    Screens.push(self.game, "PartyMenu", { onCancel = reopen })
  elseif id == "bag" then
    Screens.push(self.game, "BagMenu", { onCancel = reopen })
  elseif id == "trainerCase" then
    Screens.push(self.game, "TrainerCard", { onCancel = reopen })
  elseif id == "options" then
    Screens.push(self.game, "OptionsMenu", { onCancel = reopen })
  elseif id == "save" then
    self:engineAction(Strings("SAVE"), reopen)
  else
    Logger.warn("gen4 start menu: '%s' has no screen yet", tostring(id))
    if self.onCancel then self.onCancel() end
  end
end

-- SAVE IS THE ENGINE'S, deliberately and not by omission.  It is the one row
-- with a consequence -- the panel, the confirmation, the "now saving" beat, the
-- write and the failure message -- and all of that already exists, correct, in
-- `StartMenu`.  Re-implementing it here would give this port two save flows
-- that can disagree, and the one that disagrees would be the one nobody tests.
--
-- So the row is fetched FROM the engine's own menu by its label and its action
-- is run.  If the engine's menu has no such row on this cartridge, that is said
-- rather than silently doing nothing on a keypress.
function Gen4StartMenu:engineAction(label, reopen)
  local ok, menu = pcall(require("src.ui.StartMenu").new, self.game)
  local item
  if ok and type(menu) == "table" then
    for _, candidate in ipairs(menu.items or {}) do
      if candidate.label == label then item = candidate break end
    end
  end
  if item and item.onSelect then
    -- The engine's rows re-open the ENGINE's start menu on cancel; this one
    -- has to come back here instead, which is what `reopen` is.
    local okRun, err = pcall(item.onSelect)
    if okRun then return end
    Logger.warn("gen4 start menu: the engine's '%s' row raised (%s)",
                tostring(label), tostring(err))
  else
    Logger.warn("gen4 start menu: the engine's start menu has no '%s' row on "
                .. "this cartridge", tostring(label))
  end
  if reopen then reopen() end
end

function Gen4StartMenu:update()
  local input = self.game.input
  if not input then return end
  local count = #self.rows
  if count == 0 then return self:close() end
  self.frame = (self.frame or 0) + 1
  local before = self.index
  -- a tapped row (touchpressed below) is chosen as A on it would be
  local tap = self.tapRow
  self.tapRow = nil
  if tap and self.rows[tap] then
    self.index = tap
    self.game.gen4StartMenuCursor = self.rows[tap].id
    se(self, "SEQ_SE_DP_SELECT")
    return self:select()
  end
  -- StartMenu_Select -> Menu_ProcessInputWithSound(menu, SEQ_SE_DP_SELECT78)
  -- (start_menu.c:690, menu.c:120-156): A and the cancel keys play
  -- SE_CONFIRM_sseq_3, a cursor move that lands plays SELECT78
  if input:wasPressed("up") then
    self.index = (self.index - 2) % count + 1
  elseif input:wasPressed("down") then
    self.index = self.index % count + 1
  elseif input:wasPressed("a") then
    se(self, "SEQ_SE_DP_SELECT")
    self:select()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    se(self, "SEQ_SE_DP_SELECT")
    self:close()
  end
  if self.index ~= before then
    se(self, "SEQ_SE_DP_SELECT78")
    -- StartMenu_ChangeActiveMenuIcon: the new row's icon swells, then wiggles
    self.swellFrom = self.frame
    local row = self.rows[self.index]
    self.game.gen4StartMenuCursor = row and row.id
  end
end

-- ------------------------------------------------------------------- draw --

-- THE ICONS (Gen4StartMenuArt): animation icon * 3 + 0 (still, PALETTE_
-- GRAYSCALE) on every row but the cursor's, whose icon runs 1 (the swell,
-- SRT 1 -> 1.3 -> 1) once it arrives and then 2 (the wiggle, +-10 degrees,
-- looping) in PALETTE_COLORED. The field's sprite clock is 30 Hz, so each
-- NANR frame is two of the port's.
function Gen4StartMenu:iconFrame(row, selected)
  local data = self.game.data or {}
  local anims = ((data.gen4_start_menu_ink or {}).anims) or {}
  local art = data.gen4_start_menu_art or {}
  local seq, t = row.icon * 3, 0
  if selected then
    local since = (self.frame or 0) - (self.swellFrom or -1000)
    local swell = anims[row.icon * 3 + 2]
    local swellLen = 0
    for _, f in ipairs((swell or {}).frames or {}) do swellLen = swellLen + (f.duration or 1) * 2 end
    if self.swellFrom and since < swellLen then seq, t = row.icon * 3 + 1, since
    else seq, t = row.icon * 3 + 2, since - swellLen end
  end
  local a = anims[seq + 1]
  local frame = { cell = row.icon }
  if a and a.frames and #a.frames > 0 then
    local total = 0
    for _, f in ipairs(a.frames) do total = total + (f.duration or 1) * 2 end
    local k = math.max(0, math.floor(t))
    if a.mode == 2 or a.mode == 4 then k = k % math.max(1, total) end
    frame = a.frames[#a.frames]
    for _, f in ipairs(a.frames) do
      local d = (f.duration or 1) * 2
      if k < d then frame = f; break end
      k = k - d
    end
  end
  local rec = art[("icon_%02d_%d"):format(frame.cell or row.icon, selected and 1 or 0)]
  return rec, frame
end

function Gen4StartMenu:drawIcon(row, selected, x, y)
  local rec, frame = self:iconFrame(row, selected)
  local image = rec and self:imgAt(rec.path)
  if not image then return false end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local rot = (frame.rot or 0) * 2 * math.pi / 65536
  local sx, sy = frame.sx or 1, frame.sy or 1
  g.draw(image, x + (frame.x or 0), y + (frame.y or 0), rot, sx, sy, -(rec.originX or -16), -(rec.originY or -16))
  return true
end

-- The cartridge's geometry, made to FIT: seven rows at tile 1 end at tile 22,
-- and an eighth (the port's MODS) would run off the 24-tile screen.  The
-- panel first moves up toward tile 0, then -- only if that is not enough --
-- the rows close up.  Seven rows get the cartridge's layout untouched.
function Gen4StartMenu:fittedLayout()
  local L = self.layout
  local rows = math.max(1, #self.rows)
  local tileY = math.floor(L.panelY / 8)
  local over = tileY + rows * L.rowTiles - 24
  if over <= 0 then return L end
  local F = {}
  for k, v in pairs(L) do F[k] = v end
  local up = math.min(over, tileY)
  tileY = tileY - up
  F.panelY = L.panelY - up * 8
  F.firstY = L.firstY - up * 8
  if tileY + rows * L.rowTiles > 24 then
    F.rowTiles = math.max(2, math.floor((24 - tileY) / rows))
    F.pitch = F.rowTiles * 8
    F.firstY = F.panelY + math.floor(F.pitch / 2)
  end
  return F
end

-- Touch: a tap on a row picks it.  Only a tap that lands on a row is claimed,
-- so the on-screen pad keeps every other touch.
function Gen4StartMenu:touchpressed(_, px, py)
  local x, y
  -- the same test draw() uses to put the panel on the second screen
  local onSecond = self:style() == "bottom" and SecondScreen.mode(self.game) ~= "off"
  if onSecond and SecondScreen.toLocal then
    x, y = SecondScreen.toLocal(self.game, px, py)
  else
    local rect = require("src.render.Renderer").uiPresentation
    x, y = px, py
    if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
  end
  if not x then return false end
  local L = self:fittedLayout()
  if x < L.panelX or x >= L.panelX + L.panelW then return false end
  local i = math.floor((y - L.panelY - 4) / L.pitch) + 1
  if y < L.panelY or i < 1 or i > #self.rows then return false end
  self.tapRow = i
  return true
end

function Gen4StartMenu:drawPanel()
  local g = love.graphics
  local L = self:fittedLayout()
  local rows = #self.rows
  local h = rows * L.pitch + 8

  Font.drawBox(math.floor(L.panelX / 8), math.floor(L.panelY / 8),
               math.floor(L.panelW / 8), rows * L.rowTiles)

  for i, row in ipairs(self.rows) do
    local y = L.firstY + (i - 1) * L.pitch
    local selected = (i == self.index)

    -- The cursor first: on hardware it is a sprite behind the row, and drawing
    -- it after the label would cover the label.
    if selected then
      -- menu_gra's cursor in menu.NCLR ROW 1 (the orange edge) from
      -- `gen4_menu_art`; the planner's `menu/cursor` is row 0 (grey). The
      -- cell's origin is (-48, -16) on its 96x32, i.e. centred.
      local rec = ((self.game.data or {}).gen4_menu_art or {}).cursor
      local cursor = (type(rec) == "table" and self:imgAt(rec.path)) or self:img("menu/cursor")
      if cursor then
        local cw, ch = cursor:getDimensions()
        g.setColor(1, 1, 1, 1)
        g.draw(cursor, L.cursorX - cw / 2, y - ch / 2)
      else
        g.setColor(0.98, 0.83, 0.30, 0.55)
        g.rectangle("fill", L.panelX + 4, y - 10, L.panelW - 8, 20)
        g.setColor(1, 1, 1, 1)
      end
    end

    local icon = not (row.icon and self:drawIcon(row, selected, L.iconX, y)) and self:icon(row.icon)
    if icon then
      local iw, ih = icon:getDimensions()
      -- Grey when it is not the row you are on, colour when it is: the
      -- cartridge swaps the sprite's palette (PALETTE_GRAYSCALE /
      -- PALETTE_COLORED) rather than its picture, and one composed picture is
      -- all this port has, so the difference is carried in the tint.
      if selected then g.setColor(1, 1, 1, 1) else g.setColor(0.62, 0.64, 0.68, 1) end
      g.draw(icon, L.iconX - iw / 2, y - ih / 2)
      g.setColor(1, 1, 1, 1)
    end

    -- The words: the list menu over the window at tile (20, 1), drawn by
    -- Menu_New(template, 28, 4, ...) -- left-aligned 28 pixels in, 4 down,
    -- one row every 24 (16 + lineSpacing 8).
    local label = row.label or ""
    Font.draw(label, L.panelX + 28, L.panelY + 4 + (i - 1) * L.pitch)
  end
  g.setColor(1, 1, 1, 1)
end

-- THE BALL COUNT (`StartMenu_PrintBallCount`): a 12x4-tile window at tile
-- (1, 1) while a Safari Game runs -- "SAFARI BALLS" over "Stock: NN".
function Gen4StartMenu:drawBallCount()
  local st = (self.game.save or {}).safari
  local text = (self.game.data or {}).text or {}
  -- Pal Park's: "PARK BALLS", the balls not yet thrown (FieldSystem_GetParkBallCount)
  local PalPark = require("src.world.Gen4PalPark")
  if not st and PalPark.inPark(self.game.save) then
    Font.drawBox(1, 1, 12, 4)
    Font.draw(text.TEXT_B0367_00010 or "PARK BALLS", 16, 16)
    Font.draw((text.TEXT_B0367_00011 or "Stock: {N}"):gsub("{[^}]*}", ("%d"):format(PalPark.parkBalls(self.game.save)), 1), 16, 32)
    return
  end
  if not st then return end
  Font.drawBox(1, 1, 12, 4)
  local title = text.TEXT_B0367_00009 or "SAFARI BALLS"
  local stock = (text.TEXT_B0367_00011 or "Stock: {N}")
    :gsub("{[^}]*}", ("%d"):format(st.balls or 0), 1)
  Font.draw(title, 16, 16)
  Font.draw(stock, 16, 32)
end

function Gen4StartMenu:draw()
  if self:style() == "bottom" and SecondScreen.mode(self.game) ~= "off" then
    -- The authentic arrangement, through the second-screen surface -- so on
    -- `inset` the menu is in the corner panel and on `swap` it takes the
    -- window, and this file does not have to know which.
    SecondScreen.drawFrame(self.game)
    return SecondScreen.draw(self.game, function() self:drawPanel() end)
  end
  self:drawPanel()
  self:drawBallCount()
end

return Gen4StartMenu
