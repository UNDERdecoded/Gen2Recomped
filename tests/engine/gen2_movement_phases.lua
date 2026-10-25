package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local oldVersion=V.get();V.set('crystal')
local W=require('src.world.OverworldController')
local Screens=require('src.ui.Screens');local oldPush=Screens.push
local Sound=require('src.core.Sound');local oldPlay=Sound.play;Sound.play=function()end
local game={input={},data={field={forcedMovement={}}},save={flags={}},stack={states={}}}
game.stack.top=function(self)return self.states[#self.states]end
local slot,oldGame
for i=1,100 do local name,value=debug.getupvalue(W.handleInput,i);if not name then break end;if name=='Game'then slot,oldGame=i,value;break end end
assert(slot);debug.setupvalue(W.handleInput,slot,game)
local down,press={},{}
function game.input:isDown(key)return down[key]or false end
function game.input:wasPressed(key)return press[key]or false end
local calls={};local function note(x)calls[#calls+1]=x end
local w=setmetatable({map={id='ROAD',def={generation=2}},player={facing='right'},entities={},runner={isRunning=function()return false end},scriptMoves={}}, {__index=W})
game.overworld=w
w.orbitalGroundFor=function()return nil end
w.dirHeld=function()return false end
w.walkDirection=function(_,d)note('rotate:'..d);return 'left'end
for _,name in ipairs({'checkGen2Whirlpool','checkHgssLadder','checkGen2CarpetExit','checkGen3ArrowWarp','checkGen4EntranceWarp','checkEdgeExit','checkLedgeHop','checkBoulderPush','checkGen3Gate','checkAcroSideJump'})do
 w[name]=function(_,dir)note(name..':'..dir);return false end
end
w.player.tryMove=function(_,dir)note('move:'..dir);return 'moved'end
w.pollInput=function(self,input)W.pollInput(self,input);note('poll:'..tostring(self.heldDir));self.heldDir='right'end
-- Cardinal key -> wrapper's world-space direction -> real native dispatch.
down.up=true;W.handleInput(w)
T.eq(calls[1],'poll:up','actual native input path calls the overridable poll')
T.eq(calls[2],'checkGen2Whirlpool:right','terrain checks consume remapped world-space intent')
T.eq(calls[#calls],'move:right','native mover consumes the same remapped intent')
T.eq(table.concat(calls,','):find('rotate:',1,true),nil,'camera intent is not rotated twice')
calls={};w.pollInput=function(self,input)W.pollInput(self,input);self.heldDir=nil end
W.handleInput(w)
T.eq(#calls,0,'suppressed Gen2 intent cannot fall back to held raw d-pad')
T.eq(w.player.turnArmed,true,'no-direction native turn rearming is retained')
-- Poll preserves the original raw-key priority and clears released keys.
w.pollInput=W.pollInput;down={up=true,down=true,left=true,right=true};w:pollInput(game.input)
T.eq(w.heldDir,'up','native priority up')
down.up=nil;w:pollInput(game.input);T.eq(w.heldDir,'down','native priority down')
down.down=nil;w:pollInput(game.input);T.eq(w.heldDir,'left','native priority left')
down={};w:pollInput(game.input);T.eq(w.heldDir,nil,'release clears old intent')
w:pollInput(nil);T.eq(w.heldDir,nil,'missing input clears old intent')
-- Other generations retain their raw-key + walkDirection path.
V.set('red');down.up=true;calls={};W.handleInput(w)
T.eq(calls[1],'rotate:up','other-generation camera direction remains native')
T.eq(calls[#calls],'move:left','other-generation mover retains its rotation result')
V.set('crystal');down={};press.start=true
Screens.push=function(_,name)game.stack.states[1]={screen=name}end
W.handleInput(w)
T.eq(game.stack:top().screen,'StartMenu','real native START branch acquires an overlay owner')
T.eq(w:busy(),true,'same-tick menu ownership blocks a post-body movement wrapper')
game.stack.states={};press={};T.eq(w:busy(),false,'closing overlay restores free-roam readiness')
game.stack.states={w};T.eq(w:busy(),false,'the world itself on a legacy stack is not an overlay owner');game.stack.states={}
w.battleActive=true;T.eq(w:busy(),true,'battle owner also blocks post-body movement');w.battleActive=nil
-- The actual extracted body retains actor/input/player/landing ordering.
local ticks={};local scripted=false
local body=setmetatable({map={id='ROAD',def={}},npcs={},ghosts={},entities={},scriptMoves={},player={cellX=1,cellY=1},runner={isRunning=function()return scripted end}}, {__index=W})
body.updateCast=function()ticks[#ticks+1]='cast'end
body.npcs={{update=function()ticks[#ticks+1]='npc'end}}
body.updateScriptMoves=function()ticks[#ticks+1]='script-moves'end
body.checkTrainerSight=function()ticks[#ticks+1]='trainer'end
body.handleInput=function()ticks[#ticks+1]='input'end
body.player.update=function()ticks[#ticks+1]='player';return true end
body.onStepComplete=function()ticks[#ticks+1]='landing'end
W.stepBody(body,false)
T.eq(table.concat(ticks,','),'cast,npc,script-moves,trainer,input,player,landing','real actor/body phase keeps native landing order')
ticks={};body.scriptMoves={{}};body.player.moving=true
body.updateScriptMoves=function()ticks[#ticks+1]='script-moves';body.scriptMoves={};body.player.moving=false end
W.stepBody(body,false)
local count=0;for _,x in ipairs(ticks)do if x=='player'then count=count+1 end end
T.eq(count,1,'scripted moving player advances once while its queue drains')
ticks={};scripted=true;W.stepBody(body,false)
T.eq(table.concat(ticks,','),'cast,npc,script-moves,player','script owner prevents input and unscripted landing dispatch')
Sound.play=oldPlay;Screens.push=oldPush;debug.setupvalue(W.handleInput,slot,oldGame);V.set(oldVersion)
T.finish('native input intent, body phases and overlay movement ownership')
