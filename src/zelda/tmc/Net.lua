-- Minish Cap online: friends as coloured Links in your Hyrule, emotes, and
-- Kinstone fusion with them (Kinstone.lua holds the fusion rules).
--
-- The cartridge has no link play, so this is built to fit it.  It rides the
-- foundation's ZeldaSession (src/online/zelda/ZeldaSession.lua; the runtime
-- calls game:netSnapshot / netApply / netEvent).  What goes over the wire:
--
--   snapshot (unreliable, ~30 Hz)  {a=area, r=room, x, y, s=facing,
--                                   an=animation id, k=minish, n=name}
--   event (reliable)               {t="emote", e=kind}
--                                  {t="fuse_offer", piece, fused={ids}}
--                                  {t="fuse_result", ok, id, piece, why}
--                                  {t="fuse_busy"}
--
-- Friends' Links take the Four Swords colours by join order (green, red,
-- blue, purple): Link's own palette with the tunic hues turned.

local Anim = require("src.zelda.tmc.Anim")

local Net = {}
Net.__index = Net

Net.COLORS = { "green", "red", "blue", "purple" }
local HUE = { green = 0, red = -0.36, blue = 0.27, purple = 0.45 }

function Net.new(game, session)
  local self = setmetatable({ game = game, session = session, ghosts = {}, emoteT = 0 }, Net)
  return self
end

-- ---------------------------------------------------------------------------
-- palette: rotate the green tunic colours of Link's palette
-- ---------------------------------------------------------------------------
local function rgb2hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h / 6
  end
  return h, mx == 0 and 0 or d / mx, mx
end

local function hsv2rgb(h, s, v)
  h = (h % 1) * 6
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  local r, g, b
  if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
  return r, g, b
end

function Net.tintPalette(pal, color)
  local shift = HUE[color] or 0
  if shift == 0 then return pal end
  local out = {}
  for i = 0, 15 do
    local c = pal[i] or { 0, 0, 0 }
    local h, s, v = rgb2hsv(c[1] / 255, c[2] / 255, c[3] / 255)
    -- the tunic and cap are the saturated greens (hue ~0.2-0.45)
    if s > 0.25 and h > 0.17 and h < 0.48 then
      local r, g, b = hsv2rgb(h + shift, s, v)
      out[i] = { r * 255, g * 255, b * 255 }
    else
      out[i] = c
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- sending
-- ---------------------------------------------------------------------------
-- ZeldaSession: sendEventTo(id, tbl) for one player, sendEvent(tbl) for all
function Net:send(ev, peer)
  local s = self.session
  if not s then return false end
  local ok, sent
  if peer and s.sendEventTo then ok, sent = pcall(s.sendEventTo, s, peer, ev)
  elseif s.sendEvent then ok, sent = pcall(s.sendEvent, s, ev) end
  return ok and sent ~= false
end

-- a player's id is also their colour (1 green, 2 red, 3 blue, 4 purple)
function Net:colorFor(peer)
  local idx = tonumber(peer) or 1
  return Net.COLORS[((idx - 1) % 4) + 1]
end

-- ---------------------------------------------------------------------------
-- the game's net callbacks
-- ---------------------------------------------------------------------------
function Net:snapshot(field)
  local p = field.player
  return {
    a = field.room.area, r = field.room.room,
    x = math.floor(p.x), y = math.floor(p.y), s = p.animationState,
    an = p.animId, k = p.minish and 1 or 0, n = field.save.name,
  }
end

function Net:apply(peer, snap, field)
  if type(snap) ~= "table" then return end
  local g = self.ghosts[peer]
  if not g then
    g = { peer = peer, anim = Anim.new(), color = self:colorFor(peer), animId = -1 }
    g.drawGhost = Net.drawGhost
    self.ghosts[peer] = g
    field.ghosts[peer] = g
    -- the runtime's harnesses read game.peers (id -> {x, y})
    self.game.peers = self.game.peers or {}
    self.game.peers[peer] = g
  end
  g.area, g.room = snap.a, snap.r
  g.tx, g.ty = snap.x or g.tx, snap.y or g.ty
  if not g.x then g.x, g.y = g.tx, g.ty end
  g.animationState = snap.s or 4
  g.name = snap.n
  g.minish = snap.k == 1
  if snap.an and snap.an ~= g.animId then
    g.animId = snap.an
    local sprite = math.floor(snap.an / 256)
    g.anim:set(field.assets:sprite(sprite), snap.an % 256, true)
  end
  g.update = function(self_)
    -- ease towards the last reported position (snapshots are ~30 Hz)
    if self_.tx then
      self_.x = self_.x + (self_.tx - self_.x) * 0.5
      self_.y = self_.y + (self_.ty - self_.y) * 0.5
    end
    self_.anim:update(1)
    if self_.emoteT and self_.emoteT > 0 then self_.emoteT = self_.emoteT - 1 end
  end
end

function Net:event(peer, ev, field)
  if type(ev) ~= "table" then return end
  if ev.t == "emote" then
    local g = self.ghosts[peer]
    if g then g.emote, g.emoteT = ev.e, 90 end
  elseif ev.t == "fuse_offer" then
    field.kinstone:onOffer(peer, ev)
  elseif ev.t == "fuse_result" then
    field.kinstone:onResult(peer, ev)
  elseif ev.t == "gift_shells" then
    local n = math.max(0, math.min(99, tonumber(ev.n) or 0))
    field.save.stats.shells = (field.save.stats.shells or 0) + n
    field:showToast(string.format("A friend gave you %d shells!", n), 120)
  elseif ev.t == "fuse_busy" then
    field.kinstone:onResult(peer, { ok = false, why = "Your friend is busy." })
  end
end

function Net:peerLeft(peer, field)
  self.ghosts[peer] = nil
  if self.game.peers then self.game.peers[peer] = nil end
  if field then field.ghosts[peer] = nil end
end

function Net:friendInFront(player)
  local field = self.game.field
  if not field then return nil end
  local fx, fy = player:frontPoint(12)
  for _, g in pairs(self.ghosts) do
    if g.area == field.room.area and g.room == field.room.room and g.x then
      if math.abs(g.x - fx) + math.abs(g.y - fy) < 22 then return g end
    end
  end
  return nil
end

local EMOTES = { "!", "?", "<3", "~" }
function Net:emote(field, kind)
  kind = kind or 1
  self:send({ t = "emote", e = kind })
  field.player.emote, field.player.emoteT = kind, 90
end

-- drawn by Field:drawEntities through e:drawGhost(field, camX, camY)
function Net.drawGhost(g, field, camX, camY)
  local A = field.assets
  local frame = g.anim.frame
  if not frame or frame == 0xFF or not g.x then return end
  local sprite = math.floor((g.animId or 0x100) / 256)
  local pal = Net.tintPalette(A:objPalette(0x16), g.color)
  local img, ox, oy = A:spriteFrame(sprite, frame, pal, "ghost_" .. tostring(g.color))
  if not img then return end
  local x, y = math.floor(g.x - camX), math.floor(g.y - camY)
  if g.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
  if g.name then
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(tostring(g.name):sub(1, 8), x - 12, y - 34)
  end
  if g.emoteT and g.emoteT > 0 and g.emote then
    love.graphics.setColor(1, 1, 0.6, 1)
    love.graphics.print(EMOTES[g.emote] or "!", x + 6, y - 26)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- a loopback "session" pair for tests and solo checking: whatever one side
-- sends arrives at the other's game on the next pump
-- ---------------------------------------------------------------------------
function Net.loopbackPair()
  local a, b = { peer = 1, inbox = {} }, { peer = 2, inbox = {} }
  local function make(me, other)
    return {
      localId = me.peer,
      localIndex = function() return me.peer end,
      sendEvent = function(_, ev) other.inbox[#other.inbox + 1] = { kind = "event", peer = me.peer, data = ev } return true end,
      sendEventTo = function(_, _, ev) other.inbox[#other.inbox + 1] = { kind = "event", peer = me.peer, data = ev } return true end,
      sendSnapshot = function(_, snap) other.inbox[#other.inbox + 1] = { kind = "snapshot", peer = me.peer, data = snap } end,
      drain = function()
        local box = me.inbox
        me.inbox = {}
        return box
      end,
    }
  end
  return make(a, b), make(b, a)
end

return Net
