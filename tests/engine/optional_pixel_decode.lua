-- Optional pixel input failure must reach the caller's fallback decision.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Assets=require('src.render.Assets')
local originalImage=love.image
local imageData=love.image and love.image.newImageData
love.image=love.image or {}
local optional='mods/pixel_probe/optional.png'
local corrupt='mods/pixel_probe/corrupt.png'
local native='assets/generated/sprites/not-imported.png'
local present=false
local calls={}
local imageCalls={}
local newImage=love.graphics.newImage
local texture={getDimensions=function()return 64,64 end}
local recoveryTexture={getDimensions=function()return 16,16 end}
local pixel={getDimensions=function()return 64,64 end}
local placeholder={getDimensions=function()return 16,16 end}
-- The file decoder is the external boundary; real Assets resolution/caching,
-- SDK module lookup and the consumer's pcall/fallback all remain active.
love.image.newImageData=function(path,...)
  calls[path]=(calls[path]or 0)+1
  if path==optional then if present then return pixel end;error('optional input absent')end
  if path==corrupt then error('invalid PNG header')end
  if path==native then error('native generated sheet absent')end
  if path=='assets/generated/sprites/placeholder_sprite.png'then return placeholder end
  assert(imageData,'unexpected decoder input: '..tostring(path))
  return imageData(path,...)
end
love.graphics.newImage=function(path,...)
  imageCalls[path]=(imageCalls[path]or 0)+1
  if path==optional then if present then return texture end;error('optional texture absent')end
  if path==corrupt then error('invalid texture PNG')end
  if path==native then error('native generated texture absent')end
  if path=='assets/generated/sprites/placeholder_sprite.png'then return recoveryTexture end
  return newImage(path,...)
end
local run=T.sdk.loadMods({'mods/pixel_probe'},{data=T.fixtures.fresh(),fs=T.sdk.memfs({
 ['mods/pixel_probe/manifest.json']=[[{"id":"pixel_probe","name":"Pixel probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
 ['mods/pixel_probe/main.lua']=[[
   local mod=...
   local Assets=require('src.render.Assets')
   function mod.exports.chooseTexture(path)
     local ok,image=pcall(Assets.image,path)
     if not ok then return {owner='native',failure=tostring(image)}end
     return {owner='optional',image=image}
   end
   function mod.exports.choose(path)
     local ok,pixels=pcall(Assets.imageData,path)
     if not ok then return {owner='native',failure=tostring(pixels)}end
     return {owner='optional',pixels=pixels,width=select(1,pixels:getDimensions())}
   end
 ]],
})})
T.eq(#run.errors,0,'real SDK optional pixel consumer loads')
local probe=assert(run.loader.exports.pixel_probe)
local result=probe.choose(optional)
T.eq(result.owner,'native','missing optional pixels select the consumer native fallback')
T.eq(result.pixels,nil,'missing optional input never advertises placeholder pixels')
T.check(result.failure and result.failure:find('optional input absent',1,true),
 'original decoder failure remains available to the consumer')
result=probe.choose(corrupt)
T.eq(result.owner,'native','corrupt optional pixels select native fallback')
T.check(result.failure and result.failure:find('invalid PNG header',1,true),
 'invalid optional PNG failure is not hidden behind a fake image')
T.eq(Assets.imageData(native),placeholder,'missing native generated sheet retains its recovery image')
local before=calls[optional]
result=probe.choose(optional)
T.eq(result.owner,'native','repeated missing optional reads still select native fallback')
T.eq(calls[optional],before+1,'failed optional reads remain retryable')
local chosen=probe.chooseTexture(optional)
T.eq(chosen.owner,'native','missing optional texture selects the native fallback')
T.eq(chosen.image,nil,'failed optional texture is never cached as a completed image')
chosen=probe.chooseTexture(corrupt)
T.eq(chosen.owner,'native','corrupt optional texture selects native fallback')
T.eq(Assets.image(native),recoveryTexture,'native generated texture keeps its recovery image')
-- Generated and optional requests may resolve to the same underlying path.
-- A cached native recovery must never make an optional request look valid.
local loader=Assets.loader
Assets.loader={overrideOrder=function()return{}end,derivedPath=function(_,rel)
  if rel=='sprites/optional-alias.png'then return optional end
end}
Assets.invalidate()
local alias='assets/generated/sprites/optional-alias.png'
T.eq(Assets.image(alias),recoveryTexture,'generated alias can recover at its native owner')
T.eq(probe.chooseTexture(optional).owner,'native','native cached recovery cannot satisfy an optional image')
present=true
result=probe.choose(optional)
T.eq(result.owner,'optional','the same newly available optional file is usable')
T.eq(result.pixels,pixel,'actual decoded pixel identity reaches the consumer')
T.eq(result.width,64,'actual optional dimensions are preserved')
before=calls[optional]
T.eq(Assets.imageData(optional),pixel,'mutable pixel reads preserve actual decoded identity')
T.eq(calls[optional],before+1,'mutable pixel reads are not shared implicitly')
T.eq(probe.chooseTexture(optional).image,texture,'a newly available texture replaces its failed optional attempt')
local textureCalls=imageCalls[optional]
T.eq(Assets.image(optional),texture,'successful optional texture identity remains cached')
T.eq(imageCalls[optional],textureCalls,'successful texture cache avoids decoding again')
T.eq(Assets.image(alias),texture,'the generated alias reads the same actual completed texture')
Assets.loader=loader;Assets.invalidate()
love.graphics.newImage=newImage
love.image.newImageData=imageData
love.image=originalImage
require('src.mods.Loader').teardown();run.release()
T.finish('optional pixel decode failure, fallback and retry through real SDK')
