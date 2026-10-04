package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald daycare residents')
local V=require('src.core.GameVersion');V.set('emerald')
local P=require('src.pokemon.Pokemon')
local DC=require('src.pokemon.DayCare')
local G3=require('src.script.Gen3Commands')
local Growth=require('src.pokemon.Growth')
local root='G:/Gen2Recomped/emerald/data/generated/'
local data={}
for _,key in ipairs({'constants','pokemon','moves'}) do data[key]=assert(loadfile(root..key..'.lua'))() end
Growth.setTables(data.constants.experienceTables)
local function context(mon)
  return {save={flags={},gen3Vars={[0x8004]=0},party={mon}},game={data=data}}
end
-- Native BoxMonRestorePP honors the bonus on every move, including 1-PP moves.
for id,def in pairs(data.moves) do
  if type(def)=='table' and type(def.pp)=='number' then
    for ups=0,3 do
      local mon=P.new(data,'PIKACHU',20)
      mon.moves={{id=id,pp=0,ppUps=ups}};mon.hp=1;mon.status='PSN'
      local ctx=context(mon);G3.SPECIALS[190](ctx)
      local resident=DC.mon(ctx.save,1)
      T.eq(resident.moves[1].pp,def.pp+math.floor(def.pp*ups/5),'deposit restores native PP bonus for '..id)
      T.eq(resident.moves[1].ppUps,ups,'deposit retains PP Up count')
    end
  end
end
for _,species in ipairs({'PIKACHU','RALTS','MAGIKARP','SHEDINJA','NINCADA','MARILL','WOBBUFFET'}) do
  for _,status in ipairs({'PSN','BRN','SLP','PAR','FRZ'}) do
    local mon=P.new(data,species,20);mon.nickname='DAYCARE';mon.hp=0;mon.status=status
    local ctx=context(mon);G3.SPECIALS[190](ctx)
    local slot=DC.slot(ctx.save,1)
    slot.steps=Growth.expForLevel(data.pokemon[species].growthRate,25)-mon.exp
    T.eq(G3.SPECIALS[193](ctx),5,'attendant reports banked levels')
    T.eq(ctx.game.stringBuffers[1],'DAYCARE','growth report substitutes resident nickname')
    T.eq(ctx.game.stringBuffers[2],'5','growth report substitutes level gain')
    T.eq(G3.SPECIALS[194](ctx),600,'withdrawal costs100 plus100 per level')
    T.eq(ctx.save.gen3Vars[0x8005],600,'script money argument matches quote')
    T.eq(ctx.game.stringBuffers[1],'DAYCARE','quote substitutes nickname')
    T.eq(ctx.game.stringBuffers[2],'600','quote substitutes cost in second buffer')
    G3.SPECIALS[195](ctx)
    local returned=ctx.save.party[1]
    T.eq(returned.level,25,'withdrawal applies banked experience')
    T.eq(returned.status,nil,'boxed conversion clears persistent status')
    T.eq(returned.hp,returned.stats.hp,'boxed conversion restores full current HP')
    T.eq(returned.stats.hp,require('src.pokemon.Stats').calcGen3(data.pokemon[species],25,returned.ivs,returned.evs,returned.nature).hp,'HP reflects new level')
    T.eq(returned.species,species,'daycare does not evolve residents')
  end
end
local mon=P.new(data,'PIKACHU',100);mon.hp=1;mon.status='PSN'
local originalExp=mon.exp
local ctx=context(mon);G3.SPECIALS[190](ctx);DC.slot(ctx.save,1).steps=10000
T.eq(G3.SPECIALS[194](ctx),100,'level100 resident has no level surcharge')
G3.SPECIALS[195](ctx)
T.eq(mon.exp,originalExp,'level100 resident does not receive banked experience')
T.eq(mon.hp,mon.stats.hp,'level100 resident is healthy on return')
T.eq(mon.status,nil,'level100 resident status cleared')
-- No available pen must leave the selected party member and its PP alone.
mon=P.new(data,'PIKACHU',20);mon.moves={{id='THUNDERSHOCK',pp=0}}
ctx=context(mon);DC.deposit(ctx.save,1,P.new(data,'RALTS',20));DC.deposit(ctx.save,2,P.new(data,'MAGIKARP',20))
G3.SPECIALS[190](ctx)
T.eq(ctx.save.party[1],mon,'full daycare refuses deposit')
T.eq(mon.moves[1].pp,0,'refused deposit does not restore PP')
-- The second resident must supply its own report/quote, regardless of stale buffers.
local other=DC.mon(ctx.save,2);other.nickname='SECOND'
ctx.save.gen3Vars[0x8004]=1;ctx.game.stringBuffers={[1]='STALE',[2]='STALE'}
G3.SPECIALS[193](ctx)
T.eq(ctx.game.stringBuffers[1],'SECOND','second resident growth report selects correct nickname')
T.eq(ctx.game.stringBuffers[2],'0','second resident report clears stale gain')
G3.SPECIALS[194](ctx)
T.eq(ctx.game.stringBuffers[1],'SECOND','second resident quote selects correct nickname')
T.eq(ctx.game.stringBuffers[2],'100','second resident quote updates cost')
local Data=require('src.core.Data');local previousMoves=Data.moves;Data.moves=data.moves
mon.hp=0;mon.status='BRN';mon.moves={{id='THUNDERSHOCK',pp=0,ppUps=3}}
P.heal(mon)
T.eq(mon.hp,mon.stats.hp,'shared Center healing still restores HP')
T.eq(mon.status,nil,'shared Center healing still clears status')
T.eq(mon.moves[1].pp,48,'shared Center healing retains PP Up restoration')
Data.moves=previousMoves
T.finish()
