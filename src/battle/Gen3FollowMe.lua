-- Round-local GBA Follow Me state. The native flag names a position: a new
-- occupant of that slot inherits redirection until the next turn is planned.
local Version = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local F = {}
local function position(battle, user)
  return user == battle.player and 0 or user == battle.enemy and 1 or user.position
end
function F.apply(battle, user)
  if not Version.isGen3() then
    return { Strings("But, it failed!") }
  end
  local id = position(battle, user)
  local side = battle.sides and battle.sides[user.isPlayer and 1 or 2]
  if not side or type(id) ~= "number" or id % 1 ~= 0 or id < 0 or id > 3 then
    return { Strings("But, it failed!") }
  end
  side._gen3FollowMePosition = id
  local name = user.isPlayer and user.name or ("Enemy " .. user.name)
  return { battle:romText("STRINGID_PKMNCENTERATTENTION", "%s became the\ncenter of attention!", name) }
end
function F.center(battle, user)
  if not Version.isGen3() then
    return nil, false
  end
  local side = battle.sides and battle.sides[user.isPlayer and 2 or 1]
  local id = side and side._gen3FollowMePosition
  if id == nil then
    return nil, false
  end
  local holder
  if id == 0 then
    holder = battle.player
  elseif id == 1 then
    holder = battle.enemy
  else
    holder = battle:battlerAt(id)
  end
  if holder and holder.mon and (holder.mon.hp or 0) > 0 and holder.isPlayer ~= user.isPlayer then
    return holder, true
  end
  -- The native timer still suppresses Lightning Rod even if its holder has
  -- fainted. Only the next turn's planning resets the flag.
  return nil, true
end
function F.clear(battle)
  for _, side in ipairs(battle.sides or {}) do
    side._gen3FollowMePosition = nil
  end
end
return F
