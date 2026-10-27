-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
require('tools.native-atlas.cpu-gpu').install(love)
local N=require('src.core.game3.tileset_native')
local A=require('src.core.game3.tileset_anim')
local B=require('src.compat.gen1.MetatileBehavior')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.native-atlas.session-fixture').new(edition)
 local primary=f.game.data.map_tilesets.P
 local translator=B.translator(edition)
 local raw=assert(translator and translator.raw(B.POND_WATER)or B.POND_WATER)
 primary.sourceBehaviorMask=edition=='firered'or edition=='leafgreen'
 primary.sourceBehaviorMask=primary.sourceBehaviorMask and 511 or 255
 if primary.sourceAttributeBytes==4 then
  primary.sourceAttributes=string.char(raw,0,0,0)..primary.sourceAttributes:sub(5)
 else primary.attributes=string.char(raw,0)..primary.attributes:sub(3)end
 primary.animations={{tile=0,count=1,step=7,frames={string.rep('\17',32),string.rep('\34',32)}}}
 local atlas=assert(N.get(f.pair))
 local tick=atlas._model.decoder.animationTicks
 local bytes=atlas.imageData:getString()
 T.eq(A.bindPair(f.pair),true);T.eq(A._pair,f.pair)
 T.eq(A.bindPair(f.pair,{}),false,'foreign atlas cannot replace native ownership')
 local entry=assert(A._pairs[f.pair]);local bank=assert(entry.banks.water)
 T.eq(entry.atlas,atlas);T.eq(entry.rse,edition~='firered'and edition~='leafgreen')
 T.eq(bank.frames,2);T.eq(bank.period,14);T.eq(bank.ticks[1],0);T.eq(bank.ticks[2],7)
 T.eq(#bank.rgba,#bank.mids*1024*2)
 local size=#bank.mids*1024
 T.check(bank.rgba:sub(1,size)~=bank.rgba:sub(size+1),'actual imported animation pixels differ')
 T.eq(atlas.imageData:getString(),bytes,'metadata does not repaint the live atlas')
 T.eq(atlas._model.decoder.animationTicks,tick,'metadata does not rewind or advance the live decoder')
 T.eq(A._pairs[f.pair],entry,'unchanged admitted atlas reuses its observation')
 A.invalidate();T.eq(A._pair,nil);T.check(A._pairs[f.pair]~=entry)
 local retained=setmetatable({atlas},{__mode='v'})
 N.trim({},0);atlas=nil;collectgarbage('collect')
 T.eq(retained[1],nil,'metadata cannot retain a trimmed native atlas')
 T.eq(entry.atlas,nil,'retained observations do not prolong the resource owner')
 local original=package.loaded['src.core.Game'];package.loaded['src.core.Game']=nil
 T.eq(A._pairs[f.pair],nil,'a retired session cannot expose cached metadata')
 package.loaded['src.core.Game']=original
 N.release();f.views:release();require('src.core.game3.map').release()
end
T.finish('native animation metadata, exact pixels and clock isolation')
