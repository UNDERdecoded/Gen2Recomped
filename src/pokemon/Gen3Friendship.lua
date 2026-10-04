-- Emerald UpdateFriendshipStepCounter / AdjustFriendship(WALKING).
local Friendship={}
function Friendship.step(data,save,mapDef,rng)
  rng=rng or math.random
  save.gen3FriendshipSteps=((save.gen3FriendshipSteps or 0)+1)%128
  if save.gen3FriendshipSteps~=0 then return end
  local Party=require('src.pokemon.Party')
  for _,mon in ipairs(save.party or {}) do
    if mon.species and not Party.isEgg(mon) then
      local def=data.pokemon and data.pokemon[mon.species]
      -- Old engine-created residents omitted this native species byte.
      if mon.happiness==nil then mon.happiness=def and def.friendship or 70 end
      if rng(0,65535)%2==0 then
        local gain=1
        if mon.ball=='LUXURY_BALL' then gain=gain+1 end
        if mon.metLocation~=nil and mapDef and mon.metLocation==mapDef.regionMapSection then gain=gain+1 end
        -- Soothe Bell multiplies the base +1, rounding down: still +1.
        -- Luxury Ball and birthplace bonuses are added after that operation.
        mon.happiness=math.min(255,mon.happiness+gain)
      end
    end
  end
end
return Friendship
