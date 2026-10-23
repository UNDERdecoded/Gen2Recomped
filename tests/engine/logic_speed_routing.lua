package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/logic_speed/fixture.lua")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Loader = require("src.mods.Loader")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local e, g, api = f.exports, f.game, f.public
    local label = version .. "/" .. mode[1] .. "/" .. mode[2] .. ": "
    T.eq(api:supports("hooks", "core.logic_speed"), true, label .. "native capability")
    T.eq(g:logicSpeed(), 4, label .. "native option through hook")
    T.eq(e.seen.game, g, label .. "opaque owner identity")
    T.eq(e.seen.extra, 0, label .. "scalar signature")
    T.eq(e.seen.calls, 1, label .. "one dispatch")
    e.setSpeed(20)
    T.eq(g:logicSpeed(), 20, label .. "override")
    local calls = e.seen.calls
    g.linkNet = { closed = false }
    g.speedOverride = 100
    T.eq(g:logicSpeed(), 1, label .. "open link beats override")
    T.eq(e.seen.calls, calls, label .. "link bypasses hook")
    g.linkNet.closed = true
    T.eq(g:logicSpeed(), 100, label .. "closed link restores explicit override")
    T.eq(e.seen.calls, calls, label .. "explicit override bypasses hook")
    g.speedOverride = nil
    T.eq(g:logicSpeed(), 20, label .. "closed link permits hook")
    for _, marker in ipairs({ "isFixedSpeed", "isMinigame" }) do
      g.stack.states = { { [marker] = true }, { isMenu = true } }
      calls = e.seen.calls
      T.eq(g:logicSpeed(), 1, label .. marker .. " stays locked under a menu")
      T.eq(select(2, g:speedLocked()), "minigame", label .. "lock reason")
      T.eq(e.seen.calls, calls, label .. "fixed-speed bypasses hook")
    end
    g.stack = nil
    T.eq(g:logicSpeed(), 20, label .. "missing stack is unlocked")
    -- Loader ownership removes only the affected mod's contribution.
    local peers = 0
    local off = f.result.loader.hooks:wrap("core.logic_speed", function(next, ...)
      peers = peers + 1
      return next(...)
    end, 10, "other_speed_owner")
    f.result.loader.hooks:removeOwner("portable_logic_speed")
    calls = e.seen.calls
    T.eq(g:logicSpeed(), 4, label .. "owner cleanup restores native option")
    T.eq(e.seen.calls, calls, label .. "owner cleanup retires consumer")
    T.eq(peers, 1, label .. "other owner still runs")
    off()
    f.close()
  end
end
local bare = Fixture.new(".", "gen2", "red", 3, "unified", true)
T.eq(Runtime.wantsHook("core.logic_speed"), false, "no-mod fast path")
T.eq(bare.game:logicSpeed(), 4, "no-mod native option")
bare.game.save = nil
T.eq(bare.game:logicSpeed(), 1, "no save uses native default")
bare.close()
local files = {
  ["mods/broken_speed/manifest.json"] = [[{"id":"broken_speed","name":"Broken Speed",
    "version":"1.0.0","api":3,"entry":"main.lua"}]],
  ["mods/broken_speed/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("core.logic_speed", function() return 200 end)
    error("intentional speed entry failure")
  ]],
}
local failed = T.sdk.loadMods({ "mods/broken_speed" }, { fs = T.sdk.memfs(files), data = T.fixtures.fresh() })
T.check(#failed.errors > 0, "failed entry is reported")
T.eq(Runtime.wantsHook("core.logic_speed"), false, "entry rollback removes speed hook")
Loader.teardown()
T.eq(Runtime.wantsHook("core.logic_speed"), false, "teardown removes speed hook")
failed.release()
Version.set(originalVersion)
T.finish("core.logic_speed routing")
