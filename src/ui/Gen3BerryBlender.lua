-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BERRY BLENDER, which is the only machine in Hoenn that makes a
-- POKéBLOCK.
--
-- WHAT IT REALLY IS: two to four people each throw one berry in, an arrow
-- spins, and each player presses A as their marker passes.  A hit speeds the
-- arrow up and a miss slows it down; the PEAK RPM is the only thing the
-- machine remembers, and it becomes a percentage multiplier on the block:
--
--     multiplier = 100 + maxRPM / 333          (maxRPM in hundredths)
--
-- so a peak of 300 RPM is x1.90 on every flavour.  Everything else about the
-- block -- the ring subtraction that turns four identical berries into
-- nothing, the penalty for every flavour that went negative, the feel off the
-- smoothness sum -- is CalculatePokeblock's, and lives in
-- src/inventory/Pokeblocks.lua.
--
-- WHAT IS SIMPLIFIED HERE, said plainly: the cartridge's arrow has its own
-- acceleration curve, a "BEST" zone and a set of NPC personalities that miss
-- on purpose.  This runs the same loop with one speed-up per hit and one
-- slow-down per miss, and the NPCs hit at a fixed rate.  The BLOCK it
-- produces is the cartridge's arithmetic on the cartridge's berries; only the
-- feel of the minigame is the port's.

local Font = require("src.render.Font")
local Pokeblocks = require("src.inventory.Pokeblocks")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local Gen3BerryBlender = {}
Gen3BerryBlender.__index = Gen3BerryBlender
Gen3BerryBlender.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- hundredths of an RPM, which is how the machine stores it
Gen3BerryBlender.START_RPM = 6000
Gen3BerryBlender.HIT = 1500
Gen3BerryBlender.MISS = 1200
Gen3BerryBlender.MIN_RPM = 3000
Gen3BerryBlender.MAX_RPM = 40000
Gen3BerryBlender.SPINS = 12
-- how close to a marker counts, in units of the 256-step circle
Gen3BerryBlender.WINDOW = 12

function Gen3BerryBlender:uiSize() return GBA_W, GBA_H end
function Gen3BerryBlender:wantsFillScale() return true end

function Gen3BerryBlender.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3BerryBlender)
  self.game = game
  self.onDone = opts.onDone
  self.onResult = opts.onResult
  self.rng = opts.rng or love.math.random
  -- every participant's berry, the player's first
  self.berries = opts.berries or {}
  self.players = #self.berries
  self.angle = 0
  self.rpm = Gen3BerryBlender.START_RPM
  self.maxRPM = self.rpm
  self.spins = 0
  self.hits, self.misses = 0, 0
  self.phase = (self.players >= 2) and "spin" or "done"
  self.block = nil
  if self.phase == "done" then self:finishRun() end
  return self
end

-- Where each participant's marker sits on the 256-step circle.
function Gen3BerryBlender:markerAt(i)
  return math.floor((i - 1) * 256 / math.max(1, self.players))
end

local function near(a, b, window)
  local d = math.abs(((a - b + 128) % 256) - 128)
  return d <= window
end

function Gen3BerryBlender:press()
  if near(self.angle, self:markerAt(1), Gen3BerryBlender.WINDOW) then
    self.hits = self.hits + 1
    self.rpm = math.min(Gen3BerryBlender.MAX_RPM,
                        self.rpm + Gen3BerryBlender.HIT)
    Sound.play(self.game.data, "Press_AB")
  else
    self.misses = self.misses + 1
    self.rpm = math.max(Gen3BerryBlender.MIN_RPM,
                        self.rpm - Gen3BerryBlender.MISS)
    Sound.play(self.game.data, "Wrong")
  end
  self.maxRPM = math.max(self.maxRPM, self.rpm)
end

function Gen3BerryBlender:update()
  local input = self.game.input
  if self.phase == "spin" then
    local before = self.angle
    -- one revolution is 256 steps; the rpm is in hundredths of a revolution
    -- per minute, and the game runs at sixty frames a second
    local step = math.max(1, math.floor(self.rpm * 256 / (100 * 60 * 60)))
    self.angle = (self.angle + step) % 256
    if self.angle < before then
      self.spins = self.spins + 1
      -- the NPCs take their turn once a revolution: they hit more often than
      -- they miss, which is what keeps the arrow up when the player is bad
      for _ = 2, self.players do
        if self.rng(1, 4) > 1 then
          self.rpm = math.min(Gen3BerryBlender.MAX_RPM,
                              self.rpm + Gen3BerryBlender.HIT)
        else
          self.rpm = math.max(Gen3BerryBlender.MIN_RPM,
                              self.rpm - Gen3BerryBlender.MISS)
        end
      end
      self.maxRPM = math.max(self.maxRPM, self.rpm)
      if self.spins >= Gen3BerryBlender.SPINS then return self:finishRun() end
    end
    if input and input:wasPressed("a") then self:press() end
    return
  end
  if input and (input:wasPressed("a") or input:wasPressed("b")) then
    return self:close()
  end
end

function Gen3BerryBlender:finishRun()
  self.phase = "done"
  self.block = Pokeblocks.blend(self.game.data, self.berries, self.maxRPM,
                                self.rng)
  if self.block then
    self.slot = Pokeblocks.add(self.game.save, self.block, self.game.data)
    if not self.slot then self.full = true end
  end
end

function Gen3BerryBlender:close()
  if self.game.stack then self.game.stack:pop() end
  if self.onResult then self.onResult(self.block, self.slot) end
  if self.onDone then self.onDone() end
end

function Gen3BerryBlender:keypressed(key)
  if key == "a" and self.phase == "spin" then return self:press() end
  if (key == "a" or key == "b") and self.phase == "done" then
    return self:close()
  end
end

function Gen3BerryBlender:draw()
  love.graphics.setColor(0.16, 0.26, 0.20, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)

  local cx, cy, r = 120, 74, 46
  love.graphics.setColor(0.32, 0.42, 0.34, 1)
  love.graphics.circle("fill", cx, cy, r)
  love.graphics.setColor(0.75, 0.82, 0.70, 1)
  love.graphics.circle("line", cx, cy, r)

  for i = 1, self.players do
    local a = self:markerAt(i) * 2 * math.pi / 256
    local mx, my = cx + math.sin(a) * r, cy - math.cos(a) * r
    love.graphics.setColor(i == 1 and 0.98 or 0.55, i == 1 and 0.86 or 0.60,
                           i == 1 and 0.30 or 0.62, 1)
    love.graphics.circle("fill", mx, my, 5)
  end

  local a = self.angle * 2 * math.pi / 256
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.line(cx, cy, cx + math.sin(a) * (r - 6),
                     cy - math.cos(a) * (r - 6))

  Font.drawBox(0, 0, 30, 3)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("RPM %d", math.floor(self.rpm / 100)), 8, 6)
  local best = Strings("BEST %d", math.floor(self.maxRPM / 100))
  Font.draw(best, GBA_W - 8 - Font.width(best), 6)
  love.graphics.setColor(1, 1, 1, 1)

  if self.phase == "done" then
    Font.drawBox(0, 14, 30, 6)
    love.graphics.setColor(0, 0, 0, 1)
    if self.full then
      Font.draw(Strings("The CASE is full!"), 8, 122)
    elseif self.block then
      Font.draw(Strings("Made a %s!", Pokeblocks.name(self.game.data, self.block)),
                8, 122)
      local parts = {}
      for _, key in ipairs(Pokeblocks.FLAVOURS) do
        parts[#parts + 1] = ("%s %d"):format(key:sub(1, 2):upper(),
                                             math.floor(tonumber(self.block[key]) or 0))
      end
      Font.draw(table.concat(parts, "  "), 8, 136)
      Font.draw(Strings("FEEL %d", Pokeblocks.shownFeel(self.block)), 8, 150)
    else
      Font.draw(Strings("Nothing came out."), 8, 122)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Gen3BerryBlender
