package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Platinum PC exit and displays')
require('src.core.GameVersion').set('platinum')
local Commands=require('src.script.Commands');require('src.script.Gen4Commands')
local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack')
local Screens=require('src.ui.Screens');local push=Screens.push
local PC=require('src.ui.Gen4BoxMenu')
for mode=0,3 do
  local stack=setmetatable({}, {__index=Stack});stack:init()
  local game={stack=stack,data={pokemon={},constants={}},save={party={},flags={},player={}},input={wasPressed=function() return false end}}
  local ow={};local runner=Runner.new(game,ow);ow.runner=runner
  ow.update=function() runner:update() end
  stack:push(ow)
  local notifications=0
  Screens.push=function(g,id,opts)
    assert(id=='BoxMenu');local done=opts.onCancel
    opts.onCancel=function() notifications=notifications+1;done() end
    local pc=PC.new(g,opts);stack:push(pc);return pc
  end
  local reached=false
  Commands.pc_exit_verified=function() reached=true end
  runner:run({{'g4_fade',0,6,1,0},{'g4_storage',mode},{'g4_fade',1,6,1,0},{'pc_exit_verified'}})
  local closed=false
  for frame=1,40 do
    local top=stack:top()
    if top and top.opts and not closed then
      T.eq(top.opts.mode,({'deposit','withdraw','move','items'})[mode+1],'native storage mode reaches PC')
      top.partyOpen=nil
      game.input.wasPressed=function(_,key) return key=='b' end
      top:update(1/60);closed=true
      T.eq(stack:top(),ow.fadeOverlay,'closing PC retains underlying fade')
    end
    stack:update(1/60)
  end
  T.check(closed,'storage was closed through its actual exit callback')
  T.eq(notifications,1,'script receives one exit notification')
  T.check(reached,'return fade resumes script promptly, without watchdog')
  T.eq(runner:isRunning(),false,'storage script finishes')
  T.eq(ow.fadeOverlay,nil,'return fade cleans field reference')
  T.eq(stack:top(),ow,'storage returns control to field')
end
Screens.push=push;Commands.pc_exit_verified=nil
local G=require('src.render.Gen4Ground');local P=require('src.import.Gen4PropAnim')
local rom=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local arc=assert(require('src.import.NarcArchive').parse(rom:read('/arc/bm_anime_list.narc')))
local members=G.oneShotAnimations()
for _,model in ipairs({112,115,119,124,248,517}) do
  local native=P.parse(arc:get(model))
  T.check(P.deferredLoad(native),'PC/display model is deferred in native animation list')
  for _,id in ipairs(native.ids) do T.check(members[id],'interaction animation excluded from ambient clock') end
end
local record={member=32,kind='BTP0',frames=8,pattern={textures={'screen'},targets={{name='monitor',keys={{frame=0,texture=0}}}}}}
local ground=setmetatable({buildingSet={models={[125]={name='monitor',patternImages={screen='screen.png'}}}},animsByName={monitor={record}},animsByProp={[124]={record}}},{__index=G})
T.eq(ground:animationsFor(124),nil,'healing monitor steady while idle')
ground.healScreenActive=true
T.check(ground:animationsFor(124)~=nil,'healing monitor animates during healing')
ground.healScreenActive=false
T.eq(ground:animationsFor(124),nil,'monitor stops after healing')
record.member=14
T.check(ground:animationsFor(124)~=nil,'ambient effects continue to animate')
T.finish()
