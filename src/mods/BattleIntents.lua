-- Data-only intent validation and private cross-facade submission state.
local Intents = {}
local states = setmetatable({}, { __mode = "k" })
local FIELDS = {
  menu = { choice = true },
  move = { slot = true },
  target = { target = true },
  back = {},
  safari = { action = true },
  mimic = { index = true },
}
local MENU = { fight = true, party = true, item = true, run = true }
local SAFARI = { ball = true, bait = true, rock = true, run = true }
local function integer(v, lo, hi)
  return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end
function Intents.normalize(raw)
  if type(raw) ~= "table" or getmetatable(raw) ~= nil then
    return nil, "intent must be a plain table"
  end
  if not integer(raw.id, 1, 9007199254740991) then
    return nil, "intent id must be a positive safe integer"
  end
  if not integer(raw.revision, 1, 9007199254740991) then
    return nil, "invalid battle revision"
  end
  local fields = type(raw.kind) == "string" and FIELDS[raw.kind]
  if not fields then
    return nil, "unknown battle intent"
  end
  for key in pairs(raw) do
    if key ~= "id" and key ~= "revision" and key ~= "kind" and not fields[key] then
      return nil, "unknown battle intent field"
    end
  end
  local out = { id = raw.id, revision = raw.revision, kind = raw.kind }
  if raw.kind == "menu" then
    if type(raw.choice) ~= "string" or not MENU[raw.choice] then
      return nil, "unknown battle menu choice"
    end
    out.choice = raw.choice
  elseif raw.kind == "move" then
    if not integer(raw.slot, 1, 4) then
      return nil, "invalid move slot"
    end
    out.slot = raw.slot
  elseif raw.kind == "target" then
    if not integer(raw.target, 0, 3) then
      return nil, "target must be a battler id 0-3"
    end
    out.target = raw.target
  elseif raw.kind == "safari" then
    if type(raw.action) ~= "string" or not SAFARI[raw.action] then
      return nil, "invalid safari action"
    end
    out.action = raw.action
  elseif raw.kind == "mimic" then
    if not integer(raw.index, 1, 4) then
      return nil, "invalid mimic index"
    end
    out.index = raw.index
  end
  return out
end
function Intents.state(game)
  local state = states[game]
  if not state then
    state = { epoch = 0, busy = false }
    states[game] = state
  end
  return state
end

local BATTLE_FLAGS = {
  "waitingUI",
  "dead",
  "demo",
  "dudeDemo",
  "pokedudeDemo",
  "palace",
  "arena",
  "spectating",
  "bugContest",
  "noItems",
  "gen4Safari",
}
local BATTLER_FLAGS = {
  "disabledSlot",
  "tauntTurns",
  "tormented",
  "lastMove",
  "mustRecharge",
  "charging",
  "thrashTurns",
  "thrashMove",
  "rageMove",
  "trappingTurns",
  "bideTurns",
  "encoreTurns",
  "encoreMove",
  "bwSkyDropped",
  "bwChoiceLock",
  "bwImprison",
  "bwHealBlock",
  "bwEmbargo",
}
-- Reference identity matters as well as record values: an identical replacement
-- Pokemon, move slot, selector or covering screen must invalidate old commands.
-- refs are compared shallowly; values are copied by the snapshot owner.
function Intents.context(game, b, top, at)
  local refs = {
    game = game,
    battle = b,
    top = top,
    stack = game.stack,
    queue = b.queue,
    current = b.current,
    targets = b.targetChoices,
    mimic = b.mimicCtx,
    mimicMoves = b.mimicMoves,
    pendingMove = b.pendingMove,
    pending = b.pendingActions,
    chosen = b.chosenTargets,
    safari = b.safari,
  }
  local values = { queueLength = #(b.queue or {}), flags = {}, battlers = {} }
  for _, key in ipairs(BATTLE_FLAGS) do
    values.flags[key] = type(b[key]) == "table" and true or b[key]
  end
  values.bw = type(b.bw) == "table"
      and { gravity = b.bw.field and b.bw.field.gravity, magicRoom = b.bw.field and b.bw.field.magicRoom }
    or b.bw
  if b.mimicCtx then
    refs.mimicUser, refs.mimicTarget, refs.mimicMove = b.mimicCtx.user, b.mimicCtx.target, b.mimicCtx.moveInst
  end
  for i, move in ipairs(b.mimicMoves or {}) do
    refs["mimicOption" .. i] = move
  end
  for pos = 0, 3 do
    local actor = at(b, pos)
    refs["b" .. pos] = actor
    if actor then
      refs["mon" .. pos] = actor.mon
      refs["moves" .. pos] = actor.curMoves
      local flags = {}
      for _, key in ipairs(BATTLER_FLAGS) do
        flags[key] = type(actor[key]) == "table" and true or actor[key]
      end
      values.battlers[pos] = flags
      for slot, mv in ipairs(actor.curMoves or {}) do
        refs["move" .. pos .. ":" .. slot] = mv
      end
    end
    refs["pending" .. pos] = b.pendingActions and b.pendingActions[pos]
    refs["chosen" .. pos] = b.chosenTargets and b.chosenTargets[pos]
  end
  for i, target in ipairs(b.targetChoices or {}) do
    refs["target" .. i] = target
  end
  return refs, values
end
function Intents.sameRefs(a, b)
  if not a or not b then
    return a == b
  end
  for key, value in pairs(a) do
    if b[key] ~= value then
      return false
    end
  end
  for key, value in pairs(b) do
    if a[key] ~= value then
      return false
    end
  end
  return true
end
return Intents
