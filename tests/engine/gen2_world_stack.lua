package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Stack=require('src.core.StateStack')
local Game=require('src.core.Game')
local WorldAPI=require('src.world.WorldAPI')
local function stack()local s=setmetatable({}, {__index=Stack});s:init();return s end
local s=stack();local owner={};s:setWorldOwner(owner)
local entered,exited,updated,worldDraws,overlayDraws=0,0,0,0,0
local world={isOverworld=true,isOpaque=true,map={id='NEW_BARK_TOWN'},
 enter=function(_,id,x)entered=entered+1;T.eq(id,'NEW_BARK_TOWN','world entry map');T.eq(x,6,'world entry position')end,
 exit=function()exited=exited+1 end,update=function()updated=updated+1 end,draw=function()worldDraws=worldDraws+1 end}
owner.overworld=world;owner.stack=s
s:push(world,'NEW_BARK_TOWN',6)
T.eq(owner.world,world,'engine owns live world')
T.eq(s:top(),nil,'free roam has no overlay')
T.eq(#s.states,0,'world not stored as a menu')
T.eq(s:active(),world,'native input still has active world')
T.eq(WorldAPI.new(owner,'probe'):overworld(),world,'public world query resolves persistent world')
s:update(1/60);T.eq(updated,1,'free roam ticks once')
s:draw();T.eq(worldDraws,0,'drawing overlays never recursively draws world')
local scene=s:sceneStack();T.eq(scene.states[1],world,'native scene contains world')
T.eq(scene:visibleBase(),1,'world is scene base');T.eq(Game.ensureStack(owner),false,'empty overlay stack is healthy')
local overlay={draw=function()overlayDraws=overlayDraws+1 end,update=function()end}
s:push(overlay);T.eq(s:top(),overlay,'menu owns public stack')
s:update(1/60);T.eq(updated,1,'menu blocks world input and movement')
s:draw();T.eq(overlayDraws,1,'overlay rendered once');T.eq(worldDraws,0,'overlay rendering excludes world')
scene=s:sceneStack();T.eq(#scene.states,2,'native scene contains both layers');T.eq(scene:visibleBase(),1,'transparent menu keeps world below')
local opaque={isOpaque=true};s:push(opaque);scene=s:sceneStack()
T.eq(scene:visibleBase(),3,'opaque screen suppresses world in native draw')
s:pop();s:pop();T.eq(s:top(),nil,'closing menus returns to free roam')
s:update(1/60);T.eq(updated,2,'world resumes after menu')
scene=s:sceneStack();T.eq(#scene.states,1,'scene view sheds popped states')
s:restore(world);T.eq(entered,1,'restoring persistent world never re-enters map')
s:clearWorld();T.eq(owner.world,nil,'title/restore can release world')
T.eq(s:active(),nil,'released world cannot read input');T.eq(exited,1,'world exits exactly once')
T.eq(WorldAPI.new(owner,'probe'):overworld(),nil,'title cannot expose stale overworld')
local legacy=stack();legacy:push(world,'NEW_BARK_TOWN',6)
T.eq(legacy:top(),world,'legacy generations retain original stack contract')
T.eq(legacy:sceneStack(),legacy,'legacy scene has no adapter')
legacy:draw();T.eq(worldDraws,1,'legacy stack still draws world normally')
legacy:pop();T.eq(exited,2,'legacy world exit retained')
T.finish('native Gen2 world and overlay ownership')
