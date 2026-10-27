package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local old=V.get()
for _,version in ipairs{'gold','silver','crystal','prism','polishedcrystal','red','emerald'}do
 V.set(version)
 local data=T.fixtures.fresh();data.constants.gen=V.generation()
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',5)}
 local stack={states={}}
 function stack:top()return self.states[#self.states]end
 function stack:push(s)self.states[#self.states+1]=s end
 function stack:pop()return table.remove(self.states)end
 local game={data=data,save=save,stack=stack,input={wasPressed=function()return false end,isDown=function()return false end}}
 local b=Battle.newWild(game,'FIXMON_C',3)
 b.phase,b.queue,b.current,b.introSlide,b.sendingOut='messages',{},nil,0,false
 b.afterQueue='menu';stack:push(b)
 local before,child,nested,actions
 actions=0
 b:ui(function()
  before=b.phase;child={};return child
 end)
 b:act(function()actions=actions+1 end)
 b:update(1/60)
 T.eq(before,V.isGen2()and'submenu'or'messages',version..' constructor sees the native interactive phase')
 T.eq(b.phase,before,'the public phase stays stable while the child owns input')
 T.eq(stack:top(),child,'the actual queue pushes its child')
 T.eq(actions,0,'queue does not run a battle action during construction')
 T.eq(b:updateQueue(),true,'queue remains suspended while the child owns the stack')
 T.eq(actions,0,'child input cannot spend the continuation')
 nested={};stack:push(nested)
 T.eq(b:updateQueue(),true,'nested target picker keeps the same native queue suspended')
 stack:pop();T.eq(b:updateQueue(),true,'returning from the nested picker does not resume the battle')
 stack:pop()
 for _=1,5 do b:update(1/60)end
 T.eq(actions,1,'the native continuation resumes exactly once after all children close')
 T.eq(b.phase,'menu','the native queue returns to the decision menu')
 T.eq(b.waitingUI,nil,'no orphaned UI owner survives cancel/selection')
 T.eq(stack:top(),b,'the battle remains the real stack owner')
end
V.set(old)
T.finish('native Gen2 interactive submenu queue ownership')
