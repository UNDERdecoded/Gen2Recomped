-- Driver: regression coverage for #232 "Hey! Don't go away yet!".
--
-- The Oak leave-block in data/scripts/oaks_lab.lua onStep must halt a
-- pre-starter player at the bookshelf row (cell y == 6), the same
-- coordinate the sibling rival challenge below it uses.  In
-- pret/pokered scripts/OaksLab.asm the "don't go away yet" intercept
-- and OaksLabRivalChallengesPlayerScript share the wYCoord == 6
-- coordinate script slot (gated on EVENT_GOT_STARTER); the bookshelves
-- flank that corridor, so Oak stops you level with the shelves rather
-- than one full corridor later on the exit mat.
--
-- Bug (before the fix): the guard read `y == 11 and (x == 4 or x == 5)`,
-- i.e. it only fired on the exit door mat.  A pre-starter player walked
-- the whole corridor down through the shelves (y=6,7,8,9,10) and was only
-- halted at y=11, exactly the port screenshot the issue attached.
--
-- OAKS_LAB is 10x12 cells (x 0-9, y 0-11).  Live walkability:
--   y=5  ..........  (open)
--   y=6  ####..####  (bookshelves solid at x=0-3/6-9, corridor at x=4,5)
--   y=7  ####..####
--   y=10 ..........  door mat warps at (4,11)/(5,11)
-- so at y>=6 only the x=4,5 corridor is walkable, and once Oak pushes the
-- player back to y=5 they can never reach y>=7 -- the trigger only ever
-- fires at y=6 in the corridor, matching the rival trigger's shape.
--
-- We monkeypatch TextBox.new to detect the raw "Don't go" text and record
-- the player's cell Y at that instant (interceptY).  No battle is involved
-- (EVENT_GOT_STARTER stays clear so the rival-challenge branch is skipped),
-- so nothing needs stubbing.

return function(game)
  io.stdout:setvbuf("no") -- LOVE block-buffers stdout; flush [driver] logs
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- Capture the raw text handed to TextBox and the Y it fired at.
  local TextBox = require("src.render.TextBox")
  local origNew = TextBox.new
  local dontGoSeen = false
  local interceptY = nil
  TextBox.new = function(g, text, ...)
    if type(text) == "string" and text:find("Don't go", 1, true) then
      dontGoSeen = true
      if game.overworld and game.overworld.player then
        interceptY = interceptY or game.overworld.player.cellY
      end
    end
    return origNew(g, text, ...)
  end

  local function restore()
    TextBox.new = origNew
  end

  -- The pre-starter state right after the walk-in cutscene: FOLLOWED_OAK
  -- set, no starter yet, no lab battle yet.
  local function setFlags()
    local flags = game.save.flags or {}
    game.save.flags = flags
    flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
    flags.EVENT_GOT_STARTER = nil
    flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = nil
  end

  -- story2.lua labWalkIn ends the follow-Oak cutscene at (5,3) facing down.
  U.teleport(game, "OAKS_LAB", 5, 3, "down")
  setFlags()
  U.wait(6)

  local ow = game.overworld
  U.log("start cell:", tostring(ow.player.cellX), tostring(ow.player.cellY),
        "map:", ow.map.id)
  U.shot(game, DIR .. "/bug232_start.png")

  -- Walk down toward the exit in bursts, mashing A to dismiss the "don't go
  -- away" box each time it opens.  Track how far down the player ever gets.
  local maxY = ow.player.cellY
  local shotIntercept = false
  for _ = 1, 12 do
    U.hold(game, "down", 8)
    maxY = math.max(maxY, ow.player.cellY)
    if dontGoSeen and not shotIntercept then
      -- let the typewriter reveal the line before shooting the box
      U.wait(20)
      U.shot(game, DIR .. "/bug232_intercept.png")
      shotIntercept = true
    end
    for _ = 1, 6 do
      U.tap(game, "a")
      U.wait(2)
      maxY = math.max(maxY, ow.player.cellY)
    end
    maxY = math.max(maxY, ow.player.cellY)
    U.log("iter cell:", tostring(ow.player.cellX), tostring(ow.player.cellY),
          "map:", ow.map.id, "maxY:", maxY, "dontGoSeen:", tostring(dontGoSeen))
    if ow.map.id ~= "OAKS_LAB" then break end
  end

  U.shot(game, DIR .. "/bug232_end.png")

  local finalMap = ow.map.id
  U.log("RESULT dontGoSeen:", tostring(dontGoSeen),
        "interceptY:", tostring(interceptY), "maxY:", maxY,
        "finalMap:", finalMap, "finalY:", tostring(ow.player.cellY))

  -- restore the hook before any assert so a failure can't leave it installed
  restore()

  assert(dontGoSeen,
    "Oak's 'don't go away yet' block must fire when a pre-starter player "
    .. "walks toward the exit")
  assert(interceptY == 6,
    "Oak must intercept at the bookshelf row (cell y == 6), not the exit "
    .. "mat; interceptY=" .. tostring(interceptY))
  assert(maxY <= 6,
    "the player must never pass the bookshelves (y>=7) before Oak stops "
    .. "them; maxY=" .. tostring(maxY))
  assert(finalMap == "OAKS_LAB",
    "the pre-starter player must never warp out of the lab; finalMap="
    .. tostring(finalMap))
  U.log("RESULT bug232 PASS")
end
