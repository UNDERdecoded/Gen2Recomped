package.path = "./?.lua;./?/init.lua;" .. package.path
local F = dofile("tests/catch_party_full/fixture.lua")
local f = F.new(".", "red", 2, "native")
dofile("tests/catch_party_full/cases.lua").run(f)
f.close()
local native = F.new(".", "red", 2, "native", true)
local T = native.T
local r = native.capture("box")
T.eq(r.event.destination, "box", "no-mod full party uses PC")
T.eq(r.stored, r.caught, "no-mod PC keeps original mon")
T.eq(#r.ui, 1, "no-mod PC queues naming prompt")
native.close()
local owner = F.new(".", "red", 2, "native")
local seen, argc
local peer = owner.run.loader.hooks:wrap("catch.party_full", function(next, ...)
  argc, seen = select("#", ...), ...
  return next(...)
end, 50, "peer_custody")
owner.exports.set(true)
r = owner.capture("box")
T.eq(argc, 1, "native hook takes exactly one context")
T.eq(seen and seen.mon, r.caught, "native context holds original caught mon")
T.eq(seen and seen.battle, r.battle, "native context preserves battle identity")
T.eq(seen and seen.game, r.battle.game, "native context preserves game identity")
T.eq(owner.exports.custody[1], r.caught, "API2 native custody retains original mon")
local high = owner.run.loader.hooks:wrap("catch.party_full", function()
  return false
end, 100, "veto_custody")
r = owner.capture("box")
T.eq(r.event.destination, "box", "higher priority fallback controls actual catch")
high()
owner.run.loader.hooks:removeOwner("portable_catch_party_full")
seen = nil
r = owner.capture("box")
T.eq(seen and seen.mon, r.caught, "owner removal preserves unrelated wrapper")
T.eq(r.event.destination, "box", "owner removal restores PC")
peer()
owner.close()
for _, version in ipairs({ "gold", "firered", "emerald" }) do
  local other = F.new(".", version, 2, "native", true)
  local calls = 0
  local off = other.run.loader.hooks:wrap("catch.party_full", function()
    calls = calls + 1
    return true
  end, 0, "foreign_custody")
  r = other.capture("box")
  T.eq(calls, 0, "unsupported generation does not dispatch Gen1 custody hook")
  T.eq(r.event.destination, "box", "unsupported generation retains native PC")
  T.eq(r.stored, r.caught, "unsupported generation preserves native recipient")
  off()
  other.close()
end
require("src.core.GameVersion").set("red")
local failed = T.sdk.loadMods({ "mods/broken_custody" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs({
    ["mods/broken_custody/manifest.json"] = [[{"id":"broken_custody","name":"Broken Custody","version":"1.0.0","api":2,"entry":"main.lua"}]],
    ["mods/broken_custody/main.lua"] = [[local mod = ...; mod.hooks:wrap("catch.party_full", function() return true end); error("intentional custody entry failure")]],
  }),
})
T.check(#failed.errors > 0, "failed custody entry is reported")
T.eq(require("src.mods.Runtime").wantsHook("catch.party_full"), false, "failed entry removes custody wrapper")
failed.release()
T.finish("portable party-full catch")
