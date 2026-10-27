-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- A visible starter portrait must retain its script beyond watchdog expiry.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local World=require('src.world.OverworldController')
local Stack=require('src.core.StateStack')
local Runner=require('src.script.ScriptRunner')
local Commands=require('src.script.Commands')
require('src.script.Gen2Commands')
local PicBox=require('src.ui.PicBox')
local game={data={},save={flags={}},input={wasPressed=function()return false end}}
game.stack=setmetatable({}, {__index=Stack});game.stack:init()
local slot,previous
for i=1,100 do local name,value=debug.getupvalue(World.handleInput,i)
 if not name then break end
 if name=='Game'then slot=i;previous=value;debug.setupvalue(World.handleInput,i,game);break end
end
assert(slot,'native field game owner')
local world=setmetatable({map={id='ELMS_LAB'},scriptMoves={},player={}}, {__index=World})
game.overworld=world
world.runner=Runner.new(game,world)
-- Use the real portrait and script owners; replace only rendering/field IO.
world.update=function(self)self:watchStuckScript();self.runner:update()end
local pic=setmetatable({game=game,overworld=world,passive=true},PicBox)
world.pokepicBox=pic
game.stack:push(pic)
local resumed=0
local old=Commands.qa_portrait_followup
Commands.qa_portrait_followup=function()resumed=resumed+1 end
world.runner:run({{'g2_close_pokepic'},{'qa_portrait_followup'}})
world.runner:update()
T.eq(world.runner:isRunning(),true,'actual closepokepic yields until user acknowledgment')
T.eq(pic.passive,false,'actual closepokepic arms the portrait')
for _=1,1800 do game.stack:update(1/60)end
T.eq(world.runner:isRunning(),true,'thirty seconds inspecting a visible portrait retains its real runner')
T.eq(world.stuckFrames,nil,'foreground wait does not accumulate stranded-script frames')
T.eq(resumed,0,'foreground wait does not skip remaining story rows')
game.input.wasPressed=function(_,button)return button=='a'end
game.stack:update(1/60)
game.input.wasPressed=function()return false end
world.runner:update()
T.eq(game.stack:top(),nil,'A removes the actual portrait')
T.eq(resumed,1,'A resumes remaining native story exactly once')
T.eq(world.runner:isRunning(),false,'completed portrait script releases its input gate')
-- The watchdog still detects a genuinely stranded native world script.
world.runner.co=coroutine.create(function()coroutine.yield()end)
coroutine.resume(world.runner.co)
world.runner.ctx={};world.runner.waitingFrames=nil;world.runner.waitingCheck=nil
game.stack.worldState=world
for _=1,720 do world:watchStuckScript()end
T.eq(world.runner:isRunning(),false,'persistent bare world still retires a truly stranded runner')
-- Legacy stacks with the world itself on top are not a foreground wait.
world.runner.co=coroutine.create(function()coroutine.yield()end)
coroutine.resume(world.runner.co)
game.stack.states[1]=world -- model the legacy stack without running map-entry IO
for _=1,720 do world:watchStuckScript()end
T.eq(world.runner:isRunning(),false,'legacy world-on-stack watchdog remains active')
Commands.qa_portrait_followup=old
debug.setupvalue(World.handleInput,slot,previous)
T.finish('native portrait foreground waits and stranded-script recovery')
