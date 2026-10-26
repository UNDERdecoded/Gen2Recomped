package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local read,asset,created=require('tools.sprite-runtime.cpu-gpu').install(love)
local S=require('src.core.game3.ow_sprites');local F=require('tools.sprite-runtime.fixture')
local Runtime=require('src.mods.Runtime');local Stream=require('src.core.game3.asset_stream')
local function u16(n)return string.char(n%256,math.floor(n/256)%256)end
local function meta(id,version)
  local s='SVOW'..string.char(version or 4,0)..u16(id)..u16(16)..u16(16)..u16(1)..u16(4)
  if version==1 then return s end
  s=s..u16(65535)..string.char(2)..u16(65535)..string.char(0)
  for _=1,3 do for i=0,15 do s=s..u16(i*1057)end end
  return s..string.char(254,3)
end
local f=F.new('emerald');local count=0
local bytes={['data/generated/gba/ow/4.meta']=meta(4),['data/generated/gba/ow/4.rgba']=string.rep('\7\17\27\255',256),
 ['data/generated/gba/ow/manifest.lua']='return {count=1,sprites={[4]={}},avatars={player={{state="NORMAL",male=4,female=4}}}}'}
local cache={};function cache:read(path)count=count+1;return bytes[path]end
Runtime.currentMod='provider_a';T.eq(S.install(cache),true)
local custom=assert(S.get(4));T.eq(custom.drawOffX,-2);T.eq(custom.drawOffY,3)
T.eq(read(custom.image),bytes['data/generated/gba/ow/4.rgba'])
T.eq(S.playerGraphicsId(f.game),4)
local fallback=assert(S.get(1));T.eq(fallback.graphicsId,1,'missing explicit payload falls back to its native sheet')
local reads=count
for _=1,20 do T.eq(S.get(4),custom)end
T.eq(count,reads,'cache-backed sprites do not reread disk payloads per query')
-- Explicit malformed provider data declines rather than selecting another
-- original/native record with the same requested id.
bytes['data/generated/gba/ow/0.meta']=meta(4)
T.eq(S.get(0),nil,'a declared wrong identity cannot borrow native graphic zero')
bytes['data/generated/gba/ow/5.meta']=meta(5);bytes['data/generated/gba/ow/5.rgba']='short'
T.eq(S.get(5),nil)
local malformed=require('src.compat.gen1.SpriteCache')
T.eq(malformed.decode('SVOW',4),nil);T.eq(malformed.decode(meta(4):sub(1,118),4),nil)
T.eq(malformed.decode(meta(4,1),4).drawOffX,0)
local image=custom.image;Stream.cancelOwner('provider_a')
T.eq(custom._retired,true);T.eq(not pcall(image.getWidth,image),true)
Runtime.currentMod=nil;T.eq(S.playerGraphicsId(f.game),0,'provider rollback restores the native dataset')
local base=assert(S.get(0))
Runtime.currentMod='good';local shared=S.get(0)
Runtime.currentMod='bad';T.eq(S.get(0),shared);S.prefetch(1)
for _=1,6 do S._stream:step(0)end
T.eq(S._stream.pending[1],true)
Stream.cancelOwner('bad');T.eq(S._stream.pending[1],nil);T.eq(S.get(0),base,'another consumer retains a shared resident sprite')
Runtime.currentMod='good';Stream.cancelOwner('good');Runtime.currentMod=nil
-- Derived resources and allocations displaced from a public cache are still
-- owned by their original consumers. Rollback must not wait for global exit.
Runtime.currentMod='failed_reflection';local mirror=assert(S.getReflectionDraw(0))
local displaced=assert(S.get(2));local injectedData=love.image.newImageData(1,1)
local injected=love.graphics.newImage(injectedData);injectedData:release()
S._loaded[2]={image=injected,quads={},frameCount=1}
Stream.cancelOwner('failed_reflection')
T.eq(mirror._retired,true);T.eq(displaced._retired,true)
T.eq(S._reflectionLoaded[0],nil);T.eq(injected:getWidth(),1,'injected images remain caller-owned')
T.eq(S.get(0),base,'engine-held base survives a failed derived-resource consumer')
injected:release();S._loaded[2]=nil;Runtime.currentMod=nil
Runtime.currentMod='reflection_a';local sharedMirror=assert(S.getReflectionDraw(0))
Runtime.currentMod='reflection_b';T.eq(S.getReflectionDraw(0),sharedMirror)
Stream.cancelOwner('reflection_a');T.eq(sharedMirror._retired,nil,'a second reflection consumer retains its texture')
Stream.cancelOwner('reflection_b');T.eq(sharedMirror._retired,true);Runtime.currentMod=nil
-- A provider can prepare assets before Game exists; no session is invented.
S.release();package.loaded['src.core.Game']=nil;Runtime.currentMod='preview'
T.eq(S.install(cache),true);local before=assert(S.get(4));T.eq(package.loaded['src.core.Game'],nil)
S.release();T.eq(before._retired,true);Runtime.currentMod=nil
-- Untrusted manifest chunks have an empty environment and a bounded VM slice.
local hook,mask,interval=debug.gethook()
local bad={read=function(_,path)if path:find('manifest',1,true)then return 'while true do end'end end}
T.eq(S.install(bad),false);T.eq(debug.gethook(),hook,'manifest errors restore the previous debug hook')
S.release()
bad.read=function()return 'return {danger = os.execute("false")}'end
T.eq(S.install(bad),false);S.release()
package.loaded['src.core.Game']=f.game
-- No failed upload is allowed to retain a partial image, quad or data block.
local oldImage=love.graphics.newImage
love.graphics.newImage=function()error('intentional texture upload failure')end
T.eq(S.get(2),nil);T.check(S.errors[2]:find('intentional texture upload failure',1,true)~=nil)
love.graphics.newImage=oldImage;S.invalidate();T.check(S.get(2)~=nil)
S.release()
for _,object in ipairs(created)do T.eq(object.dead,true,'every owned allocation is released, including aborted jobs')end
T.finish('sprite cache providers and resource owners')
