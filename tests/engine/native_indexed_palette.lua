-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local before=package.loaded['src.core.Game']
local Core=require('src.render.Gen3IndexedPalette')
local Pal=require('src.core.game3.battle.anim_pal')
T.eq(package.loaded['src.core.Game'],before,'palette math cannot bootstrap a game')
local native=require('src.battle.Gen3MoveAnim')
for value=0,32767,17 do
 local r,g,b=Core.rgb(value);local nr,ng,nb=native.blendColour(value)
 T.eq(Core.pack(r,g,b),value);T.check(math.abs(r/31-nr)<1e-12);T.check(math.abs(g/31-ng)<1e-12);T.check(math.abs(b/31-nb)<1e-12)
end
T.eq(Core.pack(Core.rgb(65535)),32767)
for _,c in ipairs{-1,0,.5,1,7.5,15,16,17}do
 local r,g,b=Core.blend5(3,17,31,c,29,1,4)
 T.eq(r,math.floor((3*(16-c)+29*c)/16));T.eq(g,math.floor((17*(16-c)+c)/16));T.eq(b,math.floor((31*(16-c)+4*c)/16))
end
local colours={[0]=Core.pack(31,0,0),Core.pack(0,31,0),Core.pack(0,0,31)}
local out=Pal.resolve(colours,{coeff=16,color=Core.pack(3,9,21)})
for i=0,15 do T.eq(out[i],Core.pack(3,9,21))end
T.eq(Pal.resolve(colours,{coeff=-1})[0],colours[0],'negative resolve coefficients leave the original buffer unchanged')
T.eq(Pal.resolve(colours,{gray=true})[0],Core.pack(10,10,10))
T.eq(Pal.resolve(colours,{affine={m=-1,r=1,g=1,b=1}})[0],Core.pack(0,31,31))
local sourceCompiler=love.graphics.newShader;local compiled={}
love.graphics.newShader=function(source)
 local s={source=source,uploads={}}
 function s:send(name,...)
  local values={};for i=1,select('#',...)do local v=select(i,...);values[i]={unpack(v)}end
  self.uploads[#self.uploads+1]={name=name,values=values}
 end
 function s:release()self.released=true end
 compiled[#compiled+1]=s;return s
end
local Host=require('src.mods.Runtime');Host.currentMod='palette_a'
local old={};love.graphics.setShader(old)
local source=assert(Pal.send(colours));T.eq(love.graphics.getShader(),old,'send does not bind a caller shader')
local sent=source.uploads[#source.uploads];T.eq(sent.name,'pal');T.eq(#sent.values,16)
T.eq(sent.values[1][1],1);T.eq(sent.values[1][4],0);T.eq(sent.values[2][2],1)
Pal.send(colours,{opaque0=true});T.eq(source.uploads[#source.uploads].values[1][4],1)
local n=Core.new();local a={};for i=1,16 do a[i]={.1,.2,.3,0}end
local shader=assert(n:sendNormalized(a));T.neq(shader,source,'source and native callers do not share mutable uniforms')
T.eq(shader.uploads[1].values[1][4],1,'native RGB backdrop ignores caller alpha as before')
T.eq(#shader.uploads,1,'one native palette upload replaces sixteen scalar sends')
Host.currentMod='palette_b';Pal.shader();require('src.core.game3.asset_stream').cancelOwner('palette_a')
T.eq(source.released,nil,'another source owner keeps the bank alive')
require('src.core.game3.asset_stream').cancelOwner('palette_b');T.eq(source.released,true)
T.eq(shader.released,nil,'source retirement cannot release native backdrop resources')
n:release();T.eq(shader.released,true)
Host.currentMod=nil;love.graphics.newShader=sourceCompiler
T.finish('native indexed palettes, packed arithmetic and independent owned banks')
