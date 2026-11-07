-- ENTER A CODE (docs/online-design.md 2.2 "Entry", workstream WS2).
--
-- Takes either kind of invite code: a direct code (10-23 symbols, checked by
-- its own check symbol) or a six-symbol hub/relay room code.  Four ways in,
-- all feeding one model:
--
--   * D-pad / gamepad: a key grid of the 31 symbols plus DEL, PASTE and OK.
--     A types the key under the cursor, B deletes (and backs out when the
--     field is empty), START is OK, SELECT pastes.  A grid rather than
--     CodeEntry's per-slot scrub because a 17-symbol code by scrub is ~130
--     presses; by grid it is ~60.
--   * Keyboard: love.textinput types (letters are taken as code symbols, so
--     WASD/Z/X do not move the cursor here -- the arrow keys, Enter, Escape
--     and Backspace do), Ctrl+V / Cmd+V pastes, Ctrl+C copies.
--   * Touch / mouse: tap a key.  Tapping the code field opens the phone's
--     on-screen keyboard where there is one (love.keyboard.setTextInput).
--   * Clipboard: love.system.getClipboardText, with the code pulled out of
--     whatever text surrounds it (InviteCode.findInText).
--
-- Typos are caught before anything is sent: a full-length code whose check
-- symbol does not match says so in words, and 0/O/1/I/L are named as the
-- characters codes never use.
--
-- USE (WS4):
--   LongCodeEntry.open(game, {
--     title = "ENTER CODE",          -- optional
--     myLanIp = Net.lanIP(),        -- rebuilds a short LAN address
--     allowShort = true,             -- accept 6-symbol room codes (default)
--     allowDirect = true,            -- accept direct codes (default)
--     onDone = function(invite) end, -- InviteCode.decode's table
--     onCancel = function() end,
--     style = "game" | "neutral",    -- default: game when a font is loaded
--     width = , height = ,           -- surface; default Theme.uiSize / DS 256x192
--   })
-- The screen pops itself before calling onDone / onCancel.
--
-- LongCodeEntry.Model and LongCodeEntry.Grid are pure (no love) for tests.

local InviteCode = require("src.online.InviteCode")

local LongCodeEntry = {}
LongCodeEntry.__index = LongCodeEntry
LongCodeEntry.isOpaque = true

-- ===================================================================== model

local Model = {}
LongCodeEntry.Model = Model

function Model.new(opts)
  opts = opts or {}
  return {
    chars = {},
    max = opts.max or InviteCode.MAX_LENGTH,
    myLanIp = opts.myLanIp,
    allowShort = opts.allowShort ~= false,
    allowDirect = opts.allowDirect ~= false,
  }
end

function Model.text(m) return table.concat(m.chars) end

function Model.display(m) return InviteCode.group(Model.text(m)) end

function Model.clear(m) m.chars = {} end

-- one symbol (any case); false when it is not a symbol or the field is full
function Model.insert(m, ch)
  if type(ch) ~= "string" or #ch ~= 1 then return false end
  ch = ch:upper()
  if not InviteCode.isSymbol(ch) then return false end
  if #m.chars >= m.max then return false end
  m.chars[#m.chars + 1] = ch
  return true
end

function Model.backspace(m)
  if #m.chars == 0 then return false end
  m.chars[#m.chars] = nil
  return true
end

-- Typed text (love.textinput delivers a string, maybe several characters on
-- a phone).  Separators are skipped.  Returns true, or false and a message
-- naming the first character that is not part of any code.
function Model.typeText(m, text)
  local okAll, msg = true, nil
  for ch in tostring(text or ""):gmatch(".") do
    if ch:match("[%s%-_%.]") then
      -- grouping the player typed: ignored
    elseif InviteCode.isSymbol(ch) then
      if not Model.insert(m, ch) then
        okAll, msg = false, okAll and ("A code is at most %d characters."):format(m.max) or msg
      end
    else
      local up = ch:upper()
      if okAll then
        if up == "0" or up == "O" or up == "1" or up == "I" or up == "L" then
          msg = "Codes have no 0, O, 1, I or L."
        else
          msg = ("%s is not part of a code."):format(ch)
        end
      end
      okAll = false
    end
  end
  return okAll, msg
end

-- Replace the field with a code found in `text` (the clipboard).  Returns
-- invite on a code that decodes; otherwise false and the message, leaving
-- whatever symbols the text did hold in the field so the player can fix it.
function Model.paste(m, text)
  if type(text) ~= "string" or text == "" then
    return false, "The clipboard is empty."
  end
  local invite, raw = InviteCode.findInText(text, m.myLanIp)
  if invite and Model.accepts(m, invite) then
    Model.clear(m)
    for i = 1, math.min(#raw, m.max) do m.chars[i] = raw:sub(i, i) end
    return invite
  end
  -- keep the symbols that were there, so a near-miss can be corrected
  local kept = {}
  for ch in text:upper():gmatch(".") do
    if InviteCode.isSymbol(ch) and #kept < m.max then kept[#kept + 1] = ch end
  end
  if #kept > 0 then m.chars = kept end
  if invite then return false, Model.refusal(m, invite) end
  local _, why = InviteCode.findInText(text, m.myLanIp)
  return false, why or "No code found in the clipboard."
end

function Model.accepts(m, invite)
  if invite.type == "short" then return m.allowShort end
  return m.allowDirect
end

function Model.refusal(m, invite)
  if invite.type == "short" then
    return "Short room codes need a hub. Ask for the long code."
  end
  return "This screen takes a six-character room code."
end

-- What the field holds right now:
--   { state = "empty" }
--   { state = "typing", count = n, need = nextLength }
--   { state = "ok", invite = invite }
--   { state = "bad", message = why, reason = reason }   (a full-length code
--                                                         that does not decode)
function Model.status(m)
  local n = #m.chars
  if n == 0 then return { state = "empty", count = 0 } end
  local text = Model.text(m)
  if InviteCode.isValidLength(n) then
    local invite, why, reason = InviteCode.decode(text, m.myLanIp)
    if invite and Model.accepts(m, invite) then return { state = "ok", invite = invite, count = n } end
    if invite and invite.type == "short" then
      -- six symbols of a longer code, on a screen that takes no room codes
      return { state = "typing", count = n, need = InviteCode.MIN_LENGTH }
    end
    if invite then return { state = "bad", message = Model.refusal(m, invite), reason = "kind", count = n } end
    -- still typing a longer code?  A valid length is only final at the
    -- longest one; before that a mismatch just means "keep going"
    local need
    for _, len in ipairs(InviteCode.LENGTHS) do
      if len > n then need = len; break end
    end
    if need and reason == "checksum" then
      return { state = "typing", count = n, need = need, message = why, reason = reason }
    end
    return { state = "bad", message = why, reason = reason, count = n }
  end
  local need
  if n < InviteCode.SHORT_LENGTH and m.allowShort then need = InviteCode.SHORT_LENGTH end
  if not need then
    for _, len in ipairs(InviteCode.LENGTHS) do
      if len > n then need = len; break end
    end
  end
  return { state = "typing", count = n, need = need }
end

-- OK pressed: invite, or nil, message, reason
function Model.submit(m)
  local n = #m.chars
  if n == 0 then return nil, "Enter the code your friend gave you.", "empty" end
  local invite, why, reason = InviteCode.decode(Model.text(m), m.myLanIp)
  if not invite then return nil, why, reason end
  if not Model.accepts(m, invite) then return nil, Model.refusal(m, invite), "kind" end
  return invite
end

-- ===================================================================== grid
-- The key grid: 31 symbols then DEL in four rows of eight, PASTE and OK
-- sharing the fifth.  Cells are in grid units { id, label, col, row, span }.

local Grid = {}
LongCodeEntry.Grid = Grid
Grid.COLS = 8

function Grid.cells()
  local cells = {}
  local charset = InviteCode.CHARSET
  for i = 1, #charset do
    local ch = charset:sub(i, i)
    cells[#cells + 1] = { id = ch, label = ch, col = (i - 1) % Grid.COLS, row = math.floor((i - 1) / Grid.COLS), span = 1 }
  end
  local n = #charset -- 31: DEL takes the 32nd cell
  cells[#cells + 1] = { id = "del", label = "DEL", col = n % Grid.COLS, row = math.floor(n / Grid.COLS), span = 1 }
  local lastRow = math.floor(n / Grid.COLS) + 1
  cells[#cells + 1] = { id = "paste", label = "PASTE", col = 0, row = lastRow, span = Grid.COLS / 2 }
  cells[#cells + 1] = { id = "ok", label = "OK", col = Grid.COLS / 2, row = lastRow, span = Grid.COLS / 2 }
  return cells
end

Grid.ROWS = math.floor(#InviteCode.CHARSET / Grid.COLS) + 2 -- 5

-- the cell index reached from `index` moving (dx, dy), wrapping
function Grid.move(cells, index, dx, dy)
  local cur = cells[index]
  local cx = cur.col + cur.span / 2
  if dx ~= 0 then
    local row = {}
    for i, c in ipairs(cells) do if c.row == cur.row then row[#row + 1] = i end end
    table.sort(row, function(a, b) return cells[a].col < cells[b].col end)
    for k, i in ipairs(row) do
      if i == index then
        local nk = (k - 1 + dx) % #row + 1
        return row[nk]
      end
    end
    return index
  end
  local rows = Grid.ROWS
  local target = (cur.row + dy) % rows
  -- the cell in the target row under the current centre (or the nearest)
  local best, bestD
  for i, c in ipairs(cells) do
    if c.row == target then
      local d
      if cx >= c.col and cx < c.col + c.span then d = 0 else d = math.abs((c.col + c.span / 2) - cx) end
      if not bestD or d < bestD then best, bestD = i, d end
    end
  end
  return best or index
end

function Grid.find(cells, id)
  for i, c in ipairs(cells) do if c.id == id then return i end end
  return nil
end

-- ===================================================================== screen

local function playSound(game, name)
  if not (game and game.data) then return end
  pcall(function() require("src.core.Sound").play(game.data, name) end)
end

function LongCodeEntry.new(game, opts)
  local self = setmetatable({}, LongCodeEntry)
  opts = opts or {}
  self.game = game
  self.opts = opts
  self.title = opts.title or "ENTER CODE"
  self.model = Model.new(opts)
  self.cells = Grid.cells()
  self.index = 1
  self.message = nil      -- { text=, color= , timer= }
  self.flash = {}         -- cell index -> seconds of "pressed" highlight
  self.width, self.height = require("src.ui.online.CodeStyle").surface(opts)
  self.styleKind = opts.style or require("src.ui.online.CodeStyle").defaultKind(game)
  if opts.text then Model.typeText(self.model, opts.text) end
  return self
end

function LongCodeEntry.open(game, opts)
  local screen = LongCodeEntry.new(game, opts)
  game.stack:push(screen)
  return screen
end

function LongCodeEntry:uiSize() return self.width, self.height end

function LongCodeEntry:say(text, kind)
  local C = require("src.ui.online.CodeStyle").colors
  self.message = text and { text = text, color = kind == "bad" and C.bad or (kind == "good" and C.good or C.dim),
                            timer = 4 } or nil
end

function LongCodeEntry:close()
  if self.softKeyboard and love and love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, false)
    self.softKeyboard = nil
  end
  if self.game and self.game.stack and self.game.stack:top() == self then self.game.stack:pop() end
end

function LongCodeEntry:cancel()
  playSound(self.game, "Press_AB")
  self:close()
  if self.opts.onCancel then self.opts.onCancel() end
end

function LongCodeEntry:submit()
  local invite, why = Model.submit(self.model)
  if not invite then
    self:say(why, "bad")
    playSound(self.game, "Wrong")
    return false
  end
  playSound(self.game, "Press_AB")
  self.done = invite
  self:close()
  if self.opts.onDone then self.opts.onDone(invite) end
  return true
end

function LongCodeEntry:paste()
  local text
  if love and love.system and love.system.getClipboardText then
    local ok, t = pcall(love.system.getClipboardText)
    if ok then text = t end
  end
  if self.opts.clipboard then text = self.opts.clipboard() end -- tests / hosts
  local invite, why = Model.paste(self.model, text)
  if invite then
    self:say("Pasted. Press OK.", "good")
    self.index = Grid.find(self.cells, "ok") or self.index
  else
    self:say(why, "bad")
  end
  return invite
end

function LongCodeEntry:copy()
  if love and love.system and love.system.setClipboardText and #self.model.chars > 0 then
    pcall(love.system.setClipboardText, Model.display(self.model))
    self:say("Copied.", "good")
  end
end

-- one key of the grid (by cell index), as A or a tap does
function LongCodeEntry:pressCell(i)
  local cell = self.cells[i]
  if not cell then return end
  self.flash[i] = 0.12
  if cell.id == "del" then
    Model.backspace(self.model)
    self.message = nil
  elseif cell.id == "paste" then
    self:paste()
  elseif cell.id == "ok" then
    self:submit()
  else
    if Model.insert(self.model, cell.id) then
      self.message = nil
      -- a full-length code that checks out: put the cursor on OK
      if Model.status(self.model).state == "ok" and #self.model.chars == InviteCode.MAX_LENGTH then
        self.index = Grid.find(self.cells, "ok") or self.index
      end
    else
      self:say(("A code is at most %d characters."):format(self.model.max), "bad")
    end
  end
end

function LongCodeEntry:update(dt)
  dt = dt or 1 / 60
  for i, t in pairs(self.flash) do
    t = t - dt
    self.flash[i] = t > 0 and t or nil
  end
  if self.message and self.message.timer then
    self.message.timer = self.message.timer - dt
    if self.message.timer <= 0 then self.message = nil end
  end
  local input = self.game and self.game.input
  if not input then return end
  local moved = false
  if input:wasPressed("left") then self.index = Grid.move(self.cells, self.index, -1, 0); moved = true end
  if input:wasPressed("right") then self.index = Grid.move(self.cells, self.index, 1, 0); moved = true end
  if input:wasPressed("up") then self.index = Grid.move(self.cells, self.index, 0, -1); moved = true end
  if input:wasPressed("down") then self.index = Grid.move(self.cells, self.index, 0, 1); moved = true end
  if moved then playSound(self.game, "Select") end
  if input:wasPressed("a") then
    self:pressCell(self.index)
  elseif input:wasPressed("b") then
    if #self.model.chars == 0 then self:cancel() return end
    Model.backspace(self.model)
    self.message = nil
  elseif input:wasPressed("start") then
    self:submit()
  elseif input:wasPressed("select") then
    self:paste()
  end
end

-- ------------------------------------------------------------- keyboard

local function modifierDown()
  if not (love and love.keyboard and love.keyboard.isDown) then return false end
  return love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
end

-- Game:keypressed hands every key here instead of to Input while this
-- screen is on top.  Keys that type are kept (textinput brings the
-- character); keys that steer are passed on to Input so the grid, a
-- gamepad and rebinds work as anywhere else.
function LongCodeEntry:onKeyPressed(key)
  if modifierDown() then
    if key == "v" then self:paste() return end
    if key == "c" then self:copy() return end
    if key == "a" or key == "x" or key == "z" then return end
  end
  if key == "backspace" or key == "delete" then
    Model.backspace(self.model); self.message = nil; return
  end
  if key == "escape" then self:cancel() return end
  if key == "return" or key == "kpenter" then self:submit() return end
  if #key == 1 or key == "space" then return end -- typed: textinput delivers it
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

function LongCodeEntry:onTextInput(text)
  local ok, msg = Model.typeText(self.model, text)
  if ok then self.message = nil else self:say(msg, "bad") end
end

-- ------------------------------------------------------------- touch

function LongCodeEntry:layout()
  local CodeStyle = require("src.ui.online.CodeStyle")
  local style = self.style or CodeStyle.new(self.styleKind)
  self.style = style
  local W, H = self.width, self.height
  local lh = style:lineHeight()
  local cw = style:cellWidth(InviteCode.CHARSET)
  local L = {}
  L.margin = 8
  L.lh = lh
  L.cw = cw
  L.titleY = 2
  -- the code field: groups of four, as many groups per line as fit
  local gap = math.max(4, math.floor(cw / 2))
  L.groupW = 4 * cw + gap
  L.groupsPerLine = math.max(1, math.floor((W - 2 * L.margin - 8 + gap) / L.groupW))
  local maxGroups = math.ceil(InviteCode.MAX_LENGTH / 4)
  L.codeLines = math.ceil(maxGroups / L.groupsPerLine)
  -- the frame is tile art in the game look, so the field sits on whole tiles
  -- and the code is centred inside it
  local function tile(v) return math.ceil(v / 8) * 8 end
  L.fieldX = L.margin
  L.fieldY = tile(L.titleY + lh + 1)
  L.fieldW = W - 2 * L.margin
  L.fieldH = tile(L.codeLines * (lh + 2) + (L.codeLines > 1 and 16 or 8))
  L.codeX = L.fieldX + math.floor((L.fieldW - (L.groupsPerLine * L.groupW - gap)) / 2)
  L.codeY = L.fieldY + math.floor((L.fieldH - L.codeLines * (lh + 2)) / 2) + 1
  L.statusY = L.fieldY + L.fieldH + 1
  -- the key grid fills the bottom; keys give up height before the status
  -- line drops below two rows
  local remaining = H - 2 - L.statusY
  local keyH = math.floor((remaining - 2 * lh) / Grid.ROWS)
  -- (a cartridge face's line height counts descender room the capitals on
  -- the keys do not use, so a key may be a little shorter than a line)
  keyH = math.max(math.max(11, lh - 4), math.min(lh + 6, keyH))
  local keyW = math.floor((W - 2 * 4) / Grid.COLS)
  L.keyW, L.keyH = keyW, keyH
  L.gridX = math.floor((W - keyW * Grid.COLS) / 2)
  L.gridY = H - 2 - keyH * Grid.ROWS
  L.statusLines = math.max(1, math.floor((L.gridY - L.statusY) / lh))
  return L
end

function LongCodeEntry:cellRect(L, cell)
  return L.gridX + cell.col * L.keyW, L.gridY + cell.row * L.keyH, cell.span * L.keyW, L.keyH
end

function LongCodeEntry:touchpressed(_, px, py)
  local CodeStyle = require("src.ui.online.CodeStyle")
  local x, y = CodeStyle.toSurface(px, py)
  if not x then return false end
  return self:tap(x, y)
end

-- a tap in surface pixels (also what tests drive)
function LongCodeEntry:tap(x, y)
  local L = self:layout()
  for i, cell in ipairs(self.cells) do
    local cx, cy, cw, ch = self:cellRect(L, cell)
    if x >= cx and x < cx + cw and y >= cy and y < cy + ch then
      self.index = i
      self:pressCell(i)
      return true
    end
  end
  if y >= L.fieldY and y < L.fieldY + L.fieldH then
    -- the field: bring up a phone's keyboard, where it has one
    if love and love.keyboard and love.keyboard.hasScreenKeyboard
       and love.keyboard.hasScreenKeyboard() and love.keyboard.setTextInput then
      pcall(love.keyboard.setTextInput, true)
      self.softKeyboard = true
    end
    return true
  end
  return true -- the whole screen is this widget's
end

-- ------------------------------------------------------------- draw

function LongCodeEntry:drawCode(L)
  local style = self.style
  local chars = self.model.chars
  local n = #chars
  local slots = math.max(n + 1, 1)
  if n >= self.model.max then slots = n end
  local blink = (love and love.timer and love.timer.getTime and math.floor(love.timer.getTime() * 2) % 2 == 0)
  for i = 1, slots do
    local g = math.floor((i - 1) / 4)
    local line = math.floor(g / L.groupsPerLine)
    local gx = g % L.groupsPerLine
    local x = L.codeX + gx * L.groupW + ((i - 1) % 4) * L.cw
    local y = L.codeY + line * (L.lh + 2)
    if i <= n then
      local ch = chars[i]
      style:text(ch, x + math.floor((L.cw - style:width(ch)) / 2), y)
    elseif blink ~= false then
      style:rect("fill", x + 1, y + L.lh - 1, L.cw - 2, 1)
    end
  end
end

function LongCodeEntry:draw()
  local L = self:layout()
  local style = self.style
  local C = require("src.ui.online.CodeStyle").colors
  local W = self.width
  style:clear(self.width, self.height)
  style:text(self.title, L.margin, L.titleY)
  local count = #self.model.chars
  local st = Model.status(self.model)
  local counter = tostring(count)
  if st.need then counter = ("%d/%d"):format(count, st.need) end
  style:text(counter, W - L.margin - style:width(counter), L.titleY, C.dim)

  style:box(L.fieldX, L.fieldY, L.fieldW, L.fieldH)
  self:drawCode(L)

  -- status: the message of the moment, else what the field holds
  local text, color
  if self.message then
    text, color = self.message.text, self.message.color
  elseif st.state == "ok" then
    text, color = (st.invite.type == "short") and "Room code. Press OK." or "Code OK. Press OK.", C.good
  elseif st.state == "bad" then
    text, color = st.message, C.bad
  elseif st.state == "typing" and st.reason == "checksum" then
    text, color = "No match yet: keep typing, or look for a typo.", C.dim
  elseif st.state == "empty" then
    text, color = "Type, paste or pick the code.", C.dim
  end
  if text then
    local lines = style:wrap(text, W - 2 * L.margin)
    for i = 1, math.min(#lines, L.statusLines) do
      style:text(lines[i], L.margin, L.statusY + (i - 1) * L.lh, color)
    end
  end

  for i, cell in ipairs(self.cells) do
    local x, y, w, h = self:cellRect(L, cell)
    style:key(x, y, w, h, i == self.index, self.flash[i] ~= nil)
    local label = cell.label
    if style:width(label) > w - 2 then
      label = ({ paste = "PST", del = "DL" })[cell.id] or label
    end
    local ink = (cell.id == "ok" and st.state == "ok") and C.good or C.ink
    style:text(label, x + math.floor((w - style:width(label)) / 2),
               y + math.floor((h - L.lh) / 2) + 1, ink)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return LongCodeEntry
