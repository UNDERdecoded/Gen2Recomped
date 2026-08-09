-- Manual check that the rival shoves Red off the EEVEE ball on the right
-- beat (#559).  pokeyellow scripts/OaksLab.asm: OaksLabChoseStarterScript
-- queues DOWN + RIGHT x3, and .asm_1c564 polls until wNPCNumScriptedSteps
-- reads 1 before it simulates the PAD_RIGHT x2 -- so the push starts as the
-- rival steps onto the player's own tile, not when he leaves the table.
-- No POKEPORT_SPEED: the whole point is which frame the player starts on.
-- No POKEPORT_IDENTITY either -- a sandbox save dir has no Yellow cache and
-- boots stale Red data underneath a Yellow-looking run.
--   POKEPORT_DRIVER=tests/drivers/eevee_shove_bug559_test.lua POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local MapScripts = require("src.script.MapScripts")
  local Commands = require("src.script.Commands")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function idle()
    while true do coroutine.yield() end
  end

  -- Red and Blue load data/scripts/oaks_lab.lua instead (three starter
  -- balls, no shove at all), so every line below would fail for the wrong
  -- reason on the Red cache.
  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    U.log("Yellow is the only version with an EEVEE ball. Re-run with")
    U.log("POKEPORT_VERSION=yellow.")
    idle()
  end

  -- pokeyellow data/maps/objects/OaksLab.asm: OAKSLAB_RIVAL (4,3),
  -- OAKSLAB_EEVEE_POKE_BALL (7,3), OAKSLAB_OAK1 (5,2).  The player talks to
  -- the ball from (7,4), and that y == 4 is what selects the shove branch
  -- in both the original (.asm_1c564 tests wYCoord) and the port.
  local MAP = "OAKS_LAB"
  local BALL = "OAKSLAB_EEVEE_POKE_BALL"
  local RIVAL_INDEX = 1
  local RIVAL_HOME = { x = 4, y = 3 }
  local STAND = { x = 7, y = 4, facing = "up" }

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  -- data/scripts/init.lua picks oaks_lab_yellow over oaks_lab on the Yellow
  -- cache; if the Red module won, the ball is one of three starters and
  -- nothing below means anything.  Asked after the teleport because the
  -- registry only fills when OverworldState first requires it.
  local labModule = require("data.scripts.oaks_lab_yellow")
  local bound = MapScripts.talkScript(MAP, "TEXT_OAKSLAB_EEVEE_POKE_BALL")
  U.log("the map dispatches a", type(bound), "for the ball")
  check("the Yellow ball handler is the one bound to the map",
        bound ~= nil and bound == labModule.talk.TEXT_OAKSLAB_EEVEE_POKE_BALL)

  local ow = game.overworld
  local ctx = { game = game, save = game.save, overworld = ow }

  local function npcNamed(name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- The scene the shove belongs to: Oak has asked the player to choose and
  -- the rival is still standing at the table.  Oak himself starts hidden on
  -- this map, so put him back the way OaksLabScript does before its speech.
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  game.save.flags.EVENT_GOT_STARTER = nil
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  Commands.show_object(ctx, MAP, "OAKSLAB_RIVAL")
  Commands.show_object(ctx, MAP, "OAKSLAB_OAK1")
  U.wait(2)

  local rival = ow:npcByIndex(RIVAL_INDEX)
  if rival and (rival.cellX ~= RIVAL_HOME.x or rival.cellY ~= RIVAL_HOME.y) then
    -- he wanders nowhere on this map (STAY), but a converted save can drop
    -- him mid-walk; pin him back on the table corner he starts from
    U.log("rival was at", rival.cellX, rival.cellY, "- pinning him to",
          RIVAL_HOME.x, RIVAL_HOME.y)
    Commands.place_npc(ctx, RIVAL_INDEX, RIVAL_HOME.x, RIVAL_HOME.y, "down")
  end
  if not check("the rival is on the map at (4,3)",
               rival ~= nil and rival.cellX == RIVAL_HOME.x
               and rival.cellY == RIVAL_HOME.y) then
    idle()
  end

  local ball = npcNamed(BALL)
  if not check("the EEVEE ball object is on the map", ball ~= nil) then
    U.log("Nothing to talk to. A save past EVENT_GOT_STARTER has already")
    U.log("hidden it, and this scene cannot be replayed on that save.")
    idle()
  end

  -- derive the talking cell from the ball rather than trusting (7,4): a
  -- later map edit degrades to another free neighbour instead of parking
  -- the player inside the table
  local DIRS = { { "up", 0, 1 }, { "down", 0, -1 },
                 { "left", 1, 0 }, { "right", -1, 0 } }
  local function facingBall()
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == ball
  end
  if not facingBall() then
    for _, d in ipairs(DIRS) do
      local cx, cy = ball.cellX + d[2], ball.cellY + d[3]
      if ow.map:inBounds(cx, cy) and ow.map:isWalkableCell(cx, cy)
         and not ow:npcAtCell(cx, cy) then
        U.log("standing at", cx, cy, "facing", d[1], "instead")
        U.teleport(game, MAP, cx, cy, d[1])
        U.wait(6)
        ow = game.overworld
        ctx.overworld = ow
        ball = npcNamed(BALL)
        rival = ow:npcByIndex(RIVAL_INDEX)
        break
      end
    end
  end
  check("player is facing the ball", facingBall())
  local p = ow.player
  U.log("player at", p.cellX, p.cellY, "facing", p.facing,
        "| rival at", rival.cellX, rival.cellY,
        "| ball at", ball.cellX, ball.cellY)
  -- y == 4 is the branch under test; from anywhere else both the original
  -- and the port just walk the rival over with no shove at all
  check("the player is on the row that triggers the shove (y == 4)",
        p.cellY == 4)

  if U.shot(game, SHOT_DIR .. "/bug559_before.png") then
    U.log("captured", SHOT_DIR .. "/bug559_before.png")
  end

  -- ---- talk to the ball and watch the two walks frame by frame ----
  U.tap(game, "a")

  local shoveFrame, rivalAtShove
  local trace, lastCell = {}, nil
  for f = 1, 900 do
    local cell = rival.cellX .. "," .. rival.cellY
    if cell ~= lastCell then
      lastCell = cell
      trace[#trace + 1] = "f" .. f .. " rival " .. cell
    end
    if not shoveFrame and ow.player.moving then
      shoveFrame = f
      rivalAtShove = { x = rival.cellX, y = rival.cellY }
    end
    if shoveFrame and not ow.player.moving and ow.player.cellX >= STAND.x + 2 then
      break
    end
    U.wait(1)
  end

  U.log("rival trace:", table.concat(trace, " | "))
  if not check("the player was pushed at all", shoveFrame ~= nil) then
    U.log("The rival's walk ran but nothing moved the player, so the scene")
    U.log("never reached move_player. Check the runner did not stall on the")
    U.log("emote row.")
    idle()
  end
  U.log("the push started on driver frame", shoveFrame, "with the rival at",
        rivalAtShove.x, rivalAtShove.y)

  -- The whole of #559: at the frame the player starts moving the rival must
  -- already be alongside him on row 4, one step from the tile he is being
  -- pushed off.  Before the fix both walks started together and the rival
  -- was still up at the table (4,3)/(4,4).
  check("the rival had reached row 4 before the push", rivalAtShove.y == 4)
  check("he was one step from the player's tile, not still at the table",
        rivalAtShove.x >= ball.cellX - 1)

  if U.shot(game, SHOT_DIR .. "/bug559_shove.png") then
    U.log("captured", SHOT_DIR .. "/bug559_shove.png")
  end

  -- let the two walks settle, then the beat the script waits before it turns
  -- the rival up to face the player (the row after move_player)
  for _ = 1, 240 do
    if not ow.player.moving and not rival.moving and rival.facing == "up" then
      break
    end
    U.wait(1)
  end
  U.log("after the push: player at", ow.player.cellX, ow.player.cellY,
        "| rival at", rival.cellX, rival.cellY, "facing", rival.facing)
  check("the player ended two tiles right of where he stood",
        ow.player.cellX == STAND.x + 2 and ow.player.cellY == STAND.y)
  check("the rival ended on the ball's row-4 tile facing up",
        rival.cellX == ball.cellX and rival.cellY == 4
        and rival.facing == "up")

  if U.shot(game, SHOT_DIR .. "/bug559_after.png") then
    U.log("captured", SHOT_DIR .. "/bug559_after.png")
  end

  U.log("The shove has already happened; the box on screen is the rival")
  U.log("gloating. Press A through his five lines to see the rest. Watch the")
  U.log("shot pair: the rival walks down and across the table first, and Red")
  U.log("only slides right as the rival arrives on top of him, both moving")
  U.log("together for that last tile. The near miss to look for is Red")
  U.log("stepping away early, with the rival still up at (4,3) or halfway")
  U.log("along row 4 behind him -- that is #559 unchanged.")
  U.log("Control case: on a save where Oak has not asked you to choose yet,")
  U.log("the same A press only prints \"That's a POKe BALL\" and nobody")
  U.log("moves, which is the handler working correctly.")

  idle()
end
