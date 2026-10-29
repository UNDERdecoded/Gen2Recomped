-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Pokemon=require('src.pokemon.Pokemon')
local PP=require('src.pokemon.Gen2PP')
local Save=require('src.core.SaveData')
local oldVersion=Version.get()
local function clone(t)
 if type(t)~='table' then return t end
 local out={};for k,v in pairs(t)do out[k]=clone(v)end;return out
end
for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 Version.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 local loaded=T.sdk.loadMods({'mods/pp_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/pp_probe/manifest.json']='{"id":"pp_probe","name":"PP probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/pp_probe/main.lua']=[[
   local mod=...
   local Mon=require('src.battle.gen2.Mon')
   mod.exports.api=Mon
  ]],
 })})
 T.eq(#loaded.errors,0,'actual SDK loads unchanged source module name')
 local Mon=loaded.loader.exports.pp_probe.api
 local present=true
 for _,name in ipairs({'ppUpsOf','maxPpOf','partyMoves','restoreAllPp','repairMoves'})do
  T.eq(type(Mon[name]),'function',edition..' source PP method '..name)
  present=present and type(Mon[name])=='function'
 end
 if present then
  data.moves.FIX_TACKLE.pp=40
  for base=1,64 do
   data.moves.FIX_TACKLE.pp=base
   for ups=0,3 do
    local bonus=math.min(math.floor(base/5),7)
    local expected=base+ups*bonus
    local slot={id='FIX_TACKLE',pp=0,ppUps=ups}
    T.eq(Mon.maxPpOf(slot,data),expected,'source maximum uses capped native Gen2 arithmetic')
    T.eq(Mon.ppUpsOf(slot,data),ups,'source reads actual PP-Up counter')
    T.eq(slot.pp,0,'reading maximum cannot restore PP')
    local legacy={id='FIX_TACKLE',pp=0,maxPp=expected}
    T.eq(Mon.maxPpOf(legacy,data),expected,'legacy saved maximum follows actual native bonus')
    T.eq(legacy.ppUps,nil,'reading legacy bonus does not stamp a field')
   end
  end
  data.moves.FIX_TACKLE.pp=40
  T.eq(Mon.maxPpOf(nil,data),0,'absent source move has zero maximum')
  T.eq(Mon.ppUpsOf(nil,data),0,'absent source move has zero upgrades')
  T.eq(Mon.maxPpOf({id='UNKNOWN',maxPp='23',pp=9},data),23,'unknown source move retains authored maximum')
  T.eq(Mon.maxPpOf({id='UNKNOWN',pp='9'},data),9,'unknown source move retains authored PP fallback')
  T.eq(Mon.maxPpOf({id='FIX_TACKLE',ppUps=9},data),61,'excess PP Ups clamp to three')
  T.eq(Mon.maxPpOf({id='FIX_TACKLE',ppUps=-1},data),40,'negative PP Ups clamp to zero')
  T.eq(Mon.maxPpOf({id='FIX_TACKLE',maxPp=53},data),40,'malformed legacy maximum cannot infer a fractional bonus')
  local mon=Pokemon.new(data,'FIXMON_A',20)
  mon.moves={{id='FIX_TACKLE',pp=99,maxPp=54},{id='FIX_SCRATCH',pp=-4,ppUps=0},
   {id='UNKNOWN',pp=2,maxPp=8}}
  local moves,first=mon.moves,mon.moves[1]
  Mon.repairMoves(mon,data)
  T.eq(mon.moves,moves,'repair retains actual party list identity')
  T.eq(mon.moves[1],first,'repair retains actual slot identity')
  T.eq(first.ppUps,2,'repair migrates valid legacy bonus')
  T.eq(first.maxPp,54,'repair retains inferred maximum')
  T.eq(first.pp,54,'repair clamps overfull actual PP')
  T.eq(mon.moves[2].pp,0,'repair clamps negative PP')
  T.eq(mon.moves[3].pp,2,'repair leaves unknown definition untouched')
  T.eq(Mon.partyMoves(mon),moves,'source reads actual original party moves')
  local pre={moves={{id='FIX_SCRATCH',pp=3}}}
  mon.volatile={preTransform=pre}
  T.eq(Mon.partyMoves(mon),pre.moves,'source Transform snapshot reads original saved moves')
  mon.volatile=nil
  first.pp=0
  Mon.restoreAllPp(mon,data)
  T.eq(first.pp,54,'source restore heals actual slot')
  T.eq(mon.moves[3].pp,8,'source restore uses unknown authored fallback')
  first.pp=0;first.maxPp=999
  Pokemon.restorePP(mon,data.moves)
  T.eq(first.pp,54,'native healing shares source PP owner')
  T.eq(first.maxPp,54,'native healing publishes actual current maximum')
  local save=Save.newGame()
  local Boxes=require('src.pokemon.Boxes')
  Boxes.load(data);Boxes.ensure(save)
  local function wounded()
   local m=Pokemon.new(data,'FIXMON_A',20)
   m.moves={{id='FIX_TACKLE',pp=99,maxPp=61}}
   return m
  end
  save.party={wounded()};save.boxes[1][7]=wounded()
  save.daycare={mon=wounded(),breed={{mon=wounded()},{mon=wounded()},egg=wounded()}}
  local decoded=assert(Save.decode(Save.encode(save)))
  local party=decoded.party[1]
  Save.validate(decoded,data)
  T.eq(decoded.party[1],party,'actual save validation retains original native Pokemon')
  for _,m in ipairs({decoded.party[1],decoded.boxes[1][7],decoded.daycare.mon,
    decoded.daycare.breed[1].mon,decoded.daycare.breed[2].mon,decoded.daycare.breed.egg})do
   T.eq(m.moves[1].pp,61,'actual restore boundary repairs overfull party/box/daycare PP')
   T.eq(m.moves[1].ppUps,3,'actual restore boundary infers saved native bonus')
   T.eq(m.moves[1].maxPp,61,'actual restore boundary publishes native maximum')
  end
  local encoded=Save.encode(decoded)
  Save.validate(decoded,data)
  T.eq(Save.encode(decoded),encoded,'repeated real save validation is stable')
 end
 loaded.release()
end
for _,edition in ipairs({'red','firered','emerald','platinum','heartgold','black'})do
 Version.set(edition)
 local data=T.fixtures.fresh();data.moves.FIX_TACKLE.pp=40
 local mon={moves={{id='FIX_TACKLE',pp=0,ppUps=3}}}
 Pokemon.restorePP(mon,data.moves)
 T.eq(mon.moves[1].pp,64,'other native generations retain their PP rule')
 T.eq(mon.moves[1].maxPp,nil,'other native healing does not stamp GSC maximum')
end
Version.set(oldVersion)
T.finish('source GSC PP methods, actual SDK slots, native healing and restored saves')
