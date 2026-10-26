-- Detached Gen 1-5 snapshots and revision-bound native command admission.
-- Snapshot building stays data-only; submit validates before native dispatch.
local Ids = require("src.mods.UnifiedIds")
local Intents = require("src.mods.BattleIntents")
local Commands = require("src.battle.BattleCommands")
local Runtime = require("src.mods.Runtime")
-- Native work requested through a facade remains engine work. The buses keep
-- their existing callback/error attribution; lazy requires must not be blamed
-- on the requesting mod by the dev-mode permission shim.
local function enginePcall(fn, ...)
  local owner = Runtime.currentMod
  Runtime.currentMod = nil
  local ok, a, b = pcall(fn, ...)
  Runtime.currentMod = owner
  return ok, a, b
end
local Snapshots = {}

local STATUS =
  { SLP = "sleep", PSN = "poison", BRN = "burn", FRZ = "freeze", PAR = "paralyze", TOX = "toxic" }
local STATS = {
  hp = "hp",
  attack = "attack",
  defense = "defense",
  speed = "speed",
  special = "special",
  specialAttack = "spatk",
  specialDefense = "spdef",
}

local function copy(value, seen)
  local kind = type(value)
  if kind ~= "table" then
    if kind == "string" or kind == "boolean" or kind == "number" then
      return value
    end
    return nil
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local out = {}
  seen[value] = out
  for key, v in pairs(value) do
    if type(key) == "string" or type(key) == "number" then
      out[key] = copy(v, seen)
    end
  end
  return out
end

local function equal(a, b, seen)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b or (a ~= a and b ~= b)
  end
  seen = seen or {}
  if seen[a] then
    return seen[a] == b
  end
  seen[a] = b
  for k, v in pairs(a) do
    if not equal(v, b[k], seen) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function stats(raw)
  local out = {}
  for public, native in pairs(STATS) do
    out[public] = (raw or {})[native]
  end
  out.specialAttack = out.specialAttack or out.special
  out.specialDefense = out.specialDefense or out.special
  return out
end

local function at(battle, pos)
  -- Constructors fill these aliases before enter()/syncSides populates the
  -- positional arrays. A cleared alias also truthfully represents a faint.
  if pos == 0 then
    return battle.player
  end
  if pos == 1 then
    return battle.enemy
  end
  local side = battle.sides and battle.sides[pos % 2 + 1]
  return side and side.battlers and side.battlers[math.floor(pos / 2) + 1]
end

local function activeSlot(battle)
  if battle.phase == "mimicSelect" and battle.mimicCtx then
    for _, pos in ipairs({ 0, 2 }) do
      if at(battle, pos) == battle.mimicCtx.user then
        return pos
      end
    end
  end
  if not battle.double then
    return 0
  end
  local pos = battle.choosingSlot
  if (pos == 0 or pos == 2) and at(battle, pos) then
    return pos
  end
  for _, id in ipairs({ 0, 2 }) do
    local b = at(battle, id)
    if b and not b.ally then
      return id
    end
  end
  return 0
end

local function moveView(move, slot, data, ids)
  local id = type(move) == "table" and move.id or move
  local def = (data.moves or {})[id] or {}
  local ups = type(move) == "table" and math.min(3, math.max(0, math.floor(tonumber(move.ppUps) or 0))) or 0
  return {
    slot = slot,
    id = ids:read("moves", id),
    name = def.name,
    pp = type(move) == "table" and move.pp or nil,
    maxPp = def.pp and (def.pp + ups * math.floor(def.pp / 5)) or nil,
    ppUps = ups,
    type = def.type,
    power = def.power,
    accuracy = def.accuracy,
  }
end

local function monView(raw, data, ids)
  if not raw then
    return nil
  end
  local out = {
    species = ids:read("pokemon", raw.species),
    item = ids:read("items", raw.item),
    nickname = raw.nickname,
    name = raw.name or raw.nickname or ((data.pokemon or {})[raw.species] or {}).name,
    level = raw.level,
    hp = raw.hp,
    maxHp = raw.stats and raw.stats.hp,
    status = STATUS[raw.status] or raw.status,
    isEgg = raw.isEgg == true,
    stats = stats(raw.stats),
    moves = {},
    native = copy(raw),
  }
  for slot, move in ipairs(raw.moves or {}) do
    out.moves[slot] = moveView(move, slot, data, ids)
  end
  return out
end

local function battlerView(b, pos, party, data, ids)
  if not (b and b.mon) then
    return nil
  end
  local out = monView(b.mon, data, ids)
  out.name = b.name or out.name
  out.id, out.side, out.active, out.absent = pos, pos % 2 == 0 and "player" or "enemy", true, false
  out.displaySpecies = ids:read("pokemon", b.species or b.mon.species)
  out.battleStats, out.types, out.stages =
    stats(b.curStats or b.mon.stats), copy(b.curTypes), copy(b.stages or {})
  out.ally = b.ally == true
  for index, mon in ipairs(party) do
    if mon == b.mon then
      out.partyIndex = index
      break
    end
  end
  out.moves = {}
  for slot, move in ipairs(b.curMoves or b.mon.moves or {}) do
    out.moves[slot] = moveView(move, slot, data, ids)
  end
  return out
end

-- Prompt describes the battle screen only. Covered screens and automatic
-- controllers stay locked; no attempt is made to inspect or drive their UI.
local function prompt(b, covered, actor)
  if
    covered
    or b.result
    or b.waitingUI
    or b.demo
    or b.pokedudeDemo
    or b.palace
    or b.kind == "link"
    or (b.arena and b.phase == "menu")
  then
    return "locked"
  end
  if b.phase == "menu" then
    if b.safari then
      return (b.safari.balls or 0) > 0 and "safari" or "locked"
    end
    if
      not (actor and actor.mon and (actor.mon.hp or 0) > 0)
      or actor.ally
      or actor.mustRecharge
      or actor.charging
      or actor.rageMove
      or (actor.thrashTurns and actor.thrashTurns > 0)
    then
      return "locked"
    end
    -- Sky Drop's controller in BW owns the menu; unknown native locks are
    -- not advertised as actionable (this API never submits input).
    if b.bw and actor.bwSkyDropped then
      return "locked"
    end
    return "menu"
  end
  if b.phase == "moveSelect" then
    return "moves"
  end
  if b.phase == "targetSelect" then
    return "target"
  end
  if b.phase == "mimicSelect" then
    return "mimic"
  end
  if
    b.phase == "messages"
    and b.current
    and not b.current.choice
    and ((b.msgWaiting and (b.msgPreWait or 0) <= 0) or (b.msgPrompt and (b.msgPromptWait or 0) <= 0))
  then
    return "advance"
  end
  return "locked"
end

-- Decode only glyphs already revealed by the native message clock. Unknown
-- glyphs leave the optional visible message unavailable, never reveal ahead.
local function visibleMessage(battle, covered, data)
  if covered or battle.phase ~= "messages" or not battle.shown then
    return nil
  end
  local reverse = {}
  local function add(rows)
    for _, row in ipairs(rows or {}) do
      if type(row.code) == "number" and type(row.seq) == "string" and reverse[row.code] == nil then
        reverse[row.code] = row.seq
      end
    end
  end
  add(data.font and data.font.charmap)
  local pages, names = data.font and data.font.pages or {}, {}
  for name in pairs(pages) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    add(type(pages[name]) == "table" and pages[name].charmap)
  end
  local unicode = package.loaded["src.translation.UnicodeFont"]
  local chars = type(unicode) == "table" and unicode.chars or {}
  local scaffold = data.font
    and type(data.font.source) == "string"
    and data.font.source:find("Gen2 scaffold", 1, true)
  local out = {}
  for i, codes in ipairs(battle.shown) do
    local line = {}
    for _, code in ipairs(codes) do
      local seq = chars[code] or reverse[code]
      if scaffold and type(code) == "number" and code >= 0 and code <= 255 then
        seq = string.char(code)
      end
      if not seq then
        return nil
      end
      line[#line + 1] = seq
    end
    out[i] = table.concat(line)
  end
  return out
end

local function kind(battle)
  -- The same variants as BattleState:battleKind(), without a method call.
  if battle.ghost then
    return "ghost"
  end
  if battle.safari then
    return "safari"
  end
  if battle.demo and not battle.dudeDemo then
    return "oldman"
  end
  return battle.kind
end

local function build(game, battle, covered, ids)
  local data, save = battle.data or game.data or {}, game.save or {}
  local party, enemyParty = battle.playerParty or save.party or {}, battle.enemyParty or {}
  local active = activeSlot(battle)
  local actor = at(battle, active)
  local out = {
    kind = kind(battle),
    phase = battle.phase,
    double = battle.double == true,
    active = active,
    turn = battle.turnCount or 0,
    prompt = prompt(battle, covered, actor),
    message = visibleMessage(battle, covered, data),
    messageSource = battle.current and battle.current.text,
    safariBalls = battle.safari and battle.safari.balls,
    menuIndex = battle.menuIndex,
    moveIndex = battle.moveIndex,
    moveSwapIndex = battle.moveSwapIndex,
    result = battle.result,
    party = {},
    battlers = {},
    moves = {},
    items = {},
    targets = {},
  }
  local foes = 0
  local rows = {}
  for pos = 0, (out.double and 3 or 1) do
    local b = at(battle, pos)
    local row = battlerView(
      b,
      pos,
      pos % 2 == 0 and (b and b.ally and battle.ally and battle.ally.party or party) or enemyParty,
      data,
      ids
    )
    rows[pos] = row
    if row then
      out.battlers[#out.battlers + 1] = row
      if pos % 2 == 1 and (row.hp or 0) > 0 then
        foes = foes + 1
      end
    end
  end
  out.player, out.enemy = rows[active], rows[1]
  out.catchable = battle.kind == "wild"
    and not battle.ghost
    and not battle.noCatch
    and not battle.result
    and foes == 1
  for slot, raw in ipairs(party) do
    local row = monView(raw, data, ids)
    row.slot, row.active = slot, false
    for _, pos in ipairs({ 0, 2 }) do
      local b = at(battle, pos)
      if b and not b.ally and b.mon == raw then
        row.active = true
      end
    end
    out.party[slot] = row
  end
  for slot, move in ipairs(actor and (actor.curMoves or actor.mon.moves) or {}) do
    local row = moveView(move, slot, data, ids)
    local def = (data.moves or {})[move.id] or {}
    -- The three explicit guards used by BattleState's move selector. This
    -- is a local menu restriction, not a guarantee a move will execute.
    row.disabled = require("src.battle.Gen3Disable").blocked(actor, move, slot)
      or (move.pp or 0) <= 0
      or (actor.tauntTurns ~= nil and (def.power or 0) == 0)
      or (actor.tormented and actor.lastMove ~= nil and move.id == actor.lastMove)
      or false
    -- BW adds Choice/Imprison/Gravity/Heal Block checks through native
    -- controllers. Do not report an unverified false for those moves.
    if battle.bw and not row.disabled then
      row.disabled = nil
    end
    out.moves[slot] = row
  end
  -- Inventory quantities, not a use-eligibility result. Keep acquisition
  -- order, then append positive unlisted IDs deterministically.
  local inventory, seen, remaining = save.inventory or {}, {}, {}
  local function item(id)
    if seen[id] then
      return
    end
    seen[id] = true
    local count = inventory[id]
    if type(count) ~= "number" or count <= 0 then
      return
    end
    local def = (data.items or {})[id] or {}
    local balls = data.balls or {}
    local ball = def.ball ~= nil and def.ball ~= false or balls[id] ~= nil or balls[tostring(id)] ~= nil
    out.items[#out.items + 1] = {
      id = ids:read("items", id),
      name = def.name,
      count = count,
      ball = ball,
      catchable = ball and out.catchable,
      pocket = def.pocket,
    }
  end
  for _, id in ipairs(save.bagOrder or {}) do
    item(id)
  end
  for id in pairs(inventory) do
    if not seen[id] then
      remaining[#remaining + 1] = id
    end
  end
  table.sort(remaining, function(a, b)
    return type(a) == type(b) and a < b or type(a) < type(b)
  end)
  for _, id in ipairs(remaining) do
    item(id)
  end
  if battle.phase == "targetSelect" then
    for _, target in ipairs(battle.targetChoices or {}) do
      for pos = 0, 3 do
        if at(battle, pos) == target then
          out.targets[#out.targets + 1] = pos
          break
        end
      end
    end
    out.targetIndex = battle.targetIndex
  end
  if battle.phase == "mimicSelect" then
    out.mimicMoves, out.mimicIndex = {}, battle.mimicIndex
    for index, move in ipairs(battle.mimicMoves or {}) do
      out.mimicMoves[index] = moveView(move, move.slot or index, data, ids)
    end
  end
  return out
end

function Snapshots.new(gameProvider, loader)
  -- Ids keeps alias metadata on the loader, never on gameplay records.
  local initial = Ids.new(loader)
  for _, kind in ipairs({ "pokemon", "moves", "items" }) do
    initial:entries(kind)
  end
  local facade = {}
  local lastGame, lastBattle, previous, revision = nil, nil, nil, 0
  local lastRefs, lastControl, lastEpoch, offeredRevision, lastIntentId = nil, nil, nil, nil, 0
  local function refresh()
    local game = gameProvider()
    local states = game and game.stack and game.stack.states or {}
    local battle, index
    for i = #states, 1, -1 do
      if states[i].isBattleState == true then
        battle, index = states[i], i
        break
      end
    end
    if not battle then
      lastGame, lastBattle, previous, lastRefs, lastControl, offeredRevision = nil, nil, nil, nil, nil, nil
      return nil, nil, nil, "no battle"
    end
    local state = Intents.state(game)
    local out = copy(build(game, battle, index ~= #states, Ids.new(loader)))
    local refs, control = Intents.context(game, battle, states[#states], at)
    control = copy(control)
    if
      game ~= lastGame
      or battle ~= lastBattle
      or not equal(out, previous)
      or not Intents.sameRefs(refs, lastRefs)
      or not equal(control, lastControl)
      or state.epoch ~= lastEpoch
    then
      revision = revision + 1
    end
    lastGame, lastBattle, previous = game, battle, out
    lastRefs, lastControl, lastEpoch = refs, control, state.epoch
    return game, battle, index, state
  end
  function facade:snapshot()
    local game, battle, _, state = refresh()
    if not battle then
      return nil, "no battle"
    end
    local result = copy(previous)
    result.revision = revision
    if state.busy then
      result.prompt = "locked"
    end
    offeredRevision = revision
    return result
  end
  function facade:submit(raw)
    local intent, reason = Intents.normalize(raw)
    if not intent then
      return nil, reason
    end
    if intent.id <= lastIntentId then
      return nil, "replayed intent"
    end
    local game, battle, index, state = refresh()
    if not battle then
      return nil, "no battle"
    end
    if state.busy then
      return nil, "battle action is already in progress"
    end
    if intent.revision ~= revision then
      return nil, "stale battle context"
    end
    if offeredRevision ~= revision then
      return nil, "fresh battle snapshot required"
    end
    if battle.game ~= game then
      return nil, "battle does not belong to current Game"
    end
    if index ~= #game.stack.states then
      return nil, "battle menu is covered"
    end
    -- The native admission helpers are read-only. Lock during validation too,
    -- so a mod callback/overridden helper cannot recursively enter submission.
    local refs, control = lastRefs, lastControl
    state.busy = true
    local checked, refusal = enginePcall(Commands.reason, battle, intent)
    if not checked or refusal then
      state.busy = false
      return nil, checked and refusal or "battle validation failed"
    end
    local fresh, currentGame, currentBattle = pcall(refresh)
    if not fresh then
      state.busy = false
      return nil, "battle validation failed"
    end
    if
      game ~= currentGame
      or battle ~= currentBattle
      or revision ~= intent.revision
      or not Intents.sameRefs(refs, lastRefs)
      or not equal(control, lastControl)
    then
      state.busy = false
      return nil, "stale battle context"
    end
    -- Consume BEFORE native code: a callback or partial native failure cannot
    -- replay this ID. Both boundaries invalidate snapshots held by other mods,
    -- including snapshots observed halfway through an accepted action.
    lastIntentId, offeredRevision = intent.id, nil
    state.epoch = state.epoch + 1
    local ok, accepted, err = enginePcall(Commands.dispatch, battle, intent)
    state.epoch = state.epoch + 1
    state.busy = false
    if not ok then
      local printable, message = pcall(tostring, accepted)
      return nil, "battle action failed; intent consumed" .. (printable and ": " .. message or "")
    end
    if not accepted then
      return nil, err or "battle action did not complete; intent consumed"
    end
    return true
  end
  return facade
end
-- Run after construction so an optional capability provider and its other
-- surface wrappers are already installed. Standalone main has no provider.
function Snapshots.withCapabilities(api)
  if api.supports then
    local supports = api.supports
    function api:supports(surface, name)
      if surface == "battle" then
        if name == "snapshot" or name == "submit" then
          return true
        end
        return false, "unknown battle capability: " .. tostring(name)
      end
      return supports(self, surface, name)
    end
  end
  return api
end
return Snapshots
