-- Driver: trainer sight must not engage off the GB screen (#153/#183).
-- Oracle: engine/overworld/trainer_sight.asm TrainerEngage (IMAGEINDEX=$ff)
-- + movement.asm CheckSpriteAvailability (10x9 window).  8-bit pixel
-- distance wraps at ~12/28 tiles; without the on-screen gate, Viridian
-- Forest / Victory Road trainers aggro through trees and walls.
--
-- Scene A: VIRIDIAN_FOREST (18,33), west of tree wall vs Bug Catcher
--          (30,33) LEFT range 4 -- dx=12 pixel-wrap must NOT engage.
-- Scene B: same trainer at (26,33) on-screen -- MUST engage + walk-up.
-- Scene C: VICTORY_ROAD_2F (0,9) vs Hiker (12,9) -- dx=12 must NOT engage.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local function trainerByIndex(ow, index)
    for _, npc in ipairs(ow.npcs) do
      if npc.def.index == index then return npc end
    end
  end

  -- --- A: Viridian Forest wrap through trees (dx=12, walkable west of wall) ---
  U.teleport(game, "VIRIDIAN_FOREST", 18, 33, "right")
  local ow = game.overworld
  local t = trainerByIndex(ow, 2)
  U.wait(10)
  U.log("VF far: player", ow.player.cellX, ow.player.cellY,
        "trainer", t and t.cellX, t and t.cellY,
        "engaging", tostring(ow.engaging))
  assert(t and t.cellX == 30 and t.cellY == 33, "VF Bug Catcher at (30,33)")
  assert(not ow.engaging, "VF: off-screen trainer must not engage through trees")
  assert(t.cellX == 30 and t.cellY == 33, "VF: trainer must not walk through trees")
  U.shot(game, DIR .. "/153_vf_far_no_aggro.png")

  -- --- B: real on-screen sight line (same corridor, no tree wall) ---
  U.teleport(game, "VIRIDIAN_FOREST", 26, 33, "right")
  ow = game.overworld
  t = trainerByIndex(ow, 2)
  local guard = 0
  while not ow.engaging and guard < 30 do
    guard = guard + 1
    U.wait(1)
  end
  U.log("VF near: engaging", tostring(ow.engaging),
        "emote", tostring(ow.emote and ow.emote.frames),
        "trainer", t and t.cellX, t and t.cellY)
  assert(ow.engaging, "VF: distance-4 on-screen must engage")
  U.shot(game, DIR .. "/153_vf_near_engage.png")
  -- EmotionBubble 60f + (dist-1)*16 walk frames
  U.wait(60 + 3 * 16 + 10)
  U.log("VF walkup: trainer", t.cellX, t.cellY, "player", ow.player.cellX, ow.player.cellY)
  assert(t.cellY == 33 and t.cellX >= 26 and t.cellX <= 30,
         "VF: walk-up stays on the open corridor")
  assert(t.cellX == 27, "VF: trainer stops adjacent after distance-1 walk-up")
  U.shot(game, DIR .. "/153_vf_near_walkup.png")

  -- --- C: Victory Road 2F wrap (dx=12) ---
  U.teleport(game, "VICTORY_ROAD_2F", 0, 9, "right")
  ow = game.overworld
  t = trainerByIndex(ow, 1)
  U.wait(10)
  U.log("VR2 far: player", ow.player.cellX, ow.player.cellY,
        "trainer", t and t.cellX, t and t.cellY,
        "engaging", tostring(ow.engaging))
  assert(t and t.cellX == 12 and t.cellY == 9, "VR2 Hiker at (12,9)")
  assert(not ow.engaging, "VR2: off-screen trainer must not engage")
  assert(t.cellX == 12 and t.cellY == 9, "VR2: trainer must not walk through walls")
  U.shot(game, DIR .. "/183_vr2_far_no_aggro.png")

  U.log("trainer_sight_walls_test OK")
end
