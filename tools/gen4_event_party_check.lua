package.path='./?.lua;'..package.path
require('src.script.Gen4Commands')
local C=require('src.script.Commands')
local VM=require('src.script.Gen4ScriptVM')
local ctx={save={party={},gen4Vars={[0x4001]=486}},g4Compare=2,lastCheck=false}
local function answer() return ctx.save.gen4Vars[0x4002] end
C.g4_fateful_slot(ctx,0x4002,0x4001);assert(answer()==255,'no match must be FF, not slot zero')
ctx.save.party={{species=486,fatefulEncounter=true,isEgg=true},{species=486},{species=486,fatefulEncounter=1}}
C.g4_fateful_slot(ctx,0x4002,0x4001);assert(answer()==2,'skip eggs and ordinary specimens')
C.g4_fateful_regigigas(ctx,0x4002);assert(answer()==1)
ctx.save.party[3].fatefulEncounter=false
C.g4_fateful_regigigas(ctx,0x4002);assert(answer()==0)
ctx.save.party[3].species='SPECIES_492';ctx.save.party[3].fateful=true;ctx.save.party[3].fatefulEncounter=nil
C.g4_fateful_slot(ctx,0x4002,492);assert(answer()==2,'support extracted species keys')
C.g4_fateful_regigigas(ctx,0x4002);assert(answer()==0,'other event species cannot unlock Regigigas gates')
C.g4_party_pokerus(ctx,0x4002);assert(answer()==0)
ctx.save.party[1].pokerus=16
C.g4_party_pokerus(ctx,0x4002);assert(answer()==1,'cured Pokerus and eggs count in this ROM query')
ctx.save.party[1].pokerus=0;ctx.save.party[2].gen4Pokerus=17
C.g4_party_pokerus(ctx,0x4002);assert(answer()==1)
assert(ctx.g4Compare==2 and ctx.lastCheck==false,'party queries must preserve the comparison register')
local rows=VM.lower({
 {name='findpartyslotwithfatefulencounterspecies',args={0x4002,0x4001}},
 {name='checkpartyhasfatefulencounterregigigas',args={0x4002}},
 {name='checkpartypokerus',args={0x4002}},
})
assert(rows[1][1]=='g4_fateful_slot' and rows[1][2]==0x4002 and rows[1][3]==0x4001)
assert(rows[2][1]=='g4_fateful_regigigas' and rows[3][1]=='g4_party_pokerus')
print('Platinum event party checks passed: event species slots, Regigigas gates, Pokerus, var operands and preserved comparisons')
local Origin=require('src.pokemon.Gen4Origin')
local game={data={constants={gen=4}}}
local mon={}
Origin.stamp(game,mon,'egg','Day-Care Couple',{year=2026,month=9,day=30})
Origin.stamp(game,mon,'hatch','Route 209',{year=2026,month=10,day=1})
assert(mon.eggDate.day==30 and mon.eggLocation=='Day-Care Couple')
assert(mon.metDate.day==1 and mon.metLocation=='Route 209' and mon.hatched)
Origin.stamp(game,mon,'met','Different location',{year=2027,month=1,day=1})
assert(mon.metDate.year==2026 and mon.metLocation=='Route 209','receiving again cannot replace provenance')
local old={};Origin.stamp({data={constants={gen=3}}},old,'met','Route 1',{year=2026,month=10,day=1})
assert(next(old)==nil,'Gen3 origin behavior must remain unchanged')
for _,file in ipairs({'src/script/Commands.lua','src/battle/BattleState.lua','src/pokemon/DayCare.lua','src/world/OverworldController.lua'}) do assert(loadfile(file),file) end
print('Gen4 origin checks passed: egg receipt, hatch history, retained dates and other-generation isolation')
local dexData=assert(loadfile('G:/Gen2Recomped/platinum/data/generated/gen4_dex.lua'))()
ctx.game={data={gen4_dex=dexData}}
ctx.save.pokedex={seen={},owned={}}
for _,id in ipairs(dexData.orders.sinnoh) do ctx.save.pokedex.seen[id]=true end
assert(#dexData.orders.sinnoh==210)
C.g4_dex_complete(ctx,0x4002,false);assert(answer()==1)
ctx.save.pokedex.seen[490]=nil
C.g4_dex_complete(ctx,0x4002,false);assert(answer()==0,'Platinum includes Manaphy in its regional goal')
ctx.save.pokedex.seen[151]=true
C.g4_dex_seen_count(ctx,0x4002);assert(answer()==209,'a non-Sinnoh species cannot inflate the local count')
ctx.save.pokedex.seen['SPECIES_387']=true;ctx.save.pokedex.seen[900]=true;ctx.save.pokedex.seen[490]=false
C.g4_dex_seen_count(ctx,0x4002);assert(answer()==209,'deduplicate keys and ignore false/invalid records')
C.g4_national_dex_seen(ctx,0x4002);assert(answer()==210)
for id=1,493 do ctx.save.pokedex.owned[id]=true end
for _,id in ipairs({151,249,250,251,385,386,489,490,491,492,493}) do ctx.save.pokedex.owned[id]=nil end
C.g4_dex_complete(ctx,0x4002,true);assert(answer()==1,'National completion excludes the ROM event-only list')
ctx.save.pokedex.owned[387]=nil
C.g4_dex_complete(ctx,0x4002,true);assert(answer()==0,'481 required catches is not complete')
C.g4_dex_caught_count(ctx,0x4002,true);assert(answer()==481)
assert(ctx.g4Compare==2 and ctx.lastCheck==false)
print('Dex story checks passed: regional numbering/counts, Manaphy requirement, National exclusions and completion thresholds')
ctx.save.party={{species=486,isEgg=true},{species=387}}
ctx.save.gen4Vars[0x4001]=387
C.g4_party_has_species(ctx,0x4002,0x4001);assert(answer()==1,'destination-first party query was overwritten')
C.g4_party_has_species(ctx,0x4002,486);assert(answer()==0,'destination-first query excludes eggs')
C.g4_party_has_species2(ctx,0x4001,0x4002);assert(answer()==1,'species-first query must keep its operand order')
local queryRows=VM.lower({{name='checkpartyhasspecies',args={0x4002,0x4001}},
 {name='checkpartyhasspecies2',args={0x4001,0x4002}}})
assert(queryRows[1][1]=='g4_party_has_species' and queryRows[2][1]=='g4_party_has_species2')
print('Both party-species opcodes preserve their distinct argument orders')
