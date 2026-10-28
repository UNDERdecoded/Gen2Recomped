-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local F=require('tests.gsc_species_fixture')
local Names=require('src.core.Gen2SpeciesNames')
local Pokemon=require('src.pokemon.Pokemon')
local Commands=require('src.script.Commands')
local VM=require('src.script.Gen2ScriptVM')
local DC=require('src.pokemon.DayCare')
for _,edition in ipairs{'gold','silver','crystal'}do
  V.set(edition);local d=F.new();d:seedDefaults()
  local function mon(index)return Pokemon.new(d,Names.fromNumber(d,index),5,function(lo)return lo end)end
  d.map_scripts={scripts={IDENTITY={
    {'getmonname',155,0},{'checkpoke',155},{'giveegg',175,5},{'cry',155},
    {'pokepic',155},{'loadwildmon',133,5},{'end'},
  },GIFT={{'checkpoke',155},{'giveegg',175,5},{'end'}}}}
  local rows=assert(VM.compile(d,'IDENTITY'));local lowered={}
  for _,row in ipairs(rows)do lowered[row[1]]=row end
  for _,op in ipairs{'g2_getmonname','g2_check_poke','g2_cry','g2_pokepic'}do
    T.eq(lowered[op][2],'CYNDAQUIL',op..' resolves native byte operand through the same dataset')
  end
  T.eq(lowered.g2_give_egg[2],'TOGEPI');T.eq(lowered.g2_load_wild[2],'EEVEE')
  local save={party={mon(155)},boxes={},flags={},player={name='TEST',id=42},
    pokedex={seen={},owned={}}}
  local game={data=d,save=save,overworld={}}
  local ctx={game=game,save=save,overworld=game.overworld,g2Var=155}
  Commands.g2_check_poke(ctx,'SPECIES_155');T.eq(ctx.g2Var,1)
  ctx.g2Var=155;Commands.g2_find_party_species_own(ctx);T.eq(ctx.g2Var,1)
  ctx.g2Var=155;Commands.g2_seen_mon(ctx);T.eq(save.pokedex.seen.CYNDAQUIL,true)
  T.eq(save.pokedex.seen.SPECIES_155,nil)
  Commands.g2_give_poke(ctx,133,5,0)
  T.eq(#save.party,2);T.eq(save.party[2].species,'EEVEE')
  -- Runtime wildcard/gift/check bytecode executes with actual native rows,
  -- not a second simulated VM or a facade replacing the party Pokemon.
  local Runner=require('src.script.ScriptRunner')
  local runner=Runner.new(game,game.overworld)
  runner:run(VM.compile(d,'GIFT'))
  T.eq(runner:isRunning(),false,'real noninteractive gift program finishes')
  T.eq(save.party[1].species,'CYNDAQUIL')
  local found
  for _,m in ipairs(save.party)do if m.isEgg and m.species=='TOGEPI'then found=m end end
  T.check(found~=nil,'real native lowered giveegg creates the named hatchling')
  if found then
    require('src.pokemon.Gen2Breeding').hatch(game,found)
    T.eq(save.flags[require('src.script.Gen2Flags').eventFlag(0x54)],true)
    T.eq(save.pokedex.owned.TOGEPI,true)
  end
  -- A genderless Ditto must breed with a male of another egg group and
  -- return that parent's actual canonical species in either slot order.
  d.pokemon.DITTO.eggGroups={'DITTO'};d.pokemon.DITTO.genderRatio=255
  d.pokemon.CYNDAQUIL.eggGroups={'FIELD'}
  local ditto,other=mon(132),mon(155)
  other.dvs.attack=15;other.dvs.defense=3;ditto.dvs.defense=6
  for _,parents in ipairs{{ditto,other},{other,ditto}}do
    local s={daycare={breed={{mon=parents[1]},{mon=parents[2]}}}}
    local a,b=DC.pair(d,s);T.eq(a,parents[1]);T.eq(b,parents[2])
    T.eq(DC.eggSpecies(d,s),'CYNDAQUIL')
  end
  local s={daycare={breed={{mon=ditto},{mon=mon(132)}}}}
  T.eq(DC.pair(d,s),nil,'two canonical Dittos cannot breed')
  local nidoran=mon(29)
  s={daycare={breed={{mon=ditto},{mon=nidoran}}}}
  local random=math.random
  math.random=function()return 127 end;T.eq(DC.eggSpecies(d,s),'NIDORAN_F')
  math.random=function()return 128 end;T.eq(DC.eggSpecies(d,s),'NIDORAN_M')
  math.random=random
  -- Roaming encounters, once staged, also expose the canonical identity.
  Commands.g2_init_roam_mons(ctx)
  T.eq(save.g2Roam.RAIKOU.speciesId,'RAIKOU')
  T.eq(save.g2Roam.ENTEI.speciesId,'ENTEI')

end
V.set(old)
T.finish('native canonical GSC script operands, gifts, breeding and hatch ownership')
