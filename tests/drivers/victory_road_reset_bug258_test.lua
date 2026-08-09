-- Driver: the Victory Road boulder puzzle resets on re-entry via Route 23
-- (#258).  scripts/Route23.asm:8 clears the 2F/3F switch events on every entry
-- and VictoryRoad2F.asm:19 clears 1F's, so each floor restamps its own block.
--   POKEPORT_DRIVER=tests/drivers/victory_road_reset_bug258_test.lua \
--     POKEPORT_IDENTITY=bug258 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapScripts = require("data.scripts.init")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local SW1F = "EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH"
  local SW2A = "EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1"
  local SW2B = "EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2"
  local SW3A = "EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1"
  local SW3B = "EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2"

  -- Barriers are BLOCK coords: block (bx,by) covers cells (2bx,2by) ..
  -- (2bx+1,2by+1).  sx/sy is the walkable cell immediately west of each one,
  -- so the barrier fills the view just right of the player.
  local B1F  = { map = "VICTORY_ROAD_1F", bx = 4,  by = 6, open = 0x1D, shut = 0x25,
                 sx = 7,  sy = 12 }
  local B2A  = { map = "VICTORY_ROAD_2F", bx = 3,  by = 4, open = 0x15, shut = 0x37,
                 sx = 5,  sy = 8 }
  local B2B  = { map = "VICTORY_ROAD_2F", bx = 11, by = 7, open = 0x1D, shut = 0x25,
                 sx = 21, sy = 14 }
  local B3   = { map = "VICTORY_ROAD_3F", bx = 3,  by = 5, open = 0x1D, shut = 0x25,
                 sx = 5,  sy = 10 }
  -- the hole at 3F (23,15) and the boulder that lives beside it
  local HOLE = { x = 23, y = 15 }
  local ROCK3F = { name = "VICTORYROAD3F_BOULDER4", x = 22, y = 15, sx = 21, sy = 15 }
  local ROCK2F = { name = "VICTORYROAD2F_BOULDER3", x = 23, y = 16, sx = 22, sy = 16 }

  -- ---- preconditions -----------------------------------------------------
  -- a missing onEnter, a renamed object and a barrier that never redraws all
  -- look the same on screen: the same picture twice

  for _, id in ipairs({ "ROUTE_23", "VICTORY_ROAD_1F", "VICTORY_ROAD_2F",
                        "VICTORY_ROAD_3F" }) do
    local h = mapScripts.get(id)
    check(id .. " has an onEnter hook", h ~= nil and type(h.onEnter) == "function")
  end

  local function blockAt(mapId, bx, by)
    local def = game.data.maps[mapId]
    return def.blocks[by * def.width + bx + 1]
  end

  local function objectNamed(mapId, name)
    for _, o in ipairs(game.data.maps[mapId].objects or {}) do
      if o.name == name then return o end
    end
    return nil
  end
  check("VICTORY_ROAD_3F really has " .. ROCK3F.name,
        objectNamed("VICTORY_ROAD_3F", ROCK3F.name) ~= nil)
  check("VICTORY_ROAD_2F really has " .. ROCK2F.name,
        objectNamed("VICTORY_ROAD_2F", ROCK2F.name) ~= nil)

  -- ---- helpers -----------------------------------------------------------
  local function goto_(mapId, x, y, facing)
    U.teleport(game, mapId, x, y, facing or "right")
    U.wait(12)
    return game.overworld
  end

  -- stand west of a barrier and record the live block id, so the screenshot is
  -- never the only evidence
  local function shootBarrier(b, tag, wantOpen)
    goto_(b.map, b.sx, b.sy, "right")
    local got = blockAt(b.map, b.bx, b.by)
    local want = wantOpen and b.open or b.shut
    check(("%s block (%d,%d) is 0x%02X (%s) -- %s")
            :format(b.map, b.bx, b.by, want, wantOpen and "open" or "solid rock", tag),
          got == want)
    if got ~= want then
      U.log(("  actually 0x%02X"):format(got or -1))
    end
    local path = ("%s/bug258_%s.png"):format(SHOT_DIR, tag)
    if not U.shot(game, path) then check("screenshot reached disk: " .. tag, false) end
  end

  local function npcNamed(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- ---- 2F: solve both switches, then walk Route 23 -----------------------
  game.save.flags[SW2A] = true
  game.save.flags[SW2B] = true
  shootBarrier(B2A, "2f_barrier1_solved", true)
  shootBarrier(B2B, "2f_barrier2_solved", true)

  goto_("ROUTE_23", 8, 71, "down")
  check("Route 23 cleared 2F switch 1", not game.save.flags[SW2A])
  check("Route 23 cleared 2F switch 2", not game.save.flags[SW2B])
  check("Route 23 cleared 3F switch 1", not game.save.flags[SW3A])
  check("Route 23 cleared 3F switch 2", not game.save.flags[SW3B])

  shootBarrier(B2A, "2f_barrier1_after_route23", false)
  shootBarrier(B2B, "2f_barrier2_after_route23", false)

  -- ---- 3F: same barrier, and the boulder that fell through the hole ------
  game.save.flags[SW3A] = true
  shootBarrier(B3, "3f_barrier_solved", true)

  -- push the boulder into the hole for real: the map's own object moved onto
  -- (23,15), then onBoulderMoved, the same call checkBoulderPush makes
  local ow = goto_("VICTORY_ROAD_3F", ROCK3F.sx, ROCK3F.sy, "right")
  local rock = npcNamed(ow, ROCK3F.name)
  if check("the 3F boulder is standing beside the hole", rock ~= nil) then
    U.shot(game, SHOT_DIR .. "/bug258_3f_boulder_before_hole.png")
    rock.cellX, rock.cellY = HOLE.x, HOLE.y
    rock.px, rock.py = HOLE.x * 16, HOLE.y * 16
    local hooks = mapScripts.get("VICTORY_ROAD_3F")
    hooks.onBoulderMoved(game, ow, rock)
    U.wait(10)
    check("the hole sets 3F switch 2 (CheckAndSetEvent)", game.save.flags[SW3B] == true)
    check("the boulder is gone from 3F", npcNamed(game.overworld, ROCK3F.name) == nil)
    U.shot(game, SHOT_DIR .. "/bug258_3f_boulder_gone.png")
  end

  local ow2 = goto_("VICTORY_ROAD_2F", ROCK2F.sx, ROCK2F.sy, "right")
  check("the boulder has arrived on 2F beside switch 2",
        npcNamed(ow2, ROCK2F.name) ~= nil)
  U.shot(game, SHOT_DIR .. "/bug258_2f_boulder_arrived.png")

  goto_("ROUTE_23", 8, 71, "down")
  shootBarrier(B3, "3f_barrier_after_route23", false)

  local ow3 = goto_("VICTORY_ROAD_3F", ROCK3F.sx, ROCK3F.sy, "right")
  check("after Route 23 the boulder is back beside the 3F hole",
        npcNamed(ow3, ROCK3F.name) ~= nil)
  U.shot(game, SHOT_DIR .. "/bug258_3f_boulder_back.png")

  local ow4 = goto_("VICTORY_ROAD_2F", ROCK2F.sx, ROCK2F.sy, "right")
  check("and the 2F copy is gone again", npcNamed(ow4, ROCK2F.name) == nil)
  U.shot(game, SHOT_DIR .. "/bug258_2f_boulder_gone.png")

  -- ---- 1F: entering 2F closes the barrier behind you ---------------------
  game.save.flags[SW1F] = true
  shootBarrier(B1F, "1f_barrier_solved", true)
  goto_("VICTORY_ROAD_2F", B2A.sx, B2A.sy, "right")
  check("entering 2F cleared the 1F switch event", not game.save.flags[SW1F])
  shootBarrier(B1F, "1f_barrier_after_2f", false)

  -- ---- hand off ----------------------------------------------------------
  -- leave the player looking at the reset 3F barrier
  game.save.flags[SW3A] = nil
  goto_(B3.map, B3.sx, B3.sy, "right")

  U.log("Victory Road 3F, just west of the barrier at block (3,5).  The puzzle")
  U.log("was solved and reset once already, so expect solid rock and the boulder")
  U.log("back beside the 3F hole at (22,15); #258 was the gap staying open.")
  U.log("Shots in " .. SHOT_DIR .. "/bug258_*.png (_solved / _after_route23).")
  U.log("A switch you solve now still opens its barrier while you stay on 3F.")

  while true do
    coroutine.yield()
  end
end
