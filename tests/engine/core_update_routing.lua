package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/core_update/fixture.lua")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Loader = require("src.mods.Loader")
local savedVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local e, g, api = f.exports, f.game, f.public
    local label = version .. "/" .. mode[1] .. "/" .. mode[2] .. ": "
    T.eq(api:supports("hooks", "core.update"), true, label .. "native hook capability")
    f.update(0.125)
    T.eq(g.calls, 1, label .. "native update runs once")
    T.eq(e.polls(), 1, label .. "hook runs once")
    T.eq(e.seen.game, g, label .. "Game stays opaque under every callback format")
    T.eq(e.seen.dt, 0.125, label .. "delta stays scalar")
    e.pause(true)
    T.eq(f.bridge.update(g, 0.5), "paused", label .. "hook result returned by bridge")
    T.eq(g.calls, 1, label .. "bridge respects pause")
    e.pause(false)
    -- Boot reports own their frame before any Game/mod processing.
    f.set("bootReport", {})
    local polls, n, host = e.polls(), g.calls, f.hostPolls()
    f.update(1 / 60)
    T.eq(e.polls(), polls, label .. "boot report bypasses hook")
    T.eq(g.calls, n, label .. "boot report bypasses game")
    T.eq(f.hostPolls(), host, label .. "boot report retains native housekeeping boundary")
    f.set("bootReport", nil)
    -- Driver failure/completion must not accidentally fall into the hook.
    local quit, oldQuit = {}, love.event.quit
    love.event.quit = function(code)
      quit[#quit + 1] = code or "normal"
    end
    f.set(
      "driverCo",
      coroutine.create(function()
        error("intentional core.update driver failure")
      end)
    )
    f.update(1 / 60)
    T.eq(quit[1], 1, label .. "driver error requests failure exit")
    T.eq(e.polls(), polls, label .. "failed driver bypasses hook")
    T.eq(g.calls, n, label .. "failed driver does not update game")
    f.set("driverCo", coroutine.create(function() end))
    f.update(1 / 60)
    T.eq(quit[2], "normal", label .. "completed driver requests native exit")
    T.eq(e.polls(), polls, label .. "completed driver bypasses hook")
    T.eq(g.calls, n, label .. "completed driver does not update game")
    f.set("driverCo", nil)
    love.event.quit = oldQuit
    -- Owner cleanup removes only that contributor's frame wrapper.
    local peerCalls = 0
    local off = f.result.loader.hooks:wrap("core.update", function(next, ...)
      peerCalls = peerCalls + 1
      return next(...)
    end, 5, "other_owner")
    f.result.loader.hooks:removeOwner("portable_core_update")
    f.update(1 / 60)
    T.eq(e.polls(), polls, label .. "owner removal retires mod wrapper")
    T.eq(peerCalls, 1, label .. "owner removal preserves another wrapper")
    T.eq(g.calls, n + 1, label .. "owner removal preserves native update")
    off()
    f.close()
  end
end
-- With no mods, the actual love.update and direct bridge keep native behavior.
local bare = Fixture.new(".", "gen2", "red", 2, "native", true)
T.eq(Runtime.wantsHook("core.update"), false, "no-mod Runtime has no frame subscriber")
for _, dt in ipairs({ 0, 0.125, 2 }) do
  bare.update(dt)
end
T.eq(bare.game.calls, 3, "no-mod interactive update runs once per call")
T.same(bare.game.dts, { 0, 0.125, 2 }, "no-mod delta forwarding unchanged")
T.eq(select("#", bare.bridge.update(bare.game, 0)), 0, "native return values discarded without subscribers")
bare.close()
-- A failed entry's registered update cannot survive its public-loader rollback.
local files = {
  ["mods/broken_frame/manifest.json"] = [[{"id":"broken_frame","name":"Broken Frame",
    "version":"1.0.0","api":3,"entry":"main.lua"}]],
  ["mods/broken_frame/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("core.update", function() error("rolled-back wrapper survived") end)
    error("intentional frame entry failure")
  ]],
}
local failed = T.sdk.loadMods({ "mods/broken_frame" }, { fs = T.sdk.memfs(files), data = T.fixtures.fresh() })
T.check(#failed.errors > 0, "failed frame entry is reported")
T.eq(Runtime.wantsHook("core.update"), false, "rollback removes registered frame wrapper")
local count = 0
require("src.core.PlatformHooks").update({
  update = function()
    count = count + 1
  end,
}, 1 / 60)
T.eq(count, 1, "rollback preserves native frame fallback")
Loader.teardown()
T.eq(Runtime.wantsHook("core.update"), false, "teardown leaves no frame wrapper")
failed.release()
Version.set(savedVersion)
T.finish("core.update routing")
