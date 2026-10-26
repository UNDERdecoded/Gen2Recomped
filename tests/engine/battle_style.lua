package.path = "./?.lua;./?/init.lua;" .. package.path
local F = dofile("tests/battle_style/fixture.lua")
local f = F.new(".", "red", 2, "native")
dofile("tests/battle_style/cases.lua").run(f)
f.close()
local noMod = F.new(".", "red", 2, "native", true)
local b, save = noMod.battle(nil)
local T = noMod.T
T.eq(b:battleStyle(), "shift", "no option defaults to shift without mods")
T.eq(save.options.battleStyle, nil, "default query does not persist an option")
T.eq(noMod.faint(b), true, "native no-mod default still offers shift")
noMod.close()
local owner = F.new(".", "red", 2, "native")
local rawBattle = owner.battle("shift")
local seen, argumentCount
local peer = owner.run.loader.hooks:wrap("battle.style", function(next, ...)
  argumentCount = select("#", ...)
  seen = ...
  return next(...)
end, -10, "style_peer")
T.eq(rawBattle:battleStyle(), "shift", "peer forwards stored decision")
T.eq(seen, rawBattle, "native callback receives the actual battle identity")
T.eq(argumentCount, 1, "native callback receives exactly one battle argument")
local high = owner.run.loader.hooks:wrap("battle.style", function()
  return "set"
end, 100, "style_high")
T.eq(owner.faint(rawBattle), false, "priority override steers actual trainer send-out")
T.eq(rawBattle.game.save.options.battleStyle, "shift", "priority override keeps persisted preference")
high()
owner.run.loader.hooks:removeOwner("portable_battle_style")
seen = nil
T.eq(rawBattle:battleStyle(), "shift", "removing owner restores stored choice")
T.eq(seen, rawBattle, "removing owner retains a different owner's wrapper")
peer()
owner.close()

local other = F.new(".", "gold", 2, "native", true)
local foreignCalls = 0
local off = other.run.loader.hooks:wrap("battle.style", function()
  foreignCalls = foreignCalls + 1
  return "set"
end, 0, "style_non_gen1")
local gold = other.battle("shift")
T.eq(gold:battleStyle(), "shift", "shared host controller keeps Gen2 native option")
T.eq(other.faint(gold), true, "Gen2 shared controller does not adopt the Gen1 override")
T.eq(foreignCalls, 0, "no unsupported Gen2 producer is dispatched")
off()
other.close()
require("src.core.GameVersion").set("red")

local broken = T.sdk.loadMods({ "mods/broken_style" }, {
  data = T.fixtures.fresh(),
  fs = T.sdk.memfs({
    ["mods/broken_style/manifest.json"] = [[{"id":"broken_style","name":"Broken Style","version":"1.0.0","api":2,"entry":"main.lua"}]],
    ["mods/broken_style/main.lua"] = [[
      local mod = ...
      mod.hooks:wrap("battle.style", function() return "set" end)
      error("intentional style entry failure")
    ]],
  }),
})
T.check(#broken.errors > 0, "failed entry is reported")
T.eq(
  require("src.mods.Runtime").wantsHook("battle.style"),
  false,
  "failed entry rolls back its decision wrapper"
)
T.eq(rawBattle:battleStyle(), "shift", "failed entry preserves actual stored decision")
broken.release()
T.finish("portable battle style")
