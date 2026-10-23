package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Fixture, Cases = dofile("tests/item_use/fixture.lua"), dofile("tests/item_use/cases.lua")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local gen, api = Version.generation(), f.e.api
    T.eq(api:supports("hooks", "item.use"), gen == 1, "GB producer availability is honest")
    if gen == 1 then
      Cases.run(f)
    else
      -- Registration is legal in API 3, but the GB-shaped producer must
      -- never run on GBA's different field tuple contract or DS screens.
      local calls = 0
      local off = api.hooks:wrap("item.use", function()
        calls = calls + 1
      end)
      f.begin("REPEL", false)
      T.eq(calls, 0, "unavailable host never dispatches GB item signature")
      T.eq(f.count("REPEL"), 2, "unsupported hosts retain native item flow")
      off()
    end
    f.close()
    local failed = Fixture.new(".", "gen2", version, mode[1], mode[2], false, true)
    T.check(#failed.result.errors > 0, "failed entry is recorded")
    for _, entry in ipairs(Runtime.hooks.chains["item.use"] or {}) do
      T.check(entry.owner ~= "portable_item_use", "rollback removes owned item wrapper")
    end
    failed.close()
  end
end
for _, mode in ipairs({ { 2, "unified" }, { 3, "unified" } }) do
  local f = Fixture.new(".", "gen2", "red", mode[1], mode[2], false, false, true)
  f.e.state.mode = "block"
  f.begin("ITEM_777", false)
  f.target()
  T.eq(f.e.state.item, "POTION", "native alias is canonical at the shared item-ID slot")
  T.eq(f.count("ITEM_777"), 3, "canonical block leaves native inventory unchanged")
  f.e.state.mode = "native"
  f.begin("ITEM_777", false)
  f.target()
  T.eq(f.count("ITEM_777"), 2, "next restores native alias before item use")
  T.eq(f.game.save.inventory.POTION, nil, "next never invents a canonical inventory key")
  f.close()
end
Version.set(old)
T.finish("portable native GB item dispatch")
