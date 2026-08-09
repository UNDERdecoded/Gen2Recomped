-- Driver: the black pause between the battle wipe and the battle screen (#315).
-- Shrink and Split end with BattleTransition_BlackScreen then DelayFrames 10
-- (engine/battle/battle_transitions.asm:390-392, 422-424); the other six get
-- the same gap free from the load the original hides behind.  BLACK_HOLD in
-- src/render/BattleTransition.lua is the knob.  Not under POKEPORT_SPEED.
--   POKEPORT_DRIVER=tests/drivers/battle_transition_hold_bug315_test.lua SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local BattleTransition = require("src.render.BattleTransition")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- BLACK_HOLD is a file-local, so this is the driver's own copy of it
  local TARGET = 30

  game.save.player.name = "bryan"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(20)
  local ow = game.overworld
  check("overworld is up to push the battle from", ow ~= nil)

  -- ---- measure the hold --------------------------------------------------
  -- No screenshots in this pass: U.shot spins frames of its own and would
  -- corrupt the count.
  local function measure(opts)
    local battle = BattleState.newWild(game, "PIDGEY", 8)
    battle.onFinish = function() end
    ow:pushBattle(battle)
    local tr = game.stack:top()
    if getmetatable(tr) ~= BattleTransition then return nil, "no transition" end
    local style, wipeLen = tr.style, tr.wipeLen
    local f, wipeDone, popped = 0, nil, nil
    while f < 600 do
      f = f + 1
      if not wipeDone and tr.phase == "wipe" and tr.t >= wipeLen then
        wipeDone = f
      end
      if game.stack:top() ~= tr then popped = f break end
      U.wait(1)
    end
    return { style = style, wipeLen = wipeLen, wipeDone = wipeDone,
             popped = popped, battle = battle, tr = tr }, nil
  end

  local m, err = measure()
  check("a BattleTransition was pushed for the battle", m ~= nil)
  if not m then
    U.log("could not measure:", tostring(err))
    while true do coroutine.yield() end
  end
  U.log(("style %s: wipe is %d frames"):format(tostring(m.style), m.wipeLen))
  check("the wipe reached its last frame", m.wipeDone ~= nil)
  check("the transition popped itself", m.popped ~= nil)
  local hold = (m.wipeDone and m.popped) and (m.popped - m.wipeDone) or -1
  U.log(("black hold measured: %d frames (%.2f s at 60 Hz); target %d")
          :format(hold, hold / 60, TARGET))
  check(("the screen holds black well past the old 6 frames (got %d) (#315)")
          :format(hold), hold >= 20)
  check(("the hold is not absurdly long either (got %d)"):format(hold),
        hold <= 90)

  -- unwind that battle before the next one
  while game.stack:top() ~= ow do game.stack:pop() end
  U.wait(10)

  -- ---- screenshot the beat ------------------------------------------------
  -- One frame inside the hold (solid black edge to edge) and one after the pop.
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  local tr = game.stack:top()
  check("second transition pushed", getmetatable(tr) == BattleTransition)
  for _ = 1, 600 do
    if tr.phase == "wipe" and tr.t >= tr.wipeLen then break end
    U.wait(1)
  end
  check("hold screenshot reached disk",
        U.shot(game, DIR .. "/bug315_black_hold.png"))
  U.log("captured", DIR .. "/bug315_black_hold.png",
        "-- this one must be SOLID BLACK")
  for _ = 1, 300 do
    if game.stack:top() ~= tr then break end
    U.wait(1)
  end
  U.wait(2)
  check("post-hold screenshot reached disk",
        U.shot(game, DIR .. "/bug315_battle_appears.png"))
  U.log("captured", DIR .. "/bug315_battle_appears.png")

  -- back to the overworld and into tall grass, so the hand-off is a real
  -- encounter rather than a scripted push
  while game.stack:top() ~= ow do game.stack:pop() end
  U.wait(10)

  -- Grass cell comes off the loaded map, not a hard-coded pair, so a map edit
  -- degrades to "somewhere else in the grass" instead of a wall.
  local map = ow.map
  local gx, gy
  for cy = 0, map.heightCells - 1 do
    for cx = 0, map.widthCells - 1 do
      if map:isGrassCell(cx, cy) and map:isWalkableCell(cx, cy)
         and map:isWalkableCell(cx, cy + 1) then
        gx, gy = cx, cy
        break
      end
    end
    if gx then break end
  end
  check("found a tall-grass cell on ROUTE_1 to hand off in", gx ~= nil)
  if gx then
    U.log(("standing in the grass at (%d, %d)"):format(gx, gy))
    U.teleport(game, "ROUTE_1", gx, gy, "down")
    U.wait(10)
  end

  -- ---- hand off, then stay out of the way --------------------------------
  U.log("You are in the tall grass on ROUTE 1. Walk until an encounter fires and")
  U.log("watch the join: the wipe should finish, the screen sit solid black for")
  U.log(("about half a second (%d frames this run), and only then the battle")
          :format(hold))
  U.log("screen appear (#315). Wipe style varies, so try it a few times.")

  while true do
    coroutine.yield()
  end
end
