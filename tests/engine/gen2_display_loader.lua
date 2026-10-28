-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion')
require('src.core.ModCompat').install()
local P=require('src.render.PaletteFX');local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local A={{255,255,255},{193,41,71},{31,139,83},{0,0,0}}
local R={{239,223,197},{173,137,91},{97,59,29},{19,13,7}}
local S={{217,231,243},{137,171,209},{61,103,151},{11,23,41}}
V.set('crystal')
for _,api in ipairs({1,2})do
 local files={['mods/palette-cache/manifest.json']=Json.encode({id='palette_cache',name='Registered indexed texture producer',version='1.0.0',api=api,content_format=api==3 and 'unified'or'native',entry='main.lua',affects_link=false}),
 ['mods/palette-cache/main.lua']=[[
 local mod=...;local G=require('src.render.GbcPalette');local Assets=require('src.render.Assets')
 local cache,flushes={},0
 Assets.register(function()cache={};flushes=flushes+1 end)
 mod.exports.palette=function(source)
  local key=G.mode
  if not cache[key]then
   local resolved=G.resolve(source);local rows={}
   for i=1,4 do rows[i]={resolved[i][1],resolved[i][2],resolved[i][3]}end
   cache[key]=rows
  end
  return cache[key],flushes,key
 end
 ]]}
 P.setDisplay('gbc',nil)
 local loaded=T.sdk.loadMods({'mods/palette-cache'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
 T.eq(#loaded.errors,0,'API'..api..' actual texture producer loads')
 local consumer=loaded.loader.exports.palette_cache
 local initial=consumer.palette(A);T.same(initial,A,'API'..api..' initial native row')
 P.setDisplay('custom',R)
 local first,count,mode=consumer.palette(A)
 T.same(first,R,'API'..api..' first display ramp reaches registered producer')
 T.eq(mode,'custom','API'..api..' public mode follows native owner')
 P.setCustomRamp(S)
 local second,newCount,sameMode=consumer.palette(A)
 T.eq(sameMode,mode,'API'..api..' second ramp retains public mode ID')
 T.eq(newCount,count+1,'API'..api..' native change flushes registered cache once')
 T.neq(second,first,'API'..api..' producer rebuilds baked colour rows')
 T.same(second,S,'API'..api..' second ramp replaces stale atlas colours')
 Loader.teardown();loaded.release()
end
P.setDisplay('gbc',nil)
T.finish('native Gen2 display changes invalidate loaded API 1/2 texture producers')
