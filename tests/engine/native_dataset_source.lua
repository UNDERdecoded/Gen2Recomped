-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Dataset=require('src.core.game3.dataset')
local Fs=require('src.import.CacheFs')
local Version=require('src.core.GameVersion')
local Stream=require('src.core.game3.asset_stream')
local root,fs=Fs.root,Fs.dataFs
local seen,files={},{}
Fs.root=function()return nil end
Fs.dataFs=function()return{
 read=function(name)seen[#seen+1]=name;return files[name]end,
 getInfo=function(name)seen[#seen+1]=name;return files[name]and{type='file'}or nil end,
}end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Stream.shutdown();require('src.core.Game3').release()
 local f=require('tools.session-runtime.fixture').new(edition)
 local prefix=Version.cachePrefix();local rel='data/generated/gba/native/test/palettes.bin'
 files[prefix..rel]='exact-raw-'..edition..'\0\255';files[rel]='wrong-unversioned-artifact'
 local cache=Dataset.cache();T.eq(Dataset.cache(),cache,'same native dataset retains its reader identity')
 T.eq(cache:read(rel),files[prefix..rel]);T.eq(cache:exists(rel),true)
 T.eq(seen[#seen],prefix..rel,'reader uses the current cartridge prefix without changing CacheFs.prefix')
 T.eq(cache:read('data/generated/missing.bin'),nil);T.eq(cache:exists('data/generated/missing.bin'),false)
 local count=#seen
 for _,bad in ipairs{'../save.lua','saves/player.sav','data/generated/../save.lua','/data/generated/x','data/generated/C:\\save','data/generated//x'}do
  T.eq(cache:read(bad),nil);T.eq(cache:exists(bad),false)
 end
 T.eq(#seen,count,'non-artifact paths never reach a filesystem')
 local data=f.game.data;f.game.data={};Stream.poll()
 T.eq(cache:read(rel),nil,'replacement import retires the old reader');T.eq(cache:exists(rel),false)
 f.game.data=data;T.neq(Dataset.cache(),cache,'retired reader cannot revive')
 local nextCache=Dataset.cache();Stream.shutdown();T.eq(nextCache:read(rel),nil,'shutdown revokes retained readers')
 files={}
end
Fs.root,Fs.dataFs=root,fs
T.finish('native imported artifact readers, edition isolation and session revocation')
