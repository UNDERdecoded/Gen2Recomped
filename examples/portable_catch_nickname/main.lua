local mod = ...
local verdict, calls, last = "forward", 0, nil
local off = mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
  calls = calls + 1
  last = { mon = mon, context = ctx }
  if verdict == "forward" then
    return next(mon, ctx)
  end
  if verdict == "error" then
    error("intentional catch nickname consumer error")
  end
  return verdict
end)
mod.exports = {
  set = function(value)
    verdict = value
  end,
  calls = function()
    return calls
  end,
  last = function()
    return last
  end,
  off = off,
}
