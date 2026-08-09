-- Unit coverage for event:discord.join_requested (DiscordPresence Ask-to-Join).
-- Mods subscribe through Runtime; the engine emits before pushing JoinOnline.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Events = require("src.mods.Events")
local DiscordPresence = require("src.core.DiscordPresence")

local savedLink = package.loaded["src.link.LinkState"]
local savedTour = package.loaded["src.link.Tournament"]
package.loaded["src.link.LinkState"] = {
  newJoinOnline = function(_game, code)
    return { tag = "link", code = code, stage = true, net = {} }
  end,
}
package.loaded["src.link.Tournament"] = {
  newJoinOnline = function(_game, code)
    return { tag = "tournament", code = code, stage = true, net = {} }
  end,
}

local function freshGame()
  local items = {}
  return {
    stack = {
      items = items,
      top = function(self) return self.items[#self.items] end,
      push = function(self, screen) self.items[#self.items + 1] = screen end,
    },
  }
end

local bus = Events.new()
local savedEvents, savedHooks = Runtime.events, Runtime.hooks
Runtime.events = bus

local function listen()
  local seen = {}
  bus:on("discord.join_requested", function(ev)
    seen[#seen + 1] = ev
  end, 0, "discord_join_test")
  return seen
end

do
  local game = freshGame()
  local st = DiscordPresence._state
  st.game = game
  st.activity = "exploring"
  local seen = listen()

  DiscordPresence.handleJoinRequest("m:HOST01")
  T.eq(#seen, 1, "match join emits discord.join_requested")
  T.eq(seen[1].code, "HOST01", "payload carries the match code")
  T.eq(seen[1].kind, "m", "payload carries kind tag m")
  T.eq(game.stack:top().tag, "link", "pushes LinkState.newJoinOnline")
  T.eq(game.stack:top().code, "HOST01", "join screen gets the code")
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame()
  local st = DiscordPresence._state
  st.game = game
  st.activity = "menu"
  local seen = listen()

  DiscordPresence.handleJoinRequest("t:TOUR99")
  T.eq(#seen, 1, "tournament join emits discord.join_requested")
  T.eq(seen[1].kind, "t", "payload carries kind tag t")
  T.eq(seen[1].code, "TOUR99", "payload carries the tournament code")
  T.eq(game.stack:top().tag, "tournament", "pushes Tournament.newJoinOnline")
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame()
  local st = DiscordPresence._state
  st.game = game
  st.activity = "exploring"
  local seen = listen()

  DiscordPresence.handleJoinRequest("PLAIN42")
  T.eq(#seen, 1, "plain secret still emits discord.join_requested")
  T.eq(seen[1].kind, "m", "plain secret defaults to match kind")
  T.eq(seen[1].code, "PLAIN42", "plain secret is the whole code")
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame()
  local st = DiscordPresence._state
  st.game = game
  st.activity = "battle"
  local seen = listen()

  DiscordPresence.handleJoinRequest("m:NOPE")
  T.eq(#seen, 0, "battle activity suppresses join dispatch")
  T.eq(game.stack:top(), nil, "battle activity pushes no join screen")
  bus:removeOwner("discord_join_test")
end

do
  local game = freshGame()
  game.stack:push({ stage = true, net = {} }) -- already in a link session
  local st = DiscordPresence._state
  st.game = game
  st.activity = "exploring"
  local seen = listen()

  DiscordPresence.handleJoinRequest("m:NOPE")
  T.eq(#seen, 0, "active link session suppresses join dispatch")
  T.eq(#game.stack.items, 1, "active link session is not replaced")
  bus:removeOwner("discord_join_test")
end

DiscordPresence._state.game = nil
DiscordPresence._state.activity = "menu"
Runtime.events, Runtime.hooks = savedEvents, savedHooks
package.loaded["src.link.LinkState"] = savedLink
package.loaded["src.link.Tournament"] = savedTour

T.finish("discord_join_requested")
