-- Party helpers (max 6, like the original).

local Party = {}

Party.MAX = 6

function Party.add(party, mon)
  if #party >= Party.MAX then
    return false -- box system comes later
  end
  table.insert(party, mon)
  return true
end

-- An EGG occupies a party slot but is not a Pokemon yet: CheckFirstMonIsEgg
-- (01:$728B) refuses to send one out, and every "usable mon" test in Gen2
-- goes through it.  Modelling that here keeps eggs out of battle leads,
-- switch-ins and the blackout check in one place.
function Party.isEgg(mon)
  return mon ~= nil and mon.isEgg == true
end

function Party.firstHealthy(party)
  for i, mon in ipairs(party) do
    if mon.hp > 0 and not Party.isEgg(mon) then return mon, i end
  end
  return nil
end

return Party
