-- ROM RandomWildSpeciesForms.Unown / UnlockedUnownLetterSets:
-- one-based stored forms A..Z, !, ?; four puzzle-unlocked groups.
local U={groups={{1,2,3,4,5,6,7,8,9,10},{11,12,13,14,15,16,17},
 {18,19,20,21,22,23},{24,25,26,27,28}},address=0xDEDF}
function U.choose(save,rng)
 local mask=save and save.g2Wram and save.g2Wram[U.address] or 0
 -- Older port saves never recorded this byte when completing puzzles.
 if mask==0 then mask=1 end
 local eligible={}
 for i,group in ipairs(U.groups)do
  if math.floor(mask/2^(i-1))%2==1 then
   for _,form in ipairs(group)do eligible[#eligible+1]=form end
  end
 end
 return eligible[(rng or love.math.random)(1,#eligible)]
end
function U.unlock(save,picture)
 local i=tonumber(picture)
 if not i or i<0 or i>3 then return end
 save.g2Wram=save.g2Wram or {}
 local mask=save.g2Wram[U.address] or 0
 local bit=2^i
 if math.floor(mask/bit)%2==0 then mask=mask+bit end
 save.g2Wram[U.address]=mask
end
return U
