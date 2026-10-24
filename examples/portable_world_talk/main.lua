-- A portable mod can answer its own NPC without replacing engine methods.
local mod = ...
local out = mod.exports
local claimedId
out.api, out.seen = mod, { calls = 0, claimed = 0 }
function out.claim(id)
  claimedId = id
end
out.stop = mod.hooks:wrap("world.talk", function(next, owner, target, ...)
  local seen = out.seen
  seen.calls = seen.calls + 1
  seen.owner, seen.target, seen.extra = owner, target, select("#", ...)
  if claimedId and target and target.id == claimedId then
    seen.claimed = seen.claimed + 1
    return "claimed"
  end
  return next(owner, target)
end)
