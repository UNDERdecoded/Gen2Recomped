-- Driver: Seafoam Islands B3F strong-current plug rocks (issue #212).
--
-- The two boulders the player pushes down through the B2F holes land on B3F
-- at cells (18,6) and (19,6) and plug the strong current (the reporter's
-- expected.png shows two round rocks sitting in the channel).  The B2F
-- pluggedByHolesOn holes were wired to showObject TOGGLE_..._B3F_BOULDER_3/_4,
-- which OverworldState:toggleToObjectName resolves to SEAFOAMISLANDSB3F_
-- BOULDER3/4 -- the ALREADY-VISIBLE pushable boulders at (8,14)/(9,14), not the
-- hidden landing rocks.  The real landing objects at (18,6)/(19,6) are the
-- hidden BOULDER5/6, so the plug rocks never appeared (data/generated/field.lua
-- + tools/rom_manifest*.json now point showObject at BOULDER_5/_6).
--
-- Case A asserts the CORRECT Gen1 outcome (rocks appear after plugging), so it
-- FAILS on the bug and PASSES once the toggles are repointed.
--
-- Case B is a regression guard: with only ONE rock the current stays active
-- and gates the sole water chokepoint (the 2-wide gap at (18,7)/(19,7) is the
-- only water passage between the south and north pools -- verified from the
-- B3F water map), so a surfing player stepping up into it is swept south
-- (SeafoamIslandsB3F.asm) and cannot cross north.  This confirms the reported
-- "swim in the strong current" is not reproducible around the trigger cells.
--
-- Run:
--   POKEPORT_DRIVER=tests/drivers/seafoam_current_bug212_test.lua \
--   POKEPORT_IDENTITY=bug212 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local shotDir = os.getenv("POKEPORT_SHOTDIR") or "."
  local function shot(name) U.shot(game, shotDir .. "/" .. name) end
  local Pokemon = require("src.pokemon.Pokemon")

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.party = { Pokemon.new(game.data, "LAPRAS", 40) }
  -- SURF (+ STRENGTH for the real puzzle) so the surfing/current paths run
  game.save.party[1].moves = { { id = "SURF" }, { id = "STRENGTH" } }

  local fails = 0
  local function expect(cond, ...)
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  -- a visible SPRITE_BOULDER standing on cell (x,y)?  self.npcs only holds
  -- objects objectVisible() accepted, so a hidden-but-untoggled rock is absent
  local function boulderAt(x, y)
    for _, n in ipairs(game.overworld.npcs) do
      local def = n.def
      if def and def.sprite == "SPRITE_BOULDER"
         and n.cellX == x and n.cellY == y then
        return true
      end
    end
    return false
  end

  -- ------------------------------------------------------------------
  -- Case A: plugging both B2F holes reveals the B3F landing rocks.
  -- ------------------------------------------------------------------
  do
    game.save.objectToggles = {}
    game.save.flags.EVENT_SEAFOAM3_BOULDER1_DOWN_HOLE = nil
    game.save.flags.EVENT_SEAFOAM3_BOULDER2_DOWN_HOLE = nil

    -- baseline: the empty channel, no plug rocks yet
    U.teleport(game, "SEAFOAM_ISLANDS_B3F", 18, 8, "up")
    game.overworld.player.surfing = true
    U.wait(8)
    shot("b3f_channel_empty.png")
    expect(not boulderAt(18, 6) and not boulderAt(19, 6),
      "A0: before plugging, no rock in the channel at (18,6)/(19,6)")

    -- push both plug boulders through their B2F holes via the real engine
    -- path (OverworldState:boulderIntoHole sets the event flag AND the
    -- destMap showObject toggle by name)
    U.teleport(game, "SEAFOAM_ISLANDS_B2F", 19, 7, "up")
    U.wait(6)
    game.overworld:boulderIntoHole({ cellX = 19, cellY = 6 }) -- lands B3F (18,6)
    game.overworld:boulderIntoHole({ cellX = 22, cellY = 6 }) -- lands B3F (19,6)
    U.wait(4)

    U.teleport(game, "SEAFOAM_ISLANDS_B3F", 18, 8, "up")
    game.overworld.player.surfing = true
    U.wait(8)
    shot("b3f_channel_plugged.png")
    expect(boulderAt(18, 6), "A1: plug rock visible at (18,6) after plugging both holes")
    expect(boulderAt(19, 6), "A2: plug rock visible at (19,6) after plugging both holes")
  end

  -- ------------------------------------------------------------------
  -- Case B: one rock -> current still gates the channel, no swim-through.
  -- ------------------------------------------------------------------
  do
    game.save.objectToggles = {}
    game.save.flags.EVENT_SEAFOAM3_BOULDER1_DOWN_HOLE = true
    game.save.flags.EVENT_SEAFOAM3_BOULDER2_DOWN_HOLE = nil
    U.teleport(game, "SEAFOAM_ISLANDS_B3F", 18, 8, "up")
    local p = game.overworld.player
    p.surfing = true
    U.wait(6)
    local startY = p.cellY
    local minY = p.cellY
    -- try to paddle north through the current toward the (18,4..6) pool
    for _ = 1, 90 do
      table.insert(game.input.pressQueue, "up")
      game.input.state["up"] = true
      coroutine.yield()
      if p.cellY < minY then minY = p.cellY end
    end
    game.input.state["up"] = false
    U.wait(20)
    if p.cellY < minY then minY = p.cellY end
    -- the north pool begins at y<=6; reaching it means the current failed to
    -- gate the passage.  Being swept keeps minY at 7 (the current cell) or south.
    expect(minY >= 7,
      "B: current gates the channel; player never crossed north (min cellY):", minY)
    U.log("B: start cellY", startY, "min cellY", minY, "end cellY", p.cellY,
      "surfing", tostring(p.surfing))
  end

  if fails > 0 then error(fails .. " check(s) failed") end
  U.log("all checks passed -- #212 seafoam B3F plug rocks appear "
    .. "and the strong current gates the channel")
end
