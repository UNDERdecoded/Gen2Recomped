-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CONTEST ITSELF.
--
-- Five appeal rounds, four contestants, and a crowd meter -- and the whole of
-- the scoring lives in src/contest/ContestRun.lua, which is the cartridge's
-- arithmetic.  This file is the part the player touches: pick one of the four
-- moves, watch the four appeals land, and see the standings move.
--
-- WHAT IS ON SCREEN, and why each piece is there:
--
--   the four contestants down the left, with their running appeal, so the
--   effect of a combo or a jam is visible on the turn it happens;
--   the crowd meter across the top, because filling it is worth six hearts
--   and nothing else in the system is worth six hearts;
--   the four moves at the bottom, each with its category, its hearts, and
--   whether it will COMBO off what this Pokemon did last turn -- which the
--   cartridge shows too, and which is unguessable without it.
--
-- HEARTS ARE TENTHS.  Every appeal and jam number in the data is in tenths of
-- a heart, so a "40" is four hearts; the screen divides, the engine does not.

local ContestRun = require("src.contest.ContestRun")
local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3Contest = {}
Gen3Contest.__index = Gen3Contest
Gen3Contest.isOpaque = true

local GBA_W, GBA_H = 240, 160

function Gen3Contest:uiSize() return GBA_W, GBA_H end
function Gen3Contest:wantsFillScale() return true end

function Gen3Contest.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3Contest)
  self.game = game
  -- TWO CALLBACKS, and they are not the same one.  `onResult` is the script's
  -- -- it wants the standings -- and `onDone` is the blocking-push wrapper's,
  -- which only resumes the runner.  pushBlocking overwrites `onDone`, so a
  -- screen that reported through it would report nothing.
  self.onResult = opts.onResult
  self.onDone = opts.onDone
  self.run = ContestRun.new(game.data, {
    mon = opts.mon,
    category = opts.category or "cool",
    rank = opts.rank or 0,
    postGame = opts.postGame,
    trainerName = (game.save.player or {}).name,
    rng = opts.rng,
  })
  self.phase = "pick"       -- pick -> show -> pick ... -> results
  self.cursor = 1
  self.message = nil
  self.hold = 0
  return self
end

function Gen3Contest:playerMon()
  return self.run.contestants[self.run.playerIndex].mon
end

function Gen3Contest:moves()
  local mon = self:playerMon()
  local out = {}
  for _, slot in ipairs((mon and mon.moves) or {}) do
    out[#out + 1] = (type(slot) == "table") and slot.id or slot
  end
  return out
end

-- The AI's pick.  The cartridge runs a whole judgement per opponent; this
-- takes the move with the best appeal it has not just used, which reproduces
-- the two behaviours that matter -- opponents lead with their strongest and
-- do not sit on a repeat penalty.
function Gen3Contest:aiMove(who)
  local c = self.run.contestants[who]
  local best, bestScore
  for _, id in ipairs(c.mon.moves or {}) do
    local def = (self.game.data.moves or {})[id]
    local score = math.floor(tonumber(def and def.contestAppeal) or 0)
    if id == c.currMove then score = score - 20 end
    if ContestRun.combo(self.game.data, c.currMove, id) then score = score + 40 end
    if not bestScore or score > bestScore then best, bestScore = id, score end
  end
  return best
end

function Gen3Contest:submit(moveId)
  local moves = {}
  moves[self.run.playerIndex] = moveId
  for i = 1, #self.run.contestants do
    if i ~= self.run.playerIndex then moves[i] = self:aiMove(i) end
  end
  local done = ContestRun.round(self.run, moves)
  self.phase = done and "results" or "show"
  self.hold = 60
  if done then
    ContestRun.finish(self.run)
    self.won = ContestRun.playerWon(self.run)
    if self.won then ContestRun.award(self.run) end
    self.artist = ContestRun.artistReady(self.run)
  end
end

function Gen3Contest:update()
  local input = self.game.input
  if not input then return end
  if self.hold > 0 then
    self.hold = self.hold - 1
    return
  end

  if self.phase == "pick" then
    local moves = self:moves()
    if #moves == 0 then return self:finish() end
    if input:wasPressed("down") or input:wasPressed("right") then
      self.cursor = self.cursor % #moves + 1
      Sound.play(self.game.data, "Press_AB")
    elseif input:wasPressed("up") or input:wasPressed("left") then
      self.cursor = (self.cursor - 2) % #moves + 1
      Sound.play(self.game.data, "Press_AB")
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      self:submit(moves[self.cursor])
    end
    return
  end

  if self.phase == "show" then
    if input:wasPressed("a") or input:wasPressed("b") then
      Sound.play(self.game.data, "Press_AB")
      self.phase = "pick"
    end
    return
  end

  if self.phase == "results" then
    if input:wasPressed("a") or input:wasPressed("b") then
      Sound.play(self.game.data, "Press_AB")
      return self:finish()
    end
  end
end

function Gen3Contest:finish()
  if self.game.stack then self.game.stack:pop() end
  if self.onResult then
    self.onResult({
      won = self.won and true or false,
      place = self.run.contestants[self.run.playerIndex].place,
      total = self.run.contestants[self.run.playerIndex].total,
      artist = self.artist and true or false,
      run = self.run,
    })
  end
  if self.onDone then self.onDone() end
end

function Gen3Contest:keypressed(key)
  if key == "a" or key == "b" then return self:update() end
end

-- ---------------------------------------------------------------------------
-- DRAWING
-- ---------------------------------------------------------------------------
local function hearts(tenths)
  return string.format("%.1f", (tonumber(tenths) or 0) / 10)
end

local function nameOf(game, c)
  local mon = c.mon
  local def = (game.data.pokemon or {})[mon and mon.species]
  return (mon and mon.nickname) or (def and def.name) or "?"
end

function Gen3Contest:draw()
  local game = self.game
  love.graphics.setColor(0.19, 0.13, 0.28, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)

  -- the banner: which contest, which round
  Font.drawBox(0, 0, 30, 3)
  love.graphics.setColor(0, 0, 0, 1)
  local r = ContestRun.record(game.data)
  local rankName = (r and r.ranks and r.ranks[self.run.rank + 1]) or ""
  Font.draw(Strings("%s %s", tostring(self.run.category):upper(), rankName), 6, 6)
  local round = Strings("ROUND %d/%d", math.max(1, self.run.round),
                        ContestRun.ROUNDS)
  Font.draw(round, GBA_W - 8 - Font.width(round), 6)
  love.graphics.setColor(1, 1, 1, 1)

  -- THE CROWD METER.  Five segments, and the fifth is the one that turns a
  -- one-heart bonus into a six-heart one.
  local S = (r and r.scoring) or {}
  local max = (S.applauseMax or 4) + 1
  for i = 0, max - 1 do
    local on = i < self.run.applause
    love.graphics.setColor(on and 0.98 or 0.30, on and 0.42 or 0.30,
                           on and 0.30 or 0.34, 1)
    love.graphics.rectangle("fill", 90 + i * 12, 26, 10, 5)
  end
  love.graphics.setColor(1, 1, 1, 1)

  -- the four contestants
  Font.drawBox(0, 4, 30, 8)
  love.graphics.setColor(0, 0, 0, 1)
  for i, c in ipairs(self.run.contestants) do
    local y = 40 + (i - 1) * 14
    local mark = c.player and ">" or " "
    Font.draw(mark .. nameOf(game, c), 8, y)
    local score = hearts(c.appealTotal)
    Font.draw(score, 150 - Font.width(score), y)
    local cond = tostring(c.condition)
    Font.draw(cond, 190 - Font.width(cond), y)
    if c.place then
      Font.draw(tostring(c.place), 208, y)
    end
    if (c.jammed or 0) > 0 then
      Font.draw(Strings("-%s", hearts(c.jammed)), 214, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)

  if self.phase == "results" then
    Font.drawBox(0, 12, 30, 8)
    love.graphics.setColor(0, 0, 0, 1)
    local me = self.run.contestants[self.run.playerIndex]
    Font.draw(Strings("%s placed %d", nameOf(game, me), me.place or 4), 8, 106)
    Font.draw(Strings("APPEAL %s x2 + CONDITION %d = %d",
                      hearts(me.appealTotal), me.condition, me.total), 8, 120)
    if self.won then
      Font.draw(Strings("Won the %s RIBBON!", tostring(self.run.category):upper()),
                8, 134)
    end
    if self.artist then
      Font.draw(Strings("The ARTIST wants to paint it!"), 8, 148)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- the four moves
  Font.drawBox(0, 12, 30, 8)
  love.graphics.setColor(0, 0, 0, 1)
  local me = self.run.contestants[self.run.playerIndex]
  for i, id in ipairs(self:moves()) do
    local def = (game.data.moves or {})[id]
    local y = 104 + (i - 1) * 14
    Font.draw(tostring((def and def.name) or id), 16, y)
    Font.draw(tostring(def and def.contestCategory or ""), 120, y)
    local a = hearts(def and def.contestAppeal)
    Font.draw(a, 190 - Font.width(a), y)
    -- WILL IT COMBO?  Only if the judge is still watching and this move
    -- follows what this Pokemon just did -- which is two conditions, and the
    -- cartridge shows the answer rather than making you remember them.
    if me.judgesAttention
       and ContestRun.combo(game.data, me.currMove, id) then
      Font.draw(Strings("COMBO"), 196, y)
    end
    if i == self.cursor and self.phase == "pick" then
      Font.drawCode(Theme.cursor, 4, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3Contest
