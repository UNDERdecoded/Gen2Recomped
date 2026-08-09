-- Mahogany Rocket Hideout Electrodes (RocketElectrode1/2/3, 45:$4DB9,
-- $4DE4, $4E0F).  Each is
--
--     cry ELECTRODE / loadwildmon ELECTRODE, 23 / startbattle
--     iftrue .done            ; <- 09 3A 4E
--     disappear <n> / disappear <n+3>
--     checkevent EVENT_..._ELECTRODE_1..3 / iffalse .done  x3
--     reloadmapafterbattle / special $3B / applymovement PLAYER ...
--   .done
--     reloadmapafterbattle / end
--
-- Script_startbattle leaves `wBattleResult and $3f` in wScriptVar (0 WIN,
-- 1 LOSE, 2 DRAW-when-nobody-won), and `iftrue` reads that same wScriptVar,
-- so after a Gen2 startbattle it means "did NOT win".  Commands.start_battle
-- set lastCheck the Gen 1 way (`result == "win"`), i.e. exactly inverted:
-- running from an Electrode made it vanish and beating one left it standing.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL", what) end
  end

  U.newGame(game)
  U.wait(10)

  local Commands = require("src.script.Commands")
  local VM = require("src.script.Gen2ScriptVM")
  local ScriptRunner = require("src.script.ScriptRunner")
  require("src.script.Gen2Commands")

  -- 1. the lowering still matches the ROM shape the fix depends on
  local rows = VM.compile(game.data, "S45_4DB9")
  ok(rows and #rows > 0, "RocketElectrode1 compiles")
  local function nameAt(i) return rows[i] and rows[i][1] end
  local battleAt
  for i, row in ipairs(rows or {}) do
    if row[1] == "g2_start_battle" then battleAt = i break end
  end
  ok(battleAt ~= nil, "RocketElectrode1 starts a battle")
  ok(nameAt(battleAt - 1) == "g2_load_wild", "the battle is a loaded wild mon")
  ok(rows[battleAt - 1][2] == "SPECIES_101", "the wild mon is ELECTRODE")
  ok(rows[battleAt - 1][3] == 23, "the ELECTRODE is level 23")
  ok(nameAt(battleAt + 1) == "jump_if_true", "startbattle is followed by iftrue")
  local bail = rows[battleAt + 1][2]
  ok(nameAt(battleAt + 2) == "g2_object", "the fallthrough hides an object")
  ok(rows[battleAt + 2][3] == false, "...by disappearing it")

  -- 2. the result -> wScriptVar map (`ld a, [wBattleResult] / and $3f`)
  local map = Commands.G2_BATTLE_RESULT
  ok(type(map) == "table", "the battle-result map is exported")
  ok(map.win == 0, "WIN is 0")
  ok(map.caught == 0, "a caught mon reads as WIN (the catch bit is masked off)")
  ok(map.lose == 1, "LOSE is 1")
  ok(map.run == 2, "running is DRAW (2)")

  -- 3. drive g2_start_battle with each outcome.  Commands.start_battle is
  --    stubbed to do exactly what BattleState.onFinish does to the ctx.
  local realStart = Commands.start_battle
  local outcome = "win"
  local started
  Commands.start_battle = function(ctx, kind, a, b)
    started = { kind = kind, a = a, b = b }
    ctx.lastBattleResult = outcome
    ctx.lastCheck = outcome == "win"
  end

  local function fight(result)
    outcome = result
    local ctx = { game = game, save = game.save, g2Wild =
                  { species = "SPECIES_101", level = 23 } }
    Commands.g2_start_battle(ctx)
    return ctx
  end

  local won = fight("win")
  ok(started and started.kind == "wild", "a loaded wild mon starts a wild battle")
  ok(won.g2Var == 0, "a win leaves wScriptVar 0")
  ok(won.lastCheck == false, "a win does NOT take the iftrue bail-out")

  local caught = fight("caught")
  ok(caught.g2Var == 0, "catching leaves wScriptVar 0")
  ok(caught.lastCheck == false, "catching does not take the bail-out either")

  local ran = fight("run")
  ok(ran.g2Var == 2, "running leaves wScriptVar 2 (DRAW)")
  ok(ran.lastCheck == true, "running DOES take the iftrue bail-out")

  local lost = fight("lose")
  ok(lost.g2Var == 1, "a loss leaves wScriptVar 1")
  ok(lost.lastCheck == true, "a loss takes the bail-out")

  -- 4. the whole script, end to end: only a win may disappear the Electrode
  local ow = {
    map = { id = "TEAM_ROCKET_BASE_B2F", def = {} },
    npcs = {}, entities = {},
    afterBattle = function() end,
  }
  local function play(result)
    outcome = result
    local hidden, moved = {}, false
    local runner = ScriptRunner.new(game, ow)
    local realObject, realMove = Commands.g2_object, Commands.g2_move
    Commands.g2_object = function(_, id, show)
      if show == false then hidden[#hidden + 1] = id end
    end
    Commands.g2_move = function() moved = true end
    runner:run(rows, { npc = { def = {} } })
    for _ = 1, 200 do
      if not runner:isRunning() then break end
      U.wait(2)
      runner:update()
    end
    Commands.g2_object, Commands.g2_move = realObject, realMove
    return hidden, moved
  end

  local hidden = play("run")
  ok(#hidden == 0, "fleeing an Electrode leaves it on the map (the bug)")

  hidden = play("lose")
  ok(#hidden == 0, "losing to an Electrode leaves it on the map")

  hidden = play("win")
  ok(#hidden == 2, "beating one disappears both of its objects")
  ok(hidden[1] == 6 and hidden[2] == 9, "RocketElectrode1 hides objects 6 and 9")

  hidden = play("caught")
  ok(#hidden == 2, "catching one also clears it")

  -- 5. the other two Electrodes share the shape and the object pairs
  for label, ids in pairs({ S45_4DE4 = { 7, 10 }, S45_4E0F = { 8, 11 } }) do
    local r = VM.compile(game.data, label)
    local at
    for i, row in ipairs(r or {}) do
      if row[1] == "g2_start_battle" then at = i break end
    end
    ok(at and r[at + 1][1] == "jump_if_true", label .. " bails on a non-win")
    ok(at and r[at + 2][1] == "g2_object" and r[at + 2][2] == ids[1]
       and r[at + 3][2] == ids[2],
       ("%s hides objects %d and %d"):format(label, ids[1], ids[2]))
  end

  ok(type(bail) == "string", "the bail-out target is a label")

  Commands.start_battle = realStart

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
