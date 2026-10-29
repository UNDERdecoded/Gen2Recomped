-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
T.eq(_G.love,nil,'GSC formula needs no rendering runtime')
for _,name in ipairs{'src.battle.BattleState','src.pokemon.Sprites','src.render.Assets'}do
  package.preload[name]=function()error('stat calculation imported presentation: '..name)end
end
local Stats=require('src.pokemon.Stats')
local Mon=require('src.compat.gen2.Mon')
T.check(type(Mon.stats)=='function'and type(Mon.hpDV)=='function','actual source formula entry points exist')
if type(Mon.stats)~='function'or type(Mon.hpDV)~='function' then T.finish('source stat formula APIs are absent')end
-- Independent integer search for the cartridge ceiling-square-root loop.
local function bonus(n)
  local root=0
  while root<255 and root*root<math.max(0,n or 0)do root=root+1 end
  return math.floor(root/4)
end
local function value(base,dv,level,effort,hp)
  return math.floor(((base or 1)*2+(dv or 0)*2+bonus(effort))*level/100)+(hp and level+10 or 5)
end
local source={hp=39,attack=52,defense=43,speed=65,specialAttack=60,specialDefense=50}
local native={hp=39,attack=52,defense=43,speed=65,special=60,spatk=60,spdef=50}
for packed=0,65535 do
  local a=math.floor(packed/4096)%16
  local d=math.floor(packed/256)%16
  local v=math.floor(packed/16)%16
  local sp=packed%16
  local genes={attack=a,defense=d,speed=v,special=sp,hp=99}
  local derived=a%2*8+d%2*4+v%2*2+sp%2
  T.eq(Mon.hpDV(genes),derived,'all four-byte gene combinations derive HP from low bits')
  if packed%257==0 then
    for _,level in ipairs{1,5,50,100}do
      for _,effort in ipairs{0,1,15,16,17,255,256,65535,-1}do
        local investment={hp=effort,attack=effort,defense=effort,speed=effort,special=effort}
        local calculated=Mon.stats(source,genes,level,investment)
        local host=Stats.calc({baseStats=native},level,genes,investment)
        local expected={hp=value(39,derived,level,effort,true),attack=value(52,a,level,effort),
          defense=value(43,d,level,effort),speed=value(65,v,level,effort),
          specialAttack=value(60,sp,level,effort),specialDefense=value(50,sp,level,effort)}
        for key,n in pairs(expected)do
          T.eq(calculated[key],n,'source formula agrees with independent cartridge integer arithmetic')
          T.eq(host[key],n,'actual native GSC formula uses the same cartridge arithmetic')
        end
        T.eq(genes.hp,99,'stat calculation never edits caller genes')
      end
    end
  end
end
T.eq(Mon.hpDV({specialAttack=1}),0,'source HP helper reads the shared Special gene only')
local fallback=Mon.stats(source,{specialAttack=3,specialDefense=10,hp=99},25,
  {specialAttack=65535,specialDefense=256})
T.eq(fallback.specialAttack,value(60,3,25,65535),'legacy special-attack investment fallback')
T.eq(fallback.specialDefense,value(50,3,25,256),'legacy special-defense investment fallback')
T.eq(fallback.hp,value(39,1,25,0,true),'legacy Special DV also supplies derived HP low bit')
local shared=Mon.stats(source,{special=0,specialAttack=15},25,
  {special=0,specialAttack=65535,specialDefense=65535})
T.eq(shared.specialAttack,value(60,0,25,0),'stored zero shared DV/investment wins over fallbacks')
local defaults=Mon.stats(nil,nil,1)
T.eq(defaults.hp,11,'source missing-base HP uses base one')
T.eq(defaults.specialAttack,5,'source missing-base non-HP uses base one')
local g1=Stats.calc({baseStats={hp=39,attack=52,defense=43,speed=65,special=60}},25,
  {hp=9,attack=1,defense=2,speed=3,special=4},{})
T.eq(g1.hp,value(39,9,25,0,true),'Gen1 existing stored-HP formula is unchanged')
T.eq(getmetatable(g1),nil,'Gen1 stat blocks remain plain')
local gba={baseStats=native,evYield={hp=1}}
local ivs={hp=31,attack=30,defense=29,speed=28,spatk=27,spdef=26}
local g3=Stats.calc(gba,25,ivs,{})
T.eq(g3.hp,math.floor((2*39+31)*25/100)+35,'Gen3 retains its independent six-IV formula')
T.eq(getmetatable(g3),nil,'Gen3 stat blocks remain plain')
local weak=setmetatable({}, {__mode='v'})
do
  local mon={stats={hp=3}};local battler={mon=mon,curStats=mon.stats}
  mon.ownedRuntime=battler
  Stats.trackBattler(battler);weak[1],weak[2]=mon,battler
end
for _=1,4 do collectgarbage('collect')end
T.eq(weak[1],nil,'stat-owner tracking cannot retain an abandoned cyclic Pokemon')
T.eq(weak[2],nil,'stat-owner tracking cannot retain a finished native battler')
T.eq(_G.love,nil,'source stat APIs do not install a fake runtime')
T.finish('source and native GSC stat formula, all genes, legacy fallbacks and generation guards without LOVE')
