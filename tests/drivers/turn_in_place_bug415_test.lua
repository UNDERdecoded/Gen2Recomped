-- A tap on the d-pad turns the player in place; only a held direction steps
-- (#415).  home/overworld.asm .handleDirectionButtonPress only reaches the
-- turn while wCheckFor180DegreeTurn is set, and .noDirectionButtonsPressed
-- (the poll that finds nothing held) is the one place that sets it, so the
-- delay is paid once per press and never at a corner.  This scripts the
-- window it can measure and then hands the pad over, because no scripted
-- press has a human thumb's length.
--   POKEPORT_DRIVER=tests/drivers/turn_in_place_bug415_test.lua \
--     POKEPORT_IDENTITY=bug415 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- pokered data/maps/objects/PalletTown.asm: PALLETTOWN_GIRL is the one
  -- WALK/ANY_DIR object on the town's open west side, at cell (3, 8) with
  -- floor on three sides -- the ordinary "someone standing next to you"
  -- shape the report is about.  object_event coords are already walk-grid
  -- cells (src/world/NPC.lua), so they carry over unchanged.
  local MAP = "PALLET_TOWN"
  local MAP_LABEL = "PalletTown"
  local NPC_NAME = "PALLETTOWN_GIRL"
  local NPC_TEXT = "TEXT_PALLETTOWN_GIRL"
  local GIRL = { x = 3, y = 8 }

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- Held-direction primitives that never lift the d-pad.  U.hold releases at
  -- the end of every call, which is exactly what the corner case below must
  -- not do: a release re-arms the turn and hides the thing being measured.
  local function press(btn)
    table.insert(game.input.pressQueue, btn)
    game.input.state[btn] = true
  end
  local function release(btn)
    game.input.state[btn] = false
  end

  -- an unresolved text label, a renamed object and a press that never landed
  -- all look like the same nothing-happened the bug looked like
  local girlText = game.data:resolveText(MAP_LABEL, NPC_TEXT)
  check(NPC_TEXT .. " resolves to a string",
        type(girlText) == "string" and girlText ~= "")

  U.teleport(game, MAP, GIRL.x, GIRL.y - 1, "up")
  U.wait(10)
  local ow = game.overworld
  check("Pallet Town is loaded", ow ~= nil and ow.map.id == MAP)

  local function girlIn(state)
    for _, n in ipairs(state.npcs or {}) do
      if n.def and n.def.name == NPC_NAME then return n end
    end
    return nil
  end

  -- She is a WALK object, so pin her before deriving anything from her cell:
  -- NPC:update returns early on frozen, and snapping the pixels back undoes
  -- any step already in flight when the driver got here.
  local function pin(state)
    local npc = girlIn(state)
    if npc then
      npc.frozen = true
      npc.moving = false
      npc.cellX, npc.cellY = GIRL.x, GIRL.y
      npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
      npc.facing = "down"
    end
    return npc
  end

  local girl = pin(ow)
  check("the girl object loaded and is pinned at (3, 8)",
        girl ~= nil and girl.cellX == GIRL.x and girl.cellY == GIRL.y)

  -- Stand on her north side facing away, so the first tap has to turn.  If a
  -- map edit takes that cell, fall back to any free walkable neighbour and
  -- face away from her there; {dx, dy, away, toward} is the offset from her
  -- to the stand cell plus the two directions that matter from it.
  local stand = { x = GIRL.x, y = GIRL.y - 1, away = "up", toward = "down" }
  local function free(cx, cy)
    return ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy)
  end
  if girl and not free(stand.x, stand.y) then
    for _, s in ipairs({ { 0, 1, "down", "up" }, { -1, 0, "left", "right" },
                         { 1, 0, "right", "left" } }) do
      local cx, cy = girl.cellX + s[1], girl.cellY + s[2]
      if free(cx, cy) then
        U.log(("(%d, %d) is not free; standing at"):format(stand.x, stand.y),
              cx, cy, "facing", s[3])
        stand = { x = cx, y = cy, away = s[3], toward = s[4] }
        break
      end
    end
  end
  U.teleport(game, MAP, stand.x, stand.y, stand.away)
  U.wait(10)
  ow = game.overworld
  pin(ow)
  local p = ow.player
  check("standing beside the girl, facing away from her",
        p.cellX == stand.x and p.cellY == stand.y and p.facing == stand.away)

  -- What the fix moved, read off the running game rather than repeated from
  -- a comment: turnFrames is the dataset constant a mod can restamp
  -- (src/world/FieldDefaults.lua) and the touch figure comes back out of
  -- Player:turnWindow with a live overlay source.  turnWindow is the fix's
  -- own entry point, so a build without it falls back to the one window it
  -- had for every source and the two checks below say so.
  local function window()
    return p.turnWindow and p:turnWindow() or p.turnFrames
  end
  local padWindow = window()
  game.input:overlayPressed(p.facing)
  game.input:step()
  local touchWindow = window()
  game.input:overlayReleased(p.facing)
  game.input:step()
  check("the pad turn window is 4 fixed steps, up from 2", padWindow == 4)
  check("the on-screen d-pad gets 8", touchWindow == 8)
  U.log(("turn window: %d fixed steps on keyboard and pad (%d ms), %d on the ")
          :format(padWindow, math.floor(padWindow * 1000 / 60), touchWindow)
        .. ("on-screen d-pad (%d ms); hold past it and the step commits.")
          :format(math.floor(touchWindow * 1000 / 60)))

  -- A press no longer than the window turns and stops there.
  for _ = 1, padWindow do
    press(stand.toward)
    coroutine.yield()
  end
  release(stand.toward)
  U.wait(6)
  check(("a %d-step press turned toward the girl"):format(padWindow),
        p.facing == stand.toward)
  check("and left the feet on the same tile",
        p.cellX == stand.x and p.cellY == stand.y)

  -- The same press held well past the window does step.  Sideways, because
  -- the girl blocks the step toward her and would mask it.
  local openDir, openBack
  for _, s in ipairs({ { "left", "right", -1, 0 }, { "right", "left", 1, 0 },
                       { "up", "down", 0, -1 }, { "down", "up", 0, 1 } }) do
    if s[1] ~= stand.toward and free(stand.x + s[3], stand.y + s[4]) then
      openDir, openBack = s[1], s[2]
      break
    end
  end
  if openDir then
    U.hold(game, openDir, 40)
    U.wait(10)
    check(("a 40-step hold of %s walks off the tile"):format(openDir),
          p.cellX ~= stand.x or p.cellY ~= stand.y)

    -- The corner: swap direction without ever lifting the d-pad.  Walk back
    -- on openBack first and break on the landing poll, so the pad is still
    -- down and the turn is still spent when the swap arrives.
    local walked = false
    for _ = 1, 240 do
      press(openBack)
      coroutine.yield()
      if p.moving then
        walked = true
      elseif walked then
        break
      end
    end
    check(("the return hold of %s is walking"):format(openBack), walked)

    -- Nothing has re-armed wCheckFor180DegreeTurn, so the new facing steps
    -- on the poll it arrives on with no turn delay.  Pre-fix, every corner
    -- paid the window again.  Perpendicular and walkable from wherever the
    -- return hold landed, so a blocked cell can't read as a stall.
    local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                    left = { -1, 0 }, right = { 1, 0 } }
    local swap
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      local dd = DELTA[d]
      if d ~= openDir and d ~= openBack
         and free(p.cellX + dd[1], p.cellY + dd[2]) then
        swap = d
        break
      end
    end
    if swap then
      local wasFacing = p.facing
      release(openBack)
      press(swap) -- same poll, so the d-pad never reads empty
      coroutine.yield()
      U.log(("corner: swapped %s for %s without a release, facing went %s to %s")
              :format(openBack, swap, wasFacing, p.facing))
      check("the swapped direction steps on the poll it arrives on",
            p.facing == swap and p.moving and p.turnTimer == 0)
      release(swap)
    else
      U.log("no perpendicular open cell here; skipped the corner check")
      release(openBack)
    end
    for _ = 1, 200 do
      if not p.moving then break end
      coroutine.yield()
    end
  else
    U.log("no open cell beside the stand tile; skipped the hold and corner")
  end

  -- Back beside her, facing her, and talk: a silent A here would look exactly
  -- like a facing that missed.
  U.teleport(game, MAP, stand.x, stand.y, stand.toward)
  U.wait(10)
  ow = game.overworld
  p = ow.player
  girl = pin(ow)
  local fx, fy = p:facingCell()
  check("the facing cell is the girl's",
        girl ~= nil and ow:npcAtCell(fx, fy) == girl)

  U.tap(game, "a")
  U.wait(30)
  local top = game.stack:top()
  local isBox = getmetatable(top) == TextBox
  check("A opened her text box", isBox)
  if isBox then
    local shown = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    U.log("box reads:", table.concat(shown, " / "))
  end
  if U.shot(game, SHOT_DIR .. "/bug415_turn_in_place.png") then
    U.log("captured", SHOT_DIR .. "/bug415_turn_in_place.png",
          "so the window did render; a blank screen later is not the driver")
  end
  U.tap(game, "b")
  U.wait(20)

  U.log("You are on the girl's north side in Pallet Town, facing her, with")
  U.log("open ground north, east and west.  Tap a direction: Red should")
  U.log("pivot on the spot and stay on his tile.  Hold the same direction")
  U.log("and he walks, with no extra pause before the first step.  Then walk")
  U.log("a lap and change direction without letting go; corners should stay")
  U.log("smooth, and a stall there is the half of #415 that is not the tap.")
  U.log("The near miss to watch for is a tap that turns AND slides one tile,")
  U.log("which still reads as a turn unless you watch Red's feet against the")
  U.log("fence.  The girl is the control: she blocks the step, so tapping")
  U.log("toward her looked fine even while this was broken.  That is the")
  U.log("Yellow complaint in the report -- the follower Pikachu does not")
  U.log("block (src/world/PikachuFollower.lua), so a tap meant to turn and")
  U.log("talk to it walked onto its cell and straight past it instead.")

  while true do
    coroutine.yield()
  end
end
