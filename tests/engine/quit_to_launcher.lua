package.path = "./?.lua;./?/init.lua;" .. package.path
local F = dofile("tests/quit_to_launcher/fixture.lua")
local f = F.new(".", "red", 2, "native")
dofile("tests/quit_to_launcher/cases.lua").run(f)
f.close()
local T = f.T
local Runtime = require("src.mods.Runtime")
local bridge = require("src.core.PlatformHooks")
local owner = F.new(".", "red", 2, "native")
local peerCalls = 0
local off = owner.result.loader.hooks:wrap("core.quit_to_launcher", function(next)
  peerCalls = peerCalls + 1
  return next()
end, 5, "another_owner")
owner.result.loader.hooks:removeOwner("portable_quit")
T.eq(
  bridge.quitToLauncher(function()
    return true
  end),
  true,
  "owner removal retains native decision"
)
T.eq(owner.exports.calls(), 0, "removed owner no longer participates")
T.eq(peerCalls, 1, "owner removal preserves peer wrapper")
off()
owner.close()
local failed = T.sdk.loadMods({ "mods/broken_quit" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs({
    ["mods/broken_quit/manifest.json"] = [[{"id":"broken_quit","name":"Broken Quit","version":"1.0.0","api":2,"entry":"main.lua"}]],
    ["mods/broken_quit/main.lua"] = [[
      local mod = ...
      mod.hooks:wrap("core.quit_to_launcher", function() return true end)
      error("intentional quit entry failure")
    ]],
  }),
})
T.check(#failed.errors > 0, "entry failure is reported")
T.eq(Runtime.wantsHook("core.quit_to_launcher"), false, "entry rollback removes quit wrapper")
local calls = 0
T.eq(
  bridge.quitToLauncher(function()
    calls = calls + 1
    return false
  end),
  false,
  "rollback retains process-exit decision"
)
T.eq(calls, 1, "rollback runs native decision once")
failed.release()
f.T.finish("portable quit decision")
