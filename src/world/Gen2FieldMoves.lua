-- Gen2 field-state queries over the native mover.
-- Action admission, scripts, badges, animations and warps remain owned by
-- OverworldController. Do not advertise legacy action entry points here:
-- their context/result protocol is different from the native script VM.
local State = require("src.world.Gen2PlayerState")

local FieldMoves = {
  PLAYER_NORMAL = State.PLAYER_NORMAL,
  PLAYER_BIKE = State.PLAYER_BIKE,
  PLAYER_SURF = State.PLAYER_SURF,
  PLAYER_SURF_PIKA = State.PLAYER_SURF_PIKA,
  isBiking = State.isBiking,
  isSurfing = State.isSurfing,
}

return FieldMoves
