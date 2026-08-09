-- Driver: holding A or B on Cycling Road holds you in place (#255).  pokered
-- home/overworld.asm:1825 masks PAD_A and PAD_B along with the d-pad before it
-- forces PAD_DOWN.  Hands check, so no POKEPORT_SPEED.
--   POKEPORT_DRIVER=tests/drivers/cycling_road_brake_bug255_test.lua \
--     POKEPORT_IDENTITY=bug255 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- x=2 is open road from y=8 past y=34; y=20 keeps the demo roll clear of the
  -- bikers at (4,18) and (7,32).
  local MAP, START_X, START_Y = "ROUTE_17", 2, 20

  -- ---- preconditions -----------------------------------------------------
  -- "the bike does not roll" and "the brake works" look the same, so prove the
  -- hill is pulling first.

  local fm = game.data.field.forcedMovement
  local isSlope = false
  for _, id in ipairs((fm and fm.slopeMaps) or {}) do
    if id == MAP then isSlope = true end
  end
  check("field.forcedMovement.slopeMaps names ROUTE_17", isSlope)

  game.save.onBike = true
  check("the player is on the BICYCLE (no bike, no roll)", game.save.onBike == true)

  U.teleport(game, MAP, START_X, START_Y, "down")
  U.wait(15)
  local ow = game.overworld
  check("standing on Cycling Road", ow.map.id == MAP)
  local clear = true
  for dy = 1, 8 do
    if not ow.map:isWalkableCell(START_X, START_Y + dy) then clear = false end
  end
  check(("open road for 8 cells south of (%d,%d)"):format(START_X, START_Y), clear)

  -- ---- the hill pulls ----------------------------------------------------
  local y0 = ow.player.cellY
  U.wait(48)
  local rolled = ow.player.cellY - y0
  check(("hands off the pad, the bike rolls south (%d cells in 48 frames)")
          :format(rolled), rolled > 0)
  U.shot(game, SHOT_DIR .. "/bug255_rolling.png")

  -- ---- and A / B stop it -------------------------------------------------
  -- Input:beginStep rebuilds `pressed` from the queue every fixed step, so one
  -- queued edge plus a sticky input.state is exactly a button held down.
  local function holdFor(btn, frames)
    local ow2 = game.overworld
    table.insert(game.input.pressQueue, btn) -- the key-down edge
    game.input.state[btn] = true
    -- the mask only suppresses the NEXT simulated PAD_DOWN, so a step already
    -- under way still lands; the brake is measured from where it puts you
    for _ = 1, 24 do
      if not ow2.player.moving then break end
      coroutine.yield()
    end
    local start = ow2.player.cellY
    local drift = 0
    for _ = 1, frames do
      coroutine.yield()
      if ow2.player.cellY ~= start then drift = ow2.player.cellY - start end
    end
    check(("holding %s for %d frames: the player does not drift south (%d cells)")
            :format(btn:upper(), frames, drift), drift == 0)
    U.shot(game, ("%s/bug255_braking_%s.png"):format(SHOT_DIR, btn))
    game.input.state[btn] = false
    local held = ow2.player.cellY
    U.wait(48)
    check(("releasing %s resumes the roll (%d cells in 48 frames)")
            :format(btn:upper(), ow2.player.cellY - held),
          ow2.player.cellY > held)
  end

  holdFor("a", 120)
  holdFor("b", 120)

  -- park somewhere with road left to roll before handing over
  U.teleport(game, MAP, START_X, START_Y, "down")
  U.wait(10)
  game.save.onBike = true

  -- ---- hand off ----------------------------------------------------------
  U.log(("On the bike on Cycling Road at (%d,%d), already rolling south.")
          :format(START_X, START_Y))
  U.log("Hold A, then B, then let go, then hold A while pressing DOWN.")
  U.log("Correct: dead stop while held, roll resumes the instant you release,")
  U.log("a held direction still steers.  #255 was B doing nothing and A")
  U.log("stalling one frame.  Shots in " .. SHOT_DIR .. "/bug255_*.png")

  while true do
    coroutine.yield()
  end
end
