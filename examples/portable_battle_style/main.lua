local mod = ...
local mode, calls = "forward", 0
local off = mod.hooks:wrap("battle.style", function(next, battle)
  calls = calls + 1
  if mode == "forward" then
    return next(battle)
  end
  if mode == "error" then
    error("intentional battle-style consumer error")
  end
  return mode
end)
mod.exports = {
  set = function(value)
    mode = value
  end,
  calls = function()
    return calls
  end,
  off = off,
}
