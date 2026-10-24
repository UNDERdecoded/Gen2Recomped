package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Fixture, Cases = dofile("tests/encounter_table/fixture.lua"), dofile("tests/encounter_table/cases.lua")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local api = f.e.api
    T.eq(api:supports("hooks", "encounter.table"), f.generation <= 3, "honest native preview availability")
    local beforeTables = require("src.link.Json").encode(f.game.data.encounters)
    if f.generation <= 3 then
      Cases.run(f)
      local dispatched = 0
      local off = api.hooks:wrap("encounter.table", function()
        dispatched = dispatched + 1
        return { MEW = 1 }
      end)
      if mode[1] >= 3 then
        local calls = f.e.state.calls
        for _, bad in ipairs({ { daytime = "night" }, { unknown = true } }) do
          T.eq(f.e.preview("PROBE", "grass", bad), nil, "API-3 invalid options refused")
        end
        if f.generation ~= 2 then
          T.eq(f.e.preview("PROBE", "grass", { daytime = "DAY" }), nil, "API-3 time selection is Gold-only")
        end
        T.eq(dispatched, 0, "invalid API-3 query cannot invoke active preview hook")
      end
      -- Ordinary native rolls never acquire the preview-only table callback.
      f.e.state.mode = "replace"
      local calls = f.e.state.calls
      require("src.world.Encounter").load(f.game.data)
      local def = f.game.data.encounters.PROBE
      local result = require("src.world.Encounter").roll(def, function(lo)
        return lo
      end)
      T.check(result ~= nil and result.species ~= "MEW", "native chooser retains actual cartridge slots")
      T.eq(dispatched, 0, "native roll does not execute active preview seam")
      off()
    else
      local calls = 0
      local off = api.hooks:wrap("encounter.table", function()
        calls = calls + 1
        return { MEW = 1 }
      end)
      local out = require("src.world.WorldAPI").new(f.game, "probe"):effectiveEncounters("PROBE", "grass")
      T.check(out.dist.PIDGEY ~= nil, "DS retains native distribution")
      T.eq(calls, 0, "DS never dispatches unavailable preview seam")
      off()
    end
    T.eq(
      require("src.link.Json").encode(f.game.data.encounters),
      beforeTables,
      "query leaves native dataset unchanged"
    )
    f.close()
    if Version.generation() <= 3 then
      local empty = Fixture.new(".", "gen2", version, mode[1], mode[2], true)
      local before = require("src.link.Json").encode(empty.game.save)
      local out = assert(
        empty.nativeApi.world:effectiveEncounters(
          "PROBE",
          "grass",
          empty.generation == 2 and { daytime = "DAY" } or {}
        )
      )
      T.check(out.dist.PIDGEY ~= nil, "no-mod native preview")
      T.eq(require("src.link.Json").encode(empty.game.save), before, "no-mod query leaves save unchanged")
      empty.close()
    end
  end
end
-- Unregistered profiles must not silently run Red fixtures and masquerade as GBA.
for _, version in ipairs({ "leafgreen", "ruby", "sapphire" }) do
  T.eq(Version.VERSIONS[version], nil, "additional GBA ROM profile is not yet registered")
end
Version.set(old)
T.finish("native encounter.table preview and generation contracts")
