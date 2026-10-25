package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/substitute_presentation.lua").run(".", "gen2", version)
  T.eq(#rows, 180, "every actor/options/command input executes")
  for _, row in ipairs(rows) do
    local last = row.frames[#row.frames]
    T.check(last.done, "native controller returns to the actual battle queue")
    T.eq(last.offset, 0, "controller finishes at the original battler coordinate")
    local initialHP = row.frames[1].substituteHP
    for _, frame in ipairs(row.frames) do
      T.eq(frame.substituteHP, initialHP, "sprite exchange never removes gameplay protection")
    end
    local allowed = row.scene or row.move == 144 or row.move == 164
    local plays = allowed and (row.case == "lower" or row.case == "restore")
    if plays then
      local x = row.double and ({ 32, 200, 90, 152 })[row.actor + 1] or (row.actor == 0 and 72 or 176)
      local outward = row.actor % 2 == 0 and math.floor((x + 32) / 5) + 1
        or math.floor((304 - x - 32) / 5) + 1
      T.eq(last.tick, outward * 2 + 1, "offscreen swap uses its native outward/exchange/return ticks")
    else
      T.eq(last.tick, 0, "skipped controller command adds no waiting tick")
    end
  end
end
local V = require("src.core.GameVersion")
local B = require("src.battle.BattleState")
local P = require("src.battle.Gen3SubstitutePresentation")
local animation, trailing = { anim = "MOVE_033", attackerPosition = 0 }, { fn = function() end }
local sparse = { queue = { [1] = animation, [3] = trailing }, nextInsert = 1, _gbaMoveFrame = {} }
P.mark(sparse, animation, { substituteHP = 100 })
P.finish(sparse, sparse._gbaMoveFrame)
T.eq(sparse.queue[1].anim, "SUBSTITUTE_TO_MON", "sparse queue retains native lowering")
T.eq(sparse.queue[2], animation, "sparse queue retains original animation identity")
T.eq(sparse.queue[3].anim, "MON_TO_SUBSTITUTE", "sparse queue retains native restoration")
T.eq(sparse.queue[4], nil, "sparse queue preserves its original hole")
T.eq(sparse.queue[5], trailing, "sparse queue preserves trailing callback identity")
local user = { isPlayer = true, position = 0, substituteHP = 100, mon = { species = "FIX", hp = 400 } }
local battle = setmetatable({
  player = user,
  data = {
    moves = { MOVE_033 = { index = 33 } },
    constants = { gen3BattlerCoords = { singles = { { x = 72, y = 80 }, { x = 176, y = 40 } } } },
    pokemon = { FIX = { backPicCoords = { yOffset = 8 } } },
  },
  game = { save = { options = { animations = true } } },
  queue = {},
}, B)
local row = { anim = "SUBSTITUTE_TO_MON", gbaSubstituteMove = "MOVE_033", attackerIsPlayer = true }
T.check(P.start(battle, row), "native transition starts on the real battle controller")
for _ = 1, 43 do
  P.update(battle)
end
T.eq(battle:substituteVisible(user), false, "lowered sprite shows the Pokemon with protection retained")
T.eq(user.substituteHP, 100, "lowering does not mutate Substitute HP")
local animator = setmetatable({ data = battle.data }, require("src.battle.Gen3MoveAnim"))
T.eq(animator:battlerOamY(battle, user), 56, "lowered Pokemon uses its native species OAM Y")
T.eq(battle:updateQueue(), false, "empty actual battle queue completes")
T.eq(battle._gbaSubstitutePresentation, nil, "queue completion releases transient presentation state")
T.eq(battle:substituteVisible(user), true, "completion reconciles the doll with real protection")
T.eq(animator:battlerOamY(battle, user), 65, "restored doll uses native Substitute OAM Y")
V.set("red")
T.eq(P.start(battle, row), false, "GBA controller commands cannot alter legacy battles")
T.eq(battle._gbaSubstituteTransition, nil, "legacy forwarding leaves no transition")
user.substituteHP = false
T.eq(battle:substituteVisible(user), false, "legacy false protection remains hidden")
T.finish("native GBA Substitute controller presentation")
