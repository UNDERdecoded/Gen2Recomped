package.path = "./?.lua;./?/init.lua;" .. package.path
local F = dofile("tests/catch_nickname/fixture.lua")
local f = F.new(".", "red", 2, "native")
dofile("tests/catch_nickname/cases.lua").run(f)
f.close()
local native = F.new(".", "red", 2, "native", true)
local T = native.T
local r = native.capture("party")
T.eq(#r.ui, 1, "no-mod party catch retains nickname prompt")
T.eq(r.stored, r.caught, "no-mod recipient remains original mon")
native.close()
local owner = F.new(".", "red", 2, "native")
local seen, context, argumentCount
local peer = owner.run.loader.hooks:wrap("catch.nickname", function(next, ...)
  argumentCount = select("#", ...)
  seen, context = ...
  return next(...)
end, 50, "peer_nickname")
local actual = owner.capture("box")
T.eq(argumentCount, 2, "native hook receives exactly mon and context")
T.eq(seen, actual.caught, "native hook receives original PC recipient")
T.eq(context and context.battle, actual.battle, "native context preserves battle identity")
T.eq(context and context.game, actual.battle.game, "native context preserves game identity")
local high = owner.run.loader.hooks:wrap("catch.nickname", function()
  return "PRIORITY"
end, 100, "high_nickname")
actual = owner.capture("party")
T.eq(actual.stored.nickname, "PRIORITY", "priority wrapper controls actual party catch")
T.eq(#actual.ui, 0, "priority wrapper bypasses native naming UI")
high()
owner.run.loader.hooks:removeOwner("portable_catch_nickname")
seen = nil
actual = owner.capture("party")
T.eq(seen, actual.caught, "owner removal preserves unrelated wrapper")
T.eq(#actual.ui, 1, "owner removal restores native AskName")
peer()
owner.close()
local other = F.new(".", "gold", 2, "native", true)
local calls = 0
local off = other.run.loader.hooks:wrap("catch.nickname", function()
  calls = calls + 1
  return "FOREIGN"
end, 0, "unsupported_nickname")
r = other.capture("party")
T.eq(calls, 0, "Gen2 controller does not dispatch unsupported Gen1 hook")
T.eq(#r.ui, 1, "Gen2 controller keeps its existing native prompt")
T.eq(r.caught.nickname, nil, "Gen2 mon is not renamed by unsupported hook")
off()
other.close()
require("src.core.GameVersion").set("red")
local failed = T.sdk.loadMods({ "mods/broken_nickname" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs({
    ["mods/broken_nickname/manifest.json"] = [[{"id":"broken_nickname","name":"Broken Nickname","version":"1.0.0","api":2,"entry":"main.lua"}]],
    ["mods/broken_nickname/main.lua"] = [[
      local mod = ...
      mod.hooks:wrap("catch.nickname", function() return "LEAKED" end)
      error("intentional nickname entry failure")
    ]],
  }),
})
T.check(#failed.errors > 0, "failed nickname entry is reported")
T.eq(
  require("src.mods.Runtime").wantsHook("catch.nickname"),
  false,
  "failed entry removes its nickname wrapper"
)
failed.release()
T.finish("portable catch nickname")
