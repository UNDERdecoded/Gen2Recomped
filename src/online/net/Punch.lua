-- Simultaneous-open hole punch over one Transport (ladder rungs L3 and L4).
--
-- Both sides know each other's endpoints and nonces (from swapped invite
-- codes, or from a Link Hub's introduction).  Each side dials every remote
-- endpoint FROM ITS OWN BOUND TRANSPORT, so its NAT opens a mapping toward
-- the other, and ENet's retransmitted connect packets do the punching.
-- When both directions get through there are two ENet connections between
-- the same pair; the tie-break keeps exactly one on both sides:
--
--   * the side with the lower nonce is the initiator (L4: the guest);
--   * the kept connection is the one the INITIATOR dialled: the initiator
--     keeps its outgoing peer, the other side keeps the matching inbound
--     peer, and both drop the rest;
--   * if only the non-preferred connection ever forms (one NAT filtered the
--     other's packets), both sides see that same connection, wait `grace`
--     seconds for the preferred one, then keep it.
--
--   local job = Punch.start(transport, { endpoints = {"1.2.3.4:7777"},
--                     myNonce = 11, theirNonce = 22, timeout = 10 })
--   job:update() each frame; job.state "trying"|"connected"|"failed";
--   job.peerId, job.endpoint, job.reason
--
-- Endpoints are tried in order of preference (LAN first); when a less
-- preferred endpoint connects first, `lanGrace` seconds are given to an
-- earlier one before settling.

local Util = require("src.online.net.Util")

local Punch = {}
Punch.__index = Punch

Punch.TIMEOUT = 10
Punch.GRACE = 1.5
Punch.LAN_GRACE = 0.6

function Punch.isInitiator(myNonce, theirNonce, role)
  if role == "guest" then return true end
  if role == "host" then return false end
  return (myNonce or 0) < (theirNonce or 0)
end

function Punch.start(transport, opts)
  local self = setmetatable({
    t = transport, endpoints = opts.endpoints or {},
    myNonce = opts.myNonce, theirNonce = opts.theirNonce,
    timeout = opts.timeout or Punch.TIMEOUT,
    grace = opts.grace or Punch.GRACE,
    lanGrace = opts.lanGrace or Punch.LAN_GRACE,
    state = "trying", out = {}, started = Util.time(),
  }, Punch)
  if opts.initiator ~= nil then
    self.initiator = opts.initiator
  else
    if opts.role == nil and self.myNonce == self.theirNonce then
      self.state = "failed"
      self.reason = "both codes have the same nonce; make a new code"
      return self
    end
    self.initiator = Punch.isInitiator(self.myNonce, self.theirNonce, opts.role)
  end
  if #self.endpoints == 0 then
    self.state = "failed"
    self.reason = "no address to punch towards"
    return self
  end
  self.ips = {}
  for i, e in ipairs(self.endpoints) do
    local ip = Util.splitEndpoint(e)
    if ip and not self.ips[ip] then self.ips[ip] = i end
  end
  if not transport.open_ then
    local ok, err = transport:listen()
    if not ok then
      self.state = "failed"
      self.reason = err
      return self
    end
  end
  for i, e in ipairs(self.endpoints) do
    local id, err = transport:connect(e, self.theirNonce, { timeout = self.timeout })
    if id then
      self.out[i] = id
      local rec = transport:peer(id)
      rec.claim = self
    end
  end
  return self
end

-- preference rank of a record (lower is better), or nil if not ours
function Punch:rank(rec)
  if rec.state ~= "connected" then return nil end
  if rec.outgoing then
    -- wait for the far side's `_hi`: ENet reports "connect" even when the
    -- other transport refuses us a moment later
    if not rec.acked then return nil end
    for i, id in pairs(self.out) do
      if id == rec.id then return i, true end
    end
    return nil
  end
  local i = self.ips[rec.ip]
  if not i then return nil end
  if rec.claim and rec.claim ~= self then return nil end
  rec.claim = self -- hold it back from a host job's auto-accept
  return i, false
end

function Punch:finish(rec)
  self.state = "connected"
  self.peerId = rec.id
  self.endpoint = rec.outgoing and rec.address or self.endpoints[self.ips[rec.ip]]
  self.viaOutgoing = rec.outgoing
  for _, id in pairs(self.out) do
    if id ~= rec.id then self.t:disconnect(id, true) end
  end
  for _, other in pairs(self.t.peers) do
    if other.claim == self and other.id ~= rec.id and other.state ~= "closed" then
      self.t:disconnect(other.id, true)
    end
  end
  rec.claim = nil
end

function Punch:update()
  if self.state ~= "trying" then return self.state end
  self.t:update()
  local now = Util.time()
  local best, bestRank, bestPreferred = nil, nil, nil
  local bestFallback, fallbackRank = nil, nil
  for _, rec in pairs(self.t.peers) do
    local rank, outgoing = self:rank(rec)
    if rank then
      local preferred = (outgoing == self.initiator)
      if preferred then
        if not bestRank or rank < bestRank then best, bestRank = rec, rank end
      else
        if not fallbackRank or rank < fallbackRank then
          bestFallback, fallbackRank = rec, rank
        end
      end
    end
  end
  if best then
    -- the best endpoint is up, or a lesser one has waited out lanGrace
    if bestRank == 1 or now - best.connectedAt >= self.lanGrace then
      self:finish(best)
      return self.state
    end
  end
  if bestFallback and now - bestFallback.connectedAt >= self.grace
     and (not best or fallbackRank < bestRank) then
    self:finish(bestFallback)
    return self.state
  end
  if best and now - best.connectedAt >= self.lanGrace then
    self:finish(best)
    return self.state
  end
  if now - self.started > self.timeout then
    self:fail(("no answer from %s"):format(table.concat(self.endpoints, " / ")))
  end
  return self.state
end

function Punch:fail(reason)
  self.state = "failed"
  self.reason = reason
  for _, id in pairs(self.out) do self.t:disconnect(id, true) end
  for _, rec in pairs(self.t.peers) do
    if rec.claim == self then
      rec.claim = nil
      if rec.state ~= "closed" then self.t:disconnect(rec.id, true) end
    end
  end
end

function Punch:cancel() if self.state == "trying" then self:fail("cancelled") end end

return Punch
