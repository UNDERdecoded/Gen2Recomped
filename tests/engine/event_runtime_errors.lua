-- Failures during game.ready/update must reach the real loader diagnostics.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Events = require("src.mods.Events")
local run = T.sdk.loadMods({ "mods/event_probe" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs({
    ["mods/event_probe/manifest.json"] = [[{
      "id":"event_probe", "name":"Event probe", "version":"1.0.0",
      "api":2, "entry":"main.lua", "affects_link":false
    }]],
    ["mods/event_probe/main.lua"] = [[
      local mod = ...
      mod.exports.message = "first callback fault"
      mod.exports.fail = true
      mod.exports.healthy = 0
      mod.events:on("game.ready", function()
        if mod.exports.fail then error(mod.exports.message) end
      end, 10)
      mod.events:on("game.ready", function()
        mod.exports.healthy = mod.exports.healthy + 1
      end, 0)
    ]],
  }),
})
T.eq(#run.errors, 0, "entry succeeds before the lifecycle callback runs")
local exported = assert(run.loader.exports.event_probe)
local events = run.loader.events
T.check(Runtime.events == events, "probe uses the installed native bus")
T.check(pcall(Runtime.emit, "game.ready", { game = {} }), "callback error does not abort native startup")
T.eq(exported.healthy, 1, "remaining callbacks still execute")
T.eq(#run.loader:status().errors, 1, "actual loader diagnostics receive lifecycle failure")
local first = run.errors[1] or ""
T.check(first:find("event_probe: event game.ready:", 1, true) ~= nil, "diagnostics retain owner and event")
T.check(first:find("first callback fault", 1, true) ~= nil, "diagnostics retain the cause")
for _ = 1, 100 do Runtime.emit("game.ready", { game = {} }) end
T.eq(#run.errors, 1, "persistent frame/lifecycle failure cannot grow the feed every frame")
T.eq(exported.healthy, 101, "deduplication does not suppress healthy callbacks")
exported.message = "second callback fault"
Runtime.emit("game.ready", { game = {} })
T.eq(#run.errors, 2, "a different cause is reported")
exported.fail = false
Runtime.emit("game.ready", { game = {} })
exported.fail = true
Runtime.emit("game.ready", { game = {} })
T.eq(#run.errors, 3, "recurrence after recovery is a new error episode")
local oldBus = events
local nextBus, nextErrors = Events.new(), {}
Runtime.install(nextBus, Runtime.hooks, nextErrors)
oldBus:emit("game.ready", { game = {} })
T.eq(#nextErrors, 0, "retired bus cannot write errors into the next session")
T.eq(#run.errors, 3, "retired bus does not append to the old live diagnostics")
local after = 0
nextBus:on("update", function() error("current session fault") end, 0, "next_probe")
nextBus:on("update", function() after = after + 1 end, -1, "next_probe")
T.check(pcall(Runtime.emit, "update", {}), "new session keeps normal event dispatch")
T.eq(#nextErrors, 1, "current bus owns its new diagnostics")
T.eq(after, 1, "current healthy callback runs after a failure")
nextBus:removeOwner("next_probe")
Runtime.emit("update", {})
T.eq(#nextErrors, 1, "unsubscribed callback cannot add errors")
run.release()
T.finish("native event failures in loader diagnostics")
