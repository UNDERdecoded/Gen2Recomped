-- Public data-only field effects. Native battle code owns HP, queues and faints.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Party = require("src.pokemon.Party")
local M = {}

local function scalar(value)
  local kind = type(value)
  return kind == "string"
    or kind == "boolean"
    or (kind == "number" and value == value and value > -math.huge and value < math.huge)
end
local function data(value, active)
  if scalar(value) then
    return value
  end
  if type(value) ~= "table" then
    return nil
  end
  active = active or {}
  if active[value] then
    return nil
  end
  active[value] = true
  local out = {}
  for key, child in next, value do
    if scalar(key) then
      out[key] = data(child, active)
    end
  end
  active[value] = nil
  return out
end
local function actors(battle)
  local out, byId = {}, {}
  for _, b in battle:activeBattlers() do
    if b and b.mon then
      local id = b.position
      if id == nil then
        id = b == battle.player and 0 or b == battle.enemy and 1 or nil
      end
      if id ~= nil then
        out[#out + 1] = b
        byId[id] = b
      end
    end
  end
  return out, byId
end
local function canContinue(battle, player)
  -- A partner's party cannot keep the player's field batch alive. The GBA
  -- reference checks only the player's own half in an allied battle.
  if player then
    return Party.firstHealthy(battle:playerPartyView()) ~= nil
  end
  if battle:isDouble() then
    return battle:sideCanContinue(player)
  end
  if battle.enemy and battle.enemy.mon.hp > 0 then
    return true
  end
  return Party.firstHealthy(battle.enemyParty or {}) ~= nil
end
local function view(b, side, id, generation)
  local types = {}
  for i, kind in ipairs(b.curTypes or {}) do
    types[i] = generation == 3 and kind == "PSYCHIC_TYPE" and "PSYCHIC" or kind
  end
  if generation == 3 and types[1] and not types[2] then
    types[2] = types[1]
  end
  local mon = b.mon
  local out = {
    side = side,
    name = b.name,
    hp = mon.hp,
    maxHp = mon.stats.hp,
    types = types,
    vanished = not not b.invulnerable,
  }
  if generation == 3 then
    out.battlerId = id
  end
  return out
end
local function weather(field, generation)
  local raw = field.weather
  if generation == 2 then
    raw = ({ RAIN = "rain", SUN = "sun", SANDSTORM = "sandstorm" })[raw] or raw
  end
  return raw
end

function M.apply(battle)
  -- An empty chain must not allocate a context or inspect extension data.
  if not Runtime.wantsHook("battle.field_residual") then
    return
  end
  local gen = Version.generation()
  if gen > 3 or battle.result then
    return
  end
  local turn = battle.turnCount or 0
  if gen == 3 then
    if
      battle._modFieldResidualTurn == turn
      or not canContinue(battle, true)
      or not canContinue(battle, false)
    then
      return
    end
    battle._modFieldResidualTurn = turn
  end
  local active, byId = actors(battle)
  local mons, snapshots = {}, {}
  for _, b in ipairs(active) do
    mons[b] = b.mon
  end
  for id, b in pairs(byId) do
    local side = b.isPlayer and "player" or "enemy"
    local row = view(b, side, id, gen)
    if gen == 3 then
      snapshots[id] = row
    end
    if b == battle.player then
      snapshots.player = row
    end
    if b == battle.enemy then
      snapshots.enemy = row
    end
  end
  local game, hooks = battle.game, Runtime.hooks
  local save, dataset, stack, loader = game.save, game.data, game.stack, game.mods
  local stackStates, loaderGame = stack and stack.states, loader and loader.game
  local stackView = {}
  for i, state in ipairs(stackStates or {}) do
    stackView[i] = state
  end
  local field = battle.field or {}
  local rows = Runtime.call("battle.field_residual", function()
    return {}
  end, {
    field = data({ weather = weather(field, gen), tokens = field.tokens or {} }),
    battlers = snapshots,
    turn = turn,
  })
  -- Admission happens once after the chain. Context edits never become live
  -- field/battler state, and a suspended/replaced battle loses HP authority.
  if
    type(rows) ~= "table"
    or getmetatable(rows) ~= nil
    or battle.result
    or battle.game ~= game
    or game.save ~= save
    or game.data ~= dataset
    or game.stack ~= stack
    or (stack and stack.states ~= stackStates)
    or game.mods ~= loader
    or (loader and loader.game ~= loaderGame)
    or Runtime.hooks ~= hooks
    or (battle.turnCount or 0) ~= turn
  then
    return
  end
  if stackStates then
    if #stackStates ~= #stackView then
      return
    end
    for i, state in ipairs(stackView) do
      if stackStates[i] ~= state then
        return
      end
    end
  end
  local current, now = actors(battle)
  if #current ~= #active then
    return
  end
  for id, b in pairs(byId) do
    if now[id] ~= b or b.mon ~= mons[b] then
      return
    end
  end
  if gen == 3 and (not canContinue(battle, true) or not canContinue(battle, false)) then
    return
  end
  local accepted = {}
  for _, row in ipairs(rows) do
    if
      type(row) == "table"
      and getmetatable(row) == nil
      and (row.side == "player" or row.side == "enemy")
    then
      local b = row.side == "player" and battle.player or battle.enemy
      local id = row.battlerId
      if id == nil then
        id = row.battler
      end
      if gen == 3 and id ~= nil then
        b = type(id) == "number" and id == math.floor(id) and id >= 0 and id <= 3 and byId[id] or nil
      end
      local amount = row.amount
      if
        b
        and mons[b]
        and (b.isPlayer and "player" or "enemy") == row.side
        and type(amount) == "number"
        and amount == amount
        and amount > 0
        and amount < math.huge
        and amount == math.floor(amount)
        and (row.message == nil or type(row.message) == "string")
      then
        accepted[#accepted + 1] = { target = b, amount = amount, message = row.message }
      end
    end
  end
  local fainted = {}
  for _, row in ipairs(accepted) do
    local b = row.target
    if b.mon.hp > 0 then
      if row.message and row.message ~= "" then
        battle:sayNext(row.message)
      end
      b.mon.hp = b.mon.hp - math.min(row.amount, b.mon.hp)
      battle:drainNext(b, b.mon.hp)
      if b.mon.hp == 0 then
        fainted[b] = true
      end
    end
  end
  -- Decide only after the entire batch: descriptor order cannot turn a
  -- terminal player blackout into an enemy EXP/replacement path.
  local terminalPlayer = not canContinue(battle, true)
  if terminalPlayer and next(fainted) and battle:isDouble() then
    -- The native generic side check prefers an enemy wipe. This field batch
    -- must give the terminal player faint authority before that check runs.
    battle.sideBeaten = "player"
    battle:act(function()
      battle:playerMonFainted()
    end)
  end
  if gen == 3 then
    table.sort(active, function(a, b)
      if a.isPlayer ~= b.isPlayer then
        return a.isPlayer
      end
      return a.position < b.position
    end)
  end
  for _, b in ipairs(active) do
    if fainted[b] and (not terminalPlayer or b.isPlayer or gen == 2) then
      if gen > 1 then
        b.destinyBond, b.grudge = nil, nil
      end
      battle:onFaint(b, terminalPlayer and not b.isPlayer and gen == 2)
    end
  end
  if next(fainted) and battle:isDouble() then
    battle:act(function()
      battle:fillEmptySlots()
    end)
  end
end
return M
