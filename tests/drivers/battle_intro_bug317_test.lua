-- Driver: the battle intro's pokeball rows, HUD chrome, prompt arrow and
-- trainer-pic slides (#317).  engine/battle/common_text.asm:22-27,
-- draw_hud_pokeball_gfx.asm:1-45 (player row (88,80) +8, foe row (64,16) -8),
-- SlideTrainerPicOffScreen at core.asm:1235-1253.  Ordering is asserted in
-- parity_battle_intro_chrome.lua.  No POKEPORT_SPEED: audio has its own clock.
--   POKEPORT_DRIVER=tests/drivers/battle_intro_bug317_test.lua POKEPORT_IDENTITY=bug317 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local HudTiles = require("src.render.HudTiles")
  local Font = require("src.render.Font")

  -- pokered data/maps/objects/Route3.asm: object_event 10, 6, ... STAY, RIGHT,
  -- OPP_BUG_CATCHER, 4.  Range RIGHT means the sight line runs east along row
  -- 6, so (13,6) is one cell outside it and walking west from there trips it.
  local MAP = "ROUTE_3"
  local TRAINER = "ROUTE3_YOUNGSTER1"
  local STAND = { x = 13, y = 6, facing = "left" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- A missing sheet draws nothing, which looks identical to the bug.

  -- drawBallRow bails silently if this image will not load
  local balls = io.open("assets/generated/battle/balls.png", "rb")
  check("assets/generated/battle/balls.png exists", balls ~= nil)
  if balls then balls:close() end

  -- HudTiles.tile is a silent no-op for a code the sheets do not carry, so
  -- count the draws it issues rather than trusting the call
  local function tileDraws(code)
    local real = love.graphics.draw
    local n = 0
    love.graphics.draw = function() n = n + 1 end
    pcall(HudTiles.tile, code, 0, 0)
    love.graphics.draw = real
    return n
  end
  local CHROME = {
    [0x73] = "corner tick", [0x74] = "bar left cap", [0x76] = "underline run",
    [0x77] = "player underline left", [0x78] = "enemy underline right",
    [0x6F] = "player underline end",
  }
  for code, what in pairs(CHROME) do
    check(("HUD chrome tile $%02X (%s) resolves"):format(code, what),
          tileDraws(code) > 0)
  end

  local mapDef = game.data.maps[MAP]
  local trainerDef
  for _, o in ipairs(mapDef and mapDef.objects or {}) do
    if o.name == TRAINER then trainerDef = o end
  end
  check(TRAINER .. " is still on " .. MAP, trainerDef ~= nil)
  if trainerDef then
    check("it is still a trainer object",
          trainerDef.trainerClass ~= nil and trainerDef.trainerParty ~= nil)
    U.log("  ", TRAINER, trainerDef.trainerClass, "party", trainerDef.trainerParty,
          "at", trainerDef.x, trainerDef.y, "range", tostring(trainerDef.range))
  end

  -- Record what drawHUDs puts on screen for one frame without drawing it:
  -- drawBallRow is shadowed on the instance, Font.draw on the module
  -- BattleState routes its HUD strings through.
  local function snapshot(battle)
    local rows, strings = {}, {}
    local realRow, realFont = battle.drawBallRow, Font.draw
    local realDraw = love.graphics.draw
    battle.drawBallRow = function(_, party, x, y, dx)
      rows[#rows + 1] = { count = #party, x = x, y = y, step = dx }
    end
    Font.draw = function(text) strings[#strings + 1] = tostring(text) end
    love.graphics.draw = function() end
    pcall(battle.drawHUDs, battle, 0)
    battle.drawBallRow, Font.draw = realRow, realFont
    love.graphics.draw = realDraw
    return rows, strings
  end

  local function drewString(strings, want)
    for _, s in ipairs(strings) do
      if s:find(want, 1, true) then return true end
    end
    return false
  end

  -- ---- part 1: a WILD intro, driven and photographed ---------------------
  game.save.party = {
    Pokemon.new(game.data, "BULBASAUR", 12),
    Pokemon.new(game.data, "PIDGEY", 9),
  }
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil)

  local wild = BattleState.newWild(game, "RATTATA", 3)
  wild.onFinish = function() end
  if ow then ow:pushBattle(wild) end
  for _ = 1, 400 do
    if game.stack:top() == wild and (wild.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the wild battle reached the screen",
        game.stack:top() == wild and (wild.introSlide or 0) == 0)
  check("the DrawAllPokeballs window is open", wild.introBalls == true)

  local rows, strings = snapshot(wild)
  check("a WILD intro draws exactly one ball row", #rows == 1)
  if rows[1] then
    check("it is the player's row at (88, 80) stepping +8",
          rows[1].x == 88 and rows[1].y == 80 and rows[1].step == 8)
    check("it carries all " .. #game.save.party .. " party slots",
          rows[1].count == #game.save.party)
  end
  check("the enemy HUD is NOT up under the intro box",
        not drewString(strings, wild.enemy.name))
  if not U.shot(game, DIR .. "/bug317_1_wild_intro.png") then
    U.log("FAIL could not capture the wild intro")
  end

  -- the page finishes typing, then PromptText's arrow blinks
  local prompted = false
  for _ = 1, 300 do
    if wild.msgPrompt then prompted = true break end
    U.wait(1)
  end
  check("the typed-out intro page raises the blinking prompt", prompted)
  -- two shots half a blink apart; drawTextArea draws '▼' for frame % 60 < 30
  for _ = 1, 60 do
    if (wild.frame % 60) < 6 then break end
    U.wait(1)
  end
  U.shot(game, DIR .. "/bug317_2_arrow_on.png")
  for _ = 1, 60 do
    if (wild.frame % 60) >= 34 then break end
    U.wait(1)
  end
  U.shot(game, DIR .. "/bug317_3_arrow_off.png")

  -- dismiss it: ClearSprites + both ClearScreenAreas, then the enemy HUD
  U.tap(game, "a")
  U.wait(4)
  check("dismissing the box closes the window", wild.introBalls == nil)
  local rows2, strings2 = snapshot(wild)
  check("no ball row survives the dismissal", #rows2 == 0)
  check("the enemy HUD appears once the box is gone",
        drewString(strings2, wild.enemy.name))
  U.shot(game, DIR .. "/bug317_4_enemy_hud.png")

  -- The back pic walking off the left edge before "Go! X!".  Keep watching
  -- past the mid-slide shot: U.shot spins frames of its own, so breaking on
  -- it would under-report how far the pic travelled.
  local lowest, shot = 0, false
  for _ = 1, 400 do
    local off = wild:picOffset("back")
    if off < lowest then lowest = off end
    if not shot and off <= -24 and off >= -52 then
      shot = true
      U.shot(game, DIR .. "/bug317_5_back_slide.png")
    end
    if wild.phase == "menu" or wild.showPlayerBack == false then break end
    U.wait(1)
  end
  check("a mid-slide frame was captured", shot)
  check("the back pic walked the full 9 tiles off the left edge (reached "
        .. lowest .. "px of -72)", lowest <= -72)

  -- ---- part 2: a LIVE trainer intro, handed over -------------------------
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  ow = game.overworld

  local function liveBattle()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == BattleState then return s end
    end
    return nil
  end

  local function trainerNpc()
    for _, n in ipairs((ow and ow.npcs) or {}) do
      if n.def and n.def.name == TRAINER then return n end
    end
    return nil
  end

  local npc = trainerNpc()
  check("the trainer object loaded on the live map", npc ~= nil)

  -- Walk WEST along row 6 into the sight line.  If a map edit moved the
  -- trainer, re-approach at whatever row it now sits on.
  if npc and (npc.cellY ~= STAND.y) then
    U.log("trainer moved to", npc.cellX, npc.cellY, "-- re-approaching")
    U.teleport(game, MAP, math.min(npc.cellX + 3, (ow.map.widthCells or 60) - 1),
               npc.cellY, "left")
    U.wait(10)
  end

  local battle
  for _ = 1, 12 do
    U.hold(game, "left", 12)
    U.wait(20)
    battle = liveBattle()
    if battle then break end
    -- the pre-battle line ("I like shorts!") holds the overworld; clear it
    U.tap(game, "a")
    U.wait(20)
    battle = liveBattle()
    if battle then break end
  end

  if not battle then
    -- rather than park the player facing nothing, push the same battle
    U.log("FAIL the sight line did not trip; pushing the battle directly")
    local cls = trainerDef and trainerDef.trainerClass or "OPP_BUG_CATCHER"
    local pty = trainerDef and trainerDef.trainerParty or 4
    battle = BattleState.newTrainer(game, cls, pty)
    battle.onFinish = function() end
    if ow then ow:pushBattle(battle) end
  end

  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("a trainer battle is on screen", liveBattle() ~= nil)
  check("its intro window is open", battle.introBalls == true)
  local rows3 = snapshot(battle)
  check("a TRAINER intro draws BOTH ball rows", #rows3 == 2)
  if rows3[1] and rows3[2] then
    check("the foe's row is at (64, 16) stepping -8",
          rows3[1].x == 64 and rows3[1].y == 16 and rows3[1].step == -8)
    check("the player's row is at (88, 80) stepping +8",
          rows3[2].x == 88 and rows3[2].y == 80 and rows3[2].step == 8)
  end
  U.shot(game, DIR .. "/bug317_6_trainer_intro.png")

  -- ---- hand off ----------------------------------------------------------
  U.log("The BUG CATCHER's intro box is up. Press A to walk the rest of it.")
  U.log("Correct: six ball slots per side with a thin underline under each row,")
  U.log("an arrow blinking bottom-right, and each trainer pic WALKING off its")
  U.log("own edge before its send-out text prints (#317).")
  U.log("Screenshots of the wild half: " .. DIR .. "/bug317_*.png")

  while true do
    coroutine.yield()
  end
end
