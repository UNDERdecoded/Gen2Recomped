-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Pokemon=require('src.pokemon.Pokemon')
local Rolls=require('src.pokemon.IdentityRolls')
local Copy=require('src.mods.Merge').deepCopy
local previous=Version.get()
for _,edition in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 Version.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 local def=data.pokemon.FIXMON_A;def.id='FIXMON_A';def.genderRatio=127
 local loaded=T.sdk.loadMods({'mods/source_identity'},{data=data,fs=T.sdk.memfs({
  ['mods/source_identity/manifest.json']='{"id":"source_identity","name":"Source identity probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/source_identity/main.lua']=[[
   local mod=...
   local e=mod.exports
   e.source=require('src.battle.gen2.Mon');e.mode='delegate';e.calls={}
   local function hook(name)
    return mod.hooks:wrap(name,function(next,ctx)
     e.calls[name]=(e.calls[name]or 0)+1
     e.last=ctx
     if e.mode=='force' then if name=='shiny.roll'then return true else return 'female'end end
     if e.mode=='suppress' then if name=='shiny.roll'then return false else return 'male'end end
     if e.mode=='invalid' then if name=='shiny.roll'then return 0 else return 'invalid'end end
     if e.mode=='nil' then return nil end
     if e.mode=='edit' then
      ctx.dvs.attack=0
      if ctx.def then ctx.def.genderRatio=254 end
      if name=='gender.roll'then return 'invalid'end
     end
     return next(ctx)
    end)
   end
   e.stopShiny=hook('shiny.roll');e.stopGender=hook('gender.roll')
  ]],
 })})
 T.eq(#loaded.errors,0,edition..' actual source SDK imports identity APIs')
 def=data.pokemon.FIXMON_A
 local e=loaded.loader.exports.source_identity
 local Mon=e.source
 local ready=true
 for _,name in ipairs{'vanillaShiny','isShiny','vanillaGender','gender','randomDVs'}do
  T.eq(type(Mon[name]),'function','actual SDK exposes source '..name)
  ready=ready and type(Mon[name])=='function'
 end
 if ready then
  local mon=Pokemon.new(data,'FIXMON_A',12,function()error('fixed native genes rerolled')end,nil,
   {dvs={attack=15,defense=0,speed=15,special=0}})
  local nativeGenes=mon.dvs
  for _,case in ipairs{{'delegate',false,'male'},{'force',true,'female'},
    {'suppress',false,'male'},{'invalid',true,'male'},{'nil',false,'male'}}do
   e.mode=case[1]
   local before=Copy(mon)
   local calls=e.calls['shiny.roll']or 0
   T.eq(Mon.isShiny(mon.dvs,{species=mon.species,def=def,level=mon.level}),case[2],'source shiny signature/hook truthiness '..case[1])
   T.eq(e.calls['shiny.roll'],calls+1,'source gene query dispatches exactly one actual callback')
   T.eq(e.last.dvs,nativeGenes,'native-format source callback receives original gene identity')
   T.eq(e.last.def,def,'source callback receives actual definition')
   T.eq(e.last.species,mon.species);T.eq(e.last.level,12)
   T.eq(Rolls.gen2Shiny(mon,def),case[2],'actual native shiny owner shares source predicate/hook')
   calls=e.calls['gender.roll']or 0
   T.eq(Mon.gender(def,mon.dvs,{species=mon.species,level=mon.level}),case[3],'source definition-first gender signature '..case[1])
   T.eq(e.calls['gender.roll'],calls+1,'source gender dispatches exactly one callback')
   T.eq(e.last.dvs,nativeGenes);T.eq(e.last.def,def)
   T.eq(Rolls.gender(data,mon,2,mon.level),case[3],'actual native gender shares source hook/fallback')
   T.same(mon,before,'identity query preserves actual native Pokemon/stat/move data')
  end
  e.mode='force'
  local calls=Copy(e.calls)
  T.eq(Mon.vanillaShiny(mon.dvs),false,'explicit vanilla query bypasses hooked override')
  T.eq(Mon.vanillaGender(def,mon.dvs),'male','explicit vanilla gender bypasses hooked override')
  T.same(e.calls,calls,'vanilla predicates do not dispatch callbacks')
  e.mode='edit'
  T.eq(Mon.gender(def,mon.dvs), 'female','invalid result fallback observes native-format committed gene/definition edits')
  T.eq(mon.dvs,nativeGenes,'source edits retain actual native gene table')
  T.eq(mon.dvs.attack,0);T.eq(def.genderRatio,254)
  e.stopShiny();e.stopGender()
  calls=Copy(e.calls)
  Mon.isShiny(mon.dvs);Mon.gender(def,mon.dvs)
  T.same(e.calls,calls,'retired real callbacks are not dispatched')
  local random=love.math.random
  local n=0
  love.math.random=function(lo,hi)n=n+1;T.eq(lo,0);T.eq(hi,15);return n end
  local genes=Mon.randomDVs()
  love.math.random=random
  T.eq(n,4,'actual source API consumes four native LOVE draws')
  T.same(genes,{attack=1,defense=2,speed=3,special=4},'source random genes do not prematurely store derived HP')
  T.neq(genes,mon.dvs,'random gene request does not replace a party Pokemon')
 end
 loaded.release()
end
Version.set(previous)
T.finish('actual source GSC identity SDK, live native hooks, context identity, retirement and RNG ownership')
