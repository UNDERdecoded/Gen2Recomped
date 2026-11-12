-- SOUL LINK RELAY: a world service (src/online/world/WorldHost.lua shape:
-- open / update / close) that carries Soul Link messages between the
-- members of one world.  It only forwards: every message a member sends
-- goes to every other member who opened the service, as
--   { type = "sl_fwd", from = pid, name = memberName, msg = <the message> }
-- and a member joining / leaving is announced as sl_join / sl_leave.
-- Pairing, the encounter record and the deaths are the NUZLOCKE mod's
-- (mods/NUZLOCKE/lib/SoulLink.lua); this side never reads a save.
--
-- Registered on every world a game hosts (OnlineWorld.serviceFactories)
-- and on the Link Hub's always-on world (src/online/hub/WorldEmbed.lua),
-- so partners can link through either.

local SoulLinkService = {}

SoulLinkService.NAME = "soullink"
SoulLinkService.MAX_PER_UPDATE = 64

function SoulLinkService.new()
  local svc = { members = {} }

  local function broadcast(fromPid, msg)
    for pid, m in pairs(svc.members) do
      if pid ~= fromPid and not m.ch.closed then m.ch:send(msg) end
    end
  end

  function svc.open(ch, member)
    local pid = member and member.pid or (#svc.members + 1)
    local name = member and member.name or "?"
    svc.members[pid] = { ch = ch, name = name }
    ch:send({ type = "sl_welcome", pid = pid })
    broadcast(pid, { type = "sl_join", pid = pid, name = name })
    for other, m in pairs(svc.members) do
      if other ~= pid then ch:send({ type = "sl_join", pid = other, name = m.name }) end
    end
  end

  function svc.update()
    for pid, m in pairs(svc.members) do
      local msgs = m.ch:poll()
      for i = 1, math.min(#msgs, SoulLinkService.MAX_PER_UPDATE) do
        local msg = msgs[i]
        if type(msg) == "table" and type(msg.type) == "string" and msg.type:sub(1, 3) == "sl_" then
          broadcast(pid, { type = "sl_fwd", from = pid, name = m.name, msg = msg })
        end
      end
      if m.ch.closed then
        svc.members[pid] = nil
        broadcast(pid, { type = "sl_leave", pid = pid })
      end
    end
  end

  function svc.close()
    for _, m in pairs(svc.members) do pcall(m.ch.close, m.ch) end
    svc.members = {}
  end

  return svc
end

return SoulLinkService
