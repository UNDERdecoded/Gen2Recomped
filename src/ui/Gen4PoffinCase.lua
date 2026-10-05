-- THE POFFIN CASE from the Bag (item 449), as Platinum draws it
-- (src/applications/poffin_case: manager.c, menus.c), in the cartridge's own
-- art (src/import/Gen4PoffinArt.lua) and bank 463's words:
--
--   TOP     poru_gra's list screen. "POFFIN CASE" in the corner; six Poffins
--           at a time, newest first, "{name}  Lv. n" (#22) with CLOSE (#6)
--           last; the cursor box at (105, 40 + 16 x row) and the scroll
--           arrows at (80, 18) / (80, 140); the chosen Poffin's picture at
--           (231, 76), its smoothness ("SMOOTH / n", #4) and a dot for each
--           flavour it has. GIVE / TRASH / BACK (#1-#3) in a window at tile
--           (26, 17); "Discard this {Poffin}?" (#7) with YES / NO, then "The
--           {Poffin} was thrown out." (#8).
--   BOTTOM  the flavour pentagon and its six buttons -- SPICY, DRY, SWEET,
--           BITTER, SOUR and ALL (#11-#16), each in its own colours -- that
--           filter the list; the chosen one's line (#17-#21) along the top.
--           On the cartridge they are touched; here they are also L / R.
--
-- GIVE picks a party Pokemon and feeds it (Gen4Poffin.feed), saying bank 462's
-- line for its taste -- #0 happily, #1 disdainfully, #2 plainly -- or bank 455
-- #178, "It won't eat any more...", once its sheen is 255. A cache without the
-- case art falls back to the field menus this screen replaced.

local P = require("src.pokemon.Gen4Poffin")
local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local Case = {}
Case.__index = Case
Case.isOpaque = true
Case.BANK = 463
Case.VIEW = 6                       -- POFFIN_LIST_VIEW_HEIGHT
Case.ALL = 5                        -- FLAVOR_MAX: the ALL button

function Case:uiSize() return 256, 192 end
function Case:wantsFillScale() return true end

local function text(game, bank, n)
  return game.data and game.data.text and game.data.text[T.label(bank, n)]
end

-- a cartridge line with its {STRVAR_1 kind slot pad} slots filled: the values
-- are BUFFERED on the game (Gen4Text.buffer, slot by slot, nil as "") and
-- gen4Markup expands them, as every Gen 4 command does -- not a gsub of the
-- token here, which is the hand-rolled expansion the machine check forbids
local function fill(game, text, values)
  values = values or {}
  local n = 0
  for k in pairs(values) do if type(k) == "number" and k > n then n = k end end
  local list = {}
  for i = 1, n do list[i] = values[i] ~= nil and tostring(values[i]) or "" end
  require("src.import.Gen4Text").buffer(game, (table.unpack or unpack)(list, 1, n))
  local s = tostring(text or "")
  local ok, Commands = pcall(require, "src.script.Commands")
  if ok and Commands and Commands.gen4Markup then
    local okM, plain = pcall(Commands.gen4Markup, s, game)
    if okM and type(plain) == "string" then s = plain end
  end
  return s
end

local function say(game, message, after)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, message, after))
end

function Case.feed(game, index, mon)
  local p = P.case(game.save)[index]
  if not (p and mon) then return nil end
  if not P.canEat(mon) then return text(game, 455, 178) or "It won't eat any more..." end
  local taste = P.preference(p, mon)
  P.feed(p, mon)
  P.remove(game.save, index)
  local def = game.data.pokemon and game.data.pokemon[mon.species]
  local name = mon.nickname or (def and def.name) or "?"
  local n = taste == "like" and 0 or taste == "dislike" and 1 or 2
  return fill(game, text(game, 462, n), { name })
end

-- ------------------------------------------------------------- the list --
-- PoffinManager_FilterPoffins: the Poffins with the filter's flavour, each
-- put at the FRONT as it is found, so the newest is first
function Case:entries()
  local list, out = P.case(self.game.save), {}
  for i, p in ipairs(list) do
    local has = self.filter == Case.ALL
    if not has then has = (tonumber(p.flavors and p.flavors[self.filter + 1]) or 0) > 0 end
    if has then table.insert(out, 1, i) end
  end
  return out
end

function Case:refresh()
  self.rows = self:entries()
  local count = #self.rows + 1                     -- + CLOSE
  self.cursor = math.max(0, math.min(self.cursor, Case.VIEW - 1, count - 1))
  self.top = math.max(0, math.min(self.top, count - Case.VIEW))
  if self.top + self.cursor >= count then self.cursor = count - 1 - self.top end
end

function Case:selected()
  local row = self.top + self.cursor + 1
  return self.rows[row], row
end

function Case.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, filter = Case.ALL, top = 0, cursor = 0,
    mode = "list", action = 0, images = {} }, Case)
  self:refresh()
  return self
end

function Case:close()
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Case:setFilter(f)
  if f == self.filter then return end
  self.filter, self.top, self.cursor = f, 0, 0
  self:refresh()
end

function Case:line(n, values)
  return fill(self.game, text(self.game, Case.BANK, n), values or {})
end

function Case:update()
  local input, game = self.game.input, self.game
  if self.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.mode, self.message = "list", nil
      self:refresh()
    end
    return
  end
  if self.mode == "confirm" then
    if input:wasPressed("up") or input:wasPressed("down") then self.yes = not self.yes end
    local a, b = input:wasPressed("a"), input:wasPressed("b")
    if b or (a and not self.yes) then self.mode, self.message = "list", nil; return end
    if a then
      local index = self:selected()
      local p = P.case(game.save)[index]
      local name = p and P.name(game.data, p) or ""
      if p then P.remove(game.save, index) end
      self:refresh()
      self.message = self:line(8, { name })
      self.mode = "message"
    end
    return
  end
  if self.mode == "action" then
    if input:wasPressed("up") then self.action = (self.action + 2) % 3 end
    if input:wasPressed("down") then self.action = (self.action + 1) % 3 end
    local a, b = input:wasPressed("a"), input:wasPressed("b")
    if b or (a and self.action == 2) then self.mode = "list"; return end
    if a and self.action == 0 then return self:give() end
    if a and self.action == 1 then
      local index = self:selected()
      local p = P.case(game.save)[index]
      self.message = self:line(7, { p and P.name(game.data, p) or "" })
      self.yes, self.mode = true, "confirm"
    end
    return
  end
  -- the list (a ListMenu with PAGER_MODE_LEFT_RIGHT_PAD)
  local count = #self.rows + 1
  if input:wasPressed("up") then
    if self.cursor > 0 then self.cursor = self.cursor - 1 elseif self.top > 0 then self.top = self.top - 1 end
  elseif input:wasPressed("down") then
    if self.cursor < math.min(Case.VIEW, count) - 1 then self.cursor = self.cursor + 1
    elseif self.top + Case.VIEW < count then self.top = self.top + 1 end
  elseif input:wasPressed("left") then
    self.top = math.max(0, self.top - Case.VIEW)
  elseif input:wasPressed("right") then
    self.top = math.max(0, math.min(count - Case.VIEW, self.top + Case.VIEW))
    if self.top + self.cursor >= count then self.cursor = count - 1 - self.top end
  elseif input:wasPressed("l") then
    self:setFilter((self.filter + 5) % 6)
  elseif input:wasPressed("r") then
    self:setFilter((self.filter + 1) % 6)
  end
  local a, b = input:wasPressed("a"), input:wasPressed("b")
  if b then return self:close() end
  if a then
    local index = self:selected()
    if not index then return self:close() end      -- CLOSE
    self.mode, self.action = "action", 0
  end
end

function Case:give()
  local game = self.game
  local index = self:selected()
  self.mode = "list"
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onSwitch = function(mon)
      if not mon then return end
      -- a Pokemon whose sheen is full will not eat: no cutscene, the line only
      if not P.canEat(mon) then
        self.message = Case.feed(game, index, mon) or ""
        self.mode = "message"
        return
      end
      -- the feeding cutscene (src/ui/Gen4PoffinFeed.lua), then the stats
      local p = P.case(game.save)[index]
      local taste = p and P.preference(p, mon) or "neutral"
      game.stack:push(require("src.ui.Gen4PoffinFeed").new(game, {
        mon = mon, poffin = p, taste = taste,
        onDone = function()
          Case.feed(game, index, mon)
          self:refresh()
        end,
      }))
    end,
  })
end

-- the filter buttons' touch rectangles (ProcessTouchScreenAction)
Case.HITBOXES = {
  [0] = { 96, 34, 160, 62 }, { 160, 82, 224, 110 }, { 136, 148, 200, 176 },
  { 56, 150, 120, 178 }, { 32, 82, 96, 110 }, { 96, 102, 160, 130 },
}

function Case:touchpressed(id, px, py)
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local x, y
  if ok and SS.toLocal then x, y = SS.toLocal(self.game, px, py) end
  if not x then return false end
  for f = 0, 5 do
    local r = Case.HITBOXES[f]
    if x >= r[1] and x < r[3] and y >= r[2] and y < r[4] then self:setFilter(f); return true end
  end
  return false
end

-- --------------------------------------------------------------- drawing --
function Case:art(key)
  local index = self.game.data and self.game.data.gen4_poffin_art
  local rec = index and index[key]
  if not rec then return nil end
  if self.images[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    self.images[rec.path] = ok and img or false
  end
  return self.images[rec.path] or nil, rec
end

function Case:sprite(key, x, y)
  local img, rec = self:art(key)
  if img then love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0)) end
end

-- flavour dots on the top screen (sTypeIconPositions)
local DOTS = { [0] = { 40, 156 }, { 54, 165 }, { 49, 180 }, { 31, 180 }, { 26, 165 } }
-- the buttons (sButtonPositions) and their label windows (windows 7-12)
local BUTTONS = { [0] = { 128, 48 }, { 192, 96 }, { 168, 162 }, { 88, 164 }, { 64, 96 }, { 128, 116 } }
local LABELS = { [0] = { 96, 40, 2 }, { 160, 80, 10 }, { 136, 152, 4 }, { 56, 152, 6 }, { 32, 80, 10 }, { 96, 104, 6 } }

function Case:drawTop()
  local g, game = love.graphics, self.game
  g.setColor(1, 1, 1, 1)
  local bg = self:art("case_main")
  if bg then g.draw(bg, 0, 0) end
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.75, 0.75, 0.75 } })
  Font.draw(self:line(0) ~= "" and self:line(0) or "POFFIN CASE", 4, 0)
  -- the list window: tile (2, 4), 22 x 12, text 8 in
  local list = P.case(game.save)
  for r = 0, Case.VIEW - 1 do
    local row = self.top + r + 1
    local y = 32 + r * 16
    if row <= #self.rows then
      local p = list[self.rows[row]]
      Font.draw(P.name(game.data, p), 24, y)
      local lv = ("Lv. %d"):format(P.level(p))
      Font.draw(lv, 16 + 138, y)
    elseif row == #self.rows + 1 then
      Font.draw(self:line(6) ~= "" and self:line(6) or "CLOSE", 24, y)
    end
  end
  Font.popStyle()
  -- the cursor box, its held look while the action menu is up, and the arrows
  self:sprite(self.mode == "list" and "case_select" or "case_select_held", 105, 40 + self.cursor * 16)
  if self.top > 0 then self:sprite("case_up", 80, 18) end
  if self.top + Case.VIEW < #self.rows + 1 then self:sprite("case_down", 80, 140) end
  -- the chosen Poffin: picture, smoothness, flavour dots
  local index = self:selected()
  local p = index and list[index]
  if p then
    self:sprite("poffin_" .. (tonumber(p.type) or 0), 231, 76)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.75, 0.75, 0.75 } })
    Font.draw(self:line(4, { math.min(99, tonumber(p.smoothness) or 0) }), 88 + 8, 160)
    Font.popStyle()
    for f = 0, 4 do
      if (tonumber(p.flavors and p.flavors[f + 1]) or 0) > 0 then self:sprite("case_flavor_" .. f, DOTS[f][1], DOTS[f][2]) end
    end
  end
  -- the action menu and the YES / NO window, standard frames
  if self.mode == "action" then
    Font.drawBox(25, 16, 7, 8)
    g.setColor(0, 0, 0, 1)
    for i = 0, 2 do
      Font.draw(self:line(1 + i), 216, 136 + i * 16)
      if i == self.action then Font.drawCode(require("src.ui.Theme").cursor, 208, 136 + i * 16) end
    end
    g.setColor(1, 1, 1, 1)
  elseif self.mode == "confirm" then
    Font.drawBox(25, 12, 7, 6)
    g.setColor(0, 0, 0, 1)
    for i, n in ipairs({ 9, 10 }) do
      local y = 104 + (i - 1) * 16
      Font.draw(self:line(n), 216, y)
      if (i == 1) == self.yes then Font.drawCode(require("src.ui.Theme").cursor, 208, y) end
    end
    g.setColor(1, 1, 1, 1)
  end
  -- the message box, tile (2, 19), 27 x 4
  if self.message and self.message ~= "" then
    Font.drawDialogueBox(1, 18, 29, 6)
    g.setColor(0, 0, 0, 1)
    local y = 152
    for l in (self.message .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    g.setColor(1, 1, 1, 1)
  end
end

function Case:drawBottom()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local bg = self:art("case_sub")
  if bg then g.draw(bg, 0, 0) end
  for f = 0, 5 do
    local active = f == self.filter
    self:sprite(("case_button_%d_%d"):format(f, active and 1 or 0), BUTTONS[f][1], BUTTONS[f][2])
    local label = self:line(11 + f)
    local L = LABELS[f]
    Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.3, 0.3, 0.3 } })
    Font.draw(label, L[1] + math.floor((64 - Font.width(label)) / 2), L[2] + L[3] + (active and 2 or 0))
    Font.popStyle()
  end
  -- window 6: the filter's line, centred in 160 pixels from x 48
  if self.filter ~= Case.ALL then
    local desc = self:line(17 + self.filter)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.75, 0.75, 0.75 } })
    Font.draw(desc, 48 + math.floor((160 - Font.width(desc)) / 2), 3)
    Font.popStyle()
  end
end

function Case:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  self:drawTop()
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local mode = ok and SS.mode(self.game) or "off"
  if ok and (mode == "display" or mode == "inset") and not SS.stowed(self.game) then
    SS.draw(self.game, function() self:drawBottom() end)
  end
  g.setColor(1, 1, 1, 1)
end

-- -------------------------------------------------------- the old menus --
local function openMenus(game, onDone)
  local Menu = require("src.ui.Menu")
  local reopen
  local function actions(index)
    local p = P.case(game.save)[index]
    local name = P.name(game.data, p)
    local rows = {
      { label = text(game, 463, 1) or "GIVE", onSelect = function()
        require("src.ui.Screens").push(game, "PartyMenu", {
          pickOnly = true,
          onSwitch = function(mon)
            if not mon then return reopen() end
            say(game, Case.feed(game, index, mon) or "", reopen)
          end,
        })
      end },
      { label = text(game, 463, 2) or "TRASH", onSelect = function()
        local TextBox = require("src.render.TextBox")
        game.stack:push(TextBox.new(game, fill(game, text(game, 463, 7), { name }), nil, {
          choice = function(yes)
            if not yes then return reopen() end
            P.remove(game.save, index)
            say(game, fill(game, text(game, 463, 8), { name }), reopen)
          end,
        }))
      end },
      { label = text(game, 463, 3) or "BACK", onSelect = function() reopen() end },
    }
    game.stack:push(Menu.new(game, rows, { cancelable = true, onCancel = function() reopen() end }))
  end
  reopen = function()
    local list = P.case(game.save)
    if #list == 0 then
      if onDone then onDone() end
      return
    end
    local rows = {}
    for i, p in ipairs(list) do
      rows[i] = { label = fill(game, text(game, 463, 22) or "{STRVAR_1 9 0 0}  Lv. {STRVAR_1 51 1 0}",
        { P.name(game.data, p), P.level(p) }), onSelect = function() actions(i) end }
    end
    game.stack:push(Menu.new(game, rows, {
      cancelable = true, maxVisible = math.min(#rows, 7),
      onCancel = function() if onDone then onDone() end end,
    }))
  end
  reopen()
end

function Case.open(game, onDone)
  if #P.case(game.save) == 0 then
    say(game, Strings("There are no Poffins."), onDone)
    return
  end
  local art = game.data and game.data.gen4_poffin_art
  if not (art and art.case_main) then return openMenus(game, onDone) end
  game.stack:push(Case.new(game, onDone))
end

return Case
