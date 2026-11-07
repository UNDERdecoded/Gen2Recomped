-- AN ACCEPTED INVITE BECOMES A LINK SESSION (docs/online-design.md 2.8
-- "invite").  Two world members who agreed to trade or battle are handed
-- one Net-API channel each (WorldClient.SessionChannel: relayed through the
-- host, which checks every party that crosses it), and the game's own link
-- screen runs on it exactly as it runs on a cable.
--
-- WS4 owns LinkState, and its entry point for exactly this is
--
--   LinkState.openWithChannel(game, channel, {
--     mode = "trade" | "battle",   -- already agreed; no mode menu
--     isHost = bool,               -- the inviter is the host side
--     peerName = "ALICE",
--     source = "world",            -- no code screens, no relay, no Discord
--   }) -> the LinkState it pushed
--
-- which is what runs.  The fallback below is only for a LinkState that
-- predates it (an older WS4 build): it drives the same two stages by hand,
-- "waitHello" on the host side and "waitMode" on the guest side.

local WorldLink = {}

function WorldLink.open(game, channel, opts)
  opts = opts or {}
  local LinkState = require("src.link.LinkState")
  local spec = { mode = opts.mode, isHost = opts.isHost and true or false,
                 peerName = opts.peerName, source = "world" }
  if type(LinkState.openWithChannel) == "function" then
    return LinkState.openWithChannel(game, channel, spec)
  end
  require("src.core.Logger").warn("world: LinkState has no openWithChannel; driving its stages directly")
  local ls = LinkState.new(game)
  ls.net = channel
  ls.peerName = opts.peerName
  ls.fromWorld = true
  if spec.isHost then
    ls:sendHello(spec.mode)
    ls.pendingMode = spec.mode
    ls.helloWait = 0
    ls.stage = "waitHello"
  else
    ls.stage = "waitMode"
    ls:sendHello(nil)
  end
  game.stack:push(ls)
  return ls
end

return WorldLink
