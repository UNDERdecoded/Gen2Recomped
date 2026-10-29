-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local Names=require('src.core.Gen2SpeciesNames')
local F=require('tests.gsc_species_fixture')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Merge=require('src.mods.Merge')
local Registry=require('src.mods.Registry')
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
for _,edition in ipairs{'gold','silver','crystal'}do
  V.set(edition)
  local d=F.new();local p=d.pokemon;local cyndaquil=p.SPECIES_155
  local order=d.constants.speciesOrder
  p.SPECIES_155.evolutions={{method='LEVEL',level=14,species='SPECIES_156'}}
  d.encounters.TEST={slots={{species='SPECIES_155',level=5}}}
  d.identityTest={SPECIES_155={species='SPECIES_155'}}
  d.text.IDENTITY_LITERAL='SPECIES_155'
  d.field.identityTest={name='SPECIES_155',source='SPECIES_155',path='SPECIES_155',species='SPECIES_155'}
  local entry=d.identityTest.SPECIES_155
  -- Exercise the real pre-loader publication pass, including its second
  -- post-mod invocation. Existing tables/art and numeric indices survive.
  d:seedDefaults()
  T.eq(d.constants.speciesIdentity,'gsc-canonical-v1')
  T.eq(d.pokemon,p);T.eq(d.pokemon.CYNDAQUIL,cyndaquil)
  T.eq(d.pokemon.SPECIES_155,cyndaquil);T.eq(rawget(p,'SPECIES_155'),nil)
  T.eq(count(p),251,'exactly one iterated definition per native species')
  T.eq(cyndaquil.id,'CYNDAQUIL');T.eq(cyndaquil.index,155);T.eq(cyndaquil.dex,155)
  T.eq(cyndaquil.name,'Localized display name');T.eq(cyndaquil.source,'ROM:SPECIES_155')
  T.eq(cyndaquil.spriteFront,'tests/fixture_data/assets/fixmon_a_front.png')
  T.eq(cyndaquil.evolutions[1].species,'QUILAVA')
  T.eq(d.constants.speciesOrder,order);T.eq(order[155],'CYNDAQUIL')
  T.eq(d.encounters.TEST.slots[1].species,'CYNDAQUIL')
  T.eq(d.identityTest.CYNDAQUIL,entry);T.eq(entry.species,'CYNDAQUIL')
  T.eq(d.text.IDENTITY_LITERAL,'SPECIES_155','literal text never rewritten')
  for _,key in ipairs{'name','source','path'}do T.eq(d.field.identityTest[key],'SPECIES_155')end
  T.eq(d.field.identityTest.species,'CYNDAQUIL')
  T.eq(p.FARFETCHD,p.FARFETCH_D);T.eq(p.MR_MIME,p.MR__MIME)
  d:seedDefaults();T.eq(count(p),251);T.eq(p.CYNDAQUIL,cyndaquil)
  for index=1,251 do
    local id=Names.fromNumber(d,index)
    T.eq(p[id].id,id);T.eq(Names.number(d,id),index)
    T.eq(Names.registryId(p,string.format('SPECIES_%03d',index)),id)
    local mon=Pokemon.new(d,string.format('SPECIES_%03d',index),5,function(lo)return lo end)
    T.eq(mon.species,id,'actual native constructor exposes stable named identity')
  end
  local made=Pokemon.new(d,'CYNDAQUIL',5,function(lo)return lo end)
  T.eq(made.species,'CYNDAQUIL')
  -- Old and named addresses must share the real registry's edit/conflict/
  -- rollback/removal path, with no duplicate alias definitions after merge.
  local r=Registry.new('pokemon',require('src.mods.Schemas').REGISTRIES.pokemon)
  r.base=function()return p end
  r:patch('SPECIES_155',{baseExp=17},'old')
  r:patch('CYNDAQUIL',{baseStats={hp=73}},'new')
  T.eq(r:get('SPECIES_155'),r:get('CYNDAQUIL'));T.eq(#r:claimants('CYNDAQUIL'),2)
  r:rollback('old');Names.write(p,r)
  T.eq(p.CYNDAQUIL.baseStats.hp,73);T.eq(p.CYNDAQUIL.baseExp,cyndaquil.baseExp)
  r=Registry.new('pokemon',require('src.mods.Schemas').REGISTRIES.pokemon);r.base=function()return p end
  local replacement=Merge.deepCopy(cyndaquil);replacement.id='SPECIES_155'
  r:override('SPECIES_155',replacement,'replace');Names.write(p,r)
  T.eq(p.CYNDAQUIL.id,'CYNDAQUIL');T.eq(count(p),251)
  -- Validate a real save codec round trip: party, sparse PC, both day-care
  -- parents, pending egg, Hall of Fame, dex flags and roaming species.
  local function legacy(index)
    local mon=Pokemon.new(d,Names.fromNumber(d,index),5,function(lo)return lo end)
    mon.species=string.format('SPECIES_%03d',index)
    mon.hp=3;mon.moves[1].pp=2;mon.nickname='SPECIES_155'
    return mon
  end
  local s={party={legacy(155)},boxes={{[20]=legacy(133)}},
    daycare={mon=legacy(25),breed={{mon=legacy(132)},{mon=legacy(29)},egg=legacy(175)}},
    player={name='TEST',id=17,map='FIX_TOWN',x=1,y=1},flags={},
    hallOfFame={{{species='SPECIES_155',level=5}}},
    g2SecondMonBackup={legacy(152)},g2BugContest={party={legacy(158)}},
    g2PokeonlySpecies='SPECIES_155',g2Roam={RAIKOU={speciesId='SPECIES_243',hp=7}},
    pokedex={seen={SPECIES_155=true,CYNDAQUIL=false},owned={SPECIES_133=true}}}
  local encoded=Save.encode(s);local restored=assert(Save.decode(encoded))
  local report=Save.validate(restored,d)
  T.eq(#report.lostMons,0);T.eq(#report.lostItems,0)
  T.eq(restored.party[1].species,'CYNDAQUIL');T.eq(restored.boxes[1][20].species,'EEVEE')
  T.eq(restored.daycare.mon.species,'PIKACHU')
  T.eq(restored.daycare.breed[1].mon.species,'DITTO')
  T.eq(restored.daycare.breed[2].mon.species,'NIDORAN_F')
  T.eq(restored.daycare.breed.egg.species,'TOGEPI')
  T.eq(restored.hallOfFame[1][1].species,'CYNDAQUIL')
  T.eq(restored.g2SecondMonBackup[1].species,'CHIKORITA')
  T.eq(restored.g2BugContest.party[1].species,'TOTODILE')
  T.eq(restored.g2Roam.RAIKOU.speciesId,'RAIKOU');T.eq(restored.g2Roam.RAIKOU.hp,7)
  T.eq(restored.g2PokeonlySpecies,'CYNDAQUIL')
  T.eq(restored.pokedex.seen.CYNDAQUIL,true);T.eq(restored.pokedex.seen.SPECIES_155,nil)
  T.eq(restored.pokedex.owned.EEVEE,true)
  T.eq(restored.party[1].hp,3);T.eq(restored.party[1].moves[1].pp,2)
  T.eq(restored.party[1].nickname,'SPECIES_155','nicknames are literal user data')
  T.eq(s.party[1].species,'SPECIES_155','decode/validate never mutates source save')
  local cw=require('src.save_convert.Gen2Save').crosswalks(d)
  T.eq(cw.pokemonByIndex[155],'CYNDAQUIL');T.eq(cw.pokemonIndex.CYNDAQUIL,155)
  -- Legacy removal cannot leave the old alias serving a cached definition.
  r=Registry.new('pokemon',require('src.mods.Schemas').REGISTRIES.pokemon);r.base=function()return p end
  r:remove('SPECIES_155','remove');Names.write(p,r)
  T.eq(p.CYNDAQUIL,nil);T.eq(p.SPECIES_155,nil)
  d:seedDefaults();T.eq(p.CYNDAQUIL,nil)
end
V.set('crystal')
for _,kind in ipairs{'incomplete','different-index','authored','collision','alias-collision','lookup'}do
  local d=F.new();local p=d.pokemon;local mt
  if kind=='incomplete'then p.SPECIES_251=nil
  elseif kind=='different-index'then p.SPECIES_155.dex=1
  elseif kind=='authored'then p.CYNDAQUIL={id='CYNDAQUIL'}
  elseif kind=='collision'then d.extra={SPECIES_155=1,CYNDAQUIL=2}
  elseif kind=='alias-collision'then d.extra={SPECIES_083=1,FARFETCH_D=2}
  else mt={__index=function()return 'authored'end};setmetatable(p,mt)end
  T.eq(Names.canonicalize(d),false,kind..' is rejected atomically')
  T.eq(p.SPECIES_155.id,'SPECIES_155');T.eq(d.constants.speciesOrder[155],'SPECIES_155')
  T.eq(getmetatable(p),mt)
end
for _,edition in ipairs{'red','blue','yellow','firered','emerald','prism','polishedcrystal'}do
  V.set(edition);local d=F.new()
  T.eq(Names.canonicalize(d),false,edition..' own address space retained')
  T.eq(d.pokemon.SPECIES_155.id,'SPECIES_155')
end
V.set(old)
T.finish('native GSC canonical runtime graph, registry edits and legacy save round trips')
