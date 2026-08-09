-- Visual regression for #217: no phantom tall-grass tuft should be drawn
-- over the player's head while crossing the Viridian City -> Route 1 seam.
--
-- The player walks south out of Viridian City's exit path (cellX = 20).  On
-- the step off the south edge, crossConnection swaps in ROUTE_1 and parks the
-- player one cell before the entry point at cellY = -1 (off the top edge) for
-- the duration of the seam step.  ROUTE_1's border block back-fills that
-- off-map row with the grass tile, so before the fix the "feet overdraw"
-- painted an animated grass tuft over the player's head for ~5 frames.
--
-- Screenshots (paths come from SHOT_DIR):
--   grass_seam_during.png  -- the seam step, map == ROUTE_1 and cellY < 0
--   grass_seam_after.png   -- one clean frame after the step lands (cellY >= 0)
--
-- Run: POKEPORT_DRIVER=tests/drivers/grass_seam_bug217_test.lua \
--      POKEPORT_IDENTITY=bug217 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  -- a party + starter flag so the overworld is fully usable
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))

  local shotDir = os.getenv("SHOT_DIR") or "."
  -- south exit path column; four cells above the bottom edge (cellY 35)
  U.teleport(game, "VIRIDIAN_CITY", 20, 31, "down")
  local ow = game.overworld

  local shotDuring, shotAfter = false, false
  for i = 1, 120 do
    table.insert(game.input.pressQueue, "down")
    game.input.state.down = true
    coroutine.yield()
    local p = ow.player
    local inb = ow.map:inBounds(p.cellX, p.cellY)
    U.log(("f=%d map=%-14s cell=(%d,%d) inb=%s grassCell=%s py=%d moving=%s")
      :format(i, ow.map.id, p.cellX, p.cellY, tostring(inb),
        tostring(ow.map:isGrassCell(p.cellX, p.cellY)), p.py, tostring(p.moving)))

    -- BEFORE the fix this is exactly the frame the phantom grass draws:
    -- map is now ROUTE_1 but the player is still parked off the top edge.
    if not shotDuring and ow.map.id == "ROUTE_1" and p.cellY < 0 then
      game.input.state.down = false
      U.shot(game, shotDir .. "/grass_seam_during.png")
      shotDuring = true
      game.input.state.down = true
    end

    -- one clean frame after the seam step lands on the real map
    if shotDuring and not shotAfter and ow.map.id == "ROUTE_1"
       and p.cellY >= 0 and not p.moving then
      game.input.state.down = false
      U.shot(game, shotDir .. "/grass_seam_after.png")
      shotAfter = true
      break
    end
  end
  game.input.state.down = false
  U.wait(2)

  if not shotDuring then U.log("WARN: never captured the seam step frame") end
  if not shotAfter then U.log("WARN: never captured a landed frame") end
end
