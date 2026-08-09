-- Driver: screenshot a voxel-mode connection crossing frame by frame.
--
-- Stands at the Viridian -> Route 1 seam (script-free, unlike Pallet's
-- north edge where Oak interrupts a fresh save), engages voxel 35, waits
-- for the neighbourhood to finish building, then walks south across the
-- seam capturing every other frame -- the burst shows whether the seam
-- line carries stray pixels and whether the walker's height stays glued
-- to the ground through the crossing.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"

  U.teleport(game, "VIRIDIAN_CITY", 20, 33, "down")
  game:keypressed("6")
  U.wait(5)
  game:keypressed("6")   -- 35 degrees
  U.wait(150)            -- let every neighbour mesh land
  U.shot(game, DIR .. "/seam_0_viridian.png")

  local shot = 0
  for i = 1, 56 do
    table.insert(game.input.pressQueue, "down")
    game.input.state.down = true
    coroutine.yield()
    game.input.state.down = false
    if i % 2 == 0 and i >= 24 then
      shot = shot + 1
      U.shot(game, DIR .. ("/seam_cross_%02d.png"):format(shot))
    end
  end
  print("[seam-shots] end map " .. game.overworld.map.id
        .. " cell " .. game.overworld.player.cellX
        .. "," .. game.overworld.player.cellY)
end
