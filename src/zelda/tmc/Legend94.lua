-- Round 94: the new game's legend panels -- the aux cutscene behind
-- sub_080536D4 (src/cutscene.c, CutsceneMain_Update with field_0x3 0), the
-- "Legend of the Picori" a fresh file opens with.
--
-- sub_080536D4's steps (gUnk_080FCCFC, by gMenu.overlayType):
--   0          sub_08053758  the panel screen (as the Sanctuary's: DISPCNT
--                            $2640, BLDCNT $2244, WIN0, BGM_STORY), faded out
--   1, 3 .. 9  sub_08053800  panel i (gUnk_080FCCB4[i], i = 0 .. 4): palette
--                            group $8A + i, gfx group $3A + i, TEXT_PICORI
--                            1 + i, the window, fade in at the panel's speed
--   2 .. 8     sub_08053894  the hold, the alpha steps, fade out (8)
--   10         sub_08053904  the same hold for the fifth panel, fade out at
--                            speed 1 (the long fade into the game)
--   11         sub_08053974  (fade done) the intro room
-- The panel code and the panel table are the Sanctuary's (Story90.lua:
-- gUnk_080FCCB4, the Fonts, read from the player's ROM at import -- the same
-- manifest range; nothing new is imported).  The Sanctuary shows all six
-- panels and TEXT_PICORI 7; the intro shows the first five.
--
-- When: a fresh file (Game.newSave: progress 1, no items, in Link's room,
-- under a second of play) -- before the first room frame.
-- SIMPLIFIED: sub_08053974 / sub_080539BC's scenes (Zelda on her way through
--   town to the Smith's house, gUnk_080FCBC4 / gUnk_080FCC14) are not played:
--   the port's new file starts in Link's room (FinalizeSave's place); after
--   the panels the room fades in (speed 4, as Story90.finish) with its music.
local bit = require("bit")
local bor = bit.bor
local St90 = require("src.zelda.tmc.Story90")

local M = {}
M.PANELS = 5
local FADE_IN_OUT, FADE_INSTANT = 1, 4

local L = setmetatable({}, { __index = St90.Story })
L.__index = L
M.Legend = L

function M.new(field, opts)
  local s = St90.new(field, opts)
  return setmetatable(s, L)
end

-- sub_08053904: sub_08053894 with the last fade out at speed 1
function L:holdLast()
  if self.fade.active then return end
  self.timer = self.timer - 1
  if self.wait ~= 0 then
    self.wait = self.wait - 1
  elseif self.frame % 2 == 0 and self.step < 0x10 then
    self.step = self.step + 1
    self.alpha = bor(bit.lshift(self.step, 8), 0x10 - bit.rshift(self.step, 1))
  end
  if self.timer <= 0 then
    self.overlay = self.overlay + 1
    self:setFade(bor(FADE_IN_OUT, FADE_INSTANT), 1)
  end
end

function L:update(input)
  self.frame = self.frame + 1
  local o = self.overlay
  local last = 1 + 2 * M.PANELS -- 11: sub_08053974
  if o == 0 then self:setup()
  elseif o < last then
    if o % 2 == 1 then self:loadPanel()
    elseif o == last - 1 then self:holdLast()
    else self:holdPanel() end
  elseif o == last then
    if not self.fade.active then self.overlay = o + 1; return "done" end
  end
  self:fadeStep()
  return nil
end

-- a fresh file in its first second (Game.newSave)
function M.fresh(f)
  local s = f and f.save
  if not s or s.legend94 then return false end
  if (s.progress or 1) ~= 1 or (s.playTime or 0) > 1 then return false end
  if s.items and next(s.items) ~= nil then return false end
  local r = f.room
  return r ~= nil and r.area == 0x22 and r.room == 0x15
end

function M.start(f)
  f.save.legend94 = true
  f.story90 = M.new(f)
  f.legend94 = true
  f.fadeLevel, f.fadeTarget, f.iris = 0, 0, nil
end

-- R27B frame hook (listed after Story90, which runs f.story90 from the next frame on)
function M.frame(f, input)
  if f.legend94 and not f.story90 then
    f.legend94 = nil
    if f.bgm then f:bgm("area") end -- the room's music back after BGM_STORY
  end
  if not f.story90 and M.fresh(f) then M.start(f) return true end
  return false
end

return M
