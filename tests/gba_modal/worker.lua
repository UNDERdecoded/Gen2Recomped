local engine,backend,consumer,version=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4])
package.path=engine..'/?.lua;'..engine..'/?/init.lua;'..package.path
local T=require('tests.modkit');require('src.core.GameVersion').set(version)
if backend=='gen2'then
 local Game=require('src.core.Game');Game.stack=setmetatable({},{__index=require('src.core.StateStack')});Game.stack:init();Game.save={};Game.sessionStartedAt=1
 Game.stack:push{isOverworld=true}
end
local out=assert(loadfile(consumer))()(T,require('src.ui.game3.stack'))
print('GBA_MODAL_CONTRACT '..require('src.link.Json').encode(out))
T.finish('shared native GBA modal contract')
