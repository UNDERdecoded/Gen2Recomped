-- FireRed regression: Lorelei's north door must become a real step warp as
-- soon as her victory flag is set. This exercises the same onVictory hook the
-- battle path runs, then physically walks through to Bruno's room.
return function(game)
  local U = require("tests.drivers.util")
  local save = U.freshSave(game)

  -- Keep the room-entry helper from moving the player while this test starts
  -- one step south of the exit. Lorelei is deliberately still undefeated so
  -- the shipped closed door is what the map loads first.
  save.flags.EVENT_AUTOWALKED_INTO_LORELEIS_ROOM = true
  U.teleport(game, "MAP_G01_N75", 6, 3, "up")

  local ow = assert(game.overworld)
  local room = assert(require("data.scripts.init").get("LORELEIS_ROOM"))
  assert(ow.map:blockAt(6, 2) ~= 0x296,
    "Lorelei exit unexpectedly starts open")

  save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0 = true
  room.onVictory(game, ow)

  assert(ow.map:blockAt(6, 1) == 0x28E,
    "Lorelei exit top metatile did not open")
  assert(ow.map:blockAt(6, 2) == 0x296,
    "Lorelei exit warp metatile did not open")
  assert(ow.map:cellCollision(6, 2) == 0,
    "Lorelei exit warp remained collision-blocked")

  U.hold(game, "up", 90)
  U.wait(10)
  assert(game.overworld.map.id == "BRUNOS_ROOM",
    "walking through Lorelei's opened door did not reach Bruno's room")
  U.log("PASS Lorelei door opens and physically warps to Bruno")
  love.event.quit(0)
end
