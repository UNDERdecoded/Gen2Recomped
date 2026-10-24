local mod = ...
local battle = mod.battle
local choices = 0
local stop = mod.hooks:wrap("battle.enemy_action", function(next, ...)
  choices = choices + 1
  return next(...)
end)
mod.exports.read = function()
  local snapshot, reason = battle:snapshot()
  if not snapshot then
    return nil, reason
  end
  local moves = {}
  for i, move in ipairs(snapshot.enemy.moves or {}) do
    moves[i] = { id = move.id, pp = move.pp }
  end
  return { moves = moves, choices = choices }
end
mod.exports.stop = stop
