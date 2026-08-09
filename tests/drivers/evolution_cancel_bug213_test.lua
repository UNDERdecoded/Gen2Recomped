-- Driver: cancel an evolution with the B button (#213).
--
-- pokered engine/pokemon/evos_moves.asm polls hJoyHeld during the pic
-- flash: holding B aborts the evolution (the mon keeps its species and
-- _StoppedEvolvingText prints).  Trade evolutions (wLinkState ==
-- LINK_STATE_TRADING) skip that poll and cannot be cancelled.
--
-- Case 1 (level path, cancelable): open EvolutionState directly, wait a
-- few frames into the flash (t well under FLASH_FRAMES=220), hold B, and
-- assert the mon stays CATERPIE with "stopped evolving" text on screen.
-- Case 1b: after cancel, checkParty with no level-ups must not re-offer;
-- a subsequent level-up set must offer again (EvolveAfterBattle parity).
-- Case 2 (control): let the flash run to completion with no input and
-- assert the mon becomes METAPOD with the "Congratulations!" text.
--
--   SHOT_DIR=/tmp/evo213 POKEPORT_DRIVER=tests/drivers/evolution_cancel_bug213_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/evo213"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local Evolution = require("src.pokemon.Evolution")

  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1

  local function top() return game.stack:top() end
  local function evoTop()
    local t = top()
    return t and t.screenId == "EvolutionState"
  end
  local function waitFor(cond, max)
    for _ = 1, max or 600 do
      if cond() then return true end
      U.wait(1)
    end
    return false
  end
  -- flatten a TextBox's paginated pages (list of line lists) to one string
  local function pagesText(st)
    if not st.pages then return nil end
    local parts = {}
    for _, page in ipairs(st.pages) do
      if type(page) == "table" then
        for _, line in ipairs(page) do
          if type(line) == "string" then parts[#parts + 1] = line end
        end
      elseif type(page) == "string" then
        parts[#parts + 1] = page
      end
    end
    return table.concat(parts, " ")
  end
  local function findText(needle)
    for _, st in ipairs(game.stack.states or {}) do
      local blob = pagesText(st)
      if blob and blob:find(needle, 1, true) then return st end
    end
    return nil
  end
  -- mash A (one tap every few frames) until cond holds; a single tap only
  -- fast-forwards a still-typing TextBox, so mashing both finishes the
  -- typewriter and then presses the close button
  local function mashUntil(cond, max)
    for _ = 1, max or 200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return cond()
  end

  U.teleport(game, "ROUTE_1", 5, 5, "down")

  -- === Case 1: hold B during the flash -> evolution aborts ===
  local mon = Pokemon.new(game.data, "CATERPIE", 7)
  table.insert(game.save.party, 1, mon)
  local done1 = false
  Evolution.evolve(game, mon, "METAPOD", function() done1 = true end)

  if not waitFor(evoTop, 300) then error("EvolutionState never opened (case1)") end
  U.wait(20) -- into the flash, well under FLASH_FRAMES=220
  U.log("case1 flash", "t=", top().t, "species=", mon.species)
  U.shot(game, DIR .. "/evo213_1_evolving.png")

  U.hold(game, "b", 20) -- Gen1 hJoyHeld B-cancel

  -- the flash aborts: EvolutionState is no longer the top (the stopped
  -- text overlays it and then pops it)
  if not waitFor(function() return not evoTop() end, 240) then
    error("evolution did not abort on B: still on EvolutionState, species="
      .. tostring(mon.species))
  end
  U.log("case1 aborted", "species=", mon.species)
  U.wait(40) -- let "Huh? MON stopped evolving!" finish typing before the shot
  U.shot(game, DIR .. "/evo213_2_stopped.png")

  assert(mon.species == "CATERPIE",
    "B-cancel failed: mon evolved to " .. tostring(mon.species)
    .. " (expected CATERPIE)")
  assert(findText("stopped evolving"), "StoppedEvolvingText not shown")

  mashUntil(function() return done1 end, 80) -- close the stopped-evolving text
  assert(done1, "cancel onDone never fired")
  assert(mon.species == "CATERPIE", "species changed after cancel tail")

  -- === Case 1b: after B-cancel, checkParty without a level-up must not
  -- re-offer (regression: cancelled mons stuck at threshold tried again
  -- after every later battle, even non-participants). ===
  local nQuiet = Evolution.checkParty(game, nil, {})
  assert(nQuiet == 0, "checkParty with no level-ups re-offered after cancel")
  assert(not evoTop(), "EvolutionState opened after quiet afterBattle")
  assert(mon.species == "CATERPIE", "species changed on quiet checkParty")

  local nLevel = Evolution.checkParty(game, nil, { [mon] = true })
  assert(nLevel == 1, "checkParty after a real level-up should offer once")
  if not waitFor(evoTop, 300) then
    error("EvolutionState never opened after level-up re-offer")
  end
  U.wait(20)
  U.hold(game, "b", 20) -- cancel so case 2 stays independent
  if not waitFor(function() return not evoTop() end, 240) then
    error("level-up re-offer did not abort on B")
  end
  mashUntil(function() return not findText("stopped evolving") end, 80)
  assert(mon.species == "CATERPIE", "species changed after re-offer cancel")

  -- === Case 2 (control): no input -> evolution completes ===
  local mon2 = Pokemon.new(game.data, "CATERPIE", 7)
  table.insert(game.save.party, 1, mon2)
  local done2 = false
  Evolution.evolve(game, mon2, "METAPOD", function() done2 = true end)
  if not waitFor(evoTop, 300) then error("EvolutionState never opened (case2)") end
  -- let the full flash run (FLASH_FRAMES=220) without pressing B
  waitFor(function() return not evoTop() end, 400)
  if not waitFor(function() return findText("evolved into") ~= nil end, 120) then
    error("Congratulations text not shown (case2)")
  end
  U.wait(40) -- let the Congratulations text finish typing before the shot
  U.shot(game, DIR .. "/evo213_3_congrats.png")
  assert(mon2.species == "METAPOD",
    "control failed: mon2 stayed " .. tostring(mon2.species)
    .. " (expected METAPOD)")
  mashUntil(function() return done2 end, 80)

  U.log("done", "case1=", mon.species, "case2=", mon2.species)
  love.event.quit()
end
