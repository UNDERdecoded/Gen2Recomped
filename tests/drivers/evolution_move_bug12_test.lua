-- Driver: evolution grants the new species' level-up move (#12).
--
-- pokered engine/pokemon/evos_moves.asm (EvolveMon) re-runs the level-up
-- learn check on the *evolved* species after the "evolved into" text, via
-- the LearnMoveFromLevelUp predef (engine/pokemon/learn_move.asm).  The
-- check is EXACT level equality (learnset entry level == mon.level), so a
-- mon evolving at exactly a learnset level gains that move.
--
-- Data pins: GYARADOS.learnset has { level = 20, move = "BITE" }
-- (data/generated/pokemon.lua), so MAGIKARP->GYARADOS at level 20 must
-- learn BITE, while an evolution at level 21 must NOT (nothing at 21).
--
-- Case 1 (repro/fix): Lv20 MAGIKARP knowing only SPLASH evolves; after the
-- congratulations text the mon must be GYARADOS and know BITE, and the
-- "GYARADOS learned BITE!" text must appear.  This assertion FAILS on the
-- pre-fix build (no learn step) and PASSES once the fix runs the check.
-- Case 2 (control): Lv21 MAGIKARP evolves to GYARADOS and must NOT gain
-- BITE (guards the exact-level == rule against an over-broad <= fix).
--
--   SHOT_DIR=/tmp/evo12 POKEPORT_DRIVER=tests/drivers/evolution_move_bug12_test.lua \
--     POKEPORT_IDENTITY=bug12 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/evo12"
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
  local function mashUntil(cond, max)
    for _ = 1, max or 200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return cond()
  end
  local function hasMove(mon, id)
    for _, mv in ipairs(mon.moves) do
      if mv.id == id then return true end
    end
    return false
  end

  U.teleport(game, "ROUTE_1", 5, 5, "down")

  -- === Case 1: MAGIKARP @20 -> GYARADOS must learn BITE ===
  local mon = Pokemon.new(game.data, "MAGIKARP", 20)
  mon.moves = { { id = "SPLASH", pp = 40 } } -- deterministic single slot
  table.insert(game.save.party, 1, mon)
  local done1 = false
  Evolution.evolve(game, mon, "GYARADOS", function() done1 = true end)

  if not waitFor(evoTop, 300) then error("EvolutionState never opened (case1)") end
  -- let the full flash run (FLASH_FRAMES=220) with no input, then apply
  waitFor(function() return not evoTop() end, 400)
  if not waitFor(function() return findText("evolved into") ~= nil end, 120) then
    error("Congratulations text not shown (case1)")
  end
  U.wait(40) -- let the congrats text finish typing before the shot
  U.shot(game, DIR .. "/evo12_1_congrats.png")

  -- advance past congrats into the level-up learn flow; the fix pushes
  -- "GYARADOS learned BITE!" here (pre-fix: onDone fires with no learn)
  local sawLearned = false
  mashUntil(function()
    if findText("learned") then sawLearned = true; return true end
    return done1
  end, 200)
  U.wait(30) -- let the "learned BITE!" text type out (fix path)
  U.shot(game, DIR .. "/evo12_2_learned.png")

  mashUntil(function() return done1 end, 120)
  U.log("case1", "species=", mon.species, "hasBite=", hasMove(mon, "BITE"),
        "sawLearned=", sawLearned)

  assert(mon.species == "GYARADOS",
    "case1: mon stayed " .. tostring(mon.species) .. " (expected GYARADOS)")
  assert(hasMove(mon, "BITE"),
    "case1: GYARADOS did not learn BITE on evolution at level 20 (bug #12)")
  assert(sawLearned, "case1: no 'learned' text shown for the evolution move")

  -- === Case 2 (control): MAGIKARP @21 -> GYARADOS must NOT gain BITE ===
  local mon2 = Pokemon.new(game.data, "MAGIKARP", 21)
  mon2.moves = { { id = "SPLASH", pp = 40 } }
  table.insert(game.save.party, 1, mon2)
  local done2 = false
  Evolution.evolve(game, mon2, "GYARADOS", function() done2 = true end)
  if not waitFor(evoTop, 300) then error("EvolutionState never opened (case2)") end
  waitFor(function() return not evoTop() end, 400)
  if not waitFor(function() return findText("evolved into") ~= nil end, 120) then
    error("Congratulations text not shown (case2)")
  end
  mashUntil(function() return done2 end, 200)
  U.wait(20)
  U.shot(game, DIR .. "/evo12_3_lv21_no_bite.png")
  U.log("case2", "species=", mon2.species, "hasBite=", hasMove(mon2, "BITE"))

  assert(mon2.species == "GYARADOS",
    "case2: mon2 stayed " .. tostring(mon2.species) .. " (expected GYARADOS)")
  assert(not hasMove(mon2, "BITE"),
    "case2: GYARADOS wrongly learned BITE at level 21 (over-grant; exact == broken)")

  U.log("done", "case1=", mon.species, "case2=", mon2.species)
  love.event.quit()
end
