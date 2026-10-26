local mod = ...
local verdict, calls, last = "forward", 0, nil
local custody = {}
local off = mod.hooks:wrap("catch.party_full", function(next, ctx)
  calls = calls + 1
  last = ctx
  if verdict == "forward" then
    return next(ctx)
  end
  if verdict == "error" then
    error("intentional party-full consumer error")
  end
  if verdict then
    custody[#custody + 1] = ctx.mon
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
  custody = custody,
  off = off,
}
