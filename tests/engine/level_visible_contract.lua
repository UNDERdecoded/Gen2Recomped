package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/level_visible/fixture.lua")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Display = require("src.ui.LevelDisplay")
local Capabilities = require("src.mods.Capabilities")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  local supported = Version.generation(version) <= 3
  T.eq(
    Capabilities.supports("hooks", "pokemon.level_visible", version),
    supported,
    version .. " native capability"
  )
  if supported then
    for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
      local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
      dofile("tests/level_visible/native.lua").run(f)
      dofile("tests/level_visible/cases.lua").run(f)
      f.close()
    end
    local f = Fixture.new(".", "gen2", version, 3, "unified", true)
    local calls = 0
    f.patch(Runtime, "call", function()
      calls = calls + 1
    end)
    local opaque = setmetatable({}, {
      __index = function()
        error("no-mod path touched mon")
      end,
    })
    T.eq(Display.visible(opaque, "party", opaque), true, "unsubscribed default")
    T.eq(calls, 0, "no-mod hot path skips dispatch and record adaptation")
    f.close()
  end
end
Version.set(originalVersion)
T.finish("pokemon.level_visible capability and SDK modes")
