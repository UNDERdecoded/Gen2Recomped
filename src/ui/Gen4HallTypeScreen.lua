-- THE BATTLE HALL'S TYPE GRID (src/applications/frontier/battle_hall/main.c,
-- OpenBattleHallApp), in bank 549's words (TEXT_BANK_BATTLE_HALL_SCENE).
--
-- Four columns by five rows (GRID_WIDTH x GRID_HEIGHT, 64 x 36 px cells),
-- laid out by sBattleHallAppGridOrder: the seventeen types, NORMAL first, each
-- with its rank to come (the stored rank + 1, never past 10); two cells for
-- your Pokemon (on the cartridge they open its summary, which this screen
-- does not); and the ??? cell, the Hall Matron's.
--
-- A on a type asks "Will you battle the {type}-type, Rank {n} Pokemon?" (#24).
-- A type already at rank 10 cannot be chosen, nor can ??? until Argenta is
-- on her way: when the battle you confirm is the 50th or 170th of a singles
-- streak, the attendant breaks in (#32), every other cell greys out, and the
-- only choice left is ??? -- "Will you battle against the Hall Matron?" (#31).
-- The type you had picked is still the one handed back.
--
-- opts = { hall, cursor, onDone(cell) }

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local T = require("src.import.Gen4BattleHallTables")
local Gen4Text = require("src.import.Gen4Text")

local S = {}
S.__index = S
S.isOpaque = true
-- the scene's words and the type names: Platinum's banks 549 / 624,
-- HeartGold / SoulSilver's 441 / 735 -- read by family
S.BANKS = { platinum = { BANK = 549, TYPE_NAMES = 624 }, hgss = { BANK = 441, TYPE_NAMES = 735 } }
setmetatable(S, { __index = function(_, k)
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  return S.BANKS[(okB and Bands.family == "hgss") and "hgss" or "platinum"][k]
end })
S.W, S.H, S.COL, S.ROW = 4, 5, 64, 36
S.MSG_CONFIRM, S.MSG_MATRON, S.MSG_APPROACHING = 24, 31, 32
S.MYSTERY_CELL = 19
S.NO_SAVED = 0x75

function S:uiSize() return 256, 192 end
function S:wantsFillScale() return true end

function S.new(game, opts)
  local self = setmetatable({ game = game, data = game.data, hall = opts.hall, onDone = opts.onDone,
    cursor = opts.cursor or 0, saved = S.NO_SAVED, matron = false }, S)
  if T.GRID[self.cursor] == 0xFE then self.cursor = 0 end   -- ReInitApp
  return self
end

-- a bank line through the shared resolve: markup expanded, trailing wait off
local function text(game, n) return Gen4Text.resolve(game.data, S.BANK, n, game) end
-- a line with placeholders: buffer the values FIRST (slot 0 up), then resolve
-- expands its {STRVAR_1} tokens from them, as StringTemplate_Format does
local function fill(game, n, fallback, ...)
  Gen4Text.buffer(game, ...)
  local s = text(game, n)
  if s then return s end
  local Commands = require("src.script.Commands")
  local ok, plain = pcall(Commands.gen4Markup, fallback, game)
  return ok and plain or fallback
end
function S:typeName(t)
  return Gen4Text.resolve(self.data, S.TYPE_NAMES, t, self.game)
    or (t == 9 and "???" or tostring(t))
end
-- GetCursorPos: cells past 16 read the ??? rank slot
function S:rankAt(cell)
  local h = self.hall
  return (h and h.ranks[math.min(cell, 17)]) or 0
end

-- BattleHall_IsMultiPlayerChallenge aside, NextOpponentIsHallMatron:
-- the app's streak is the challenge's + 1
function S:nextIsMatron()
  local h = self.hall
  if not h or h.challenge ~= 0 then return false end
  local next = (h.streak or 0) + 1
  return next == 50 or next == 170
end

function S:selectable(cell)
  local t = T.GRID[cell]
  if t == 0xFE then return true end
  if self.matron then return cell == S.MYSTERY_CELL end
  return t ~= 9 and self:rankAt(cell) < 10
end

function S:finish(cell)
  if self.closed then return end
  self.closed = true
  self.game.stack:pop()
  if self.onDone then self.onDone(cell) end
end

function S:ask()
  local game = self.game
  local cell = self.cursor
  local msg
  if self.matron then
    msg = text(game, S.MSG_MATRON) or "Will you battle against the Hall Matron?"
  else
    local rank = math.min(self:rankAt(cell) + 1, 10)
    msg = fill(game, S.MSG_CONFIRM, "Battle the {STRVAR_1 15 0 0}-type?",
               self:typeName(T.GRID[cell]), tostring(rank))
  end
  self.asking = true
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, msg, nil, { choice = function(yes)
    if not yes then self.asking = false return end
    if self:nextIsMatron() and not self.matron then
      -- SELECT_STATE_PRINT_MATRON_MSG: the attendant, then only ??? is left
      self.saved = cell
      game.stack:push(TextBox.new(game, text(game, S.MSG_APPROACHING) or "Excuse me!", function()
        self.matron = true
        self.cursor = S.MYSTERY_CELL
        self.asking = false
      end))
      return
    end
    self.asking = false
    Sound.play(self.data, "SEQ_SE_DP_UG_020")
    self:finish(self.saved ~= S.NO_SAVED and self.saved or cell)
  end }))
end

function S:update()
  if self.asking or self.closed then return end
  local input = self.game.input
  if not input then return end
  local c = self.cursor
  local col, row = c % S.W, math.floor(c / S.W)
  if input:wasPressed("left") then col = (col - 1) % S.W
  elseif input:wasPressed("right") then col = (col + 1) % S.W
  elseif input:wasPressed("up") then row = (row - 1) % S.H
  elseif input:wasPressed("down") then row = (row + 1) % S.H
  elseif input:wasPressed("a") then
    local t = T.GRID[c]
    if t == 0xFE then
      Sound.play(self.data, "SEQ_SE_DP_BOX03")       -- the summary is not ported
    elseif not self:selectable(c) then
      Sound.play(self.data, "SEQ_SE_DP_BOX03")
    else
      Sound.play(self.data, "SEQ_SE_DP_DECIDE")
      self:ask()
    end
    return
  else
    return
  end
  self.cursor = row * S.W + col
  Sound.play(self.data, "SEQ_SE_DP_SELECT")
end

function S:monImage()
  if self.img ~= nil then return self.img or nil end
  self.img = false
  local h = self.hall
  local mon = h and h.save.party and h.save.party[(h.slots[0] or 0) + 1]
  if mon then
    pcall(function()
      local path = require("src.pokemon.Sprites").path(self.data, mon.species, "front", mon)
      self.img = path and require("src.render.Assets").image(path) or false
    end)
  end
  return self.img or nil
end

function S:draw()
  local g = love.graphics
  g.setColor(0.93, 0.89, 0.78, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  for cell = 0, S.W * S.H - 1 do
    local t = T.GRID[cell]
    local x, y = (cell % S.W) * S.COL, math.floor(cell / S.W) * S.ROW + 6
    if t ~= 0xFE then
      local on = self:selectable(cell)
      if cell == S.MYSTERY_CELL and not self.matron then on = false end
      if on then g.setColor(0.98, 0.97, 0.92, 1) else g.setColor(0.62, 0.6, 0.56, 1) end
      g.rectangle("fill", x + 1, y + 1, S.COL - 2, S.ROW - 2)
      g.setColor(0.25, 0.25, 0.25, 1)
      g.rectangle("line", x + 1.5, y + 1.5, S.COL - 3, S.ROW - 3)
      if t ~= 9 then
        Font.draw(tostring(math.min(self:rankAt(cell) + 1, 10)), x + 18, y + 4)
        Font.draw(self:typeName(t), x + 1, y + 16)
      else
        -- slot 9's own name: "???" on retail, FAIRY on Renegade (bank 624)
        Font.draw(self:typeName(9), x + 18, y + 12)
      end
    end
  end
  -- your Pokemon, over the two summary cells (17 and 18)
  local h = self.hall
  local mon = h and h.save.party and h.save.party[(h.slots[0] or 0) + 1]
  local x, y = 1 * S.COL, 4 * S.ROW + 6
  g.setColor(0.98, 0.97, 0.92, 1)
  g.rectangle("fill", x + 1, y + 1, S.COL * 2 - 2, S.ROW - 2)
  g.setColor(1, 1, 1, 1)
  local img = self:monImage()
  if img then g.draw(img, x + 2, y - 30, 0, 0.5, 0.5) end
  g.setColor(0.25, 0.25, 0.25, 1)
  if mon then
    local def = self.data.pokemon and self.data.pokemon[mon.species]
    Font.draw(mon.nickname or (def and def.name) or "?", x + 44, y + 12)
  end
  -- the cursor
  local c = self.cursor
  local cx, cy = (c % S.W) * S.COL, math.floor(c / S.W) * S.ROW + 6
  g.setColor(0.9, 0.2, 0.2, 1)
  g.setLineWidth(2)
  g.rectangle("line", cx + 1, cy + 1, S.COL - 2, S.ROW - 2)
  g.setLineWidth(1)
  g.setColor(1, 1, 1, 1)
end

return S
