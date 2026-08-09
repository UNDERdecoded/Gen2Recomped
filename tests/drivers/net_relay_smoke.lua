-- Driver: exercises src/link/Net.lua's TCP relay backend for real, inside
-- LOVE (real lua-enet/luasocket), against a pokeserver already running at
-- 127.0.0.1:7778 (POKEPORT_RELAY_ADDR overrides). Doesn't touch the game
-- UI at all -- just proves host/join/relay/close over a real socket.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Net = require("src.link.Net")
  local addr = os.getenv("POKEPORT_RELAY_ADDR") or "127.0.0.1:7778"

  local host = Net.new()
  local ok = host:hostOnline(addr)
  U.log("hostOnline ok:", ok, "error:", host.error)

  local frames = 0
  while not host.code and not host.error and frames < 180 do
    host:update()
    frames = frames + 1
    coroutine.yield()
  end
  U.log("host code:", host.code, "error:", host.error)

  local guest = Net.new()
  local gok = guest:joinOnline(addr, host.code)
  U.log("joinOnline ok:", gok, "error:", guest.error)

  frames = 0
  while (not host.paired or not guest.paired) and frames < 180 do
    host:update()
    guest:update()
    frames = frames + 1
    coroutine.yield()
  end
  U.log("host.paired:", host.paired, "guest.paired:", guest.paired)

  host:send({ type = "hello", name = "RED" })
  local relayed = nil
  frames = 0
  while not relayed and frames < 180 do
    host:update() -- flushes host's queued send
    guest:update()
    for _, msg in ipairs(guest:poll()) do
      if msg.type == "hello" then relayed = msg end
    end
    frames = frames + 1
    coroutine.yield()
  end
  U.log("relayed hello name:", relayed and relayed.name)

  guest:close()
  frames = 0
  while not host.closed and frames < 180 do
    host:update()
    frames = frames + 1
    coroutine.yield()
  end
  U.log("host saw peer_gone / closed:", host.closed)

  host:close()

  local pass = host.code ~= nil and host.paired and guest.paired
               and relayed ~= nil and relayed.name == "RED" and host.closed
  U.log("NET_RELAY_SMOKE:", pass and "PASS" or "FAIL")
end
