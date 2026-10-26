-- GBA's hit-count opcode runs only after a successful accuracy check.
local M = {}
local V = require("src.core.GameVersion")
local cache = setmetatable({}, { __mode = "k" })
function M.ordinary(move)
  local effect = tonumber(move.gen3Effect)
  return effect == 29 or effect == 44 or effect == 77
end
function M.builtin(id, base)
  if not V.isGen3() or not base or id ~= "TWO_TO_FIVE_ATTACKS_EFFECT" then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  out.hitCount = function(ctx)
    if not V.isGen3() then
      return base.hitCount(ctx)
    end
    local first = ctx.rng(0, 3)
    return first > 1 and ctx.rng(0, 3) % 4 + 2 or first + 2
  end
  cache[base] = out
  return out
end
function M.sleepTalk(battle)
  local frame = battle._gbaMoveFrame
  local caller = frame and frame.parent and frame.parent.move
  return caller
    and (tonumber(caller.index) == 214 or tonumber(caller.gen3Effect) == 97 or caller.id == "SLEEP_TALK")
end
return M
