-- Real host decision entry points must learn before running membership queries.
local T = require("tests.modkit")
local AI = require("src.battle.Gen3AI")
local K = require("src.battle.Gen3AIMoveKnowledge")
for _, version in ipairs({ "firered", "emerald" }) do
  require("src.core.GameVersion").set(version)
  local moves = { { id = "TACKLE", pp = 10 }, { id = "FLY", pp = 10 } }
  local battle = {
    trainer = { aiFlags = 1 },
    data = {
      moves = {
        TACKLE = { index = 33 },
        FLY = { index = 19 },
        PROTECT = { index = 182 },
      },
      constants = {
        gen3BattleAI = {
          entries = { [0] = 1 },
          code = {
            { name = "if_has_move", args = { 0, 33, 3 }, next = 2 },
            { name = "end", args = {} },
            { name = "if_move", args = { 33, 5 }, next = 4 },
            { name = "end", args = {} },
            { name = "score", args = { 5 }, next = 6 },
            { name = "end", args = {} },
          },
        },
      },
    },
    rng = function()
      error("knowledge must not need a random draw")
    end,
  }
  local user = { mon = {}, position = 1 }
  local target = { position = 0, mon = {}, curMoves = moves, lastMove = "TACKLE" }
  local chosen = AI.chooseMove(battle, user, target, moves)
  T.eq(chosen, moves[1], version .. " ordinary chooser learns before querying")
  T.eq(battle._aiHistory ~= nil, version == "emerald", version .. " history is Emerald only")
  if version == "emerald" then
    T.eq(K.usedMoves(battle, target)[1], 33, "ordinary chooser records last move")
    -- Reusing the field slot for a distinct party member must hide old knowledge.
    target.mon, target.lastMove, target.curMoves = {}, nil, { { id = "FLY", pp = 10 } }
    T.eq(AI.chooseMove(battle, user, target, moves), nil, "switch does not inherit old move knowledge")
    T.eq(K.usedMoves(battle, target)[1], 0, "new occupant starts unobserved")
    target.lastMove = 19
    AI.chooseMove(battle, user, target, moves)
    T.eq(K.usedMoves(battle, target)[1], 19, "numeric move learns on the new occupant")
    local right = { position = 2, mon = {}, lastMove = "PROTECT", curMoves = {} }
    AI.chooseAction(battle, user, moves, { target, right })
    T.eq(K.usedMoves(battle, right)[1], 182, "double chooser records right target separately")
    T.eq(K.usedMoves(battle, target)[1], 19, "right target cannot overwrite left history")
    K.observe(battle, nil)
  end
end
