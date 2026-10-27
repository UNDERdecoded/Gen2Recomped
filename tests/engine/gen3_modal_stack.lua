package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local priorVersion=Version.get()
local Native=require('src.core.StateStack');local Plane=require('src.ui.ModalStack')
local Game=require('src.core.Game');local G3=require('src.ui.game3.stack')
local Save=require('src.core.SaveData');local Pokemon=require('src.pokemon.Pokemon')
local Battle=require('src.battle.BattleState');local Screens=require('src.ui.Screens')
local before={stack=Game.stack,save=Game.save,data=Game.data,input=Game.input,session=Game.sessionStartedAt,ready=Game.nativeStackReady}
local function setup(version)
 Version.set(version);local stack=setmetatable({},{__index=Native});stack:init()
 local data=T.fixtures.fresh();data.constants.gen=3;require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
 Game.stack,Game.data,Game.save,Game.sessionStartedAt=stack,data,save,1
 Game.nativeStackReady=true
 Game.input=setmetatable({},{__index=require('src.core.Input')});Game.input:init()
 return stack,Plane.forGame(Game)
end
for _,version in ipairs{'firered','emerald'}do
 local stack,ui=setup(version);local updates,draws,exits,enters=0,{},0,0
 local world={isOverworld=true,isOpaque=true,map={id='FIX_TOWN'},update=function()updates=updates+1 end,
  draw=function()draws[#draws+1]='world'end}
 stack:push(world)
 T.eq(ui.depth(),0,version..' world is not a modal')
 T.eq(G3.busy(),false,'public GBA spelling sees actual empty modal plane')
 T.eq(stack:top(),world,'native world/input owner retained')
 local battle=Battle.newWild(Game,'FIXMON_C',23);stack:push(battle)
 T.eq(ui.top(),nil,'actual native battle controller is not a menu')
 T.eq(stack:top(),battle,'real battle remains native execution root')
 stack:pop();T.eq(stack:top(),world,'native battle pop restores same world')
 local code=[=[local mod=...
 mod.content.screens:register('NATIVE_PLANE_TEST',{new=function(game,payload)
  return{game=game,payload=payload,isOpaque=payload.opaque,
   enter=function()mod.exports.entered=(mod.exports.entered or 0)+1 end,
   exit=function()mod.exports.exited=(mod.exports.exited or 0)+1 end,
   update=function(self)if game.input:wasPressed('b')then game.stack:pop()end end,
   draw=function(self)mod.exports.draw(self.payload.name)end}
 end})
 mod.exports.open=function(game,payload)return mod.ui.push(game,'NATIVE_PLANE_TEST',payload)end
 mod.exports.draw=function()end
 mod.exports.pushed=0;mod.exports.popped=0
 mod.events:on('screen.pushed',function()mod.exports.pushed=mod.exports.pushed+1 end)
 mod.events:on('screen.popped',function()mod.exports.popped=mod.exports.popped+1 end)
 ]=]
 local Json=require('src.link.Json');local files={['mods/modal/manifest.json']=Json.encode{id='modal',name='modal',version='1.0.0',api=3,entry='main.lua'},['mods/modal/main.lua']=code}
 local f=T.sdk.loadMod('mods/modal',{fs=T.sdk.memfs(files),data=Game.data,dev=false});f.loader.game=Game
 T.eq(#f.errors,0,'real API3 screen factory loads');local e=f.loader.exports.modal
 e.draw=function(name)draws[#draws+1]=name end
 local first=e.open(Game,{name='first',opaque=false});local firstLayer=G3.top()
 T.eq(firstLayer.mod.state,first,'native mod UI layer exposes actual screen, not a copied controller')
 T.check(firstLayer.id:match('^modui:'),'registered native screen has stable modui layer id')
 T.eq(firstLayer.id,G3.top().id,'layer identity stable across reads')
 T.eq(stack:top(),first,'actual StateStack owns same registered screen')
 local second=e.open(Game,{name='second',opaque=false});local secondLayer=G3.top()
 T.neq(secondLayer.id,firstLayer.id,'nested same-factory screens have distinct native identities')
 T.eq(e.entered,2,'native enter once per screen');T.eq(e.pushed,2,'native push event once per screen')
 draws={};stack:draw();T.same(draws,{'world','first','second'},'transparent native layers preserve real world')
 secondLayer.hideBelow=true;draws={};stack:draw();T.same(draws,{'world','second'},'hideBelow hides other UI without hiding world')
 secondLayer.drawUnder=true;draws={};stack:draw();T.same(draws,{'world','first','second'},'drawUnder restores lower UI')
 secondLayer.fullscreen=function()return true end;draws={};stack:draw();T.same(draws,{'first','second'},'actual fullscreen predicate suppresses world draw')
 T.eq(ui.fullscreen(),true,'same fullscreen policy through facade')
 local hookCalls=0
 local off=f.loader.hooks:wrap('screen.render_visible',function(next,state)
  hookCalls=hookCalls+1;if state==second then return false end;return next(state)
 end,0,'modal')
 draws={};stack:draw();T.same(draws,{'world','first'},'mirrored fullscreen menu reveals native scene on main surface')
 T.eq(hookCalls,3,'render plan evaluates each native visibility hook once per draw')
 T.eq(stack:top(),second,'render mirroring preserves native input ownership')
 T.eq(ui.fullscreen(),true,'logic fullscreen state is independent of surface mirroring');off()
 secondLayer.fullscreen=false
 local leased=ui._layers;ui._layers={}
 T.eq(stack:top(),world,'preview suspension leaves actual world controller')
 T.eq(e.exited,nil,'suspension never exits native menus')
 T.eq(e.popped,0,'suspension emits no fake pop')
 T.eq(#leased,2,'leased rows survive suspension')
 ui.push('preview',{update=function()updates=updates+10 end,draw=function()draws[#draws+1]='preview'end})
 stack:update(1/60);T.eq(updates,10,'preview is updated by native stack once')
 T.eq(ui.pop('preview'),true,'native preview closes')
 ui._layers=leased
 T.eq(stack:top(),second,'restoration resumes same native screen')
 T.eq(e.entered,2,'restoration never re-enters native menu')
 T.eq(e.pushed,3,'only actual preview push emitted a new event')
 local retiredLayer=leased[2]
 Game.input.pressed={b=true};stack:update(1/60);Game.input.pressed={}
 T.eq(stack:top(),first,'real native input closes second screen')
 T.eq(e.exited,1,'native exit once after ordinary pop');T.eq(e.popped,2,'ordinary and preview pop events exact')
 T.raises(function()ui._layers={firstLayer,retiredLayer}end,'retired','retired menu cannot be resurrected')
 local live=ui._layers;ui._layers={};world.map={id='FIX_ROUTE'}
 T.raises(function()ui._layers=live end,'another scene','old map preview cannot restore into a different scene')
 T.raises(function()ui._layers={live[1]}end,'another scene','copied layer rows cannot bypass native scene ownership')
 world.map={id='FIX_TOWN'} -- retain real identity below, not the same spelling
 T.raises(function()ui._layers=live end,'another scene','equal map spelling does not forge scene ownership')
 -- Restore only after returning to the exact original native map object.
 -- Existing first screen is suspended; a fresh fixture below covers session
 -- invalidation without pretending this map replacement restored its lease.
 f.release()
 local stale=ui;Game.save=Save.newGame()
 T.raises(function()stale.depth()end,'retired','save replacement invalidates old plane')
 stack:init();Game.save=Save.newGame();Game.sessionStartedAt=2
 T.raises(function()stale.clear()end,'retired','native reinitialization invalidates prior plane')
end
-- Targeted removal, atomic clear/reentry, legacy input ownership, validation.
do
 local stack,ui=setup('firered');local world={isOverworld=true,isOpaque=true};stack:push(world)
 local calls={};ui.push('one',{isMenu=true,handleInput=function(input)T.eq(input,Game.input,'native input object');calls[#calls+1]='input';ui.pop('one')end,update=function()calls[#calls+1]='stale'end})
 local width,height=stack:top():uiSize()
 T.eq(width,240,'legacy GBA menu requests native width');T.eq(height,160,'legacy GBA menu requests native height')
 T.eq(Game.nativeSurfaceInStack(stack),stack:top(),'legacy menu owns the real native surface')
 stack:update(1/60);T.same(calls,{'input'},'a popped input owner never updates afterward')
 ui.push('one',{});ui.push('two',{});T.eq(ui.pop('one'),true,'named removal reaches lower native UI')
 T.eq(ui.top().id,'two','named removal preserves actual top');T.eq(ui.depth(),1,'only named UI removed')
 ui.push('two',{});T.eq(ui.depth(),1,'reopening native id replaces prior layer')
 ui.clear();T.eq(stack:top(),world,'clear preserves core world')
 local closed=0
 local a={screenId='A',exit=function()closed=closed+1;ui.push('after-clear',{})end}
 local b={screenId='B',exit=function()closed=closed+1 end}
 stack:push(a);stack:push(b);ui.clear()
 T.eq(closed,2,'native clear exits every captured screen exactly once')
 T.eq(ui.top().id,'after-clear','new UI created during exit survives atomic clear')
 ui.clear();local leased
 ui.push('safe',{});leased=ui._layers;ui._layers={}
 T.raises(function()ui._layers={leased[1],leased[1]}end,'duplicate','duplicate rows rejected before mutation')
 T.eq(stack:top(),world,'rejected layer list cannot remove native root')
 T.raises(function()ui._layers={[2]=leased[1]}end,'dense','holes rejected before native mutation')
 local other=setmetatable({},{__index=Native});other:init()
 local foreign=Plane.forGame{stack=other};foreign.push('foreign',{})
 T.raises(function()ui._layers=foreign._layers end,'another scene','foreign layer owner rejected')
 ui._layers=leased;T.eq(ui.has('safe'),true,'valid owned lease still restores')
 ui.clear();local bad={exit=function()error('intentional native exit failure')end};local good=0
 stack:push({exit=function()good=good+1 end});stack:push(bad)
 T.raises(function()ui.clear()end,'intentional','native clear reports callback failure')
 T.eq(good,1,'remaining native exits run after another exit fails');T.eq(stack:top(),world,'failed exit cannot strand removed UI')
 local TextBox=require('src.render.TextBox');local completed=0
 local stay=TextBox.new(Game,'Native stay',function()completed=completed+1 end,{stay={}})
 stack:push(stay);ui.push('transparent',{}, {hideBelow=false})
 T.check(stack.states[2]==stay,'transparent UI retains actual native stay text')
 ui.pop();ui.push('covers',{})
 T.eq(stack.states[2].nativeModalId,'covers','covering UI closes actual native stay text')
 T.eq(completed,0,'closing stay text does not complete its script callback')
 ui.clear();local prompt=TextBox.new(Game,'Native prompt',function()completed=completed+1 end)
 stack:push(prompt);ui.push('prompt-cover',{})
 T.eq(stack.states[2],prompt,'ordinary native prompt is never auto-closed')
 ui.clear();T.eq(completed,0,'modal cleanup does not fake script completion')
 local old=ui;Game.nativeStackReady=false
 T.eq(G3.top(),nil,'reload cannot expose previous game UI')
 T.eq(G3.depth(),0,'reload has no advertised active modal plane')
 T.raises(function()G3.push('bad',{})end,'live Gen3','reload cannot push into old stack')
 T.raises(function()old.clear()end,'retired','old plane cannot close UI during reload')
 Game.nativeStackReady=true
 local Runtime=require('src.mods.Runtime');local Events=require('src.mods.Events');local Hooks=require('src.mods.Hooks')
 local oldEvents,oldHooks,oldErrors=Runtime.events,Runtime.hooks,Runtime.errors
 local staleCalls,liveCalls=0,0;Runtime.currentMod='fixture-modal'
 G3.onClear(function()staleCalls=staleCalls+1 end);Runtime.currentMod=nil
 Runtime.install(Events.new(),Hooks.new(),{})
 local off=G3.onClear(function()liveCalls=liveCalls+1 end)
 G3.clear();T.eq(staleCalls,0,'retired loader hooks do not run in next session')
 T.eq(liveCalls,1,'current clear observer runs once');off();off();G3.clear()
 T.eq(liveCalls,1,'clear observer unsubscription is idempotent')
 Runtime.install(oldEvents,oldHooks,oldErrors)
 Version.set('crystal');T.eq(G3.top(),nil,'GBA modal API does not claim a Gen2 owner')
 T.raises(function()G3.push('wrong',{})end,'live Gen3','Gen2 cannot mutate its stack through GBA API')
end
Game.stack,Game.save,Game.data,Game.input,Game.sessionStartedAt=before.stack,before.save,before.data,before.input,before.session
Game.nativeStackReady=before.ready
Version.set(priorVersion);Screens.invalidate()
T.finish('native GBA modal ownership and lifecycle')
