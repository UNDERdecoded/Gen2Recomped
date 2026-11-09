-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A PLACEHOLDER ZELDA "GAME" for testing the runtime and the online layer
-- without any ROM: a test pattern (colour bars, a 8x8 grid, the button state)
-- and a square the D-pad moves. Online, every peer's square is drawn in that
-- peer's colour, A sends a reliable "ping" event, and snapshots carry the
-- square's position -- so the two-process harness can see both halves.
--
-- Not a game module on disk (it has no extract): ZeldaRegistry.register(id,
-- ZeldaPlaceholder) or POKEPORT_ZELDA_PLACEHOLDER=1 puts it behind Play.

local P = {}

P.id = "placeholder"
P.cacheVersion = 1
function P.detect() return false end
function P.extract(_, cache, progress)
  progress(0.5, "Placeholder")
  cache:write("data/generated/placeholder.lua", "return { ok = true }")
  progress(1, "Placeholder")
end
function P.isReady() return true end

local Game = {}
Game.__index = Game

local COLORS = {
  { 0.15, 0.55, 0.20 }, { 0.20, 0.35, 0.85 }, { 0.85, 0.25, 0.25 }, { 0.75, 0.30, 0.80 },
}

function P.newGame(opts)
  local self = setmetatable({}, Game)
  self.opts = opts or {}
  self.input = self.opts.input
  local save = self.opts.save or {}
  self.x, self.y = tonumber(save.x) or 112, tonumber(save.y) or 72
  self.frames = 0
  self.playTime = tonumber(save.playTime) or 0
  self.peers = {}       -- peerId -> { x, y, color }
  self.pings = {}       -- recent reliable events, newest last
  self.saves = 0
  return self
end

function Game:update(dt)
  self.frames = self.frames + 1
  self.playTime = self.playTime + dt
  local I = self.input
  if I then
    if I.isDown("left") then self.x = self.x - 1 end
    if I.isDown("right") then self.x = self.x + 1 end
    if I.isDown("up") then self.y = self.y - 1 end
    if I.isDown("down") then self.y = self.y + 1 end
    self.x = math.max(0, math.min(232, self.x))
    self.y = math.max(0, math.min(152, self.y))
    if I.wasPressed("a") then
      local s = self.opts.host and self.opts.host:session()
      if s then s:sendEvent({ kind = "ping", frame = self.frames }) end
      self.pings[#self.pings + 1] = "you: ping"
    end
    if I.wasPressed("select") and self.opts.host then self.opts.host:requestSave() end
  end
  while #self.pings > 4 do table.remove(self.pings, 1) end
end

function Game:draw()
  local g = love.graphics
  g.clear(0, 0, 0)
  -- colour bars
  local bars = { {1,1,1}, {1,1,0}, {0,1,1}, {0,1,0}, {1,0,1}, {1,0,0}, {0,0,1}, {0,0,0} }
  for i, c in ipairs(bars) do
    g.setColor(c[1], c[2], c[3])
    g.rectangle("fill", (i - 1) * 30, 0, 30, 40)
  end
  -- 8x8 tile grid
  g.setColor(0.25, 0.25, 0.30)
  for x = 0, 240, 8 do g.line(x + 0.5, 40, x + 0.5, 160) end
  for y = 40, 160, 8 do g.line(0, y + 0.5, 240, y + 0.5) end
  -- border: proves the canvas edges reach the window
  g.setColor(1, 0.4, 0)
  g.rectangle("line", 0.5, 0.5, 239, 159)
  -- peers, then us
  for _, p in pairs(self.peers) do
    local c = COLORS[p.color or 2] or COLORS[2]
    g.setColor(c[1], c[2], c[3])
    g.rectangle("fill", p.x, p.y, 8, 8)
  end
  local me = COLORS[(self.opts.online and self.opts.online.colorIndex) or 1] or COLORS[1]
  g.setColor(me[1], me[2], me[3])
  g.rectangle("fill", self.x, self.y, 8, 8)
  -- button state
  g.setColor(1, 1, 1)
  local held = {}
  for _, b in ipairs({ "a", "b", "l", "r", "start", "select", "up", "down", "left", "right" }) do
    if self.input and self.input.isDown(b) then held[#held + 1] = b end
  end
  g.print("PLACEHOLDER " .. self.frames, 4, 42)
  g.print(table.concat(held, " "), 4, 54)
  for i, line in ipairs(self.pings) do g.print(line, 4, 160 - 12 * (5 - i)) end
end

function Game:save()
  self.saves = self.saves + 1
  return { x = self.x, y = self.y, playTime = self.playTime, name = "TEST",
           summary = { line = ("placeholder (%d,%d)"):format(self.x, self.y) } }
end

-- online
function Game:netSnapshot() return { x = self.x, y = self.y } end
function Game:netApply(peerId, snap)
  if type(snap) ~= "table" then return end
  local p = self.peers[peerId] or {}
  p.x, p.y = tonumber(snap.x) or 0, tonumber(snap.y) or 0
  p.color = (peerId % 4) + 1
  self.peers[peerId] = p
end
function Game:netEvent(peerId, ev)
  if type(ev) == "table" and ev.kind == "ping" then
    self.pings[#self.pings + 1] = ("p%d: ping"):format(peerId)
  end
end
function Game:netPeerLeft(peerId) self.peers[peerId] = nil end

P.Game = Game
return P
