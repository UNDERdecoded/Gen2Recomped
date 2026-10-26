-- One ordered, validated mid-turn replacement choice on each native peer.
local M = {}
local function integer(n, lo, hi)
  return type(n) == "number" and n >= lo and n <= hi and n % 1 == 0
end
local function key(turn, serial, actor)
  return turn .. "/" .. serial .. "/" .. actor
end
function M.attach(battle, opts)
  local state = { choices = {}, role = opts.role, spectator = opts.spectator, invalid = opts.invalid }
  battle._gen3BatonLink = state
  battle._gen3BatonParty = function(_, user)
    return user.isPlayer and opts.mine or opts.theirs
  end
  local function actor(user)
    return user.isPlayer and opts.role or (opts.role == "host" and "guest" or "host")
  end
  local function take(pending, packet)
    if not require("src.battle.Gen3BatonPass").select(battle, pending, packet.index) then
      state.invalid("invalid Baton Pass selection")
    end
  end
  state.take = take
  battle._gen3BatonRequest = function(_, pending)
    local turn = battle.turnCount or 0
    if state.turn ~= turn then
      state.turn, state.serial, state.choices = turn, 0, {}
    end
    state.serial = state.serial + 1
    pending.turn, pending.serial, pending.actor = turn, state.serial, actor(pending.user)
    local remote = opts.spectator or not pending.user.isPlayer
    if remote then
      local packet = state.choices[key(turn, pending.serial, pending.actor)]
      if packet then
        take(pending, packet)
      end
    else
      pending.onSelect = function(index)
        opts.send({
          type = "baton_pass",
          turn = turn,
          serial = pending.serial,
          actor = pending.actor,
          index = index,
        })
      end
    end
    return remote
  end
end
function M.receive(battle, packet, sender)
  local state = battle._gen3BatonLink
  if not state or battle.result or battle.linkEnded then
    return false
  end
  local turn = battle.turnCount or 0
  local owner = packet.actor
  if
    not integer(packet.turn, 1, math.max(1, turn))
    or packet.turn ~= turn
    or not integer(packet.serial, 1, 64)
    or not integer(packet.index, 1, 6)
    or owner ~= "host" and owner ~= "guest"
    or not state.spectator and owner == state.role
    or state.spectator and sender ~= owner
  then
    state.invalid("invalid Baton Pass choice packet")
    return false
  end
  if state.turn ~= turn then
    state.turn, state.serial, state.choices = turn, 0, {}
  end
  local k = key(packet.turn, packet.serial, owner)
  local previous = state.choices[k]
  if previous then
    if previous.index ~= packet.index then
      state.invalid("conflicting Baton Pass choice")
    end
    return previous.index == packet.index
  end
  state.choices[k] = { index = packet.index }
  local pending = battle._gen3BatonPending
  if
    pending
    and pending.turn == packet.turn
    and pending.serial == packet.serial
    and pending.actor == owner
  then
    state.take(pending, packet)
  end
  return true
end
return M
