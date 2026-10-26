package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.critical_kinds").run(".", "gen2", version)
end
local T = require("tests.modkit")
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  require("src.core.GameVersion").set(version)
  local calls = 0
  local result = require("src.battle.Gen3Critical").roll(
    { firstBattle = true, firstBattleKind = "birch", wallyTutorial = true, pokedudeDemo = {} },
    function()
      calls = calls + 1
      return true
    end
  )
  T.eq(result, true, version .. " retains the ordinary critical result")
  T.eq(calls, 1, version .. " retains its ordinary random draw")
end
require("tests.modkit").finish("native GBA critical battle context")
