-- Driver: #198 Celadon Game Corner poster grunt exit.
-- The Rocket (GAMECORNER_ROCKET) guards the hideout poster at cell (9,5),
-- facing UP toward the poster / secret entrance at (9,4).  After you beat
-- him he warns "Our hideout might be discovered! I better tell BOSS!" and,
-- in Gen1 (scripts/GameCorner.asm GameCornerRocketExitScript), walks UP one
-- tile into the poster (the hideout entrance) before HideObject despawns
-- him -- freeing (9,5) so the player can reach the poster switch.  The bug
-- despawned him in place at (9,5) the instant the after-battle box closed.
--
-- This driver talks to him, mashes through the battle to a win, advances
-- the after-battle text, then samples the grunt every frame: it must move
-- toward the poster (cellY/targetY north of its start) before it leaves
-- ow.npcs.  Fails on the pre-fix instant-despawn, passes after the walk.
--
--   SHOT_DIR=/tmp/gc198 POKEPORT_IDENTITY=bug198 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gamecorner_rocket_bug198_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")

  -- clean slate: the grunt must not already read as defeated/hidden
  game.save.defeatedTrainers = {}
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles.GAME_CORNER = nil
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"

  -- a tank that one-shots the whole party (OPP_ROCKET #7) so the mash win
  -- is quick and deterministic regardless of type matchups
  local tank = Pokemon.new(game.data, "MEWTWO", 100)
  tank.moves = {
    { id = "PSYCHIC_M", pp = 99 },
    { id = "THUNDERBOLT", pp = 99 },
    { id = "ICE_BEAM", pp = 99 },
    { id = "EARTHQUAKE", pp = 99 },
  }
  game.save.party = { tank }

  -- stand south of the grunt (9,6) facing up; grunt at (9,5) faces the
  -- poster/secret entrance at (9,4)
  U.teleport(game, "GAME_CORNER", 9, 6, "up")
  local ow = game.overworld

  local function findGrunt()
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == "GAMECORNER_ROCKET" then return n end
    end
    return nil
  end

  local function pageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local parts = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  local function idle()
    return game.stack:top() == ow and not ow.runner:isRunning()
           and #ow.scriptMoves == 0 and not ow.transitioning
  end

  local grunt = findGrunt()
  assert(grunt, "GAMECORNER_ROCKET not present at start")
  local startX, startY = grunt.cellX, grunt.cellY
  U.log("grunt start:", startX, startY, grunt.facing)
  assert(startX == 9 and startY == 5, "grunt not at expected (9,5)")
  U.shot(game, DIR .. "/gamecorner_rocket_0_before.png")

  -- Talk, then mash A through pre-battle text, the battle (select FIGHT +
  -- first move), the won text ("Dang!"), until the after-battle "hideout"
  -- text is on screen.  Force-finish a stalled battle via onFinish("win")
  -- (same safety valve as rival_walkoff_test) so the post-battle script
  -- (which owns the exit walk) always runs.
  U.tap(game, "a")
  local sawAfter = false
  for f = 1, 4000 do
    if pageText():find("hideout", 1, true) then sawAfter = true break end
    local top = game.stack:top()
    if top and top.phase then
      if top.phase == "menu" then top.menuIndex = 1
      elseif top.phase == "moveSelect" then top.moveIndex = 1 end
      U.tap(game, "a")
      if f > 2400 and top.onFinish then
        U.log("force-finishing stalled battle")
        top.onFinish("win")
        if game.stack:top() == top then game.stack:pop() end
      end
    elseif top ~= ow then
      U.tap(game, "a")
    elseif idle() and not findGrunt() then
      break -- somehow already resolved
    else
      U.tap(game, "a")
    end
    U.wait(2)
  end
  U.log("saw after-battle text:", sawAfter, "defeated:",
        tostring(game.save.defeatedTrainers["GAME_CORNER_obj_11"]))
  U.shot(game, DIR .. "/gamecorner_rocket_1_afterbattle.png")
  assert(sawAfter, "never reached the after-battle 'hideout' text")

  -- Dismiss the after-battle box.  From here the fixed script queues a
  -- one-tile scriptMove UP before hide_object; the buggy script removes
  -- the grunt in place immediately.
  U.tap(game, "a")

  -- Sample every logic frame.  The scripted walk sets facing=up and
  -- targetY=(startY-1) for ~16 frames, then lands cellY=startY-1 and the
  -- onDone despawns him the same frame, so watch for either the in-motion
  -- targetY or the transient landed cellY north of the start.
  local walkedUp, walkShot = false, false
  for _ = 1, 600 do
    local g = findGrunt()
    if g then
      if g.cellY < startY or (g.targetY and g.targetY < startY) then
        walkedUp = true
        if not walkShot then
          walkShot = true
          U.shot(game, DIR .. "/gamecorner_rocket_2_walk.png")
        end
      end
    else
      if idle() then break end
    end
    if game.stack:top() ~= ow then U.tap(game, "a") end
    U.wait(1)
  end

  for _ = 1, 400 do
    if idle() then break end
    if game.stack:top() ~= ow then U.tap(game, "a") end
    U.wait(2)
  end
  U.wait(5)
  U.shot(game, DIR .. "/gamecorner_rocket_3_after.png")

  local toggles = game.save.objectToggles.GAME_CORNER
  U.log("walkedUp:", walkedUp, "grunt gone:", findGrunt() == nil,
        "toggle:", tostring(toggles and toggles.GAMECORNER_ROCKET))

  -- CORRECT Gen1 behavior: he walks toward the poster before despawning.
  assert(walkedUp,
    "grunt never moved toward the poster before despawning (#198)")
  assert(findGrunt() == nil, "GAMECORNER_ROCKET still present after exit")
  assert(toggles and toggles.GAMECORNER_ROCKET == false,
    "grunt objectToggle not hidden")
  assert(game.save.defeatedTrainers["GAME_CORNER_obj_11"],
    "grunt not recorded as defeated")
  for _, n in ipairs(ow.npcs or {}) do
    assert(not (n.cellX == startX and n.cellY == startY),
      "an NPC still occupies the grunt's old tile (9,5)")
  end
  U.log("gamecorner_rocket_bug198_test: ok")
end
