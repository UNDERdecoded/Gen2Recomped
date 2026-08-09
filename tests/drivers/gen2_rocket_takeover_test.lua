-- VAR_BADGES (readvar 7) and the Rocket takeover it gates.
--
-- Every Gen2 gym leader signs off with
--     setflag ENGINE_<X>BADGE / readvar 7 / scall <Gym>ActivateRockets
-- and <Gym>ActivateRockets is
--     ifequal 6, .GoldenrodRockets     ; jumpstd goldenrodrockets
--     ifequal 7, .RadioTowerRockets    ; jumpstd radiotowerrockets
--
-- RadioTowerRocketsScript (40:$41DC) is what sets ENGINE_ROCKETS_IN_RADIO_TOWER
-- (engine flag 18), flips Mahogany Town to scene 1 and arms
-- `specialphonecall 4` -- Elm's "the Radio Tower has been taken over" call.
--
-- readvar 7 used to count a `save.badges` table that nothing writes (Gen2
-- badges are ENGINE flags, so Flags puts them in save.flags under the badge
-- id), so it always answered 0: beating Pryce armed nothing, Elm never rang
-- and the Goldenrod Rocket event never started.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL", what) end
  end

  U.newGame(game)
  U.wait(10)

  local Commands = require("src.script.Commands")
  local Gen2Commands = require("src.script.Gen2Commands")
  local Flags = require("src.script.Flags")
  local Badges = require("src.inventory.Badges")
  local VM = require("src.script.Gen2ScriptVM")
  local ScriptRunner = require("src.script.ScriptRunner")

  local JOHTO = { "ZEPHYRBADGE", "HIVEBADGE", "PLAINBADGE", "FOGBADGE",
                  "MINERALBADGE", "STORMBADGE", "GLACIERBADGE", "RISINGBADGE" }

  -- 1. the badge list the count walks really is Gold's sixteen
  local list = Badges.list(game.data)
  ok(#list == 16, ("the Gen2 badge list has 16 entries (got %d)"):format(#list))
  local ids = {}
  for _, e in ipairs(list) do ids[e.id] = true end
  for _, id in ipairs(JOHTO) do ok(ids[id], id .. " is in the badge list") end

  -- 2. readvar 7 counts the ENGINE badge flags the gyms actually set
  local ctx = { game = game, save = game.save }
  for _, id in ipairs(JOHTO) do Flags.clear(game.save, id) end
  Commands.g2_readvar(ctx, 7)
  ok(ctx.g2Var == 0, "no badges -> 0")
  for i = 1, 6 do Flags.set(game.save, JOHTO[i]) end
  Commands.g2_readvar(ctx, 7)
  ok(ctx.g2Var == 6, ("six badges -> 6 (got %s)"):format(tostring(ctx.g2Var)))
  Flags.set(game.save, JOHTO[7])
  Commands.g2_readvar(ctx, 7)
  ok(ctx.g2Var == 7, ("GLACIERBADGE makes seven (got %s)"):format(tostring(ctx.g2Var)))
  Flags.set(game.save, "BOULDERBADGE")
  Commands.g2_readvar(ctx, 7)
  ok(ctx.g2Var == 8, "CountBadges spans both badge bytes")
  Flags.clear(game.save, "BOULDERBADGE")

  -- 3. MahoganyGymActivateRockets still has the shape the count feeds
  local rows = VM.compile(game.data, "S51_53C6")
  local sawSeven, sawSix = false, false
  for _, row in ipairs(rows or {}) do
    if row[1] == "g2_compare" and row[3] == 7 then sawSeven = true end
    if row[1] == "g2_compare" and row[3] == 6 then sawSix = true end
  end
  ok(sawSeven, "MahoganyGymActivateRockets branches on seven badges")
  ok(sawSix, "...and on six")

  -- 4. run it with wScriptVar from readvar 7, exactly as Pryce's script does
  local ow = { map = { id = "MAHOGANY_GYM", def = {} }, npcs = {}, entities = {} }
  local function activate()
    -- Pryce's script is `readvar 7 / scall ...`, so wScriptVar is already
    -- loaded when the callee starts.  ScriptRunner:run executes straight
    -- through to the first yield, so seed it via the context extras.
    local probe = { game = game, save = game.save }
    Commands.g2_readvar(probe, 7)
    local runner = ScriptRunner.new(game, ow)
    runner:run(rows, { npc = { def = {} }, g2Var = probe.g2Var })
    for _ = 1, 200 do
      if not runner:isRunning() then break end
      U.wait(2)
      runner:update()
    end
    return runner.ctx
  end

  game.save.g2SpecialCall = nil
  Flags.clear(game.save, "FLAG_G2_0018")
  Flags.clear(game.save, "EVENT_G2_1878")
  activate()
  ok(Flags.get(game.save, "FLAG_G2_0018"),
     "seven badges set ENGINE_ROCKETS_IN_RADIO_TOWER (engine flag 18)")
  ok(Flags.get(game.save, "EVENT_G2_1878"), "...and the takeover event")
  ok(game.save.g2SpecialCall == 4, "...and armed specialphonecall 4 (Elm)")

  -- 5. the armed call resolves to a real caller + script, and only outdoors
  ok(Gen2Commands.pendingSpecialCall(game.data, game.save, false) == nil,
     "SpecialCallOnlyWhenOutside keeps Elm quiet indoors")
  local caller, script = Gen2Commands.pendingSpecialCall(game.data, game.save, true)
  ok(caller ~= nil, "outdoors the call has a caller")
  ok(type(script) == "table" and #script > 0, "...and a compiled script")

  -- 6. six badges takes the Goldenrod branch instead, and arms no call
  Flags.clear(game.save, JOHTO[7])
  game.save.g2SpecialCall = nil
  Flags.clear(game.save, "FLAG_G2_0018")
  activate()
  ok(not Flags.get(game.save, "FLAG_G2_0018"),
     "six badges do not take over the Radio Tower")
  ok(game.save.g2SpecialCall == nil, "six badges ring nobody")

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
