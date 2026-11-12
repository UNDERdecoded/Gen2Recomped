-- RUN SETUP: the NEW GAME question "is this a Nuzlocke run?" plus Soul Link
-- and the two randomizer options, and the same rows read back from the
-- OPTIONS menus (mode = "view": the randomizer may still be toggled; the
-- Nuzlocke rows are fixed once the run started).
--
-- One screen for every game: it draws through CodeStyle in the loaded
-- game's own font and frame (Red's tiles, Emerald's face, a DS frame), on
-- the game's own surface.
--
--   RunSetup.open(game, {
--     onDone = function(choice) end,  -- {nuzlocke, soulLink, randomWild, randomStarters}
--     onCancel = function() end,      -- B on the first row (optional; nil = B does nothing)
--   })
--   RunSetup.openView(game)           -- OPTIONS -> RUN MODES
--
-- The rows are pure data (RunSetup.rows), so tests drive :press / :move
-- without love.graphics.

local RunModes = require("src.runmodes.RunModes")

local RunSetup = {}
RunSetup.__index = RunSetup
RunSetup.isOpaque = true

-- is the NUZLOCKE rules mod loaded?  It registers itself on RunModes.provider.
function RunSetup.nuzlockeAvailable()
  return RunModes.provider ~= nil
end

local ROWS = {
  { key = "nuzlocke", label = "NUZLOCKE",
    help = "First POKéMON met in each area only. A fainted POKéMON is gone for good. The run ends when the whole party is gone." },
  { key = "soulLink", label = "SOUL LINK",
    help = "Nuzlocke with a friend online: your encounters per area are paired, and when one dies, its partner dies too." },
  { key = "randomWild", label = "RANDOM WILD",
    help = "Wild POKéMON are randomized, the same for this save every time." },
  { key = "randomStarters", label = "RANDOM STARTERS",
    help = "The starter POKéMON are randomized for this save." },
  { key = "randomizer", label = "RANDOMIZER...",
    help = "Moves, types, stats, marts, items, trainers... and FULL." },
  { key = "start", label = "START", help = "Begin the adventure with these settings." },
}
RunSetup.ROWS = ROWS
local ROW_KEYS = { nuzlocke = true, soulLink = true, randomWild = true, randomStarters = true }

function RunSetup.new(game, opts)
  local self = setmetatable({}, RunSetup)
  opts = opts or {}
  self.game, self.opts = game, opts
  self.view = opts.mode == "view"
  self.index = 1
  self.notice = nil
  local rm = self.view and RunModes.get(game) or {}
  self.choice = {
    nuzlocke = rm.nuzlocke == true,
    soulLink = rm.soulLink == true,
    randomWild = rm.randomWild == true,
    randomStarters = rm.randomStarters == true,
  }
  if opts.choice then for k, v in pairs(opts.choice) do self.choice[k] = v end end
  local CodeStyle = require("src.ui.online.CodeStyle")
  self.width, self.height = CodeStyle.surface(opts)
  self.styleKind = opts.style or CodeStyle.defaultKind(game)
  return self
end

function RunSetup.open(game, opts)
  local s = RunSetup.new(game, opts)
  game.stack:push(s)
  return s
end

function RunSetup.openView(game, opts)
  opts = opts or {}
  opts.mode = "view"
  return RunSetup.open(game, opts)
end

function RunSetup:uiSize() return self.width, self.height end

-- why a row cannot be changed right now, or nil
function RunSetup:locked(key)
  if key == "start" then return nil end
  if (key == "nuzlocke" or key == "soulLink") then
    if self.view then return "Chosen at NEW GAME." end
    if not RunSetup.nuzlockeAvailable() then return "Needs the NUZLOCKE mod (MODS menu)." end
    if key == "soulLink" and not self.choice.nuzlocke then return "Turn NUZLOCKE on first." end
  end
  return nil
end

function RunSetup:rows()
  local out = {}
  for _, r in ipairs(ROWS) do
    if not (self.view and r.key == "start") then out[#out + 1] = r end
  end
  if self.view then
    local rm = RunModes.get(self.game)
    if rm.nuzlocke and RunModes.provider and RunModes.provider.openRecord then
      out[#out + 1] = { key = "record", label = rm.soulLink and "RECORD / SOUL LINK" or "NUZLOCKE RECORD",
        help = "Areas, the fallen, and the Soul Link partner." }
    end
    out[#out + 1] = { key = "done", label = "DONE", help = RunModes.describe(self.game) }
  end
  return out
end

function RunSetup:value(key)
  if key == "randomizer" then
    local RandomOptions = require("src.runmodes.RandomOptions")
    local src = self.view and RunModes.get(self.game) or self.choice
    if RandomOptions.isFull(src) then return "FULL" end
    local n = RandomOptions.count(src)
    return n > 0 and (n .. " ON") or "OFF"
  end
  return self.choice[key] and "ON" or "OFF"
end

-- the full randomizer's own screen (src/ui/RandomizerSetup.lua); RANDOM WILD
-- and RANDOM STARTERS are rows there too, so they are read back after
function RunSetup:openRandomizer()
  local RandomizerSetup = require("src.ui.RandomizerSetup")
  local function refresh()
    local src = self.view and RunModes.get(self.game) or self.choice
    self.choice.randomWild = src.randomWild == true
    self.choice.randomStarters = src.randomStarters == true
  end
  local opts = { choice = self.choice, onClose = refresh }
  if self.view then return RandomizerSetup.openView(self.game, opts) end
  return RandomizerSetup.open(self.game, opts)
end

function RunSetup:toggle(key)
  local why = self:locked(key)
  if why then self.notice = { text = why, timer = 2 } return false end
  self.choice[key] = not self.choice[key]
  if key == "nuzlocke" and not self.choice.nuzlocke then self.choice.soulLink = false end
  if self.view then
    RunModes.setRandom(self.game.save, key, self.choice[key])
  end
  return true
end

function RunSetup:close()
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
end

function RunSetup:confirm()
  local c = {}
  for k, v in pairs(self.choice) do c[k] = v end
  if c.soulLink then c.nuzlocke = true end
  self:close()
  if self.opts.onDone then self.opts.onDone(c) end
  return c
end

function RunSetup:press(button)
  local rows = self:rows()
  local row = rows[self.index]
  if button == "up" then
    self.index = (self.index - 2) % #rows + 1
  elseif button == "down" then
    self.index = self.index % #rows + 1
  elseif button == "left" or button == "right" then
    if ROW_KEYS[row.key] then self:toggle(row.key) end
    if row.key == "randomizer" then return self:openRandomizer() end
  elseif button == "a" then
    if row.key == "start" or row.key == "done" then return self:confirm() end
    if row.key == "randomizer" then return self:openRandomizer() end
    if row.key == "record" then return RunModes.provider.openRecord(self.game) end
    self:toggle(row.key)
  elseif button == "b" then
    if self.view then return self:confirm() end
    if self.opts.onCancel then self:close(); self.opts.onCancel() end
  elseif button == "start" then
    if not self.view then return self:confirm() end
  end
end

function RunSetup:update(dt)
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

function RunSetup:onKeyPressed(key)
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

function RunSetup:layout(style)
  local lh = style:lineHeight()
  local rowH = lh + 3
  local top = math.ceil((lh + 6) / 8) * 8
  return { lh = lh, rowH = rowH, top = top, margin = 8 }
end

function RunSetup:touchpressed(_, px, py)
  local CodeStyle = require("src.ui.online.CodeStyle")
  local x, y = CodeStyle.toSurface(px, py)
  if not x or not self.style then return false end
  local L = self:layout(self.style)
  local i = math.floor((y - L.top - 4) / L.rowH) + 1
  local rows = self:rows()
  if i >= 1 and i <= #rows then
    self.index = i
    self:press("a")
  end
  return true
end

function RunSetup:draw()
  local CodeStyle = require("src.ui.online.CodeStyle")
  local style = self.style or CodeStyle.new(self.styleKind)
  self.style = style
  local C = CodeStyle.colors
  local W, H = self.width, self.height
  local L = self:layout(style)
  style:clear(W, H)
  style:text(self.view and "RUN MODES" or "NEW GAME: RUN MODES", L.margin, 2)
  local rows = self:rows()
  local boxH = #rows * L.rowH + 10
  style:box(0, L.top, W, boxH)
  for i, r in ipairs(rows) do
    local y = L.top + 5 + (i - 1) * L.rowH
    local locked = self:locked(r.key)
    local color = locked and C.dim or C.ink
    if i == self.index then style:text(">", L.margin - 2, y, C.ink) end
    style:text(r.label, L.margin + 6, y, color)
    if ROW_KEYS[r.key] or r.key == "randomizer" then
      local v = self:value(r.key)
      style:text(v, W - L.margin - 4 - style:width(v), y, color)
    end
  end
  local row = rows[self.index]
  local text = (self.notice and self.notice.text) or self:locked(row.key) or row.help
  local y = L.top + boxH + 2
  for _, line in ipairs(style:wrap(text, W - 2 * L.margin)) do
    if y + L.lh > H then break end
    style:text(line, L.margin, y, C.ink)
    y = y + L.lh
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return RunSetup
