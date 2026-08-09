-- Manual check of the two trainer-battle text boxes, #565 and #566.
-- #565 _TrainerAboutToUseText (data/text/text_2.asm:911-921): the SHIFT
-- offer is one box with a `cont`, so the nick scrolls in UNDER "about to
-- use" instead of landing alone on a fresh page.
-- #566 TrainerEndBattleText (home/trainers.asm:381-386) prints
-- _TrainerNameText -- the name then ": " -- ahead of the loss line.
-- The string half is asserted in tests/engine/trainer_shift_prompt_bug565.lua
-- and tests/engine/trainer_loss_line_bug566.lua; this is the look of it.
--   POKEPORT_DRIVER=tests/drivers/trainer_battle_text_bug565_bug566_test.lua POKEPORT_IDENTITY=bug565 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Font = require("src.render.Font")
  local ChoiceBox = require("src.ui.ChoiceBox")

  -- pokered data/maps/objects/Route3.asm: ROUTE3_YOUNGSTER2 is object 3, at
  -- (14, 4), STAY, facing DOWN, OPP_YOUNGSTER party 1 (RATTATA + EKANS).  Its
  -- TrainerHeader gives sight range 3, so the cone is (14,5)..(14,7); y = 7 is
  -- the ledge row and is solid, so the walk-in is east-to-west along y = 6.
  local MAP, MAP_LABEL = "ROUTE_3", "Route3"
  local NPC_NAME = "ROUTE3_YOUNGSTER2"
  local OBJ_INDEX = 3
  local START = { x = 16, y = 6, facing = "left" }

  local fails = 0
  local function check(label, ok)
    if not ok then fails = fails + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Everything the two boxes are assembled from.  A renamed text label, an
  -- opponent whose party shrank to one mon or a species constant that no
  -- longer resolves all show up on screen as exactly the silence the bugs
  -- did, so name them here before anyone squints at a screenshot.
  local header = game.data:trainerHeader(MAP_LABEL, OBJ_INDEX)
  check("Route3 object " .. OBJ_INDEX .. " has a trainer header", header ~= nil)
  local lossText = header and header.won and game.data.text[header.won]
  check("its EndBattleText resolves to a string",
        type(lossText) == "string" and lossText ~= "")

  local trainer = game.data.trainers.OPP_YOUNGSTER
  check("OPP_YOUNGSTER is a known trainer class", trainer ~= nil)
  local party = trainer and trainer.parties[1]
  check("its party 1 has a reserve to send out (SHIFT needs one)",
        party ~= nil and #party >= 2)
  local secondName
  if party and party[2] then
    local species = game.data.pokemon[party[2].species]
    secondName = species and species.name
  end
  check("the reserve's species resolves to a name", secondName ~= nil)

  local TAG = trainer and trainer.name
  local firstLine = TAG and lossText
    and (TAG .. ": " .. lossText:match("^[^\n\f\v]*"))
  if firstLine then
    -- the tag is prose the box has to hold: 18 columns, TextBox MAX_COLS
    local spans = Font.split(firstLine)
    check("the tagged first line fits the 18-column box (" .. #spans .. " cols)",
          Font.spansFitting(spans, 18 * 8) >= #spans)
    U.log("loss box should read:",
          ((TAG .. ": " .. lossText):gsub("[\n\v]", " / "):gsub("\f", " || ")))
  end

  -- SHIFT only offers the switch when the player holds more than one party
  -- slot and the active mon is alive (core.asm:1366-1443)
  game.save.player.name = "RED"
  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 40),
    Pokemon.new(game.data, "BLASTOISE", 40),
  }
  game.save.party[1].moves[1] = { id = "SLASH", pp = 20 }
  game.save.options = game.save.options or {}
  game.save.options.battleStyle = "shift"
  check("two party slots and SHIFT style are set",
        #game.save.party > 1 and game.save.options.battleStyle == "shift")
  check("the window is open and drawing",
        love.window and love.window.isOpen and love.window.isOpen())

  if fails > 0 then
    U.log(fails .. " preflight check(s) failed; the boxes below cannot be trusted.")
  end

  U.teleport(game, MAP, START.x, START.y, START.facing)
  U.wait(15)

  local function findNpc()
    for _, n in ipairs((game.overworld and game.overworld.npcs) or {}) do
      if n.def and n.def.name == NPC_NAME then return n end
    end
  end
  local npc = findNpc()
  check("the YOUNGSTER is on the map", npc ~= nil)

  -- A map edit that moves him invalidates the hand-derived walk-in, so fall
  -- back to standing next to wherever he ended up and talking: engageTrainer
  -- is the same call the line-of-sight approach makes.
  local talkedTo = false
  if npc and (npc.cellX ~= 14 or npc.cellY ~= 4) then
    local ow = game.overworld
    -- {dx, dy, facing to look back at him}
    for _, side in ipairs({ { 0, 1, "up" }, { 0, -1, "down" },
                            { 1, 0, "left" }, { -1, 0, "right" } }) do
      local cx, cy = npc.cellX + side[1], npc.cellY + side[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("he has moved to", npc.cellX, npc.cellY, "- standing at", cx, cy)
        U.teleport(game, MAP, cx, cy, side[3])
        U.wait(10)
        talkedTo = true
        U.tap(game, "a")
        break
      end
    end
  end

  local function battleNow()
    local top = game.stack:top()
    if type(top) == "table" and top.kind == "trainer" then return top end
  end

  -- walk west into the sight cone; two cells, plus slack for the "!" bubble
  if not talkedTo then
    for _ = 1, 6 do
      if game.overworld and game.overworld.engaging then break end
      U.hold(game, "left", 18)
      U.wait(4)
    end
  end
  check("the trainer engaged",
        (game.overworld and game.overworld.engaging) or battleNow() ~= nil
        or talkedTo)

  -- Play it out.  Nothing here is fast-forwarded: the taps are A presses at
  -- the same cadence a player makes them, and the loop stops on the row
  -- under test before it can press the box away.
  local function currentRow()
    local b = battleNow()
    local row = b and b.current
    return b, row and row.text
  end
  local function pump(pred, maxFrames)
    local cool = 0
    for _ = 1, maxFrames or 4000 do
      if pred() then return true end
      if cool > 0 then
        cool = cool - 1
        U.wait(1)
      else
        U.tap(game, "a")
        local b = battleNow()
        cool = (b and (b.phase == "menu" or b.phase == "moveSelect")) and 8 or 5
      end
    end
    return pred()
  end

  local ok = pump(function()
    local _, text = currentRow()
    return text ~= nil and text:find("about to use", 1, true) ~= nil
  end)
  check("the SHIFT offer box came up after the first KO", ok)

  -- Hold at the `cont`: the box has typed "X is" / "about to use" and is
  -- blinking the arrow, waiting for A before it scrolls (ContText).
  pump(function()
    local b = currentRow()
    return b and b.msgWaiting
  end, 400)
  U.shot(game, SHOT_DIR .. "/bug565_1_cont_wait.png")
  local b = battleNow()
  if b and b.current then
    U.log("offer box holds:", (b.current.text:gsub("\n", " / "):gsub("\v", " CONT ")))
  end
  U.tap(game, "a")

  -- and after the scroll: "about to use" on top, the nick beneath it
  pump(function()
    local bb = battleNow()
    return bb and (bb.charIndex or 0) >= (bb.total or 1) and not bb.msgWaiting
  end, 400)
  U.shot(game, SHOT_DIR .. "/bug565_2_scrolled.png")

  -- decline the switch (B is NO, ChoiceBox) and finish the fight
  pump(function() return getmetatable(game.stack:top()) == ChoiceBox end, 600)
  U.wait(10)
  U.tap(game, "b")
  U.wait(10)

  local tagged = TAG and (TAG .. ": ") or "YOUNGSTER: "
  ok = pump(function()
    local _, text = currentRow()
    return text ~= nil and text:sub(1, #tagged) == tagged
  end)
  check("the loss line came up tagged with the trainer class", ok)
  pump(function()
    local bb = battleNow()
    return bb and bb.msgPrompt
  end, 400)
  U.shot(game, SHOT_DIR .. "/bug566_loss_line.png")
  local lb = battleNow()
  if lb and lb.current then
    U.log("loss box holds:", (lb.current.text:gsub("\n", " / ")))
  end

  U.log("Shots are in " .. SHOT_DIR .. ".")
  U.log("bug565_1 should read \"YOUNGSTER is\" / \"about to use\" with the")
  U.log("blinking arrow; bug565_2 the same box after the scroll, \"about to")
  U.log("use\" over \"EKANS!\".  The near miss is a box whose two lines are")
  U.log("\"about to use\" and nothing, or a page holding only \"EKANS!\".")
  U.log("bug566 should read \"YOUNGSTER: I don't\" / \"believe it!\" -- the")
  U.log("colon and the class, not a bare \"I don't believe it!\".")
  U.log("The prize line follows it; the tag never repeats on that one.")
  U.log("A is yours now: press through the money line back to the route.")
  U.log("ROUTE3_YOUNGSTER1 at (10,6) has three mons, so the SHIFT box comes")
  U.log("up twice.  ROUTE3_YOUNGSTER4 at (22,9) is the control: one mon, so")
  U.log("he must show the tagged loss line and no SHIFT offer at all.")

  while true do
    coroutine.yield()
  end
end
