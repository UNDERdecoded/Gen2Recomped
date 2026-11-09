-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ALTTP ONLINE, on the foundation's ZeldaSession (src/online/zelda): up to
-- four players in one room, each a coloured Link -- 1 green, 2 red, 3 blue,
-- 4 purple, the Four Swords colours the session already assigns.
--
-- What runs today: PRESENCE CO-OP. Every player walks their own Hyrule; each
-- ~30 Hz snapshot carries world, position, facing, walk step and hop height,
-- and every Link standing in the same world is drawn in your game with their
-- colour, smoothed between snapshots. A reliable "hi" event is sent on attach
-- so the others see who arrived.
--
-- The Four Swords adventure itself (the cartridge's own 2-4 player game,
-- Capcom's levels and its Force-Gem rules) is NOT ported yet: its stages,
-- graphics and logic are a separate engine in the ROM (around 0x62F000 on,
-- text at 0x641000). The snapshot/event shapes below are the ones it will use.
-- See docs/zelda/PROGRESS-alttp.md.
--
-- Wire (all small JSON-safe tables):
--   snapshot { v=1, w="lw"|"dw", x, y, z, f, s }
--   event    { t="hi", name } | { t="emote", id }

local O = {}
O.__index = O

O.TINT = {
  [1] = { 0.70, 1.00, 0.70, 1 },   -- green (own colours are the cartridge's)
  [2] = { 1.00, 0.55, 0.55, 1 },   -- red
  [3] = { 0.60, 0.70, 1.00, 1 },   -- blue
  [4] = { 0.85, 0.60, 1.00, 1 },   -- purple
}

function O.new(game)
  return setmetatable({ game = game, peers = {}, session = nil }, O)
end

function O:attached(session)
  self.session = session
  if session and session.sendEvent then
    pcall(session.sendEvent, session, { t = "hi" })
  end
end

function O:detached()
  self.session = nil
  self.peers = {}
end

function O:snapshot()
  local lk = self.game.link
  return { v = 1, w = lk.world, x = lk.x, y = lk.y, z = lk.z, f = lk.facing, s = lk.steps }
end

local function num(v, d) v = tonumber(v) return v and math.floor(v) or d end

-- accept only well-formed snapshots; a peer's numbers are clamped to Hyrule
function O:apply(peer, snap)
  if type(snap) ~= "table" or snap.v ~= 1 then return end
  local p = self.peers[peer] or { id = peer }
  p.w = (snap.w == "dw") and "dw" or "lw"
  p.tx = math.max(0, math.min(4095, num(snap.x, 0)))
  p.ty = math.max(0, math.min(4095, num(snap.y, 0)))
  if not p.x then p.x, p.y = p.tx, p.ty end
  p.z = math.max(0, math.min(32, num(snap.z, 0)))
  local f = num(snap.f, 2)
  p.facing = (f == 0 or f == 2 or f == 4 or f == 6) and f or 2
  p.steps = math.max(0, math.min(8, num(snap.s, 0)))
  p.seen = self.game.frame
  self.peers[peer] = p
end

function O:event(peer, ev)
  if type(ev) ~= "table" then return end
  if ev.t == "hi" then
    local p = self.peers[peer] or { id = peer }
    p.hello = true
    self.peers[peer] = p
  end
end

function O:left(peer) self.peers[peer] = nil end

-- smooth peers toward their latest snapshot (snapshots come at ~30 Hz)
function O:update()
  for _, p in pairs(self.peers) do
    if p.tx then
      local dx, dy = p.tx - p.x, p.ty - p.y
      if math.abs(dx) > 48 or math.abs(dy) > 48 then
        p.x, p.y = p.tx, p.ty
      else
        p.x = p.x + dx * 0.5
        p.y = p.y + dy * 0.5
      end
    end
  end
end

function O:colorOf(peer)
  local s = self.session
  if s and s.players then
    local ok, list = pcall(s.players, s)
    if ok and type(list) == "table" then
      for _, pl in ipairs(list) do
        if pl.id == peer and pl.color then return pl.color end
      end
    end
  end
  return ((tonumber(peer) or 2) - 1) % 4 + 1
end

function O:visiblePeers()
  local out = {}
  for id, p in pairs(self.peers) do
    if p.x and p.w == self.game.link.world then out[#out + 1] = { id = id, p = p } end
  end
  table.sort(out, function(a, b) return a.p.y < b.p.y end)
  return out
end

function O:drawPeers()
  for _, e in ipairs(self:visiblePeers()) do
    local p = e.p
    self.game:drawLink({ x = math.floor(p.x + 0.5), y = math.floor(p.y + 0.5), z = p.z,
                         facing = p.facing, steps = p.steps }, O.TINT[self:colorOf(e.id)])
  end
end

return O
