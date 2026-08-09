-- Driver: hosts a real online match (against the deployed relay) and
-- reports Discord IPC connection/subscribe/join-code state, so the whole
-- "Ask to Join" wiring can be checked against the actual local Discord
-- client instead of guessing from code review alone.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DiscordPresence = require("src.core.DiscordPresence")
  local Pokemon = require("src.pokemon.Pokemon")

  local function report(line)
    U.log(line)
    local f = io.open("/tmp/discord_test_status.txt", "a")
    if f then f:write(line .. "\n"); f:close() end
  end

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 25) }
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")

  U.wait(30) -- give the Discord IPC connection a moment to establish
  local s = DiscordPresence._state
  report(("discord: enabled=%s connected=%s subscribedJoin=%s"):format(
    tostring(s.enabled), tostring(s.connected), tostring(s.subscribedJoin)))

  local LinkState = require("src.link.LinkState")
  local link = LinkState.new(game)
  game.stack:push(link)
  U.wait(3)
  U.tap(game, "down"); U.wait(2) -- ONLINE MATCH row
  U.tap(game, "a"); U.wait(3) -- into onlineMenu
  U.tap(game, "a"); U.wait(30) -- HOST ONLINE -> connect to the real relay

  local waited = 0
  while not link.net.code and waited < 300 do
    U.wait(1)
    waited = waited + 1
  end
  report(("host code: %s net error: %s"):format(
    tostring(link.net.code), tostring(link.net.error)))

  U.wait(60) -- let DiscordPresence pick up the code and push an activity
  report(("discord joinCode now: %s connected: %s"):format(
    tostring(s.joinCode), tostring(s.connected)))
  report("DISCORD_JOIN_TEST: check your Discord profile/status now -- it")
  report("should show an 'Ask to Join' button, code " .. tostring(link.net.code))

  while true do
    coroutine.yield()
  end
end
