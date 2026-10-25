-- Native Sleep Talk selection/dispatch and the sleep precheck. Other attack
-- canceller phases retain their existing controller and are audited separately.
local S = {}
local V = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local cache, statusCache = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local EXCLUDED = { [214] = true, [274] = true, [119] = true, [118] = true, [264] = true, [253] = true }
local TWO_TURN = { [26] = true, [39] = true, [75] = true, [145] = true, [151] = true, [155] = true }
local function number(move)
  return move and tonumber(move.index or move.numId) or move and ({ SLEEP_TALK = 214, SNORE = 173 })[move.id]
end
local function clear(user)
  user.mon.status, user.sleepTurns, user.nightmare, user.expNightmare = nil, nil, nil, nil
  user.mon.sleepTurns = 0
end
function S.beforeMove(user, rng, battle, move)
  local ability = require("src.battle.Abilities").of(user)
  if ability ~= "SOUNDPROOF" then
    for id = 0, 3 do
      local b = battle
        and (
          battle.battlerAt and battle:battlerAt(id)
          or (id == 0 and battle.player or id == 1 and battle.enemy)
        )
      if b and b.mon.hp > 0 and (tonumber(b.uproarTurns) or 0) > 0 then
        clear(user)
        return true, { Strings("%s woke up in\nthe UPROAR!", user.name) }
      end
    end
  end
  local turns = tonumber(user.sleepTurns) or tonumber(user.mon.sleepTurns or user.mon.sleep)
  if not turns or turns <= 0 then
    turns = rng(0, 3) % 4 + 2
  end
  turns = math.max(0, turns - (ability == "EARLY_BIRD" and 2 or 1))
  user.sleepTurns, user.mon.sleepTurns = turns, turns
  if turns == 0 then
    clear(user)
    return true, { Strings("%s\nwoke up!", user.name) }
  end
  local n = number(move and battle and battle.data and battle.data.moves[move.id] or move)
  if n == 214 then
    return true, {}
  end
  if n == 173 then
    return true, { Strings("%s\nis fast asleep!", user.name) }
  end
  return false, { Strings("%s\nis fast asleep!", user.name) }, false, "gen3_sleep"
end
function S.status(id, base)
  if not V.isGen3() or id ~= "SLP" or not base then
    return base
  end
  if statusCache[base] then
    return statusCache[base]
  end
  local out = {}
  for k, v in pairs(base) do
    out[k] = v
  end
  out.beforeMove = function(user, rng, battle, move)
    if not V.isGen3() then
      return base.beforeMove(user, rng, battle, move)
    end
    return S.beforeMove(user, rng, battle, move)
  end
  statusCache[base] = out
  return out
end
local function noCall(ctx)
  -- Native call_moves returns without the move-end script on these failures.
  -- The outer action still performs its separate after-action item sweep.
  local frame = ctx.battle._gbaMoveFrame
  if frame then
    frame.finished = true
  end
  ctx.say(Strings("But, it failed!"))
end
function S.pick(ctx)
  local user = ctx.user
  if user.mon.status ~= "SLP" then
    noCall(ctx)
    return
  end
  local pool = {}
  for slot = 1, 4 do
    local inst = (user.curMoves or user.mon.moves or {})[slot]
    local move = inst and ctx.data.moves[inst.id]
    local n = number(move)
    if
      move
      and n ~= 0
      and not EXCLUDED[n]
      and not TWO_TURN[tonumber(move.gen3Effect)]
      and user.disabledMove ~= inst.id
      and not (user.encoreMove and (tonumber(user.encoreTurns) or 0) > 0 and user.encoreMove ~= inst.id)
    then
      pool[#pool + 1] = inst.id
    end
  end
  if #pool == 0 then
    noCall(ctx)
    return
  end
  return pool[ctx.rng(1, #pool)]
end
function S.call(ctx, pick)
  return require("src.battle.Gen3CalledMove").call(ctx, pick)
end
function S.run(ctx)
  if ctx.user.mon.status == "SLP" then
    ctx.battle:statusOnomatopoeia(ctx.user, "sleep")
  end
  ctx.gbaSleepTalk = true
  ctx.user.callsMoveId = S.pick(ctx)
  return {}
end
function S.builtin(id, base)
  if not V.isGen3() or id ~= "SLEEP_TALK_EFFECT" or not base then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local out = {}
  for k, v in pairs(base) do
    out[k] = v
  end
  out.kind, out.gbaSleepTalk, out.callsMove, out.run = "full", true, S.pick, S.run
  cache[base] = out
  return out
end
return S
