-- Keep the caller's omitted/explicit selector without changing native hook
-- arguments. Each synchronous hook/next call owns a frame, including reentry.
local C = {}
local frames = setmetatable({}, { __mode = "k" })
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
function C.call(battle, selector, fn, ...)
  local previous = frames[battle]
  frames[battle] = { explicit = selector ~= nil, default = battle.enemy }
  local result = pack(pcall(fn, ...))
  frames[battle] = previous
  if not result[1] then
    error(result[2], 0)
  end
  return unpack(result, 2, result.n)
end
local function actorAt(battle, id)
  if id == 0 then
    return battle.player
  end
  if id == 1 then
    return battle.enemy
  end
  return battle:battlerAt(id)
end
function C.publicId(battle, actor)
  local frame = frames[battle]
  if actor == nil or (frame and not frame.explicit and actor == frame.default) then
    return nil
  end
  local id = actor == battle.player and 0 or actor == battle.enemy and 1 or actor.position
  assert(
    type(id) == "number" and id % 1 == 0 and id >= 0 and id <= 3,
    "enemy action requires a positional battler"
  )
  assert(actorAt(battle, id) == actor, "enemy action battler is no longer active")
  return id
end
function C.nativeActor(battle, id)
  if id == nil then
    return battle.enemy
  end
  assert(
    type(id) == "number" and id % 1 == 0 and id >= 0 and id <= 3,
    "enemy action battler ID must be an integer from 0 to 3"
  )
  local actor = actorAt(battle, id)
  assert(actor, "enemy action battler is not active")
  return actor
end
return C
