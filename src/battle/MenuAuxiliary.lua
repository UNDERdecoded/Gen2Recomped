-- Public START action at an idle player command menu, before native navigation.
local Runtime = require("src.mods.Runtime")
local M = {}
local BUSY = {
  "current",
  "nextInsert",
  "pendingHit",
  "waitingUI",
  "waitingSound",
  "draining",
  "animPlaying",
  "growIn",
  "shrinkOut",
  "ghostReveal",
  "mimicCtx",
  "result",
  "gen3BallPlaying",
  "gen4TouchPress",
}
local COUNTERS = { "waitFrames", "hitSfxWait", "introSlide" }
local VARIANTS = {
  "safari",
  "ghost",
  "scopeReveal",
  "demo",
  "pokedudeDemo",
  "noCatch",
  "palace",
  "arena",
  "ally",
  "factory",
  "pyramid",
  "pike",
  "battleTower",
  "trainerTower",
  "secretBase",
  "eReader",
}
local function nonempty(value)
  return type(value) == "table" and next(value) ~= nil
end
local function defaultAction()
  return false
end
function M.ready(battle)
  local game = battle and battle.game
  if
    not game
    or not game.save
    or not game.data
    or battle.phase ~= "menu"
    or (battle.kind ~= "wild" and battle.kind ~= "trainer")
  then
    return false
  end
  local stack = game.stack
  if not stack or not stack.top or stack:top() ~= battle then
    return false
  end
  if
    nonempty(battle.queue)
    or nonempty(battle.pendingActions)
    or nonempty(battle.chosenTargets)
    or (battle.afterQueue and battle.afterQueue ~= "menu")
  then
    return false
  end
  for _, field in ipairs(VARIANTS) do
    if battle[field] then
      return false
    end
  end
  for _, field in ipairs(BUSY) do
    if battle[field] then
      return false
    end
  end
  for _, field in ipairs(COUNTERS) do
    local value = battle[field]
    if value and value ~= 0 then
      return false
    end
  end
  if battle.showEnemyTrainer or battle.showPlayerBack or battle.enemySendingOut then
    return false
  end
  local actor = battle.choosingBattler and battle:choosingBattler() or battle.player
  if
    not actor
    or actor.ally
    or not actor.mon
    or (actor.mon.hp or 0) <= 0
    or (battle.menuLockedAction and battle:menuLockedAction(actor))
    or actor.bwSkyDropped
  then
    return false
  end
  local count = battle.isDouble and battle:isDouble() and 4 or 2
  local enemyStanding = false
  for position = 0, count - 1 do
    local battler = battle.battlerAt and battle:battlerAt(position)
      or (position == 0 and battle.player or position == 1 and battle.enemy)
    if battler and battler.mon then
      local mon = battler.mon
      if
        (mon.hp or 0) <= 0
        or battler.fainted
        or battler.faintQueued
        or battler.draining
        or battler.drainFloor ~= nil
        or battler.drainHold ~= nil
        or battler.shownHP ~= mon.hp
        or battler.shownStatus ~= mon.status
      then
        return false
      end
      if position % 2 == 1 then
        enemyStanding = true
      end
    elseif count == 2 then
      return false
    end
  end
  return enemyStanding
end
function M.request(battle)
  if not Runtime.wantsHook("battle.menu_auxiliary") then
    return
  end
  local game = battle.game
  if not game or not game.input or not game.input:wasPressed("start") or not M.ready(battle) then
    return
  end
  return {
    game = game,
    save = game.save,
    data = game.data,
    stack = game.stack,
    session = game.sessionStartedAt,
    kind = battle.kind,
  }
end
local function current(battle, token)
  local game = token.game
  return battle.game == game
    and game.save == token.save
    and game.data == token.data
    and game.stack == token.stack
    and game.sessionStartedAt == token.session
    and battle.kind == token.kind
    and M.ready(battle)
end
function M.dispatch(battle, token)
  -- Retire input captured for an owner/session that changed during native FX.
  if not current(battle, token) then
    return true
  end
  local result = Runtime.call("battle.menu_auxiliary", defaultAction, token.game, { kind = token.kind })
  -- A pushed overlay or changed session must never receive the same input as
  -- the retired battle menu, even if the wrapper returned false or raised.
  return result == true or not current(battle, token)
end
return M
