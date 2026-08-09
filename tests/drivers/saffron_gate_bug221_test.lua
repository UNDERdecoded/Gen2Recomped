-- Driver: #221 Saffron gate guards use the WRONG dialogue.
--
-- The reporter (build 0.1.25) saw the guard ACCEPT a drink he never had --
-- "...Huh? I can have this drink? Gee, thanks!" (_SaffronGateGuardImParchedText,
-- data/generated/text.lua:2050) -- while walking up to the gate carrying NO
-- drink.  Gen1 (scripts/Route5Gate.asm Route5GateDefaultScript) instead turns
-- a drink-less player back with the thirsty line
-- (_SaffronGateGuardGeeImThirstyText, text.lua:2049: "I'm on guard duty. / Gee,
-- I'm thirsty, though! ... the road's closed."), and only ACCEPTS a drink (via
-- `farcall RemoveGuardDrink`, engine/items/inventory.asm) when one is in the bag.
--
-- The guard object sits at cell (1,3), walled into an isolated 1x3 booth
-- (pokered Route5Gate object_event 1,3 SPRITE_GUARD STAY RIGHT), so he is
-- unreachable on foot: the block/dialogue is driven entirely by the onStep
-- coordinate trigger on the corridor cells (3,3)/(4,3), not the TALK handler.
-- This driver walks the player north through that trigger and asserts:
--
--   CASE A (no drink): the box is the THIRSTY line, NOT the accept line, and
--     the player is shoved back one tile and stays inside ROUTE_5_GATE.
--   CASE B (FRESH_WATER in bag): the box is the ACCEPT line, the drink is
--     consumed, EVENT_GAVE_GUARDS_DRINK is set, and the player walks on
--     through (map leaves ROUTE_5_GATE).
--
-- On the 0.1.25 bug CASE A would type the accept line and fail; current HEAD
-- (fixed by #201) passes.  Run with:
--
--   SHOT_DIR=/tmp/saffron221 POKEPORT_IDENTITY=bug221 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/saffron_gate_bug221_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")

  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"
  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 10) }
  game.save.flags = game.save.flags or {}

  local function topText()
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

  local function isBox()
    return getmetatable(game.stack:top()) == TextBox
  end

  -- let the typewriter finish typing up to its first pause (a <CONT> scroll
  -- or page break sets self.waiting), so a screenshot shows the guard's
  -- words instead of an empty just-opened box.
  local function waitTyped(maxFrames)
    for _ = 1, (maxFrames or 240) do
      local top = game.stack:top()
      if getmetatable(top) == TextBox and (top.waiting or top.done) then return end
      U.wait(1)
    end
  end

  -- walk the player north (holding "up") until a dialogue box pops or we
  -- give up; returns true if a box appeared.  Only presses while the
  -- overworld is on top and the player is not already mid-step, so a step
  -- that lands on the trigger cleanly hands control to the pushed TextBox.
  local function walkNorthUntilBox(ow, maxFrames)
    for _ = 1, maxFrames do
      if isBox() then return true end
      if game.stack:top() == ow and not ow.player.moving
         and not ow.runner:isRunning() and #ow.scriptMoves == 0
         and not ow.transitioning then
        table.insert(game.input.pressQueue, "up")
        game.input.state.up = true
      end
      U.wait(1)
      game.input.state.up = false
    end
    return isBox()
  end

  local function settle(ow, maxFrames)
    for _ = 1, (maxFrames or 200) do
      if game.stack:top() == ow and not ow.player.moving
         and not ow.runner:isRunning() and #ow.scriptMoves == 0
         and not ow.transitioning then
        return
      end
      if game.stack:top() ~= ow then U.tap(game, "a") end
      U.wait(2)
    end
  end

  -- ---------------------------------------------------------------
  -- CASE A: no drink -> thirsty line + shove back, gate stays shut
  -- ---------------------------------------------------------------
  game.save.inventory = {}
  game.save.flags.EVENT_GAVE_GUARDS_DRINK = nil

  U.teleport(game, "ROUTE_5_GATE", 3, 5, "up")
  local ow = game.overworld
  assert(ow and ow.map.id == "ROUTE_5_GATE",
    "CASE A: teleport did not land inside ROUTE_5_GATE (got "
    .. tostring(ow and ow.map.id) .. ")")
  assert(ow.player.cellX == 3 and ow.player.cellY == 5,
    "CASE A: player not at spawn (3,5); got "
    .. ow.player.cellX .. "," .. ow.player.cellY)
  U.log("CASE A start:", ow.map.id, ow.player.cellX, ow.player.cellY)

  local gotBoxA = walkNorthUntilBox(ow, 400)
  waitTyped(240)
  U.shot(game, DIR .. "/saffron_bug221_nodrink.png")
  local textA = topText()
  U.log("CASE A box:", gotBoxA, "text:", textA)
  assert(gotBoxA, "CASE A: no dialogue box appeared at the gate trigger")

  -- CORRECT Gen1: the drink-less thirsty line, NOT the accept/parched line.
  assert(textA:find("thirsty", 1, true),
    "CASE A: box is not the thirsty line (got: " .. textA .. ")")
  assert(not textA:find("this drink", 1, true)
     and not textA:find("Gee, thanks", 1, true),
    "CASE A(#221): drink-less guard spoke the ACCEPT line (got: " .. textA .. ")")

  -- mash A through the (multi-page) thirsty box; the onDone shoves the
  -- player back one tile.  He must NOT pass -- still inside ROUTE_5_GATE.
  settle(ow, 300)
  U.log("CASE A after:", ow.map.id, ow.player.cellX, ow.player.cellY)
  assert(ow.map.id == "ROUTE_5_GATE",
    "CASE A: drink-less player passed the gate (map=" .. ow.map.id .. ")")
  assert(ow.player.cellY >= 4,
    "CASE A: player was not turned back (cellY=" .. ow.player.cellY .. ")")
  assert(not game.save.flags.EVENT_GAVE_GUARDS_DRINK,
    "CASE A: gave-drink flag set without a drink")

  -- ---------------------------------------------------------------
  -- CASE B: FRESH_WATER in bag -> accept line, drink taken, pass through
  -- ---------------------------------------------------------------
  game.save.inventory = { FRESH_WATER = 1 }
  game.save.flags.EVENT_GAVE_GUARDS_DRINK = nil

  U.teleport(game, "ROUTE_5_GATE", 3, 5, "up")
  ow = game.overworld
  assert(ow.map.id == "ROUTE_5_GATE", "CASE B: re-teleport failed")
  U.log("CASE B start:", ow.map.id, ow.player.cellX, ow.player.cellY)

  local gotBoxB = walkNorthUntilBox(ow, 400)
  waitTyped(240)
  U.shot(game, DIR .. "/saffron_bug221_drink.png")
  local textB = topText()
  U.log("CASE B box:", gotBoxB, "text:", textB)
  assert(gotBoxB, "CASE B: no dialogue box appeared at the gate trigger")

  -- CORRECT Gen1: carrying a drink triggers the parched/accept line.
  assert(textB:find("this drink", 1, true) or textB:find("Gee, thanks", 1, true),
    "CASE B: guard did not speak the accept line (got: " .. textB .. ")")

  -- clear the accept + "you can go on through" boxes, then keep walking
  -- north out the top of the gate.
  for _ = 1, 400 do
    if game.stack:top() ~= ow then
      U.tap(game, "a")
    else
      break
    end
    U.wait(2)
  end
  U.log("CASE B post-accept:", "FRESH_WATER=",
        tostring(game.save.inventory.FRESH_WATER),
        "flag=", tostring(game.save.flags.EVENT_GAVE_GUARDS_DRINK))
  assert(game.save.inventory.FRESH_WATER == nil,
    "CASE B: the drink was not consumed")
  assert(game.save.flags.EVENT_GAVE_GUARDS_DRINK == true,
    "CASE B: EVENT_GAVE_GUARDS_DRINK not set after accepting the drink")

  -- with the flag now set the corridor is free; walk on out the north side
  -- and STOP the instant the gate map is left (don't wander into the town's
  -- scripts -- the north warp resolves to the heal point when we teleported
  -- in with no remembered outdoor side, OverworldController:takeWarp).
  for _ = 1, 300 do
    ow = game.overworld
    if ow.map.id ~= "ROUTE_5_GATE" then break end
    if game.stack:top() == ow and not ow.player.moving
       and not ow.runner:isRunning() and #ow.scriptMoves == 0
       and not ow.transitioning then
      table.insert(game.input.pressQueue, "up")
      game.input.state.up = true
    end
    U.wait(1)
    game.input.state.up = false
  end
  ow = game.overworld
  U.shot(game, DIR .. "/saffron_bug221_passed.png")
  U.log("CASE B end:", ow.map.id, ow.player.cellX, ow.player.cellY)
  assert(ow.map.id ~= "ROUTE_5_GATE",
    "CASE B: player with a drink never passed the gate")

  U.log("saffron_gate_bug221_test: ok")
  love.event.quit()
end
