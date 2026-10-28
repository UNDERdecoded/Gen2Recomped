-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
require('src.core.ModCompat').install()
local P=require('src.render.PaletteFX')
local G=require('src.render.GbcPalette')
local LCD=require('src.render.GBCFX')
local V=require('src.core.GameVersion');local edition=V.get()
local Json=require('src.link.Json');local Loader=require('src.mods.Loader')
local old=love.graphics
local A={{243,241,239},{219,17,31},{19,197,83},{23,29,157}}
local B={{233,229,227},{11,61,211},{173,37,139},{3,7,13}}
local function normalized(p)
 local out={};for i=1,4 do local r=p[i];out['pal'..i-1]={r[1]/255,r[2]/255,r[3]/255}end;return out
end
local active, builds, failSend=nil,0,nil
local function fakeShader(code)
 builds=builds+1
 return {source=code,values={},send=function(self,name,value)
  if name==failSend then failSend=nil;error('uniform upload failed')end
  self.values[name]={unpack(value)}
 end}
end
love.graphics={newShader=fakeShader,setShader=function(s)active=s end,getShader=function()return active end}
T.eq(G,require('src.render.Gen2PaletteDraw'),'public spelling has typed native implementation')
T.neq(G,LCD,'palette drawing must not resolve to LCD screen effect')
T.eq(type(LCD.applyOptions),'function','native LCD options retained')
T.check(G.available(),'indexed shader is available')
local standard,keyed=G.shader(),G.keyedShader()
T.neq(standard,keyed,'keyed drawing has separate alpha policy')
T.eq(builds,2,'one lazy shader per variant')
T.check(standard.source:find('pixel.a',1,true)~=nil,'source alpha retained')
T.check(standard.source:find('* tint',1,true)~=nil,'draw colour retained')
T.check(keyed.source:find('shade < 0.5 ? 0.0',1,true)~=nil,'keyed source shade zero is transparent')
for _,variant in ipairs({'with','withRaw','keyedWith'})do
 active={external=true};local external=active
 local wanted=variant=='keyedWith'and keyed or standard
 T.check(G[variant](A,function()
  T.eq(active,wanted,variant..' shader active inside callback')
  T.same(active.values,normalized(A),variant..' all four RGB rows normalized')
  G.withRaw(B,function()T.same(active.values,normalized(B),variant..' nested different palette active')end)
  T.eq(active,wanted,variant..' nested return restores shader')
  T.same(active.values,normalized(A),variant..' nested return restores uniforms')
  local ok,err=pcall(function()G.withRaw(B,function()error('authored callback failure',0)end)end)
  T.check(not ok and err=='authored callback failure',variant..' callback failure propagated')
  T.eq(active,wanted,variant..' nested failure restores shader')
  T.same(active.values,normalized(A),variant..' nested failure restores outer palette')
 end),variant..' returns applied flag')
 T.eq(active,external,variant..' restores foreign shader')
end
G.useRaw(A);A[2][1]=111
G.withRaw(B,function()end)
local saved=normalized(A);saved.pal1[1]=219/255
T.same(active.values,saved,'restoration does not borrow caller palette rows')
A[2][1]=219
standard:send('pal1',{0,0,0});G.useRaw(A)
T.same(active.values,normalized(A),'later public call repairs externally edited uniforms')
G.useRaw(A);failSend='pal2'
local ok,err=pcall(function()G.withRaw(B,function()error('body must not run')end)end)
T.check(not ok and tostring(err):find('uniform upload failed',1,true)~=nil,'upload failure is propagated')
T.eq(active,standard,'partial upload restores previous shader')
T.same(active.values,normalized(A),'partial upload restores all previous uniforms')
local nativeMode,nativeMap=P.mode,P.shadeMap()
for _,game in ipairs({'red','gold','silver','crystal'})do
 V.set(game)
 for _,mode in ipairs(P.MODES)do
  P.setMode(mode);P.setShadeMap({[0]=3,[1]=1,[2]=2,[3]=0})
  local resolved=P.effectiveColors(A)
  local display=mode=='classic'and'classic'or((mode=='og'or mode=='og_inv')and'dmg'or'gbc')
  T.eq(G.mode,display,game..' '..mode..' public mode follows actual native resolution')
  local trueColor=true
  T.eq(not(trueColor and G.mode=='gbc'),display~='gbc',game..' '..mode..' unchanged evolution colour gate preserves true-colour art')
  T.same(G.resolve(A),P.displayColors(A),game..' '..mode..' resolves mode without consuming the register')
  G.with(A,function()T.same(active.values,normalized(resolved),game..' '..mode..' actual use shares resolved colours')end)
  G.withRaw(A,function()T.same(active.values,normalized(A),game..' '..mode..' raw use bypasses display/register state')end)
  T.same(G.color(A,2),resolved[2],game..' '..mode..' solid colour shares same native row')
 end
end
P.setShadeMap(nativeMap);P.setMode(nativeMode);V.set(edition)
for _,bad in ipairs({false,{},{{1,2,3}},{{1,2,3},{1,2,3},{1,2,3},{0/0,2,3}},{{1,2,3},{1,2,3},{1,2,3},{256,2,3}}})do
 active={foreign=true};local foreign=active;local called=false
 T.eq(G.withRaw(bad,function()called=true;T.eq(active,foreign,'invalid palette retains previous shader in body')end),false,'invalid palette declines colourization')
 T.check(called,'invalid palette still executes draw callback')
 T.eq(active,foreign,'invalid palette restores previous shader')
end
G.clear();T.eq(active,nil,'clear restores ordinary drawing')
love.graphics={}
T.eq(G.available(),false,'headless renderer declines shader availability')
local called=false;T.eq(G.with(A,function()called=true end),false,'headless with declines colourization')
T.check(called,'headless callback still executes')
love.graphics={newShader=function()error('compiler unavailable')end,setShader=function(s)active=s end,getShader=function()return active end}
T.eq(G.available(),false,'compile failure is an unavailable feature')
love.graphics.newShader=fakeShader
T.check(G.available(),'replacement compiler can recover after a failed compile')
for _,api in ipairs({1,2})do
 local files={['mods/draw/manifest.json']=Json.encode({id='draw',name='Native indexed drawing consumer',version='1.0.0',api=api,content_format=api==3 and 'unified'or'native',entry='main.lua',affects_link=false}),
 ['mods/draw/main.lua']=[[
 local mod=...;local Gbc=require('src.render.GbcPalette')
 mod.exports.draw=function(colors,body)return Gbc.with(colors,body)end
 ]]}
 local r=T.sdk.loadMods({'mods/draw'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
 T.eq(#r.errors,0,'API'..api..' unchanged indexed consumer loads')
 local ran=false
 T.check(r.loader.exports.draw.draw(A,function()ran=true end),'API'..api..' loaded consumer applies palette')
 T.check(ran,'API'..api..' loaded draw callback executes')
 Loader.teardown();r.release()
end
love.graphics=old
T.finish('native indexed palette drawing, nested uniform and shader restoration')
