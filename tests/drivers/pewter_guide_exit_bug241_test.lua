-- Driver: the Pewter gym guide leaves without walking through you (#241).
-- scripts/PewterCity.asm:133 snaps him to map 16/22 (cell 12,18 after the +4
-- border offset) and runs MovementData_PewterGymGuyExit, five NPC_MOVEMENT_RIGHT,
-- then hides him and puts him back on his object_event spawn.  The port retraced
-- the 41-step escort route instead, first step LEFT into the player's own cell.
--   POKEPORT_DRIVER=tests/drivers/pewter_guide_exit_bug241_test.lua SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Flags = require("src.script.Flags")
  local TextBox = require("src.render.TextBox")
  local mapScripts = require("data.scripts.init")

  local MAP = "PEWTER_CITY"
  local NPC = "PEWTERCITY_YOUNGSTER"
  local TEXT = "TEXT_PEWTERCITY_YOUNGSTER"
  -- engine/events/pewter_guys.asm PewterGymGuyCoords: (35,17) is the plain
  -- east-exit trigger, the one with no head-start pause.
  local TRIG = { x = 35, y = 17 }
  local PARK = { x = 11, y = 18 }   -- where the escort leaves the player
  local DROP = { x = 12, y = 18 }   -- where it leaves the guide

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- state the escort needs --------------------------------------------
  -- Brock beaten permanently HideObject's him (PewterGym.asm .gymVictory),
  -- so a stale save would show an empty street and read as a broken script.
  Flags.clear(game.save, "EVENT_BEAT_BROCK")
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles[MAP] = nil
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"

  -- ---- preconditions the eye cannot check --------------------------------
  local t = game.data.text
  for _, key in ipairs({ "_PewterCityYoungsterYoureATrainerFollowMeText",
                         "_PewterCityYoungsterGoTakeOnBrockText" }) do
    check(key .. " resolves to a string",
          type(t[key]) == "string" and t[key] ~= "")
  end

  local script = mapScripts.get(MAP)
  local escort = script and script.escort
  check("PEWTER_CITY exposes the escort tables", escort ~= nil)
  check(("PewterGymGuyCoords has a plan for the trigger tile (%d,%d)")
          :format(TRIG.x, TRIG.y),
        escort ~= nil and escort.playerPlan(TRIG.x, TRIG.y) ~= nil)

  local spawn
  for _, o in ipairs(game.data.maps[MAP].objects or {}) do
    if o.name == NPC then spawn = o end
  end
  check(NPC .. " has an object_event", spawn ~= nil)
  check("it spawns on (35,16) as in data/maps/objects/PewterCity.asm",
        spawn ~= nil and spawn.x == 35 and spawn.y == 16)

  -- ---- dry-run the escort and the exit before anything is on screen ------
  -- Same shape as the parity test: the whole callback chain runs inside one
  -- call because the stubbed TextBox fires its continuation immediately.
  local talk = mapScripts.talkScript(MAP, TEXT)
  check("the youngster's talk handler is the escort", type(talk) == "function")
  local Music = require("src.core.Music")
  local realPlay, realPlayMap = Music.play, Music.playMap
  local realNew = TextBox.new
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local moves, dryGuy, dryPlayer
  if type(talk) == "function" then
    Music.play, Music.playMap = function() end, function() end
    TextBox.new = function(_, s, done) return { text = s, done = done } end
    local ok, err = pcall(function()
      moves = {}
      dryGuy = { cellX = spawn.x, cellY = spawn.y, facing = "down", moving = false }
      dryPlayer = { cellX = TRIG.x, cellY = TRIG.y, facing = "left" }
      local mockGame = {
        data = { text = {} },
        save = { flags = {} },
        stack = { push = function(_, box) if box.done then box.done() end end },
      }
      local mockOw = {
        scriptMoves = {},
        runner = { isRunning = function() return false end },
        player = dryPlayer,
        npcByIndex = function(_, i) return (i == 5) and dryGuy or nil end,
        scriptMove = function(_, ent, dir, tiles, onDone)
          local v = D[dir]
          for _ = 1, (tiles or 1) do
            ent.cellX, ent.cellY = ent.cellX + v[1], ent.cellY + v[2]
          end
          ent.facing = dir
          moves[#moves + 1] = { who = (ent == dryGuy) and "guy" or "player", dir = dir }
          if onDone then onDone() end
        end,
      }
      talk(mockGame, mockOw, dryGuy, nil)
    end)
    Music.play, Music.playMap = realPlay, realPlayMap
    TextBox.new = realNew
    check("the dry run completed", ok)
    if not ok then U.log("dry run error:", tostring(err)) end
  end

  if moves and dryGuy and dryPlayer then
    local lastPlayer = 0
    for i, m in ipairs(moves) do if m.who == "player" then lastPlayer = i end end
    local exit = {}
    for i = lastPlayer + 1, #moves do exit[#exit + 1] = moves[i].dir end
    U.log("planned exit:", table.concat(exit, ", "),
          ("then snap to (%d,%d) facing %s")
            :format(dryGuy.cellX, dryGuy.cellY, tostring(dryGuy.facing)))
    check(("the escort parks the player on (%d,%d)"):format(PARK.x, PARK.y),
          dryPlayer.cellX == PARK.x and dryPlayer.cellY == PARK.y)
    check("MovementData_PewterGymGuyExit is five steps", #exit == 5)
    local allRight = #exit == 5
    for _, d in ipairs(exit) do if d ~= "right" then allRight = false end end
    check("every exit step is RIGHT, away from the player", allRight)
    check("the guide is snapped back to his spawn (35,16) facing down",
          dryGuy.cellX == spawn.x and dryGuy.cellY == spawn.y
          and dryGuy.facing == "down")
    -- a stale target reserves the vacated cell forever in
    -- OverworldState:npcAtCell (OverworldController.lua:1451)
    check("the snap clears the move target so (17,18) is not reserved",
          dryGuy.targetX == nil and dryGuy.targetY == nil
          and dryGuy.moving == false)
  end

  -- ---- park below the trigger tile ---------------------------------------
  -- (35,18) is open road under the trigger and the youngster is on (35,16), so
  -- stepping up onto (35,17) puts the player between them and fires the script.
  U.teleport(game, MAP, TRIG.x, TRIG.y + 1, "up")
  U.wait(10)
  local ow = game.overworld

  for _, cell in ipairs({ { PARK.x, PARK.y }, { DROP.x, DROP.y },
                          { 13, 18 }, { 14, 18 }, { 15, 18 },
                          { 16, 18 }, { 17, 18 } }) do
    check(("PEWTER_CITY (%d,%d) is walkable gym road"):format(cell[1], cell[2]),
          ow.map:isWalkableCell(cell[1], cell[2]))
  end
  check("PEWTER_CITY (18,18) is the fence that ends the road",
        not ow.map:isWalkableCell(18, 18))
  check("PEWTER_CITY (17,17) is wall, so (17,18) is a dead-end pocket",
        not ow.map:isWalkableCell(17, 17))

  local function guideNpc()
    for _, n in ipairs(game.overworld.npcs or {}) do
      if n.def and n.def.name == NPC then return n end
    end
  end
  check("the youngster is on the map", guideNpc() ~= nil)
  if not ow.map:isWalkableCell(TRIG.x, TRIG.y + 1) then
    -- a map edit moved the road: degrade to any free neighbour of the
    -- trigger tile rather than leaving the player facing a wall
    for _, s in ipairs({ { 0, 1, "up" }, { 1, 0, "left" }, { -1, 0, "right" } }) do
      local cx, cy = TRIG.x + s[1], TRIG.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("approach cell blocked, standing on", cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        ow = game.overworld
        break
      end
    end
  end
  if U.shot(game, DIR .. "/bug241_0_before.png") then
    U.log("captured", DIR .. "/bug241_0_before.png")
  end

  -- ---- step onto the trigger and ride out the escort ----------------------
  -- About 41 lockstep tiles.  A is only pressed while a TextBox is up, so a
  -- stray press can never re-arm the escort by talking to him again.
  U.hold(game, "up", 24)

  local function isBox()
    return getmetatable(game.stack:top()) == TextBox
  end
  local function boxText()
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

  local arrived = false
  for _ = 1, 1200 do
    local parked = ow.player.cellX == PARK.x and ow.player.cellY == PARK.y
    if parked and isBox() and #ow.scriptMoves == 0 then arrived = true break end
    if isBox() and #ow.scriptMoves == 0 then U.tap(game, "a") end
    U.wait(2)
  end
  check("the escort walked and the last box is up", arrived)
  U.log(("player is on (%d,%d)"):format(ow.player.cellX, ow.player.cellY))
  local guide = guideNpc()
  if guide then
    U.log(("guide is on (%d,%d) facing %s")
            :format(guide.cellX, guide.cellY, tostring(guide.facing)))
  end
  check(("the escort parked the player on (%d,%d)"):format(PARK.x, PARK.y),
        ow.player.cellX == PARK.x and ow.player.cellY == PARK.y)
  check(("the guide is standing beside him on (%d,%d)"):format(DROP.x, DROP.y),
        guide ~= nil and guide.cellX == DROP.x and guide.cellY == DROP.y)
  U.log("box reads:", (boxText():gsub("%s+", " ")))
  U.wait(20)
  if U.shot(game, DIR .. "/bug241_1_atgym.png") then
    U.log("captured", DIR .. "/bug241_1_atgym.png")
  end

  -- ---- hand off, then stay out of the way --------------------------------
  U.log("The youngster has walked you to the PEWTER GYM door and is on your right.")
  U.log("Press A to close the box and watch him go: five steps RIGHT, away from")
  U.log("you, then he blinks out and turns up again in the north-east of town")
  U.log("facing down. He must never step onto your cell (#241).")

  while true do
    coroutine.yield()
  end
end
