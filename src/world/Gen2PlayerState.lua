-- Gen2's public movement names over the native mover/save flags. This is
-- derived on demand: scripted surf/bike changes must not leave a second,
-- copied movement byte behind for observers.
local State = {}

State.PLAYER_NORMAL = "normal"
State.PLAYER_BIKE = "bike"
State.PLAYER_SURF = "surf"
State.PLAYER_SURF_PIKA = "surf_pika"

function State.isBiking(state)
  return state == State.PLAYER_BIKE
end

function State.isSurfing(state)
  return state == State.PLAYER_SURF or state == State.PLAYER_SURF_PIKA
end

function State.read(player, save)
  if not player or not save then return nil end
  if player.surfing then
    return player.surfingPikachu and State.PLAYER_SURF_PIKA or State.PLAYER_SURF
  end
  if save.onBike then return State.PLAYER_BIKE end
  return State.PLAYER_NORMAL
end

-- Low-level state adoption, like the reference's applyPlayerState. Native
-- action eligibility, animations and music still belong to their callers.
function State.apply(player, save, state)
  state = state or State.PLAYER_NORMAL
  if state ~= State.PLAYER_NORMAL and state ~= State.PLAYER_BIKE
     and not State.isSurfing(state) then
    return nil, "unknown Gen2 player state"
  end
  if not player or not save then return nil, "no native player/save" end
  player.surfing = State.isSurfing(state)
  player.surfingPikachu = state == State.PLAYER_SURF_PIKA
  save.onBike = State.isBiking(state)
  player.onBike = save.onBike
  return true
end

return State
