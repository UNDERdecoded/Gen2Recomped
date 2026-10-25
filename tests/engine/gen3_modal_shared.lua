package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local prior=Version.get()
local Game=require('src.core.Game');local Native=require('src.core.StateStack')
local before={stack=Game.stack,save=Game.save,session=Game.sessionStartedAt,ready=Game.nativeStackReady}
local consumer=dofile('tests/gba_modal/consumer.lua')
for _,version in ipairs{'firered','emerald'}do
 Version.set(version);Game.stack=setmetatable({},{__index=Native});Game.stack:init()
 Game.save={};Game.sessionStartedAt=1;Game.nativeStackReady=true
 local world={isOverworld=true};Game.stack:push(world)
 consumer(T,require('src.ui.game3.stack'))
 T.eq(Game.stack:top(),world,'shared native consumer preserves '..version..' world')
end
Game.stack,Game.save,Game.sessionStartedAt,Game.nativeStackReady=before.stack,before.save,before.session,before.ready
Version.set(prior)
T.finish('shared native GBA modal consumer')
