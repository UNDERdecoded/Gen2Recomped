-- GBA Mirror Move reads the recipient's native move-end history, not the
-- current target's last selected action. Only qualifying receipts replace it.
local M = {}
local V = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local cache = setmetatable({}, { __mode = "k" })
function M.pick(ctx)
  local previous = ctx.user.gbaLastTakenMove
  if previous and previous ~= 0 then
    local id = require("src.battle.EnemyMoveChoice").resolveMove(ctx.data, previous)
    if id then
      return id
    end
  end
  ctx.say(Strings("The MIRROR MOVE\nfailed!"))
end
function M.builtin(id, base)
  if not V.isGen3() or id ~= "MIRROR_MOVE_EFFECT" or not base then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  out.callsMove, out.announceAnim = M.pick, false
  cache[base] = out
  return out
end
function M.history(battle, frame)
  if not V.isGen3() or not frame then
    return
  end
  local user, target = frame.user, frame.target
  if not user or not target or target == user then
    return
  end
  local chosen = frame.calledBy or frame.moveId
  local move = frame.calledBy and battle.data.moves[frame.calledBy] or frame.move
  local eligible = move and math.floor((tonumber(move.flags) or 0) / 16) % 2 == 1
  if not frame.noEffect and not frame.missed and eligible and target.mon.hp > 0 then
    target.gbaLastTakenMove = chosen
  end
end
function M.signature(user)
  return ":mirror=" .. tostring(user.gbaLastTakenMove)
end
return M
