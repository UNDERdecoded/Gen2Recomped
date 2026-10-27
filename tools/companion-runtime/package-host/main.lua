-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
io.stdout:setvbuf('no')
local root=assert(os.getenv('BATTLE_SOURCE_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(error)io.stderr:write(debug.traceback(tostring(error),2)..'\n');return function()return 1 end end
function love.load()
 if love.filesystem.mountFullPath then assert(love.filesystem.mountFullPath(root,'','read',true))end
 local renderer=love.graphics.getRendererInfo()
 local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
 assert(renderer:lower():find(backend,1,true),'requested renderer was not created')
 local edition=assert(os.getenv('COMPANION_EDITION'))
 require('src.core.GameVersion').set(edition)
 local T=require('tests.modkit');local data=T.fixtures.fresh();data.constants.gen=3
 local run=T.sdk.loadMod(assert(os.getenv('COMPANION_MOD')),{data=data})
 for _,error in ipairs(run.errors)do print(error)end
 assert(#run.errors==0,'unchanged companion package failed initialization')
 local record=assert(run.mod,'selected package was not loaded')
 local exports=assert(run.loader.exports[record.manifest.id],'selected package has no exports')
 assert(exports.active and exports.rendererInstalled,'companion renderer is not active')
 local report={passed=true,backend=backend,renderer=renderer,edition=edition,
  modId=record.manifest.id,modVersion=record.manifest.version,initializationOnly=true,
  playerProfilesUsed=false,gameplayProven=false}
 require('src.mods.Loader').teardown();run.release()
 local file=assert(io.open(assert(os.getenv('BATTLE_SOURCE_REPORT')),'w'))
 file:write(require('src.link.Json').encode(report));file:close();love.event.quit(0)
end
