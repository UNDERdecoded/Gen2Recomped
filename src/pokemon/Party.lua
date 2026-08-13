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
-- Deliberately truthy rather than `== true`, and it accepts a live hatch
-- counter as proof on its own.
--
-- This one predicate is what hides everything an EGG must not give away --
-- the species icon and name in the party list, the stats screen, the battle
-- switch guards, the blackout check.  Testing `mon.isEgg == true` meant a
-- single lost or differently-typed flag (a 1 rather than a true, a field
-- dropped by an older save or an importer) leaked the whole lot at once, and
-- a leak here is a spoiler the player can never un-see.  eggSteps is only
-- ever set alongside isEgg and cleared by HatchEggs, so it is a safe second
-- witness.
function Party.isEgg(mon)
  if mon == nil then return false end
  if mon.isEgg then return true end
  return (tonumber(mon.eggSteps) or 0) > 0
end

function Party.firstHealthy(party)
  for i, mon in ipairs(party) do
    if mon.hp > 0 and not Party.isEgg(mon) then return mon, i end
  end
  return nil
end

return Party
