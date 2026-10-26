-- Native Baton Pass owns a resumable choice, not an ordinary switch action.
local M = {}
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")
local Party = require("src.pokemon.Party")
local cache = setmetatable({}, { __mode = "k" })
local TRANSFER = {
  "confusedTurns",
  "focusEnergy",
  "substituteHP",
  "leechSeeded",
  "leechSeedSource",
  "ingrained",
  "perishTurns",
  "cursed",
  "trapped",
  "escapePrevention",
}
function M.signature(user, role)
  local out = {}
  for _, key in ipairs(TRANSFER) do
    local value = user[key]
    if key == "leechSeedSource" and type(value) == "table" then
      value = value.position
      if role == "guest" and type(value) == "number" then
        value = value % 2 == 0 and value + 1 or value - 1
      end
    end
    out[#out + 1] = tostring(value)
  end
  for _, key in ipairs({ "spatk", "spdef" }) do
    out[#out + 1] = tostring((user.stages or {})[key] or 0)
  end
  return ":baton=" .. table.concat(out, ",")
end
function M.party(battle, user)
  if battle._gen3BatonParty then
    return battle:_gen3BatonParty(user)
  end
  return battle:benchFor(user.isPlayer, user.position)
end
function M.candidates(battle, user)
  local party, excluded = M.party(battle, user), {}
  for _, other in battle:activeBattlers() do
    excluded[other.mon] = true
  end
  for pos, action in pairs(battle.pendingActions or {}) do
    if pos ~= user.position and type(action) == "table" then
      if action.special == "playerSwitch" and action.mon then
        excluded[action.mon] = true
      end
      if action.special == "aiSwitch" and action.index then
        local other = battle:battlerAt(pos)
        local mon = other and M.party(battle, other)[action.index]
        if mon then
          excluded[mon] = true
        end
      end
    end
  end
  for pos, index in pairs(battle.monToSwitchInto or {}) do
    local other = battle:battlerAt(pos)
    if pos ~= user.position and other then
      local mon = M.party(battle, other)[index]
      if mon then
        excluded[mon] = true
      end
    end
  end
  local out = {}
  for i, mon in ipairs(party) do
    if not excluded[mon] and (mon.hp or 0) > 0 and not Party.isEgg(mon) then
      out[#out + 1] = i
    end
  end
  return out, party
end
local function typeRows(battle, attack, defending, value, damage)
  for _, row in ipairs((battle.data.type_chart or {}).matchups or {}) do
    if row.attacker == attack then
      for _, kind in ipairs(defending) do
        if row.defender == kind then
          value = math.floor(value * row.multiplier / 10)
          if damage and value == 0 and row.multiplier ~= 0 then
            value = 1
          end
          break
        end
      end
    end
  end
  return value
end
function M.enemyChoice(battle, user, candidates, party)
  local pos = user.position or (user.isPlayer and 0 or 1)
  local pending = battle.monToSwitchInto or {}
  if pending[pos] then
    return pending[pos]
  end
  local opposite = pos % 2 == 0 and pos + 1 or pos - 1
  if battle:isDouble() then
    opposite = (math.floor(battle.rng(0, 65535) / 2) % 2) * 2 + (1 - pos % 2)
    if not battle:battlerAt(opposite) then
      opposite = opposite < 2 and opposite + 2 or opposite - 2
    end
  end
  local foe = battle:battlerAt(opposite)
  if not foe then
    return nil
  end
  local types = foe.curTypes or {}
  local t1, t2 = types[1], types[2] or types[1]
  local allowed, invalid = {}, {}
  for _, index in ipairs(candidates) do
    allowed[index] = true
  end
  while true do
    local best, amount = nil, 0
    for i = 1, 6 do
      local mon = party[i]
      if allowed[i] and not invalid[i] then
        local def = battle.data.pokemon[mon.species] or {}
        local value = typeRows(battle, t1, def.types or {}, 10)
        value = typeRows(battle, t2, def.types or {}, value)
        if amount < value then
          best, amount = i, value
        end
      end
    end
    if not best then
      break
    end
    for _, inst in ipairs(party[best].moves or {}) do
      local move = battle.data.moves[inst.id]
      if move and typeRows(battle, move.type, types, 10) > 10 then
        return best
      end
    end
    invalid[best] = true
  end
  local best, amount = nil, 0
  for i = 1, 6 do
    if allowed[i] then
      for _, inst in ipairs(party[i].moves or {}) do
        local move = battle.data.moves[inst.id]
        if move and (tonumber(move.power) or 0) ~= 1 then
          local value = 2
          for _, kind in ipairs(user.curTypes or {}) do
            if move.type == kind then
              value = math.floor(value * 15 / 10)
              break
            end
          end
          value = typeRows(battle, move.type, types, value, true)
          if amount < value then
            best, amount = i, value
          end
        end
      end
    end
  end
  return best
end
function M.switch(battle, user, index, party)
  local mon = party[index]
  local pos = user.position or (user.isPlayer and 0 or 1)
  battle:restoreMimicked(user)
  battle:abilitySwitchOut(user)
  local State = require("src.battle.BattleState")
  local incoming = State.makeBattler(
    battle.data,
    mon,
    user.isPlayer,
    user.isPlayer and not user.ally and battle.game.save or nil,
    battle
  )
  incoming.ally, incoming.partyIndex = user.ally, index
  for key, value in pairs(user.stages or {}) do
    incoming.stages[key] = value
  end
  for _, key in ipairs(TRANSFER) do
    incoming[key] = user[key]
  end
  user.batonPass = {}
  battle:placeBattler(pos, incoming)
  user.batonPass, user.wantsSwitch = nil, nil
  for _, other in battle:activeBattlers() do
    if other ~= incoming then
      if other.leechSeedSource == user then
        other.leechSeedSource = incoming
      end
      if other.trappedBy == user then
        other.trapped, other.trappedBy, other.escapePrevention = nil, nil, nil
      end
      if other.infatuated == user or not battle:isDouble() then
        other.infatuated = nil
      end
    end
  end
  battle:syncSides()
  Runtime.emit("battle.battler_switched", {
    battle = battle,
    side = battle:sideOf(incoming),
    battler = incoming,
    previous = user,
    battlerId = pos,
    partyIndex = index,
    reason = "baton_pass",
  })
  if incoming.isPlayer then
    battle:markParticipant()
  end
  battle:sayNext(
    incoming.isPlayer and battle:sendOutText(incoming.name)
      or Strings("%s sent\nout %s!", battle.opponentName or battle:trainerLabel_(), incoming.name)
  )
  battle:actNext(function()
    battle:startGrowIn(incoming)
    require("src.core.Sound").playCry(battle.data, mon.species)
  end)
  -- State changes precede the following action; their presentation stays queued.
  local before = battle._gen3BatonSwitching
  battle._gen3BatonSwitching = true
  battle:abilitySwitchIn(incoming)
  battle._gen3BatonSwitching = before
  if mon.hp > 0 then
    require("src.battle.HeldItems").onEntry(battle, incoming)
  end
  return incoming
end
function M.select(battle, pending, index)
  if battle._gen3BatonPending ~= pending or pending.choice or battle.result then
    return false
  end
  if battle:battlerAt(pending.user.position) ~= pending.user then
    return false
  end
  local current, party = M.candidates(battle, pending.user)
  local valid = false
  for _, i in ipairs(current) do
    if i == index and party[i] == pending.offered[i] then
      valid = true
    end
  end
  if not valid then
    return false
  end
  pending.choice = index
  if pending.onSelect then
    pending.onSelect(index)
  end
  return true
end
local function switchContext(ctx, user, index, party, frame)
  ctx.user = M.switch(ctx.battle, user, index, party)
  -- The native battler slot is replaced in place; host battlers are distinct
  -- tables. Every active caller frame must follow that same slot replacement.
  while frame do
    if frame.user == user then frame.user = ctx.user end
    frame = frame.parent
  end
end
function M.await(battle, pending)
  if battle._gen3BatonPending ~= pending then
    return
  end
  if battle.result then
    battle._gen3BatonPending = nil
    return
  end
  if pending.choice then
    battle._gen3BatonPending = nil
    switchContext(pending.ctx, pending.user, pending.choice, pending.party, pending.frame)
    if pending.frame then
      local frame = pending.frame
      while frame do
        frame.finished = true
        frame = frame.parent
      end
      require("src.battle.GbaItemSchedule").moveEnd(battle, pending.frame)
      require("src.battle.GbaItemSchedule").afterAction(battle)
    end
  else
    battle:actNext(function()
      M.await(battle, pending)
    end)
  end
end
function M.picker(battle, pending)
  return battle:buildScreen("PartyMenu", {
    battle = battle,
    party = pending.party,
    forceSwitch = true,
    keepOpen = true,
    noCancel = true,
    onUpdate = function(screen)
      if battle._gen3BatonPoll then
        battle:_gen3BatonPoll()
      end
      if battle.result or battle._gen3BatonPending ~= pending then
        screen.closed = true
        if battle.game.stack:top() == screen then
          battle.game.stack:pop()
        end
        if battle._gen3BatonPending == pending then
          battle._gen3BatonPending = nil
        end
      end
    end,
    onSwitch = function(mon, screen)
      local index
      for i, candidate in ipairs(pending.party) do
        if candidate == mon then
          index = i
          break
        end
      end
      if M.select(battle, pending, index) then
        screen.closed = true
        battle.game.stack:pop()
      elseif screen.say then
        screen:say(Strings("Choose another\nPOKéMON."))
      end
    end,
    onCancel = function()
      if battle._gen3BatonPending == pending and not pending.choice then
        battle:uiNext(function()
          return M.picker(battle, pending)
        end)
      end
    end,
  })
end
function M.perform(ctx)
  local battle, user = ctx.battle, ctx.user
  local candidates, party = M.candidates(battle, user)
  if #candidates == 0 then
    if battle._gbaMoveFrame then battle._gbaMoveFrame.failed = true end
    battle:cancelMoveAnim()
    battle:sayNext(Strings("But, it failed!"))
    return
  end
  local offered = {}
  for _, i in ipairs(candidates) do
    offered[i] = party[i]
  end
  local pending = { user = user, party = party, candidates = candidates, offered = offered, ctx = ctx }
  if type(battle.batonPassChooser) == "function" then
    local ok, chosen = pcall(battle.batonPassChooser, user.isPlayer and "player" or "enemy", candidates)
    local index = candidates[1]
    for _, i in ipairs(candidates) do
      if ok and i == tonumber(chosen) then
        index = i
      end
    end
    switchContext(ctx, user, index, party, battle._gbaMoveFrame)
    return
  end
  if
    not battle._gen3BatonRequest and (not user.isPlayer or user.ally or battle.interactiveChoices == false)
  then
    local index = not user.isPlayer and M.enemyChoice(battle, user, candidates, party) or nil
    local chosen = candidates[1]
    for _, i in ipairs(candidates) do
      if index == i then
        chosen = i
      end
    end
    switchContext(ctx, user, chosen, party, battle._gbaMoveFrame)
    return
  end
  battle._gen3BatonPending = pending
  pending.frame = battle._gbaMoveFrame
  local frame = pending.frame
  while frame do
    frame.suspended = true
    frame = frame.parent
  end
  local remote = battle._gen3BatonRequest and battle:_gen3BatonRequest(pending) or false
  if not remote then
    battle:uiNext(function()
      return M.picker(battle, pending)
    end)
  end
  battle:actNext(function()
    M.await(battle, pending)
  end)
end
function M.record(base, vanilla)
  if not base or base.run ~= vanilla.run or base.perform then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local record = {}
  for key, value in pairs(base) do
    record[key] = value
  end
  record.kind, record.run, record.perform, record.gbaBatonPass = "full", nil, M.perform, true
  cache[base] = record
  return record
end
return M
