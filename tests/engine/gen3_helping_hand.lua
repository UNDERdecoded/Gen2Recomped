package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.helping_hand").run(".", "gen2", version)
end
local V, H = require("src.core.GameVersion"), require("src.battle.Gen3HelpingHand")
local previous = V.get()
for _, version in ipairs({ "red", "gold", "platinum", "black" }) do
  V.set(version)
  local partner, user = { mon = { hp = 100 } }, { _gen3HelpingHand = true }
  H.apply({
    partnerOf = function()
      return partner
    end,
  }, user)
  T.eq(partner._gen3HelpingHand, nil, version .. " does not produce GBA support")
  T.eq(H.damage(user, 11), 11, version .. " ignores GBA support state")
end
V.set(previous)
T.finish("native GBA Helping Hand")
