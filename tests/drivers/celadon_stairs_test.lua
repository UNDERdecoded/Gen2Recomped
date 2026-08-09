-- Driver: Celadon Mansion back-stair landings.  The 2F/3F/1F west and
-- middle stair landings are door tiles with a solid shelf cell directly
-- south; the door walk-out step must bump there (simulated d-pad press),
-- not force the player through the wall (the Eevee-house stairwell
-- stuck-in-shelves bug).  East stairs keep the normal walk-out.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ow
  local fails = 0
  local function expect(cond, ...)
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end
  local function settle(mapId)
    for _ = 1, 300 do
      ow = game.overworld
      if ow and ow.map.id == mapId and not ow.transitioning
         and #ow.scriptMoves == 0 and not ow.player.moving then
        break
      end
      U.wait(1)
    end
    U.wait(4)
    ow = game.overworld
  end

  -- climb the west back stairs: 1F (2,1) -> 2F landing (2,1), whose south
  -- cell is the solid shelf row
  U.teleport(game, "CELADON_MANSION_1F", 4, 1, "left")
  U.hold(game, "left", 70)
  settle("CELADON_MANSION_2F")
  expect(ow.map.id == "CELADON_MANSION_2F", "west stairs arrive 2F, map:", ow.map.id)
  expect(ow.player.cellX == 2 and ow.player.cellY == 1,
         "player stays on landing (2,1), got:", ow.player.cellX, ow.player.cellY)
  expect(ow.map:isWalkableCell(ow.player.cellX, ow.player.cellY),
         "standing cell walkable, tile:",
         string.format("%02x", ow.map:cellTile(ow.player.cellX, ow.player.cellY)))

  -- the landing is not a trap: one step east onto the walkway works
  -- (short tap: (4,1) beyond it is the middle-stairs warp)
  U.hold(game, "right", 4)
  U.wait(24)
  ow = game.overworld
  expect(ow.map.id == "CELADON_MANSION_2F" and ow.player.cellX == 3,
         "stepped east off the landing, at:", ow.map.id,
         ow.player.cellX, ow.player.cellY)

  -- stepping back onto the stairs still takes them down to 1F
  U.hold(game, "left", 4)
  settle("CELADON_MANSION_1F")
  expect(ow.map.id == "CELADON_MANSION_1F", "stairs back down, map:", ow.map.id)
  expect(ow.player.cellX == 2 and ow.player.cellY == 1,
         "1F landing holds too (2,1), got:", ow.player.cellX, ow.player.cellY)

  -- east stairs land on (7,1) with open floor south: the vanilla
  -- walk-out step must still fire
  U.teleport(game, "CELADON_MANSION_1F", 7, 3, "up")
  U.hold(game, "up", 70)
  settle("CELADON_MANSION_2F")
  expect(ow.map.id == "CELADON_MANSION_2F", "east stairs arrive 2F, map:", ow.map.id)
  expect(ow.player.cellX == 7 and ow.player.cellY == 2,
         "walk-out stepped south to (7,2), got:", ow.player.cellX, ow.player.cellY)

  -- a save already stuck inside the shelf (pre-fix) escapes north onto
  -- the stairs, which warp back down
  U.teleport(game, "CELADON_MANSION_2F", 2, 2, "up")
  U.hold(game, "up", 24)
  settle("CELADON_MANSION_1F")
  expect(ow.map.id == "CELADON_MANSION_1F", "stuck save escapes via stairs, map:",
         ow.map.id)

  if fails > 0 then error(fails .. " check(s) failed") end
  U.log("all checks passed")
end
