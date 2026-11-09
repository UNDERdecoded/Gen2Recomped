-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Opening and joining a Zelda room on the shared online stack, without any
-- UI: the link menu (ZeldaLinkMenu) and the harnesses both drive this.
--
--   ZeldaNet.settings()            the player's ONLINE settings (the same
--                                  options.online the Pokemon LINK menu and
--                                  the launcher's ONLINE page write; the
--                                  launcher's Link Hub patch applies)
--   ZeldaNet.openRoom(game, opts)  -> room   (host; room:update(), room.code,
--                                  room.session once the port is open)
--   ZeldaNet.joinRoom(game, code, opts) -> join (join:update(), join.session
--                                  once connected, join.error on failure)
--
-- A room is reached by its LONG code (direct: LAN / router mapping /
-- forwarded port / hole punch) or, when the player has a Link Hub set, by a
-- HUB code (the hub introduces each joiner, then they punch through). Short
-- relay codes pair exactly two players, so Zelda rooms do not use them.

local Session = require("src.online.zelda.ZeldaSession")

local ZeldaNet = {}

local DEFAULTS = { port = 7777, allowRelay = true, portMap = true, stun = false, lanBeacon = true }

local function linkState()
  local ok, LS = pcall(require, "src.link.LinkState")
  return ok and type(LS) == "table" and LS or nil
end

function ZeldaNet.settings()
  local okS, SaveData = pcall(require, "src.core.SaveData")
  local opts = okS and select(2, pcall(SaveData.loadOptions)) or {}
  if type(opts) ~= "table" then opts = {} end
  local LS = linkState()
  if LS and LS.settings then
    local ok, s = pcall(LS.settings, { save = { options = opts } })
    if ok and type(s) == "table" then return s end
  end
  local s = {}
  for k, v in pairs(DEFAULTS) do s[k] = v end
  for k, v in pairs(type(opts.online) == "table" and opts.online or {}) do s[k] = v end
  return s
end

function ZeldaNet.playerName(save)
  local s = ZeldaNet.settings()
  if type(s.displayName) == "string" and s.displayName ~= "" then return s.displayName end
  if type(save) == "table" and save.name then return tostring(save.name) end
  return "LINK"
end

-- "host[:port]" -> ip, port (Link Hub address; LinkState's own resolver when
-- it loads, so the launcher hub patch -- router IP for one's own hub -- holds)
local function hubEndpoint(address)
  local LS = linkState()
  if LS and LS.hubEndpoint then
    local ok, a, b, c, d = pcall(LS.hubEndpoint, address)
    if ok then return a, b, c, d end
  end
  if type(address) ~= "string" or address == "" then return nil end
  local Util = require("src.online.net.Util")
  local host, port = Util.splitEndpoint(address, 7778)
  if not Util.isIPv4(host) then
    local okD, Dns = pcall(require, "src.online.net.Dns")
    host = okD and Dns.resolve(host, 3) or nil
  end
  if not host then return nil end
  return host, tonumber(port) or 7778
end

-- ------------------------------------------------------------------ host

-- New guests of a room's Connector host job, as a `take()` source: inbound
-- peers that promoted themselves, and peers a hub-introduced hole punch
-- connected (Connector.host only drives its punches for one-guest links,
-- so a multi-guest room drives them here). The hub's own link is never a
-- guest.
function ZeldaNet.roomSource(job)
  local src = { seen = {} }
  function src:take()
    local out = {}
    local t = job.transport
    if not t then return out end
    pcall(t.update, t)
    for _, p in ipairs(job.punches or {}) do
      if p.state == "trying" then pcall(p.update, p) end
      if p.state == "connected" and p.peerId and not self.seen[p.peerId] then
        self.seen[p.peerId] = true
        local ch = t:channelFor(p.peerId)
        if ch then out[#out + 1] = ch end
      end
    end
    for _, rec in ipairs(t:peerList()) do
      if not rec.outgoing and rec.promoted and rec.state == "connected"
         and not self.seen[rec.id] and rec.id ~= job.hubId then
        self.seen[rec.id] = true
        local ch = t:channelFor(rec.id)
        if ch then out[#out + 1] = ch end
      end
    end
    return out
  end
  function src:close() end
  return src
end

local Room = {}
Room.__index = Room

-- opts: maxPlayers (2-4), name, clock, connector (extra Connector.host opts,
-- tests: port/bind/lanIp/portMap=false/lanBeacon=false), hubWait (seconds)
function ZeldaNet.openRoom(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, opts = opts, state = "opening", t = 0 }, Room)
  local s = ZeldaNet.settings()
  self.settings = s
  local max = math.max(2, math.min(4, tonumber(opts.maxPlayers) or 4))
  local o = { port = s.port, bind = s.bind, lanIp = s.lanIp, portMap = s.portMap,
              stun = s.stun, stunServer = s.stunServer, manualAddress = s.manualAddress,
              portMapOpts = s.portMapOpts, allowRelay = false, relayHost = false,
              lanBeacon = s.lanBeacon, beaconTargets = s.beaconTargets, beaconPort = s.beaconPort,
              beaconInfo = { name = opts.name, game = game, series = "zelda" },
              hub = s.hubAddress, maxPeers = max - 1 }
  for k, v in pairs(opts.connector or {}) do o[k] = v end
  o.maxPeers = max - 1
  local okC, Connector = pcall(require, "src.online.net.Connector")
  if not okC then self.state, self.error = "failed", tostring(Connector) return self end
  local ok, job = pcall(Connector.host, o)
  if not ok then self.state, self.error = "failed", tostring(job) return self end
  self.job = job
  self.maxPlayers = max
  self.hubWait = tonumber(opts.hubWait) or 6
  return self
end

function Room:_makeCode()
  local InviteCode = require("src.online.InviteCode")
  local h = self.job
  local fields = h:inviteFields()
  fields.room = nil
  local display
  local hubIp, hubPort, hubLan, hubPublicPort = hubEndpoint(self.settings.hubAddress)
  if h.info and h.info.hubTicket and hubIp then
    display = InviteCode.encode({ kind = "hub", lan = hubLan,
      hub = { ip = hubIp, port = hubPort, publicPort = hubPublicPort }, ticket = h.info.hubTicket })
    self.viaHub = display ~= nil
  end
  if not display then display = InviteCode.encode(fields) end
  return display
end

function Room:update(dt)
  self.t = self.t + (dt or 0)
  if self.state == "failed" or self.state == "closed" then return end
  local h = self.job
  if self.session then
    if self.session.state == "closed" then self.state = "closed" end
    return   -- the session pumps the job from here on
  end
  pcall(h.update, h)
  if h.state == "failed" then self.state, self.error = "failed", h.reason or "could not open a port" return end
  if not h.pending and h.transport then
    -- wait (briefly) for a hub ticket when a hub is set
    if self.settings.hubAddress and not (h.info and h.info.hubTicket) and self.t < self.hubWait then return end
    local okC, code = pcall(self._makeCode, self)
    if not okC or not code then self.state, self.error = "failed", tostring(code) return end
    self.code = code
    self.session = Session.host({ game = self.game, name = self.opts.name, maxPlayers = self.maxPlayers,
                                  source = ZeldaNet.roomSource(h), clock = self.opts.clock })
    self.session.hostJob = h
    self.session.code = code
    self.state = "open"
  end
end

function Room:close()
  if self.session then pcall(self.session.close, self.session) end
  if self.job then pcall(self.job.close, self.job) end
  self.state = "closed"
end

-- ------------------------------------------------------------------ join

local Join = {}
Join.__index = Join

-- What a typed / pasted code means: invite, or nil + why.
function ZeldaNet.decode(text)
  local okI, InviteCode = pcall(require, "src.online.InviteCode")
  if not okI then return nil, tostring(InviteCode) end
  local Util = require("src.online.net.Util")
  local okL, myLan = pcall(Util.lanIP)
  local inv, why = InviteCode.decode(tostring(text or ""), okL and myLan or nil)
  if not inv then
    local found = InviteCode.findInText and InviteCode.findInText(tostring(text or ""), okL and myLan or nil)
    inv = found
  end
  if not inv then return nil, why or "That is not a room code." end
  if inv.type == "short" then
    return nil, "That is a short relay code. Zelda rooms use the long room code."
  end
  return inv
end

-- opts: name, clock, joinOptions (extra Connector.join opts)
function ZeldaNet.joinRoom(game, code, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, opts = opts, state = "connecting" }, Join)
  local inv, why = code
  if type(code) ~= "table" then inv, why = ZeldaNet.decode(code) end
  if not inv then self.state, self.error = "failed", why return self end
  local s = ZeldaNet.settings()
  local o = { allowRelay = false, bind = s.bind, timeouts = s.timeouts, port = opts.port }
  for k, v in pairs(opts.joinOptions or {}) do o[k] = v end
  local okC, Connector = pcall(require, "src.online.net.Connector")
  if not okC then self.state, self.error = "failed", tostring(Connector) return self end
  local ok, job = pcall(Connector.join, inv, o)
  if not ok then self.state, self.error = "failed", tostring(job) return self end
  self.job = job
  return self
end

function Join:progress()
  if self.session then return "Saying hello..." end
  return self.job and self.job.progress or "Connecting..."
end

function Join:update()
  if self.state == "failed" or self.state == "open" or self.state == "closed" then return end
  if not self.session then
    pcall(self.job.update, self.job)
    if self.job.state == "failed" then
      self.state, self.error = "failed", self.job.reason or "Could not reach that room."
      return
    end
    if self.job.state == "connected" and self.job.channel then
      self.path = self.job.path
      self.session = Session.guest({ game = self.game, name = self.opts.name, channel = self.job.channel,
                                     clock = self.opts.clock })
    end
    return
  end
  local s = self.session
  s:update()
  if s.state == "open" then
    self.state = "open"
  elseif s.state == "closed" then
    self.state, self.error = "failed", s.closeReason or "The room closed."
  end
end

function Join:cancel()
  if self.session then pcall(self.session.close, self.session) end
  if self.job and self.job.cancel and self.job.state == "trying" then pcall(self.job.cancel, self.job) end
  self.state = "closed"
end

return ZeldaNet
