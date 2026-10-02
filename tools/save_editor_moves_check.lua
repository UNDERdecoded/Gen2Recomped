package.path='tools/save-editor/?.lua;tools/save-editor/panels/?.lua;'..package.path
local version='platinum'
package.loaded['src.core.GameVersion']={get=function() return version end,
 isGen4=function() return version=='platinum' end,isGen3=function() return version=='emerald' end,isGen2=function() return false end}
love={math={random=math.random},graphics={setColor=function() end,rectangle=function() end,
 newImage=function() error('not mounted') end}}
local Catalog=require('Catalog');local Ops=require('Ops');local MonOps=require('MonOps')
local MonEditor=require('MonEditor');local Pokemon=require('src.pokemon.Pokemon')
local root=arg[1] or 'G:/Gen2Recomped/platinum/data/generated/'
local data={constants={gen=4},isGen4Cache=true,pokemon=assert(loadfile(root..'pokemon.lua'))(),
 moves=assert(loadfile(root..'moves.lua'))(),items=assert(loadfile(root..'items.lua'))()}
local growth={'MEDIUM_FAST','ERRATIC','FLUCTUATING','MEDIUM_SLOW','FAST','SLOW'}
for _,def in pairs(data.pokemon) do
 local b=def.baseStats;b.spatk=b.spAttack;b.spdef=b.spDefense;b.special=b.spAttack
 def.evYield=def.evYields;def.evYield.spatk=def.evYield.spAttack;def.evYield.spdef=def.evYield.spDefense
 def.growthRate=growth[def.expRate+1];def.level1Moves={}
 for _,row in ipairs(def.learnset or {}) do if row.level<=1 then def.level1Moves[#def.level1Moves+1]=row.move end end
end
local checks=0;local function check(ok,why) assert(ok,why);checks=checks+1 end
local cat=Catalog.build(data)
check(#cat.moves==467 and cat.moves[1]==1 and cat.moves[#cat.moves]==467,'all real Platinum moves, without MOVE_NONE')
for id=1,467 do check(Catalog.moveLabel(data,id)~=tostring(id),'native move lacks readable name: '..id) end
check(Catalog.moveLabel(data,33)=='Tackle','numeric move label uses extracted name')
check(Catalog.moveLabel(data,999)=='999' and Catalog.moveLabel(data,nil)=='-- --','safe unknown and empty labels')
local mon=Pokemon.new(data,387,5)
mon.moves={{id=33,pp=7},{id=110,pp=10},{id=45,pp=0},{id=73,pp=3}}
local S={data=data,cat=cat,save={party={mon}},editingMon=mon}
local labels={};local click=false
local Kit=setmetatable({scale=1,textHeight=function() return 12 end,textWidth=function(_,s) return #tostring(s)*6 end,
 ellipsize=function(_,s) return tostring(s) end,text=function(_,s) labels[#labels+1]=s end,
 press=function(_,_,_,h) if click and h>12 then click=false;return true end;return false end},
 {__index=function() return function() return false end end})
MonEditor.draw(S,Kit,0,0,700,950)
local function shown(s) for _,label in ipairs(labels) do if label==s then return true end end end
check(shown('Tackle') and shown('Withdraw') and shown('Growl') and shown('Leech Seed'),'actual inspector renders four names')
check(not shown('33') and not shown('110'),'raw move IDs no longer printed in rows')
-- Drive the inspector's real row click, not only the mutation helper.
click=true;MonEditor.draw(S,Kit,0,0,700,950)
check(mon.moves[1].id==34 and S.status:find('Body Slam',1,true),'row cycling stores numeric ID and reports its name')
labels={};MonEditor.draw(S,Kit,0,0,700,950);check(shown('Body Slam'),'next frame shows changed name')
mon.moves[1].ppUps=3;MonOps.setMove(data,mon,1,33)
check(mon.moves[1].pp==35 and not mon.moves[1].ppUps,'replacement clears old Platinum PP Ups')
mon.moves[1].ppUps=3;MonOps.setMove(data,mon,1,33)
check(mon.moves[1].pp==56 and mon.moves[1].ppUps==3,'same-move refill retains its boosts')
mon.hp=mon.stats.hp;mon.status=nil;mon.moves[1].pp=0
check(Ops.healMon(S,mon) and mon.moves[1].pp==56,'full HP still restores depleted PP')
check(not Ops.healMon(S,mon),'already healed is a no-op')
-- Old editor saves can have holes: all four fixed PP slots must be visited.
mon.moves={[2]={id=33,pp=0},[4]={id=110,pp=0,ppUps=2}}
check(Ops.healMon(S,mon) and mon.moves[2].pp==35 and mon.moves[4].pp==56,'heal visits moves after empty slots')
mon.moves={{id=33,pp=4},{id=110,pp=6,ppUps=2},{id=45,pp=1}}
check(Ops.clearMove(S,mon,1) and mon.moves[1].id==110 and mon.moves[1].pp==6 and mon.moves[1].ppUps==2 and mon.moves[2].id==45 and mon.moves[3]==nil,'native deletion shifts complete remaining move records')
check(S.status:find('Tackle',1,true),'clear feedback uses move name')
local empty={data=data,cat={moves={}},save={}}
local before=mon.moves[1];check(not Ops.cycleMove(empty,mon,1) and mon.moves[1]==before,'empty catalog is a safe no-op')
-- Deoxys' alternate personal rows have distinct learnsets.
local deoxys=Pokemon.new(data,386,50,nil,1)
local formDef=require('src.pokemon.Gen4Forms').definition(data,deoxys)
local expected=Pokemon.movesAtLevel(formDef,50)
check(Ops.resetMoves(S,deoxys),'form reset succeeds')
local actual={};for i,mv in ipairs(deoxys.moves) do actual[i]=mv.id end
check(table.concat(actual,',')==table.concat(expected,','),'reset follows native alternate-form learnset')
check(table.concat(actual,',')~=table.concat(Pokemon.movesAtLevel(data.pokemon[386],50),','),'fixture distinguishes base and attack-form learnsets')
local SaveData=require('src.core.SaveData')
local save=assert(SaveData.decode(SaveData.encode({party={deoxys}})))
for i,mv in ipairs(save.party[1].moves) do check(type(mv.id)=='number' and mv.id==expected[i] and mv.pp==data.moves[mv.id].pp,'move IDs and PP survive save encoding') end
-- Legacy symbolic IDs and custom moves keep working.
local legacy={constants={gen=3},pokemon={},items={},moves={TACKLE={pp=35},CUSTOM={name='Custom Beam',pp=10}}}
check(Catalog.moveLabel(legacy,'TACKLE')=='TACKLE' and Catalog.moveLabel(legacy,'CUSTOM')=='Custom Beam','symbolic and custom labels')
local oldMon={moves={{id='TACKLE',ppUps=2}}};MonOps.setMove(legacy,oldMon,1,'CUSTOM')
check(oldMon.moves[1].pp==14 and oldMon.moves[1].ppUps==2,'legacy editing behavior retained')
local TrainerEditor=require('tools.map-editor.panels.PartyEditor')
love.graphics.getDimensions=function() return 1200,900 end
local trainer={trainerTeam={{species=387,level=5}}}
local mapState={data=data,cat=cat}
check(TrainerEditor.open(mapState,trainer),'trainer party editor opens')
local found=TrainerEditor.moveList(mapState,'tAcKlE')
check(#found==2 and found[1]==33 and found[2]==344,'trainer picker searches ROM names case-insensitively')
found=TrainerEditor.moveList(mapState,'467')
check(#found==1 and found[1]==467,'trainer picker also searches IDs')
mapState.cat.moves={0,33,468,469,470};found=TrainerEditor.moveList(mapState,'')
check(#found==1 and found[1]==33,'trainer picker excludes native empty/internal move records')
mapState.cat=cat;mapState.partyAsk.moveQuery='Tackle'
local slot=mapState.partyAsk.team[1];mapState.partyMovePick={slot=slot,index=3}
local chosen=false;local mapLabels={}
local MapKit=setmetatable({scale=1,textHeight=function() return 12 end,ellipsize=function(_,s) return tostring(s) end,
 textfield=function(_,_,_,_,_,value) return value end,
 button=function(_,_,_,_,label)
  mapLabels[#mapLabels+1]=label
  if label=='Tackle' and not chosen then chosen=true;return true end
  return false
 end},{__index=function() return function() return false end end})
TrainerEditor.draw(mapState,MapKit,function() error('picker must not commit yet') end)
check(chosen and slot.moves[1]==33 and slot.moves[2]==nil,'trainer choosing slot 3 with empty earlier slots retains the move')
check(not trainer.trainerTeam[1].moves,'trainer edits stay on working copy until Save')
TrainerEditor.commit(mapState,function(_,obj,key,value) obj[key]=value end)
check(trainer.trainerTeam[1].moves[1]==33,'trainer Save commits numeric move ID')
mapLabels={};TrainerEditor.draw(mapState,MapKit,function() end)
local sawName=false;for _,label in ipairs(mapLabels) do if label=='Tackle' then sawName=true end end
check(sawName,'trainer move row displays selected ROM name')
print(checks..' move-editor name/render/click/save, Platinum PP/reset/deletion and legacy checks passed')
