-- Driver: forced-step shoves use the wrong primitive (issue #151).
--
-- Two related defects, both a scripted "push the player back one step" that
-- reaches for the wrong movement primitive:
--
--   A  MUSEUM_1F ticket rope (data/scripts/story2.lua museumClerk onDecline):
--      declining the Y50 ticket must shove the player one cell SOUTH off the
--      exhibit rope (scripts/Museum1F.asm) -- the player crossed the rope
--      heading NORTH, so the shove is south.  The bug shoved "right" onto the
--      counter tile (11,4)=tile 23, non-walkable, matching the report's "moved
--      onto the table".  Correct landing is (10,5)=tile 1 (walkable floor).
--
--   B  VIRIDIAN_CITY gym lock (data/scripts/story5.lua stepGate/viridianGym-
--      Lock): the tile below the Gym door (32,8)=tile 44 is a DOWN-ledge
--      (44 -> 55, data/tilesets/ledge_tiles.asm); Gen1 shoves the player with a
--      SIMULATED JOYPAD down-press that runs the normal step pipeline including
--      HandleLedges (engine/overworld/ledges.asm), so the shove HOPS the ledge
--      and lands on (32,10)=tile 57.  The bug used a raw scriptMove that
--      ignores ledges, planting the player standing on the ledge tile (32,9).
--
-- Both cases assert the CORRECT Gen1 outcome, so this FAILS on the bug and
-- PASSES once the shove primitives are fixed.
--
-- Run:
--   POKEPORT_DRIVER=tests/drivers/decline_push_bug151_test.lua \
--   POKEPORT_IDENTITY=bug151 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local shotDir = os.getenv("POKEPORT_SHOTDIR") or "."
  local function shot(name) U.shot(game, shotDir .. "/" .. name) end
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")

  -- a party + starter flag so the overworld is fully usable
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  end

  local fails = 0
  local function expect(cond, ...)
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  -- Advance dialog until control returns to the overworld: tap A through
  -- TextBoxes, tap B through a ChoiceBox (B always declines -- ChoiceBox:update
  -- calls onChoose(false) on B).  Bounded so a stuck box can't hang the run.
  local function driveDialog(maxIters)
    for _ = 1, (maxIters or 240) do
      local top = game.stack:top()
      if top == game.overworld then return true end
      if getmetatable(top) == ChoiceBox then
        U.tap(game, "b")
      elseif getmetatable(top) == TextBox then
        U.tap(game, "a")
      else
        -- unknown state: nudge with A so we never wedge
        U.tap(game, "a")
      end
      U.wait(2)
    end
    return game.stack:top() == game.overworld
  end

  -- Drain queued scriptMoves + any in-flight step, sampling p.hopFrames each
  -- frame (a hop arc is set only by checkLedgeHop).  Returns whether a hop was
  -- ever seen while draining.
  local function drainMoves(p, maxFrames)
    local hopSeen = (p.hopFrames or 0) > 0
    for _ = 1, (maxFrames or 180) do
      local ow = game.overworld
      local pending = ow.scriptMoves and #ow.scriptMoves > 0
      if not pending and not p.moving and (p.hopFrames or 0) == 0 then break end
      if (p.hopFrames or 0) > 0 then hopSeen = true end
      U.wait(1)
    end
    return hopSeen
  end

  -- ------------------------------------------------------------------
  -- Case A: MUSEUM_1F ticket-rope decline must shove SOUTH, not RIGHT.
  -- ------------------------------------------------------------------
  do
    game.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = false
    game.save.money = 1000 -- enough to buy, so declining is a real NO choice
    U.teleport(game, "MUSEUM_1F", 10, 5, "up")
    U.wait(6)
    local p = game.overworld.player
    shot("museum_decline_before.png")
    -- step north onto the rope cell (10,4); the clerk stops us there
    U.hold(game, "up", 24)
    -- clerk dialog: advance the pitch, decline the YES/NO, clear "Come again!"
    driveDialog(240)
    drainMoves(p, 120)
    shot("museum_decline_after.png")
    expect(p.cellX == 10 and p.cellY == 5,
      "A: declining shoves the player SOUTH to (10,5), got:", p.cellX, p.cellY)
  end

  -- ------------------------------------------------------------------
  -- Case B: VIRIDIAN_CITY gym lock shove must HOP the down-ledge.
  -- ------------------------------------------------------------------
  do
    -- fresh badge state: no non-Earth badges, so the gym stays locked
    game.save.inventory = game.save.inventory or {}
    for _, b in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE",
                         "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE",
                         "VOLCANOBADGE" }) do
      game.save.inventory[b] = nil
    end
    U.teleport(game, "VIRIDIAN_CITY", 31, 8, "right")
    U.wait(6)
    local p = game.overworld.player
    shot("viridian_gymlock_before.png")
    -- step east onto (32,8) directly below the locked Gym door
    U.hold(game, "right", 24)
    -- the "GYM's doors are locked..." box appears; clearing it fires the shove
    local ow = game.overworld
    local hopSeen = false
    for _ = 1, 240 do
      local top = game.stack:top()
      if top == game.overworld then break end
      if getmetatable(top) == TextBox then U.tap(game, "a") else U.tap(game, "a") end
      if (p.hopFrames or 0) > 0 then hopSeen = true end
      U.wait(2)
      if (p.hopFrames or 0) > 0 then hopSeen = true end
    end
    if drainMoves(p, 180) then hopSeen = true end
    shot("viridian_gymlock_after.png")
    expect(hopSeen, "B: the gym-lock shove HOPS the ledge (hop arc seen)")
    expect(p.cellX == 32 and p.cellY == 10,
      "B: landed south of the ledge at (32,10), got:", p.cellX, p.cellY)
  end

  if fails > 0 then error(fails .. " check(s) failed") end
  U.log("all checks passed -- #151 shoves are Gen1-correct "
    .. "(museum decline goes south, Viridian gym lock hops the ledge)")
end
