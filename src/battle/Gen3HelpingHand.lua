-- Native GBA Helping Hand is a battler-local, turn-scoped modifier.
local Version = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local H = {}
local function name(actor)
  return actor.isPlayer and actor.name or ("Enemy " .. actor.name)
end
function H.apply(battle, user)
  local partner = Version.isGen3() and battle:partnerOf(user)
  if
    not partner
    or not partner.mon
    or (partner.mon.hp or 0) <= 0
    or user._gen3HelpingHand
    or partner._gen3HelpingHand
  then
    return { Strings("But, it failed!") }
  end
  partner._gen3HelpingHand = true
  return { battle:romText("STRINGID_PKMNREADYTOHELP", "%s is ready to\nhelp %s!", name(user), name(partner)) }
end
function H.damage(user, amount)
  if Version.isGen3() and user._gen3HelpingHand then
    return math.floor(amount * 15 / 10)
  end
  return amount
end
return H
