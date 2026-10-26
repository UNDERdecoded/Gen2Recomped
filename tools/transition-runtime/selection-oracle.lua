local code,mode,out=assert(arg[1]),assert(arg[2]),assert(arg[3])
package.path=code..'/?.lua;'..code..'/?/init.lua;'..package.path
local J=require('src.link.Json')
local cases={}
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  for terrain=0,3 do for _,levels in ipairs({{3,5},{5,5},{8,5}})do
    for _,kind in ipairs({'wild','trainer'})do
      for _,cls in ipairs({0,3,9,11,13,24,31,32,38,49,53,87,90})do
        for _,id in ipairs({0,261,262,263,264,335,410,411,412,413,735,736,737,738,1024})do
          cases[#cases+1]={edition=edition,kind=kind,opts={terrain=terrain,mapBehavior=0,mapType=0,
            playerLevel=levels[2],enemyLevel=levels[1],trainerClass=cls,trainerId=id}}
        end
      end
    end
  end end
  for _,cls in ipairs({31,38,87,90})do for _,flag in ipairs({'isLorelei','isBruno','isAgatha','isLance','isBlue','isChampion','isRival','trainerTower','eReader'})do
    for _,kind in ipairs({'wild','trainer'})do
      local opts={trainerClass=cls,mapBehavior=0,mapType=0};opts[flag]=true
      cases[#cases+1]={edition=edition,kind=kind,opts=opts}
    end
  end end
end
if mode=='source'then
  local V=require('src.core.GameVersion')
  local fr=require('src.core.game3.battle_transition_ids_frlg')
  local rse=require('src.core.game3.battle_transition_ids_rse')
  for _,case in ipairs(cases)do
    V.set(case.edition)
    local ids=(case.edition=='firered'or case.edition=='leafgreen')and fr or rse.forVersion(case.edition)
    case.expected=(case.kind=='wild'and ids.pickWild or ids.pickTrainer)(case.opts)
  end
  local f=assert(io.open(out,'w'));f:write(J.encode(cases));f:close()
  print('independent source selections',#cases)
else
  local f=assert(io.open(out));cases=J.decode(f:read('*a'));f:close()
  local C=require('src.compat.gen1.TransitionCatalog');local failures={}
  for _,case in ipairs(cases)do
    local got=C.pick(case.edition,case.opts,case.kind=='trainer')
    if got~=case.expected and #failures<20 then failures[#failures+1]={case=case,got=got}end
  end
  print('native selections',#cases,'different',#failures)
  assert(#failures==0,J.encode(failures))
end
