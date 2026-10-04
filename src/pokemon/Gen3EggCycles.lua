-- Emerald's daycare byte advances even when the party has no eggs. It ticks
-- at 255, wraps on the following step, and checks zero before decrementing.
local Eggs={}
function Eggs.subtract(data,party)
  local Party=require("src.pokemon.Party")
  for _,mon in ipairs(party or {}) do
    if not Party.isEgg(mon) then
      local ability=require("src.battle.Abilities").of({mon=mon,def=(data.pokemon or {})[mon.species]})
      if ability=="FLAME_BODY" or ability=="MAGMA_ARMOR" then return 2 end
    end
  end
  return 1
end
function Eggs.advance(data,save)
  save.gen3EggStepCounter=((tonumber(save.gen3EggStepCounter) or 0)+1)%256
  if save.gen3EggStepCounter~=255 then return nil end
  local party=save.party or {}
  local subtract=Eggs.subtract(data,party)
  for _,mon in ipairs(party) do
    if require("src.pokemon.Party").isEgg(mon) and not (mon.isBadEgg or mon.badEgg) then
      -- Existing saves store equivalent steps rather than the native byte.
      -- Preserve their remaining progress, rounding a partial cycle upward.
      local cycles
      if mon.eggSteps~=nil then cycles=math.max(0,math.ceil((tonumber(mon.eggSteps) or 0)/256))
      else cycles=tonumber(((data.pokemon or {})[mon.species] or {}).eggCycles) or 20 end
      if cycles==0 then return mon end
      cycles=cycles-(cycles>=subtract and subtract or 1)
      mon.eggSteps=cycles*256
      mon.isEgg=true
    end
  end
end
return Eggs
