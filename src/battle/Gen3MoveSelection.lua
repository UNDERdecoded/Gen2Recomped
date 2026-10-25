-- The native AI scans four slots once, through the held-effect hook. Manual
-- admission uses physical Choice Band identity and never performs that read.
local V = require("src.core.GameVersion")
local Choice = require("src.battle.Gen3ChoiceBand")
local Selection = {}
local function moves(user)
  return user.curMoves or user.mon.moves or {}
end
local function imprisoned(battle, user, move)
  local identity = Choice.identity(battle, move)
  for _, foe in ipairs(battle:foesOf(user)) do
    if foe.imprison then
      for slot = 1, 4 do
        local other = moves(foe)[slot]
        if other and Choice.identity(battle, other) == identity then
          return true
        end
      end
    end
  end
  return false
end
local function reason(battle, user, move, slot, heldChoice, manual)
  if not move or not battle.data.moves[move.id] or Choice.identity(battle, move) == 0 then
    return "empty"
  end
  local why
  if require("src.battle.Gen3Disable").blocked(user, move, slot) then
    why = "disabled"
  end
  if
    user.tormented
    and (not manual or Choice.identity(battle, move) ~= 165)
    and Choice.identity(battle, user.lastMove) == Choice.identity(battle, move)
  then
    why = "torment"
  end
  if (tonumber(user.tauntTurns) or 0) > 0 and (tonumber(battle.data.moves[move.id].power) or 0) == 0 then
    why = "taunt"
  end
  if imprisoned(battle, user, move) then
    why = "imprison"
  end
  if heldChoice and user.choicedMove and user.choicedMove ~= Choice.identity(battle, move) then
    why = "choice"
  end
  return why
end
function Selection.manualReason(battle, user, move, slot)
  if not V.isGen3() or not user then
    return nil
  end
  local why = reason(battle, user, move, slot, false, true)
  if Choice.selectionBlocked(battle, user, move) then
    why = "choice"
  end
  if move and tonumber(move.pp) and move.pp <= 0 then
    why = "pp"
  end
  return why
end
function Selection.aiMask(battle, user)
  if not V.isGen3() then
    return nil
  end
  local effect = require("src.battle.HoldItems").effectOf(user, "check")
  local mask = {}
  for slot = 1, 4 do
    local move = moves(user)[slot]
    local bad = reason(battle, user, move, slot, effect == "CHOICE_BAND") ~= nil
    if move and tonumber(move.pp) == 0 and not Choice.enemyUnlimited(battle, user) then
      bad = true
    end
    if
      (tonumber(user.encoreTurns) or 0) > 0
      and user.encoreMove
      and Choice.identity(battle, move) ~= Choice.identity(battle, user.encoreMove)
    then
      bad = true
    end
    mask[slot] = bad
  end
  return mask
end
function Selection.ordinaryWild(battle)
  if not V.isGen3() or battle.kind ~= "wild" then
    return false
  end
  local kinds = battle.kinds or {}
  if V.get() == "emerald" then
    return not (battle.firstBattleKind or kinds.firstBattle or battle.safari or battle.roamer)
  end
  return not (
    battle.roamer
    or battle.safari
    or battle.firstBattle
    or battle.wildScripted
    or battle.legendary
    or (tonumber(battle.aiFlags) or 0) ~= 0
  )
end
function Selection.wildMove(battle, user, mask, rng)
  if mask[1] and mask[2] and mask[3] and mask[4] then
    return { id = "STRUGGLE", pp = 1, struggle = true }
  end
  local move, index, found
  for _ = 1, 1000 do
    index = rng(0, 3) + 1
    move = moves(user)[index]
    local identity = move and Choice.identity(battle, move)
    if identity and identity ~= 0 and battle.data.moves[move.id] then
      found = true
      break
    end
  end
  if not found then
    for slot = 1, 4 do
      if not mask[slot] then
        move = moves(user)[slot]
        return require("src.battle.EnemyMoveChoice").withMove(move, move.id, move, slot)
      end
    end
    return { id = "STRUGGLE", pp = 1, struggle = true }
  end
  if not move then
    return { id = "STRUGGLE", pp = 1, struggle = true }
  end
  local action = require("src.battle.EnemyMoveChoice").withMove(move, move.id, move, index)
  action.scores = { 0, 0, 0, 0 }
  if battle:isDouble() then
    local targetType = tonumber(battle.data.moves[move.id].target) or 0
    action.target = math.floor(targetType / 16) % 2 == 1 and user.position
      or math.floor(rng(0, 65535) / 2) % 2 * 2
  end
  return action
end
return Selection
