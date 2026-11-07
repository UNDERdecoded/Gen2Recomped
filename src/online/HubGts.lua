-- The GTS provider (docs/online-design.md 2.7a, 2.9; WS4 client hook for
-- WS9's Link Hub).  GtsClient.open asks its provider for a channel when the
-- caller brings none -- the LINK menu's GTS row, the Global Terminal
-- counters -- and this one answers, in order:
--
--   1. the world this player is in, when its host runs a GTS
--      (OnlineWorld.gtsChannel, WS8);
--   2. the player's Link Hub (SETTINGS hubAddress): one ENet connection to
--      the hub's UDP port (WS1 Transport, the same port the hub's
--      rendezvous and relay use), wrapped as a Net-API channel that owns
--      its socket, so closing the GTS screen closes it;
--   3. nothing: the screen says the cartridge's "could not connect".
--
--   HubGts.install()        once, at boot (Game:load); idempotent
--   HubGts.provider(game)   the function GtsClient calls
--   HubGts.connect(address, settings) -> channel | nil, why

local HubGts = {}

HubGts.LABEL = "hub"

local function settingsOf(game)
  local ok, LinkState = pcall(require, "src.link.LinkState")
  if ok and type(LinkState) == "table" and LinkState.settings then
    local okS, s = pcall(LinkState.settings, game)
    if okS and type(s) == "table" then return s end
  end
  return {}
end

-- a channel to the hub's GTS (paired once the hub answers)
function HubGts.connect(address, s)
  s = s or {}
  local okT, Transport = pcall(require, "src.online.net.Transport")
  if not (okT and Transport.available and Transport.available()) then
    return nil, "online play needs lua-enet"
  end
  local Util = require("src.online.net.Util")
  local host, port = Util.splitEndpoint(address, 7778)
  if not Util.isIPv4(host) then
    local Dns = require("src.online.net.Dns")
    local ip, why = Dns.resolve(host, 3)
    if not ip then return nil, why end
    host = ip
  end
  local t = Transport.new{ port = 0, bind = s.bind, maxPeers = 1 }
  local ok, err = t:listen()
  if not ok then return nil, err end
  local id, why = t:connect(Util.endpoint(host, tonumber(port) or 7778))
  if not id then t:close(); return nil, why end
  return t:channelFor(id, { owns = true, path = "hub" })
end

function HubGts.provider(game)
  -- 1. the world's GTS
  local okW, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
  if okW and type(OnlineWorld) == "table" and OnlineWorld.gtsChannel then
    local okC, ch = pcall(OnlineWorld.gtsChannel)
    if okC and ch then return ch end
  end
  -- 2. the hub's
  local s = settingsOf(game)
  if s.hubAddress then
    local ch, why = HubGts.connect(s.hubAddress, s)
    if ch then return ch end
    pcall(function() require("src.core.Logger").warn("gts: hub %s unreachable (%s)",
      tostring(s.hubAddress), tostring(why)) end)
  end
  return nil
end

-- register with GtsClient, unless another provider is already there (a
-- world that installed its own is covered by step 1 of ours anyway)
function HubGts.install()
  local ok, GtsClient = pcall(require, "src.online.gts.GtsClient")
  if not (ok and type(GtsClient) == "table" and GtsClient.setProvider) then return false end
  local current = GtsClient.provider and GtsClient.provider()
  if current == HubGts.provider then return true end
  local okW, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
  local worldProvider = okW and type(OnlineWorld) == "table" and OnlineWorld.gtsProvider
  if current ~= nil and current ~= worldProvider then return false end
  GtsClient.setProvider(HubGts.provider, HubGts.LABEL)
  return true
end

return HubGts
