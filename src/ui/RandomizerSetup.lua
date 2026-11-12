-- RANDOMIZER SETUP: every randomizer option, by category, with a FULL
-- preset.  Opened from the NEW GAME run-modes screen (RunSetup's RANDOMIZER
-- row, editing the choice before the save exists) and from OPTIONS ->
-- RANDOMIZER (editing the live save; the seed is kept, so switching an
-- option off and on again brings the same picks back).
--
--   RandomizerSetup.open(game, { choice = tbl, onClose = fn })  -- NEW GAME
--   RandomizerSetup.openView(game, { onClose = fn })            -- OPTIONS
--
-- Rows are data (self:rows()), so tests drive :press without love.graphics.
-- Options that do nothing on the loaded generation are greyed out with the
-- reason.  Drawn through CodeStyle in the game's own font and frame.

local RunModes = require("src.runmodes.RunModes")
local RandomOptions = require("src.runmodes.RandomOptions")

local RandomizerSetup = {}
RandomizerSetup.__index = RandomizerSetup
RandomizerSetup.isOpaque = true

local function genOf(game)
  local g = game and game.data and game.data.constants and tonumber(game.data.constants.gen)
  if g then return g end
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and GV and GV.generation then
    local okG, v = pcall(GV.generation)
    if okG then return tonumber(v) end
  end
  return nil
end

function RandomizerSetup.new(game, opts)
  local self = setmetatable({}, RandomizerSetup)
  opts = opts or {}
  self.game, self.opts = game, opts
  self.view = opts.mode == "view"
  self.choice = opts.choice or {}
  self.gen = genOf(game)
  self.index = 1
  self.scroll = 0
  self.notice = nil
  local CodeStyle = require("src.ui.online.CodeStyle")
  self.width, self.height = CodeStyle.surface(opts)
  self.styleKind = opts.style or CodeStyle.defaultKind(game)
  -- start on the first selectable row
  local rows = self:rows()
  while rows[self.index] and rows[self.index].header do self.index = self.index + 1 end
  return self
end

function RandomizerSetup.open(game, opts)
  local s = RandomizerSetup.new(game, opts)
  game.stack:push(s)
  return s
end

function RandomizerSetup.openView(game, opts)
  opts = opts or {}
  opts.mode = "view"
  return RandomizerSetup.open(game, opts)
end

function RandomizerSetup:uiSize() return self.width, self.height end

-- the runModes-like table the values are read from
function RandomizerSetup:source()
  if self.view then return RunModes.get(self.game) end
  return self.choice
end

function RandomizerSetup:read(key)
  return RandomOptions.read(self:source(), key)
end

function RandomizerSetup:write(key, value)
  if self.view then
    RandomOptions.set(self.game.save, key, value)
  else
    RandomOptions.write(self.choice, key, value)
  end
end

function RandomizerSetup:rows()
  local out = {}
  out[#out + 1] = { key = "full", label = "FULL (EVERYTHING)",
    help = "Turn every randomizer option on at once." }
  out[#out + 1] = { key = "none", label = "ALL OFF", help = "Turn every randomizer option off." }
  for _, cat in ipairs(RandomOptions.CATEGORIES) do
    out[#out + 1] = { header = true, label = cat.label }
    for _, o in ipairs(RandomOptions.LIST) do
      if o.cat == cat.id then out[#out + 1] = { key = o.key, option = o, label = o.label, help = o.help } end
    end
  end
  if self.view then
    local rm = RunModes.get(self.game)
    out[#out + 1] = { key = "spoiler", label = "WRITE SPOILER LOG",
      help = "Saves a list of everything this seed changed (seed " .. tostring(rm.seed or "-") .. ")." }
  end
  out[#out + 1] = { key = "done", label = "DONE", help = "Back." }
  return out
end

function RandomizerSetup:locked(row)
  if not row or not row.option then return nil end
  local o = row.option
  if not RandomOptions.supports(o, self.gen) then
    local gens = {}
    for _, g in ipairs(o.gens or {}) do gens[#gens + 1] = tostring(g) end
    return "Not in this game (Gen " .. table.concat(gens, ", ") .. " only)."
  end
  if o.sub and not self:read(o.sub) then return "Turn " .. RandomOptions.BY_KEY[o.sub].label .. " on first." end
  return nil
end

function RandomizerSetup:value(row)
  if row.option then return RandomOptions.label(row.key, self:read(row.key)) end
  if row.key == "full" then return RandomOptions.isFull(self:source()) and "ON" or "" end
  return ""
end

function RandomizerSetup:toggle(row, back)
  if not row or not row.option then return false end
  local why = self:locked(row)
  if why then self.notice = { text = why, timer = 2 } return false end
  local cur = self:read(row.key)
  local nextV
  local o = row.option
  if back and o.values then
    local idx = 1
    for i, v in ipairs(o.values) do if v == (cur or false) then idx = i end end
    nextV = o.values[(idx - 2) % #o.values + 1]
  else
    nextV = RandomOptions.nextValue(row.key, cur)
  end
  self:write(row.key, nextV)
  return true
end

function RandomizerSetup:setAll(on)
  for _, o in ipairs(RandomOptions.LIST) do
    self:write(o.key, on and RandomOptions.FULL[o.key] or false)
  end
  self.notice = { text = on and "Every option is on." or "Every option is off.", timer = 2 }
end

function RandomizerSetup:close()
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
  if self.opts.onClose then self.opts.onClose() end
end

function RandomizerSetup:move(dir)
  local rows = self:rows()
  local i = self.index
  for _ = 1, #rows do
    i = (i - 1 + dir) % #rows + 1
    if not rows[i].header then break end
  end
  self.index = i
end

function RandomizerSetup:press(button)
  local rows = self:rows()
  local row = rows[self.index]
  if button == "up" then
    self:move(-1)
  elseif button == "down" then
    self:move(1)
  elseif button == "left" or button == "right" then
    if row and row.option then self:toggle(row, button == "left") end
  elseif button == "a" then
    if not row then return end
    if row.key == "done" then return self:close() end
    if row.key == "full" then return self:setAll(true) end
    if row.key == "none" then return self:setAll(false) end
    if row.key == "spoiler" then
      local ok, path, err = pcall(function() return require("src.runmodes.RandomData").writeSpoiler(self.game) end)
      self.notice = { text = (ok and path) and ("Saved: " .. tostring(path)) or ("Could not save: " .. tostring(err or path)), timer = 4 }
      return
    end
    self:toggle(row)
  elseif button == "b" or button == "start" then
    return self:close()
  end
end

function RandomizerSetup:update(dt)
  if self.notice then
    self.notice.timer = self.notice.timer - (dt or 1 / 60)
    if self.notice.timer <= 0 then self.notice = nil end
  end
  local input = self.game and self.game.input
  if not input then return end
  for _, b in ipairs({ "up", "down", "left", "right", "a", "b", "start" }) do
    if input:wasPressed(b) then self:press(b) return end
  end
end

function RandomizerSetup:onKeyPressed(key)
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

function RandomizerSetup:layout(style)
  local lh = style:lineHeight()
  local rowH = lh + 2
  local top = math.ceil((lh + 6) / 8) * 8
  -- leave room under the box for two lines of help
  local helpH = 2 * lh + 4
  local visible = math.max(3, math.floor((self.height - top - 10 - helpH) / rowH))
  return { lh = lh, rowH = rowH, top = top, margin = 8, visible = visible }
end

function RandomizerSetup:touchpressed(_, px, py)
  local CodeStyle = require("src.ui.online.CodeStyle")
  local x, y = CodeStyle.toSurface(px, py)
  if not x or not self.style then return false end
  local L = self:layout(self.style)
  local i = math.floor((y - L.top - 4) / L.rowH) + 1 + self.scroll
  local rows = self:rows()
  if i >= 1 and i <= #rows and not rows[i].header then
    self.index = i
    self:press("a")
  end
  return true
end

function RandomizerSetup:draw()
  local CodeStyle = require("src.ui.online.CodeStyle")
  local style = self.style or CodeStyle.new(self.styleKind)
  self.style = style
  local C = CodeStyle.colors
  local W, H = self.width, self.height
  local L = self:layout(style)
  style:clear(W, H)
  local rows = self:rows()
  local on = RandomOptions.count(self:source(), self.gen)
  style:text(("RANDOMIZER  %d ON"):format(on), L.margin, 2)
  -- keep the cursor in view
  if self.index - self.scroll > L.visible then self.scroll = self.index - L.visible end
  if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
  if self.scroll > 0 and rows[self.scroll] and rows[self.scroll].header and self.index - self.scroll + 1 <= L.visible then
    self.scroll = self.scroll - 1
  end
  local n = math.min(L.visible, #rows - self.scroll)
  local boxH = n * L.rowH + 8
  style:box(0, L.top, W, boxH)
  for k = 1, n do
    local i = k + self.scroll
    local r = rows[i]
    local y = L.top + 4 + (k - 1) * L.rowH
    if r.header then
      style:text("- " .. r.label .. " -", L.margin, y, C.dim)
    else
      local locked = self:locked(r)
      local color = locked and C.dim or C.ink
      if i == self.index then style:text(">", L.margin - 2, y, C.ink) end
      style:text(r.label, L.margin + 6, y, color)
      local v = self:value(r)
      if v ~= "" then style:text(v, W - L.margin - 4 - style:width(v), y, color) end
    end
  end
  if self.scroll > 0 then style:text("^", W - L.margin, L.top + 2, C.ink) end
  if self.scroll + n < #rows then style:text("v", W - L.margin, L.top + boxH - L.rowH, C.ink) end
  local row = rows[self.index]
  local text = (self.notice and self.notice.text) or self:locked(row) or (row and row.help) or ""
  local y = L.top + boxH + 2
  for _, line in ipairs(style:wrap(text, W - 2 * L.margin)) do
    if y + L.lh > H then break end
    style:text(line, L.margin, y, C.ink)
    y = y + L.lh
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return RandomizerSetup
