-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Pokemon=require('src.pokemon.Pokemon')
local Effects=require('src.inventory.ItemEffects')
local Protocol=require('src.link.Protocol')
local previous=V.get()
for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 data.moves.FIX_TACKLE.pp=40
 local mon=Pokemon.new(data,'FIXMON_A',30)
 local save={party={mon}}
 mon.moves={{id='FIX_TACKLE',pp=59,ppUps=3},{id='FIX_SCRATCH',pp=0}}
 T.eq(Effects.use(data,save,'ETHER',mon,nil,1),'consumed','actual ETHER restores selected GSC slot')
 T.eq(mon.moves[1].pp,61,'actual ETHER uses capped GSC maximum')
 T.eq(Effects.use(data,save,'ETHER',mon,nil,1),'failed','full actual native slot refuses further PP restoration')
 mon.moves[1].pp=58
 T.eq(Effects.use(data,save,'MYSTERYBERRY',mon,nil,1),'consumed','actual berry restores selected native slot')
 T.eq(mon.moves[1].pp,61,'actual berry shares native GSC maximum')
 T.eq(mon.moves[2].pp,0,'single-slot restoration preserves another depleted move')
 mon.moves[1]={id='FIX_TACKLE',pp=52,maxPp=54}
 T.eq(Effects.use(data,save,'PP_UP',mon,nil,1),'consumed','actual PP UP recognizes legacy native bonus')
 T.eq(mon.moves[1].ppUps,3,'actual PP UP updates real inferred counter')
 T.eq(mon.moves[1].maxPp,61,'actual PP UP publishes real capped maximum')
 T.eq(mon.moves[1].pp,59,'actual PP UP adds capped seven-point bonus')
 T.eq(Effects.use(data,save,'PP_UP',mon,nil,1),'failed','actual native counter refuses a fourth bonus')
 data.moves.SKETCH={id='SKETCH',name='SKETCH',pp=1}
 mon.moves[1]={id='SKETCH',pp=1}
 T.eq(Effects.use(data,save,'PP_UP',mon,nil,1),'failed','actual GSC SKETCH refuses PP UP')
 T.eq(mon.moves[1].ppUps,nil,'refused item preserves real saved counter')
 mon.moves[1]={id='FIX_TACKLE',pp=61,ppUps=3,maxPp=61}
 local packet=Protocol.packMon(mon)
 packet.moves[1].pp=64
 local other=Protocol.unpackMon(data,packet)
 T.check(other~=nil,'actual native link reconstruction returns Pokemon')
 T.eq(other and other.moves[1].pp,61,'actual native link clamps to destination GSC maximum')
 T.eq(mon.moves[1].pp,61,'detached link input cannot mutate original party member')
end
for _,edition in ipairs({'red','firered','emerald','platinum','heartgold','black'})do
 V.set(edition)
 T.eq(Pokemon.maxPP({pp=40},{ppUps=3}),64,'other generations retain existing PP formula')
 T.eq(Pokemon.maxPP({pp=40},{ppUps=3},2),61,'explicit destination generation overrides current preview')
end
V.set(previous)
T.finish('actual older native GSC item, legacy PP-Up, berry and link ownership')
