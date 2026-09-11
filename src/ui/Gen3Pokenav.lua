-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKéNAV.
--
-- The one row on the START menu that opened nothing.  Its flag was read
-- correctly and the row appeared exactly when the cartridge shows it; behind
-- it there was no screen at all.
--
-- FOUR THINGS IT DOES, and the gating between them is the cartridge's:
--
--   MAP          the region map, with the zoom that only exists here.
--   CONDITION    the pentagon -- PARTY, or SEARCH the boxes by a category.
--   MATCH CALL   who is registered, and who wants a rematch.
--   RIBBONS      thirty-two kinds in a nine-by-four grid.
--
-- GetPokenavMainMenuType (0x081C9268) is three lines: MAP, CONDITION and
-- SWITCH OFF always; MATCH CALL on flag $130; RIBBONS on $130 AND $89B.  The
-- cartridge really does make RIBBONS depend on MATCH CALL -- its menu type 2
-- is only reachable through type 1 -- and RIBBONS is gated a SECOND time when
-- you press A: with no ribbon anywhere in the party or the boxes it refuses
-- with a line rather than opening an empty grid.
--
-- THE ROW LABELS ARE ART, NOT TEXT.  There are no MAP / CONDITION / MATCH
-- CALL strings anywhere in the cartridge: the five rows are thirteen 128x16
-- buttons in one compressed sprite sheet, four sprites each, and the import
-- composes them into a strip.  The only words on the menu are the one-line
-- description underneath, and those ARE strings -- fourteen of them, one per
-- selectable row, which is why this screen can say what every row does
-- without inventing a single sentence.

local Assets = require("src.render.Assets")
local Boxes = require("src.pokemon.Boxes")
local Contest = require("src.pokemon.Contest")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local MatchCall = require("src.script.MatchCall")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3Pokenav = {}
Gen3Pokenav.__index = Gen3Pokenav
Gen3Pokenav.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- The row ids sMenuItems holds, named.  0..4 are the main menu, 5..7 the
-- CONDITION submenu, 8..13 the SEARCH one.
local ROW = {
  MAP = 0, CONDITION = 1, MATCH_CALL = 2, RIBBONS = 3, SWITCH_OFF = 4,
  COND_PARTY = 5, COND_SEARCH = 6, COND_CANCEL = 7,
  SEARCH_COOL = 8, SEARCH_CANCEL = 13,
}

-- Used only when the cache predates the POKéNAV stage: the same five rows,
-- the same three menus, drawn as words instead of the cartridge's buttons.
local FALLBACK = {
  menus = {
    { highlightY = 42, highlightStep = 20, rows = { 0, 1, 4 } },
    { highlightY = 42, highlightStep = 20, rows = { 0, 1, 2, 4 } },
    { highlightY = 42, highlightStep = 20, rows = { 0, 1, 2, 3, 4 } },
    { highlightY = 56, highlightStep = 20, rows = { 5, 6, 7 } },
    { highlightY = 40, highlightStep = 16, rows = { 8, 9, 10, 11, 12, 13 } },
  },
  labels = {
    [0] = "MAP", [1] = "CONDITION", [2] = "MATCH CALL", [3] = "RIBBONS",
    [4] = "SWITCH OFF", [5] = "PARTY", [6] = "SEARCH", [7] = "CANCEL",
    [8] = "COOL", [9] = "BEAUTY", [10] = "CUTE", [11] = "SMART",
    [12] = "TOUGH", [13] = "CANCEL",
  },
  flags = { matchCall = 0x130, ribbons = 0x89B, has = 0x862 },
}

local function flagKey(n)
  return require("src.script.Gen3Commands").flagKey(n)
end

function Gen3Pokenav:uiSize() return GBA_W, GBA_H end
function Gen3Pokenav:wantsFillScale() return true end

function Gen3Pokenav:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

function Gen3Pokenav:record()
  local r = (self.game.data.constants or {}).gen3Pokenav
  if type(r) ~= "table" or type(r.menus) ~= "table" then return nil end
  return r
end

function Gen3Pokenav:menus()
  local r = self:record()
  return (r and r.menus) or FALLBACK.menus
end

function Gen3Pokenav:describe(rowId)
  local r = self:record()
  local d = r and r.descriptions and r.descriptions[rowId]
  return d
end

function Gen3Pokenav:label(rowId)
  return FALLBACK.labels[rowId] or ""
end

-- ---------------------------------------------------------------------------
-- WHICH MENU, and what is on it
-- ---------------------------------------------------------------------------
function Gen3Pokenav:mainMenuType()
  local r = self:record()
  local flags = (r and r.flags) or FALLBACK.flags
  local set = self.game.save.flags or {}
  if set[flagKey(flags.matchCall)] ~= true then return 0 end
  if set[flagKey(flags.ribbons)] ~= true then return 1 end
  return 2
end

-- HasAnyRibbons: the party and every box, and it is asked ONCE when the
-- POKéNAV opens rather than every frame, which is also when the cartridge
-- asks it.
function Gen3Pokenav:anyRibbons()
  for _, mon in ipairs(self.game.save.party or {}) do
    if Contest.ribbonCount(mon) > 0 then return true end
  end
  local boxes = (self.game.save or {}).boxes
  for _, box in pairs(boxes or {}) do
    for _, mon in pairs(box.mons or box) do
      if type(mon) == "table" and Contest.ribbonCount(mon) > 0 then
        return true
      end
    end
  end
  return false
end

function Gen3Pokenav.new(game, opts)
  local self = setmetatable({}, Gen3Pokenav)
  self.game = game
  self.opts = opts or {}
  self.onCancel = self.opts.onCancel
  self.mode = "menu"
  self.menuType = self:mainMenuType()
  self.cursor = 1
  self.hasRibbons = self:anyRibbons()
  self.notice = nil
  self.blink = 0
  return self
end

function Gen3Pokenav:menu()
  return self:menus()[self.menuType + 1] or FALLBACK.menus[1]
end

function Gen3Pokenav:rowId()
  local m = self:menu()
  return m.rows[self.cursor] or m.rows[1]
end

function Gen3Pokenav:close()
  if self.game.stack then self.game.stack:pop() end
  if self.onCancel then self.onCancel() end
end

-- ---------------------------------------------------------------------------
-- CHOOSING
-- ---------------------------------------------------------------------------
function Gen3Pokenav:choose()
  local id = self:rowId()
  local game = self.game
  Sound.play(game.data, "Press_AB")

  if id == ROW.MAP then
    Screens.push(game, "Gen3RegionMap", { zoom = true })
  elseif id == ROW.CONDITION then
    self.menuType, self.cursor = 3, 1
  elseif id == ROW.MATCH_CALL then
    self:openMatchCall()
  elseif id == ROW.RIBBONS then
    -- THE SECOND GATE.  The row is on the menu because the ribbon FLAG is
    -- set; whether it opens is a different question, and the cartridge
    -- answers it with a line rather than an empty grid.
    if not self.hasRibbons then
      Sound.play(game.data, "Wrong")
      self.notice = Strings("There are no RIBBON winners.")
      self.noticePage = 1
      return
    end
    self:openList("ribbons")
  elseif id == ROW.SWITCH_OFF then
    return self:close()
  elseif id == ROW.COND_PARTY then
    self:openList("condition")
  elseif id == ROW.COND_SEARCH then
    self.menuType, self.cursor = 4, 1
  elseif id == ROW.COND_CANCEL then
    self.menuType, self.cursor = self:mainMenuType(), 2
  elseif id == ROW.SEARCH_CANCEL then
    self.menuType, self.cursor = 3, 2
  elseif id >= ROW.SEARCH_COOL and id < ROW.SEARCH_CANCEL then
    self.searchCategory = Contest.ORDER[id - ROW.SEARCH_COOL + 1]
    self:openList("condition")
  end
end

function Gen3Pokenav:back()
  Sound.play(self.game.data, "Press_AB")
  if self.notice then
    -- A TURNS THE PAGE FIRST.  Dismissing on the first A is what made a long
    -- match call show its opening line and nothing else.
    if self:noticeAdvance() then return end
    self.notice = nil
    return
  end
  if self.mode ~= "menu" then
    self.mode = "menu"
    return
  end
  if self.menuType == 3 then
    self.menuType, self.cursor = self:mainMenuType(), 2
  elseif self.menuType == 4 then
    self.menuType, self.cursor = 3, 2
  else
    self:close()
  end
end

-- ---------------------------------------------------------------------------
-- THE MON LIST, shared by CONDITION and RIBBONS
--
-- CONDITION▸PARTY walks the party; CONDITION▸SEARCH walks the party AND every
-- box, ordered by the category you picked, which is what "find cool POKéMON"
-- means.  RIBBONS walks everything that has one.
-- ---------------------------------------------------------------------------
local function boxMons(save)
  local out = {}
  for name, box in pairs((save or {}).boxes or {}) do
    local list = box.mons or box
    for slot, mon in pairs(list) do
      if type(mon) == "table" and mon.species then
        out[#out + 1] = { mon = mon, where = name, slot = slot }
      end
    end
  end
  return out
end

function Gen3Pokenav:openList(kind)
  local save = self.game.save
  local rows = {}
  if kind == "condition" and self.searchCategory then
    for i, mon in ipairs(save.party or {}) do
      rows[#rows + 1] = { mon = mon, where = "party", slot = i }
    end
    for _, row in ipairs(boxMons(save)) do rows[#rows + 1] = row end
    local cat = self.searchCategory
    table.sort(rows, function(a, b)
      return Contest.graph(a.mon, cat) > Contest.graph(b.mon, cat)
    end)
  elseif kind == "condition" then
    for i, mon in ipairs(save.party or {}) do
      rows[#rows + 1] = { mon = mon, where = "party", slot = i }
    end
  else
    for i, mon in ipairs(save.party or {}) do
      if Contest.ribbonCount(mon) > 0 then
        rows[#rows + 1] = { mon = mon, where = "party", slot = i }
      end
    end
    for _, row in ipairs(boxMons(save)) do
      if Contest.ribbonCount(row.mon) > 0 then rows[#rows + 1] = row end
    end
  end
  if #rows == 0 then
    Sound.play(self.game.data, "Wrong")
    self.notice = Strings("There are no POKéMON to check.")
    self.noticePage = 1
    return
  end
  self.mode = kind == "ribbons" and "ribbonList" or "conditionList"
  self.rows = rows
  self.listIndex = 1
  self.listTop = 1
end

function Gen3Pokenav:selectedMon()
  local row = self.rows and self.rows[self.listIndex]
  return row and row.mon or nil
end

-- ---------------------------------------------------------------------------
-- MATCH CALL
-- ---------------------------------------------------------------------------
function Gen3Pokenav:openMatchCall()
  local entries = MatchCall.list(self.game.data, self.game.save)
  self.mode = "matchCall"
  self.calls = entries
  self.callIndex = 1
  self.callTop = 1
  self.callMenu = nil
end

function Gen3Pokenav:callName(entry)
  if not entry then return "" end
  if entry.name then return entry.name end
  -- A header with no name of its own names a rematch ROW instead, and the name
  -- on it is that row's first trainer's.  The lookup lives in MatchCall
  -- because the rematch table holds trainer INDICES and the trainers module is
  -- keyed by slug -- indexing it with the number found nothing and left every
  -- Gym Leader on this screen reading as the fallback word.
  local row = entry.rematch
               and MatchCall.rematchRows(self.game.data)[entry.rematch + 1]
  local trainer = row and MatchCall.trainer(self.game.data, row.trainers[1])
  return (trainer and trainer.name) or Strings("TRAINER")
end

function Gen3Pokenav:callWhere(entry)
  local sections = (self.game.data.constants or {}).gen3MapSections
  local sec = entry and entry.mapSec
  if sec and sections and sections[sec] then return sections[sec] end
  local row = entry and entry.rematch
               and MatchCall.rematchRows(self.game.data)[entry.rematch + 1]
  local def = row and (self.game.data.maps or {})[row.map]
  local id = def and tonumber(def.regionMapSection)
  if id and sections and sections[id] then return sections[id] end
  return Strings("UNKNOWN")
end

-- ---------------------------------------------------------------------------
-- INPUT
-- ---------------------------------------------------------------------------
local function listMove(self, field, topField, delta, rows, visible)
  local n = #rows
  if n == 0 then return end
  self[field] = (self[field] - 1 + delta) % n + 1
  if self[field] < self[topField] then self[topField] = self[field] end
  if self[field] > self[topField] + visible - 1 then
    self[topField] = self[field] - visible + 1
  end
end

Gen3Pokenav.LIST_ROWS = 8

function Gen3Pokenav:update()
  self.blink = (self.blink + 1) % 60
  local input = self.game.input
  if not input then return end

  if self.notice then
    if input:wasPressed("a") or input:wasPressed("b") then
      Sound.play(self.game.data, "Press_AB")
      self.notice = nil
    end
    return
  end

  if input:wasPressed("b") then return self:back() end

  if self.mode == "menu" then
    local m = self:menu()
    if input:wasPressed("down") then
      self.cursor = self.cursor % #m.rows + 1
      Sound.play(self.game.data, "Press_AB")
    elseif input:wasPressed("up") then
      self.cursor = (self.cursor - 2) % #m.rows + 1
      Sound.play(self.game.data, "Press_AB")
    elseif input:wasPressed("a") then
      self:choose()
    end
    return
  end

  if self.mode == "conditionList" or self.mode == "ribbonList" then
    if input:wasPressed("down") then
      listMove(self, "listIndex", "listTop", 1, self.rows, Gen3Pokenav.LIST_ROWS)
    elseif input:wasPressed("up") then
      listMove(self, "listIndex", "listTop", -1, self.rows, Gen3Pokenav.LIST_ROWS)
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      self.mode = (self.mode == "ribbonList") and "ribbonGrid" or "conditionDetail"
      self.ribbonIndex = 1
    end
    return
  end

  if self.mode == "conditionDetail" then
    if input:wasPressed("down") then
      listMove(self, "listIndex", "listTop", 1, self.rows, Gen3Pokenav.LIST_ROWS)
    elseif input:wasPressed("up") then
      listMove(self, "listIndex", "listTop", -1, self.rows, Gen3Pokenav.LIST_ROWS)
    end
    return
  end

  if self.mode == "ribbonGrid" then
    local ids = Contest.ribbonIds(self:selectedMon())
    if #ids > 0 then
      if input:wasPressed("right") then
        self.ribbonIndex = self.ribbonIndex % #ids + 1
      elseif input:wasPressed("left") then
        self.ribbonIndex = (self.ribbonIndex - 2) % #ids + 1
      end
    end
    return
  end

  if self.mode == "matchCall" then
    if self.callMenu then
      if input:wasPressed("down") then
        self.callMenu = self.callMenu % 3 + 1
      elseif input:wasPressed("up") then
        self.callMenu = (self.callMenu - 2) % 3 + 1
      elseif input:wasPressed("a") then
        return self:callAction()
      end
      return
    end
    if input:wasPressed("down") then
      listMove(self, "callIndex", "callTop", 1, self.calls, Gen3Pokenav.LIST_ROWS)
    elseif input:wasPressed("up") then
      listMove(self, "callIndex", "callTop", -1, self.calls, Gen3Pokenav.LIST_ROWS)
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      self.callMenu = 1
    end
    return
  end
end

-- CALL / CHECK / CANCEL.
function Gen3Pokenav:callAction()
  local entry = self.calls and self.calls[self.callIndex]
  local game = self.game
  Sound.play(game.data, "Press_AB")
  if self.callMenu == 3 or not entry then
    self.callMenu = nil
    return
  end
  if self.callMenu == 1 then
    -- THE CALL.  SelectMatchCallMessage walks the trainer's own lines
    -- backwards and takes the highest whose gate flag is set, then sets
    -- whatever that line says to set -- which is how MR. STONE's opening
    -- line unlocks his second one.
    -- WHERE YOU ARE STANDING CHANGES WHAT THEY SAY: a registered trainer on
    -- your own route asks whether you are near them, and one anywhere else
    -- talks about their battles instead.  MatchCall cannot see the overworld,
    -- so the screen hands it the map.
    local ow = game.overworld
    local here = ow and ow.map and ow.map.id or nil
    local text = MatchCall.message(game.data, game.save, entry, { here = here })
    if not text and MatchCall.entryReady(game.data, game.save, entry) then
      text = Strings("%s wants to battle again!", self:callName(entry))
    end
    self.notice = text or Strings("%s is not answering.", self:callName(entry))
    self.noticePage = 1
  else
    local ready = MatchCall.entryReady(game.data, game.save, entry)
    local lines = {
      self:callName(entry),
      entry.row and entry.row.description or entry.className or "",
      self:callWhere(entry),
      ready and Strings("Wants a rematch!") or "",
    }
    self.notice = table.concat(lines, "\n")
    self.noticePage = 1
  end
  self.callMenu = nil
end

function Gen3Pokenav:keypressed(key)
  if key == "b" then return self:back() end
  if key == "a" and self.mode == "menu" then return self:choose() end
end

-- ---------------------------------------------------------------------------
-- DRAWING
-- ---------------------------------------------------------------------------
local warned = false
function Gen3Pokenav:art(which)
  local r = self:record()
  local path = r and r.images and r.images[which]
  if type(path) ~= "string" then
    if not warned and which == "menu" then
      warned = true
      Logger.warn("gen3 pokenav: this cache carries no POKeNAV art -- "
                    .. "re-import to get the cartridge's own screen")
    end
    return nil
  end
  local ok, img = pcall(Assets.image, path)
  return ok and img or nil
end

function Gen3Pokenav:drawBackground()
  local field = self:art("menu")
  if field then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(field, 0, 0)
  else
    love.graphics.setColor(0.16, 0.22, 0.36, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- The button strip, one 128x16 row per icon id.
function Gen3Pokenav:drawButton(rowId, x, y, selected)
  local r = self:record()
  local strip = self:art("buttons")
  local size = (r and r.button) or { width = 128, height = 16 }
  if strip then
    local iw, ih = strip:getDimensions()
    local quad = love.graphics.newQuad(0, rowId * size.height,
                                       size.width, size.height, iw, ih)
    love.graphics.setColor(1, 1, 1, selected and 1 or 0.72)
    love.graphics.draw(strip, quad, x, y)
    love.graphics.setColor(1, 1, 1, 1)
  else
    love.graphics.setColor(selected and 0.98 or 0.55, selected and 0.90 or 0.58,
                           selected and 0.40 or 0.62, 1)
    love.graphics.rectangle("fill", x, y, size.width, size.height)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self:label(rowId), x + 6, y + 4)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function Gen3Pokenav:drawMenu()
  local m = self:menu()
  -- the highlight band's own geometry: the cartridge fills sixteen scanlines
  -- starting eight above `highlightY + step * cursor`, and the buttons are
  -- 128 wide against the right edge of a 240 screen
  local x = GBA_W - 128 - 8
  for i, rowId in ipairs(m.rows) do
    local y = (m.highlightY or 42) + (m.highlightStep or 20) * (i - 1) - 8
    self:drawButton(rowId, x, y, i == self.cursor)
  end
  local text = self:describe(self:rowId()) or self:label(self:rowId())
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 17, 30, 3)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(text, math.max(4, math.floor((GBA_W - Font.width(text)) / 2)), 142)
  love.graphics.setColor(1, 1, 1, 1)
end

local function monName(game, row)
  local mon = row and row.mon
  if not mon then return "" end
  local def = (game.data.pokemon or {})[mon.species]
  return mon.nickname or (def and def.name) or tostring(mon.species)
end

function Gen3Pokenav:drawMonList()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(11, 0, 19, 17)
  love.graphics.setColor(0, 0, 0, 1)
  local cat = self.searchCategory
  for i = 0, Gen3Pokenav.LIST_ROWS - 1 do
    local row = self.rows[self.listTop + i]
    if not row then break end
    local y = 12 + i * 16
    Font.draw(monName(self.game, row), 104, y)
    if cat then
      local v = tostring(Contest.graph(row.mon, cat))
      Font.draw(v, GBA_W - 16 - Font.width(v), y)
    elseif self.mode == "ribbonList" then
      local v = tostring(Contest.ribbonCount(row.mon))
      Font.draw(v, GBA_W - 16 - Font.width(v), y)
    end
    if self.listTop + i == self.listIndex then
      Font.drawCode(Theme.cursor, 94, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- THE PENTAGON.  Five vertices about (155, 91), each pushed out by a radius
-- that is looked up rather than scaled: the cartridge's table is deliberately
-- non-linear, 4 at zero and 35 at 255, with most of its resolution spent
-- under sixty -- so a Pokémon that has eaten a couple of Pokéblocks shows a
-- visible bump instead of nothing.
function Gen3Pokenav:drawCondition()
  local r = self:record()
  local cond = r and r.condition
  local mon = self:selectedMon()
  local pts = Contest.vertices(mon, cond)
  local centre = (cond and cond.centre) or { x = 155, y = 91 }

  love.graphics.setColor(0.10, 0.14, 0.24, 0.85)
  love.graphics.circle("fill", centre.x, centre.y, 42)

  -- THE FRAME, and the five directions it is built from.
  --
  -- These are kept rather than thrown away because the CATEGORY WORDS hang
  -- off them.  They used to hang off the DATA vertices instead, and that is
  -- the bug that was on screen: a Pokemon whose conditions are all zero has
  -- all five data vertices at the centre, so all five words were drawn on top
  -- of each other in a heap -- TOUGH over SMART, BEAUTY over CUTE.  Which is
  -- every Pokemon that has never eaten a POKeBLOCK, so it is what the screen
  -- looked like for most of a playthrough.
  --
  -- On the cartridge the five words are ART at fixed places around the
  -- pentagon.  They do not move with the data and neither do these.
  love.graphics.setColor(0.42, 0.48, 0.60, 1)
  local outer, frame = {}, {}
  local full = Contest.radius(cond, Contest.MAX)
  local dirs = Contest.directions(cond)
  for i in ipairs(Contest.ORDER) do
    local cos, sin = dirs[i].cos, dirs[i].sin
    local x = centre.x + cos * full / 256
    local y = centre.y - sin * full / 256
    outer[#outer + 1] = x
    outer[#outer + 1] = y
    frame[i] = { x = x, y = y, cos = cos / 256, sin = sin / 256 }
  end
  love.graphics.polygon("line", outer)

  local poly = {}
  for _, p in ipairs(pts) do poly[#poly + 1] = p.x; poly[#poly + 1] = p.y end
  love.graphics.setColor(0.98, 0.78, 0.30, 0.75)
  if #poly >= 6 then love.graphics.polygon("fill", poly) end
  love.graphics.setColor(1, 0.94, 0.62, 1)
  if #poly >= 6 then love.graphics.polygon("line", poly) end

  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 12, 5)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(monName(self.game, self.rows[self.listIndex]), 6, 8)
  local sheen = Contest.sheenLevel(mon, cond)
  Font.draw(Strings("SHEEN %d", sheen), 6, 24)
  love.graphics.setColor(1, 1, 1, 1)

  -- AND WHAT EACH DIRECTION IS, placed off the FRAME and not off the data.
  --
  -- Each word sits just outside its own corner, pushed along that corner's
  -- own direction so it clears the pentagon's line, and then clamped to the
  -- screen -- the top corner is centred over itself, the two on the right run
  -- rightwards and the two on the left run leftwards, which is how the
  -- cartridge lays them out.
  local PAD = 5
  love.graphics.setColor(1, 1, 1, 1)
  for i, key in ipairs(Contest.ORDER) do
    local p = frame[i]
    local word = key:upper()
    local w = Font.width(word)
    if p then
      local lx = p.x + p.cos * PAD
      -- how far the corner leans left or right decides which edge of the word
      -- is anchored to it; a corner that leans neither way is centred
      if p.cos > 0.25 then lx = lx + 2
      elseif p.cos < -0.25 then lx = lx - w - 2
      else lx = lx - w / 2 end
      local ly = p.y - p.sin * PAD - Font.glyphHeight() / 2
      if p.sin > 0.25 then ly = ly - 2
      elseif p.sin < -0.25 then ly = ly + 2 end
      Font.draw(word,
                math.max(0, math.min(GBA_W - w, math.floor(lx + 0.5))),
                math.max(0, math.min(GBA_H - Font.glyphHeight(),
                                     math.floor(ly + 0.5))))
    end
  end
end

function Gen3Pokenav:drawRibbons()
  local r = self:record()
  local grid = (r and r.ribbons and r.ribbons.grid)
               or { cols = 9, x = 88, y = 32, step = 16, giftSlot = 27 }
  local mon = self:selectedMon()
  local ids = Contest.ribbonIds(mon)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 30, 3)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("RIBBONS %d", #ids), 6, 6)
  love.graphics.setColor(1, 1, 1, 1)

  for i, id in ipairs(ids) do
    -- the seven gift ribbons always start on the fourth row, whatever came
    -- before them
    local slot = (id >= 25) and (grid.giftSlot + (id - 25)) or (i - 1)
    local col = slot % grid.cols
    local row = math.floor(slot / grid.cols)
    local x = grid.x + col * grid.step
    local y = grid.y + row * grid.step
    love.graphics.setColor(0.92, 0.84, 0.34, 1)
    love.graphics.rectangle("fill", x + 1, y + 1, grid.step - 2, grid.step - 2)
    if i == self.ribbonIndex then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("line", x, y, grid.step, grid.step)
    end
  end

  local chosen = ids[self.ribbonIndex]
  local text = r and r.ribbons and r.ribbons.text and chosen
               and r.ribbons.text[chosen]
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 16, 30, 4)
  love.graphics.setColor(0, 0, 0, 1)
  if text then
    Font.draw(text[1] or "", 8, 134)
    Font.draw(text[2] or "", 8, 148)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen3Pokenav:drawMatchCall()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(11, 0, 19, 17)
  Font.drawBox(0, 5, 11, 2)
  Font.drawBox(0, 9, 11, 8)
  love.graphics.setColor(0, 0, 0, 1)

  for i = 0, Gen3Pokenav.LIST_ROWS - 1 do
    local entry = self.calls[self.callTop + i]
    if not entry then break end
    local y = 12 + i * 16
    Font.draw(self:callName(entry), 104, y)
    -- "wants a rematch" is a marker at the far right of the row, which is
    -- where the cartridge puts its two-tile icon
    if MatchCall.entryReady(self.game.data, self.game.save, entry) then
      love.graphics.setColor(0.90, 0.30, 0.25, 1)
      love.graphics.rectangle("fill", 232, y + 2, 4, 10)
      love.graphics.setColor(0, 0, 0, 1)
    end
    if self.callTop + i == self.callIndex then
      Font.drawCode(Theme.cursor, 94, y)
    end
  end

  local entry = self.calls[self.callIndex]
  local where = self:callWhere(entry)
  Font.draw(where, math.max(2, 88 - Font.width(where)), 46)

  if self.callMenu then
    for i, word in ipairs({ Strings("CALL"), Strings("CHECK"), Strings("CANCEL") }) do
      local y = 74 + (i - 1) * 16
      Font.draw(word, 16, y)
      if i == self.callMenu then Font.drawCode(Theme.cursor, 4, y) end
    end
  else
    Font.draw(Strings("No. registered"), 2, 74)
    local n = tostring(#self.calls)
    Font.draw(n, 86 - Font.width(n), 74)
    local ready = 0
    for _, e in ipairs(self.calls) do
      if MatchCall.entryReady(self.game.data, self.game.save, e) then
        ready = ready + 1
      end
    end
    Font.draw(Strings("Rematches"), 2, 90)
    local m = tostring(ready)
    Font.draw(m, 86 - Font.width(m), 90)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen3Pokenav:draw()
  self:drawBackground()
  if self.mode == "menu" then
    self:drawMenu()
  elseif self.mode == "conditionList" or self.mode == "ribbonList" then
    self:drawMonList()
  elseif self.mode == "conditionDetail" then
    self:drawCondition()
  elseif self.mode == "ribbonGrid" then
    self:drawRibbons()
  elseif self.mode == "matchCall" then
    self:drawMatchCall()
  end

  if self.notice then self:drawNotice() end
end

-- ---------------------------------------------------------------------------
-- THE MESSAGE BOX, WHICH WAS NOT A BOX.
--
-- Reported from play: "for the match call feature the text isnt fitting
-- properly and is going outside of the box and overlapping the border etc".
-- It was drawing whatever it was handed at a fixed x, splitting only on the
-- newlines already in the string and stepping down fourteen pixels a line
-- until it ran out of screen.  Two things came of that, and a MATCH CALL hit
-- both at once:
--
--   * A LINE TOO WIDE RAN OFF THE RIGHT EDGE.  Match call lines carry their
--     own breaks, but the port splices the player's name into them -- and a
--     seven-letter name is wider than the {PLAYER} it replaced, so lines that
--     fit on the cartridge do not fit here.  Nothing wrapped them.
--   * A LINE TOO MANY RAN THROUGH THE BOTTOM BORDER.  Three lines at fourteen
--     pixels from 120 reach 163 on a 160-pixel screen, so the third was drawn
--     through the frame and off the bottom.
--
-- So the box measures itself now.  The text is wrapped to the frame's own
-- inside width by the same paginator the field's text boxes use -- so a mod's
-- wider font wraps correctly too -- and what does not fit becomes another
-- PAGE rather than another line off the edge.  A more-to-come arrow sits
-- where the cartridge puts it and A turns over.
Gen3Pokenav.NOTICE = {
  tx = 0, ty = 14, tw = 30, th = 6,   -- the frame, in tiles
  padX = 8, padY = 8,                 -- inside it
  lineStep = 14,
}

function Gen3Pokenav:noticeLayout()
  local N = Gen3Pokenav.NOTICE
  local inner = N.tw * 8 - N.padX * 2
  local cols = math.max(1, math.floor(inner / 8))
  local pages = require("src.render.TextBox").paginate(
    tostring(self.notice or ""), cols)
  -- how many lines actually fit between the frame's two borders
  local height = N.th * 8 - N.padY - 4
  local rows = math.max(1, math.floor(height / N.lineStep))
  -- ...and paginate wrapped to width, not to height, so a page longer than
  -- the box becomes several
  local out = {}
  for _, page in ipairs(pages) do
    for i = 1, #page, rows do
      local slice = {}
      for k = i, math.min(i + rows - 1, #page) do slice[#slice + 1] = page[k] end
      out[#out + 1] = slice
    end
  end
  if #out == 0 then out = { { "" } } end
  return out
end

-- A turns the page; the caller only clears the notice once the last one has
-- been read, which is what stops a long call vanishing after one screen.
function Gen3Pokenav:noticeAdvance()
  local pages = self:noticeLayout()
  local at = (self.noticePage or 1) + 1
  if at > #pages then
    self.noticePage = nil
    return false
  end
  self.noticePage = at
  return true
end

function Gen3Pokenav:drawNotice()
  local N = Gen3Pokenav.NOTICE
  local pages = self:noticeLayout()
  local page = pages[math.min(self.noticePage or 1, #pages)] or {}
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(N.tx, N.ty, N.tw, N.th)
  love.graphics.setColor(0, 0, 0, 1)
  local y = N.ty * 8 + N.padY
  for _, line in ipairs(page) do
    Font.draw(line, N.tx * 8 + N.padX, y)
    y = y + N.lineStep
  end
  -- there is more of this call to come
  if (self.noticePage or 1) < #pages then
    Font.drawCode(Theme.moreArrow or Theme.cursor,
                  (N.tx + N.tw) * 8 - 12, (N.ty + N.th) * 8 - 12)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3Pokenav
