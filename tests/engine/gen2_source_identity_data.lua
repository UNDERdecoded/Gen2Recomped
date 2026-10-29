-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
T.eq(_G.love,nil,'source gene predicates do not require LOVE')
for _,name in ipairs{'src.battle.BattleState','src.pokemon.Sprites','src.render.Assets'}do
 package.preload[name]=function()error('identity predicate imported presentation: '..name)end
end
local Mon=require('src.compat.gen2.Mon')
local ready=true
for _,name in ipairs{'vanillaShiny','isShiny','vanillaGender','gender','randomDVs'}do
 T.eq(type(Mon[name]),'function','source identity method '..name)
 ready=ready and type(Mon[name])=='function'
end
local bright={attack=2,defense=10,speed=10,special=10}
if not ready then
 if type(Mon.isShiny)=='function' then
  local ok,result=pcall(Mon.isShiny,bright)
  T.check(ok and result==true,'source isShiny reads gene input, not an unrelated Pokemon shape')
 end
 T.finish('source gene identity APIs absent or inherited with wrong signature')
end
local random=math.random
math.random=function()error('identity query must not roll RNG')end
for packed=0,65535 do
 local a=math.floor(packed/4096)%16
 local d=math.floor(packed/256)%16
 local s=math.floor(packed/16)%16
 local c=packed%16
 local genes={attack=a,defense=d,speed=s,special=c}
 local expected=d==10 and s==10 and c==10 and (a%4==2 or a%4==3)
 T.eq(Mon.vanillaShiny(genes),expected,'all legal source DV vectors use cartridge shiny predicate')
 T.eq(Mon.isShiny(genes),expected,'unhooked source signature reads actual genes')
end
for ratio=0,255 do
 for attack=0,15 do for speed=0,15 do
  local expected=ratio==255 and 'unknown' or ratio==254 and 'female'
   or ratio==0 and 'male' or (attack*16+speed<=ratio and 'female' or 'male')
  local def,dvs={genderRatio=ratio},{attack=attack,speed=speed}
  T.eq(Mon.vanillaGender(def,dvs),expected,'all ratio/gene thresholds match cartridge comparison')
  T.eq(Mon.gender(def,dvs),expected,'unhooked source gender uses definition-first signature')
 end end
end
T.eq(Mon.vanillaShiny(nil),false)
T.eq(Mon.vanillaShiny({}),false)
T.eq(Mon.vanillaGender(nil,bright),'unknown')
T.eq(Mon.gender({genderRatio=false},bright),'unknown','source absent ratio semantics include false')
for _,attack in ipairs{18,-2,'2'}do
 local genes={attack=attack,defense=10,speed=10,special=10}
 T.eq(Mon.vanillaShiny(genes),true,'public source predicate preserves its modulo behavior')
end
math.random=random
local calls=0
math.random=function(lo,hi)
 calls=calls+1;T.eq(lo,0);T.eq(hi,15);return calls-1
end
local first=Mon.randomDVs()
math.random=random
T.eq(calls,4,'source randomDVs draws exactly four genes without LOVE')
T.same(first,{attack=0,defense=1,speed=2,special=3},'source gene order and absent derived HP match source birth contract')
T.eq(_G.love,nil,'identity queries do not install a rendering runtime')
T.finish('source GSC gene signatures, exhaustive shiny/gender predicates and RNG ownership without LOVE')
