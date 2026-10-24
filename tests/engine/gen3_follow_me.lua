package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.follow_me").run(".", "gen2", version)
end
local V = require("src.core.GameVersion")
local F = require("src.battle.Gen3FollowMe")
local previous = V.get()
for _, version in ipairs({ "red", "gold", "platinum", "black" }) do
  V.set(version)
  local user = { isPlayer = true }
  local battle = { player = user, sides = { {}, { _gen3FollowMePosition = 1 } } }
  T.eq(F.center(battle, user), nil, version .. " ignores GBA targeting state")
  F.apply(battle, user)
  T.eq(battle.sides[1]._gen3FollowMePosition, nil, version .. " does not produce GBA state")
end
V.set(previous)
T.finish("native GBA Follow Me")
