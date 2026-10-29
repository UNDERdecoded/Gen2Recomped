-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local P=require('src.pokemon.Pokemon')
local Stats=require('src.pokemon.Stats')
local Save=require('src.core.SaveData')
local Copy=require('src.mods.Merge').deepCopy
local F=require('tests.gsc_species_fixture')
require('src.script.Gen2Commands')
local function genes(a,d,s,c)return {attack=a,defense=d,speed=s,special=c}end
local function noRoll()error('fixed genes must not draw random birth DVs')end
for _,edition in ipairs{'gold','silver','crystal'}do
  V.set(edition);local data=F.new();data:seedDefaults()
  -- All ratio classes, both sides of thresholds and all shiny Attack-DV
  -- classes. Consumers must be able to read the actual saved fields directly.
  for _,ratio in ipairs{0,31,63,127,191,254,255}do
    data.pokemon.CYNDAQUIL.genderRatio=ratio
    for attack=0,15 do for _,speed in ipairs{0,10,15}do
      local dvs=genes(attack,10,speed,10);local before=Copy(dvs)
      local mon=P.new(data,'CYNDAQUIL',5,noRoll,nil,{dvs=dvs})
      local expected=ratio==255 and 'unknown' or ratio==0 and 'male'
        or ratio==254 and 'female' or (attack*16+speed<=ratio and 'female' or 'male')
      T.eq(mon.gender,expected,'native public birth gender '..edition..'/'..ratio)
      T.eq(mon.shiny,Stats.isShiny(dvs),'native public birth shiny')
      T.same(dvs,before,'constructor never edits caller genes')
      T.check(mon.dvs~=dvs,'native Pokemon owns its gene table')
      T.eq(mon.dvs.hp,attack%2*8+speed%2*2,'HP DV derived from final genes')
    end end
  end
  data.pokemon.CYNDAQUIL.genderRatio=127
  local draws=0
  local born=P.new(data,'CYNDAQUIL',5,function(lo,hi)draws=draws+1;return lo end)
  T.eq(draws,4,'ordinary birth still draws exactly four native DVs')
  T.eq(born.gender,'female');T.eq(born.shiny,false)
  for _,bad in ipairs{-1,16,0.5,'3'}do
    local dvs=genes(0,0,0,0);dvs.attack=bad
    T.raises(function()P.new(data,'CYNDAQUIL',5,noRoll,nil,{dvs=dvs})end,'invalid native Gen2 DV')
  end
  local shiny=genes(2,10,10,10)
  local function make(dvs)return P.new(data,'CYNDAQUIL',5,noRoll,nil,{dvs=dvs or shiny})end
  -- Loading a pre-field save goes through the actual codec and validator,
  -- including sparse boxes, day care, pending eggs and held contest parties.
  local function legacy()
    local m=make();m.gender=nil;m.shiny=nil;m.hp=3;m.moves[1].pp=1
    return m
  end
  local s={party={legacy()},boxes={{[20]=legacy()}},
    daycare={mon=legacy(),breed={{mon=legacy()},{mon=legacy()},egg=legacy()}},
    g2SecondMonBackup={legacy()},g2BugContest={party={legacy()}},
    player={name='TEST',id=17,map='FIX_TOWN',x=1,y=1},flags={},
    pokedex={seen={},owned={}},hallOfFame={{{species='CYNDAQUIL',level=5}}}}
  local restored=assert(Save.decode(Save.encode(s)))
  Save.validate(restored,data)
  for _,m in ipairs{restored.party[1],restored.boxes[1][20],restored.daycare.mon,
      restored.daycare.breed[1].mon,restored.daycare.breed[2].mon,
      restored.daycare.breed.egg,restored.g2SecondMonBackup[1],restored.g2BugContest.party[1]}do
    T.eq(m.gender,'female','validated live/save Pokemon has appearance')
    T.eq(m.shiny,true);T.eq(m.hp,3);T.eq(m.moves[1].pp,1)
    T.same(m.dvs,make().dvs,'validation preserves final genes')
  end
  T.eq(s.party[1].gender,nil,'source checkpoint untouched')
  T.eq(restored.hallOfFame[1][1].gender,nil,'minimal record gets no invented genes')
  local explicit=make();explicit.gender='male';explicit.shiny=false
  P.ensureIdentity(data,explicit)
  T.eq(explicit.gender,'male');T.eq(explicit.shiny,false,'saved explicit false stays authoritative on load')
  local snapshot={dvs=Copy(explicit.dvs),stats=Copy(explicit.stats),hp=explicit.hp,exp=explicit.exp,moves=Copy(explicit.moves)}
  P.syncIdentity(data,explicit)
  T.eq(explicit.gender,'female');T.eq(explicit.shiny,true,'stat/summary refresh reads final genes')
  T.same({dvs=explicit.dvs,stats=explicit.stats,hp=explicit.hp,exp=explicit.exp,moves=explicit.moves},snapshot)
  explicit.dvs=genes(15,0,15,0);P.syncIdentity(data,explicit)
  T.eq(explicit.gender,'male');T.eq(explicit.shiny,true,'forced true remains sticky at refresh')
  local incomplete={species='CYNDAQUIL'};P.syncIdentity(data,incomplete);P.ensureIdentity(data,incomplete)
  T.same(incomplete,{species='CYNDAQUIL'},'no invented genes for incomplete records')

  -- Final trainer genes are installed before the one actual birth callback;
  -- two trainer slots never share their mutable DVs with each other or data.
  local slot={species='CYNDAQUIL',level=5,dvs=Copy(shiny)}
  data.trainers.APPEARANCE={name='TEST',parties={{slot,slot}}}
  local game={data=data,save=Save.newGame(),stack={top=function()end}}
  game.save.party={make()}
  local battle=require('src.battle.BattleState').newTrainer(game,'APPEARANCE',1)
  for _,m in ipairs(battle.enemyParty)do T.eq(m.shiny,true);T.eq(m.gender,'female')end
  battle.enemyParty[1].dvs.attack=15
  T.eq(battle.enemyParty[2].dvs.attack,2);T.eq(slot.dvs.attack,2)

  -- The cartridge's Odd Egg is a fixed-gene gift, not a random birth whose
  -- cached identity survives replacing DVs with the distribution record.
  data.field.gen2OddEggs={eggs={{species='CYNDAQUIL',level=5,dvs={0x2a,0xaa}}},probabilities={65535}}
  local oddSave={party={}}
  require('src.script.Commands').g2_give_odd_egg({game={data=data},save=oddSave})
  T.eq(oddSave.party[1].shiny,true);T.eq(oddSave.party[1].gender,'female')
  T.eq(oddSave.party[1].isEgg,true)

  -- Normal DayCare.step inherits before publishing the egg. The Ditto's
  -- inherited Defense/Special turn an otherwise non-shiny roll into shiny.
  data.pokemon.DITTO.genderRatio=255;data.pokemon.DITTO.eggGroups={'DITTO'}
  local ditto=P.new(data,'DITTO',5,noRoll,nil,{dvs=genes(0,10,0,2)})
  local parent=make(genes(15,3,15,3));ditto.otId=1;parent.otId=2
  local breed={{mon=ditto},{mon=parent},stepsToEgg=1}
  local dcSave={daycare={breed=breed},player={name='TEST',id=17},flags={}}
  local random,mathRandom=love.math.random,math.random
  local values={2,0,10,10};local i=0
  love.math.random=function()i=i+1;return assert(values[i],'extra birth roll')end
  math.random=function(lo)return lo or 0 end
  local ok,created=pcall(require('src.pokemon.DayCare').step,data,dcSave)
  love.math.random,math.random=random,mathRandom
  T.check(ok,tostring(created));T.eq(created,true,'actual day-care step creates egg')
  if breed.egg then
    T.eq(i,4,'inheritance consumes one native DV roll')
    T.eq(breed.egg.gender,'female');T.eq(breed.egg.shiny,true)
    T.eq(breed.egg.dvs.defense,10);T.eq(breed.egg.dvs.special,10)
    T.eq(breed.egg.hp,0,'native egg current HP unchanged')
    T.eq(ditto.dvs.special,2,'parent genes never mutated')
    require('src.pokemon.Gen2Breeding').hatch({data=data,save=dcSave},breed.egg)
    T.eq(breed.egg.gender,'female');T.eq(breed.egg.shiny,true)
  end
  -- A real evolution can cross a gender threshold (a modded species too).
  local evolved=make(genes(0,0,0,0));data.pokemon.QUILAVA.genderRatio=255
  require('src.pokemon.Evolution').apply(game,evolved,'QUILAVA','level')
  T.eq(evolved.gender,'unknown');T.eq(evolved.shiny,false)
  T.eq(evolved.species,'QUILAVA')
end
-- No unconditional field cache or extra random birth path for other engines.
for _,edition in ipairs{'red','firered','emerald','platinum','black'}do
  V.set(edition);local data=T.fixtures.fresh()
  local mon=P.new(data,'FIXMON_A',5,function(lo)return lo end)
  T.eq(mon.gender,nil,edition..' birth behavior unchanged without hooks')
  local before=Copy(mon);P.ensureIdentity(data,mon);P.syncIdentity(data,mon)
  T.same(mon,before,edition..' refresh remains unchanged')
end
V.set(old)
T.finish('native GSC appearance birth, fixed genes, saves, trainer, eggs and evolution')
