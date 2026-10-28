-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local X=require('src.import.RomExtractorGen3')
local Profiles=require('src.import.Gen3BallSendOutProfile')
local Copy=require('src.mods.Merge').deepCopy
local Writer=require('src.import.ImageWriter');local blank=Writer.blank
-- Operand-only stage qualification: image composition is a separate GPU/art test.
Writer.blank=function()error('operand-only fixture has no image writer')end
X.applyAddressMap(nil)
local emerald=Copy(X.BALL_ANIM.SEND)
local hashes={firered='41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc',leafgreen='574fa542ffebb14be69902d1d36f1ec0a4afd71e'}
local function operandFixture(B)
 local u16,u32,ptr,blobs={},{},{},{}
 local function zeros(n)local out={};for i=1,n do out[i]=0 end;return out end
 for i=0,B.COUNT-1 do
  local gfx,pal=0x3000000+i*0x1000,0x4000000+i*0x1000
  ptr[B.SHEETS+i*B.STRIDE],ptr[B.PALETTES+i*B.STRIDE]=gfx,pal
  u16[B.SHEETS+i*B.STRIDE+4]=B.SHEET_BYTES
  u16[B.SHEETS+i*B.STRIDE+6],u16[B.PALETTES+i*B.STRIDE+4]=i,i
  blobs[gfx],blobs[pal]=zeros(B.SHEET_BYTES),zeros(B.PALETTE_BYTES)
 end
 blobs[B.OPEN_FRAME]=zeros(B.OPEN_BYTES)
 blobs[B.PARTICLES],blobs[B.PARTICLE_PALETTE]=zeros(B.PARTICLE_BYTES),zeros(B.PALETTE_BYTES)
 local S=B.SEND;local fr=S.AT_DEMO_X~=nil
 u16[S.AT_HAND_X]=(S.MOV_HAND_X or S.MOV_R0)+(fr and 48 or 24)
 u16[S.AT_HAND_Y]=(S.MOV_HAND_Y or S.MOV_R0)+(fr and 70 or 68)
 if fr then u16[S.AT_DEMO_X]=S.MOV_HAND_X+32;u16[S.AT_DEMO_Y]=S.MOV_HAND_Y+64 end
 u16[S.AT_FRAMES]=S.MOV_R0+25;u16[S.AT_TARGET_DY]=S.ADD_R0+24
 u16[S.AT_FOE_DY]=S.ADD_R0+24;u16[S.AT_FOE_WAIT]=S.CMP_R0+15;u16[S.AT_FADE]=S.MOV_R2+14
 for _,pair in ipairs{{S.AT_ARC,65506},{S.AT_RISE,4294967008}}do
  u16[pair[1]]=0x4801;local at=pair[1]+4;u32[at-at%4+4]=pair[2]
 end
 return {u16=function(_,at)return u16[at]or 0 end,u32=function(_,at)return u32[at]or 0 end,
  u8=function()return 0 end,pointer=function(_,at)return ptr[at]end,
  lz77=function(_,at)return blobs[at]end},u16
end
local function extract(B,mutation)
 local rom,words=operandFixture(B)
 if mutation then mutation(words,B.SEND)end
 local out
 local x=setmetatable({rom=rom,_constants={},beginStage=function()end,write=function(_,name,value)
  T.eq(name,'constants');out=value
 end},X)
 x:extractBallAnims(B);return out and out.gen3BallAnim
end
for _,edition in ipairs{'firered','leafgreen','emerald'}do
 X.applyAddressMap(nil)
 if edition~='emerald'then
  local profile=Profiles.forSha1(hashes[edition])
  T.check(profile~=nil,'FR/LG must supply its own verified send-out instruction sites')
  if profile then X.applyStageOverrides({BALL_ANIM={SEND=profile}})end
 end
 local B=Copy(X.BALL_ANIM);local record=extract(B);local s=record.timing.sendOut
 T.check(s~=nil);assert(s)
 T.eq(s.frames,25);T.eq(s.arc,-30);T.eq(s.foeWait,16);T.eq(s.fadeFrames,14);T.eq(s.riseStep,-288)
 T.eq(s.targetOffsetY,24);T.eq(s.foeOffsetY,24)
 if edition=='emerald'then T.eq(s.from.x,24);T.eq(s.from.y,68);T.eq(s.fromPokedude,nil)
 else
  T.eq(s.from.x,48);T.eq(s.from.y,70)
  T.eq(s.fromPokedude and s.fromPokedude.x,32);T.eq(s.fromPokedude and s.fromPokedude.y,64)
 end
 if edition~='emerald'then
  local Probe=dofile('tests/native_action_plan/turn.lua')
  local Native=require('src.battle.Gen3Battle');local centre=Native.battlerCentre
  -- The fixture supplies the image-derived centre; this checks native factory
  -- hand selection and its existing clock/queue, not rendered geometry.
  Native.battlerCentre=function()return 72,80 end
  for _,demo in ipairs{false,true}do
   local f,b=Probe.open(edition);b:syncSides();b.data.constants.gen3BallAnim=record
   b.pokedudeDemo=demo or nil;b.showPlayerBack=false;b.queue={}
   local accepted=b:gen3SendOut(b.player);T.eq(accepted,true)
   if accepted then
    T.eq(b.gen3Ball.from.x,demo and 32 or 48);T.eq(b.gen3Ball.from.y,demo and 64 or 70)
    T.eq(b.gen3Ball.phase,'throw');T.eq(#b.queue,1,'native send-out owns one queue wait')
    T.eq(b.queue[1].wait,b.gen3Ball:estimate(),'the existing native clock owns the queue duration')
   end
   b.pokedudeDemo=nil -- This fixture exercises hand selection, not demo-party restoration.
   Probe.close(f)
  end
  Native.battlerCentre=centre
 end
 for _,key in ipairs{'AT_HAND_X','AT_HAND_Y','AT_FRAMES','AT_TARGET_DY','AT_FOE_DY','AT_FOE_WAIT','AT_FADE','AT_ARC','AT_RISE'}do
  local bad=extract(B,function(words,sites)words[sites[key]]=0 end)
  T.eq(bad.timing.sendOut,nil,'changed native instruction refuses '..key)
 end
 local mismatch=extract(B,function(words,sites)words[sites.AT_FOE_DY]=sites.ADD_R0+25 end)
 T.eq(mismatch.timing.sendOut,nil,'inconsistent native target offsets refuse send-out')
 if edition~='emerald'then
  for _,key in ipairs{'AT_DEMO_X','AT_DEMO_Y'}do
   T.eq(extract(B,function(words,sites)words[sites[key]]=0 end).timing.sendOut,nil,'malformed tutorial hand cannot be fabricated')
  end
 end
end
local detached=Profiles.forSha1(hashes.firered);detached.AT_HAND_X=0
T.neq(Profiles.forSha1(hashes.leafgreen).AT_HAND_X,0,'a caller cannot mutate a shared cartridge profile')
T.eq(Profiles.forSha1('unverified'),nil,'unknown cartridges do not borrow FR/LG instruction sites')
X.applyAddressMap(nil);T.same(X.BALL_ANIM.SEND,emerald,'switching back restores Emerald instruction sites')
Writer.blank=blank
local Importer=require('src.import.RomImporter')
-- Exercise the marker decision already owned by the importer, including older
-- native owners which do not expose the fork's cacheContract query.
local marker
if Importer.cacheContract then marker=function(ed)return Importer.cacheContract(ed).marker end
else
 local seen={}
 local function find(fn,depth)
  if seen[fn]or depth>3 then return end;seen[fn]=true
  for i=1,100 do
   local name,value=debug.getupvalue(fn,i);if not name then break end
   if name=='markerFor'then return value end
   if type(value)=='function'then local found=find(value,depth+1);if found then return found end end
  end
 end
 for _,fn in pairs(Importer)do if type(fn)=='function'then marker=find(fn,0);if marker then break end end end
 assert(marker,'native importer marker owner unavailable')
end
for _,edition in ipairs{'firered','leafgreen'}do
 T.check(marker(edition):find('frlg%-ball%-sendout%-v1:')~=nil,'older incomplete FR/LG caches must rebuild generated timing')
end
for _,edition in ipairs{'red','crystal','emerald','ruby','sapphire'}do
 T.eq(marker(edition):find('frlg%-ball%-sendout%-v1:'),nil,'unaffected edition keeps its existing cache marker')
end
T.finish('Native ball send-out operand profiles, tutorial hand, fail-closed reads, restoration and edition-scoped cache upgrade')
