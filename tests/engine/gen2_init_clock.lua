-- Copyright (c) 2026 Roxas2712. See contribution permission: https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local version=V.get()
require('src.core.ModCompat').install()
local UI=require('src.ui.Gen2InitClock');local Clock=require('src.core.Gen2Clock')
local Stack=require('src.core.StateStack');local Box=require('src.render.TextBox');local Choice=require('src.ui.ChoiceBox')
local Timing=require('src.core.Timing');local Screens=require('src.ui.Screens')
local Json=require('src.link.Json');local Save=require('src.core.SaveData')
local function game()
 local g={data=T.fixtures.fresh(),save={player={name='QA'},flags={},options={}},input={queue={}}}
 g.input.wasPressed=function(self,k)return self.queue[k]==true end;g.input.isDown=function()return false end
 g.stack=setmetatable({}, {__index=Stack});g.stack:init()
 g.data.text={OakTimeWokeUpText='QA opening page.\fQA next page.',OakTimeWhatTimeIsItText='QA choose hour.',
  OakTimeHowManyMinutesText='QA choose minute.',OakTimeWhatHoursText='QA hour',OakTimeWhoaMinutesText='QA minute',
  ['OakTimeWhatHoursText.OakTimeHoursQuestionMarkText']='?',
  ['OakTimeWhoaMinutesText.OakTimeMinutesQuestionMarkText']='?',
  ['OakText_ResponseToSetTime.OakTimeSoDarkText']=' QA night response.',
  ['SetDayOfWeek.OakTimeWhatDayIsItText']='QA choose weekday.',['SetDayOfWeek.OakTimeIsItText']=' QA confirm?'}
 return g
end
local function tick(g,key,n)
 g.input.queue=key and {[key]=true}or{}
 for _=1,n or 1 do g.stack:update(1/60)end
 g.input.queue={}
end
local function untilState(g,fn,label)
 for _=1,2500 do if fn()then return end;tick(g,'a')end
 error('native widgets did not reach '..label)
end
local function picker(g,screen,phase)
 untilState(g,function()return g.stack:top()==screen and screen.phase==phase and not screen.fade end,phase)
end
local function choice(g)
 untilState(g,function()return getmetatable(g.stack:top())==Choice end,'YES/NO over native question')
 return g.stack:top()
end
local function answer(g,yes)
 choice(g);tick(g,yes and 'a'or'b');tick(g,nil,Timing.YES_NO_ANSWER)
end
T.eq(require('src.ui.gen2.InitClock'),UI,'public reference spelling resolves actual native screen')
for _,edition in ipairs({'gold','silver','crystal'})do
 V.set(edition);local label=edition..' '
 T.eq(require('src.ui.OakSpeech').gen2Steps()[1].id,'init_clock',label..' native speech opens with clock')
 local g=game();local n=0;local parent={};g.stack:push(parent)
 local ui=Screens.push(g,'Gen2InitClock',{fades=true,onDone=function()n=n+1;g.stack:pop()end})
 T.eq(getmetatable(ui),UI,label..' actual native screen factory used')
 T.eq(Clock.isSet(g.save),false,label..' opening screen cannot set clock')
 picker(g,ui,'hour')
 T.eq(ui:question(),'QA choose hour.',label..' question uses imported native text')
 T.eq(ui.hour,10,label..' initial picker has native default')
 tick(g,'b');T.eq(g.stack:top(),ui,label..' B cannot abandon required picker')
 for _=1,10 do tick(g,'down')end
 tick(g,'down');T.eq(ui.hour,23,label..' hour wraps backwards through midnight')
 tick(g,'up');T.eq(ui.hour,0,label..' hour wraps forward through midnight')
 tick(g,'down');tick(g,'a');local c=choice(g)
 T.eq(getmetatable(g.stack.states[#g.stack.states-1]),Box,label..' confirmation retains question under choice')
 T.eq(Clock.isSet(g.save),false,label..' hour confirmation has not committed clock')
 answer(g,false);T.eq(ui.phase,'hour',label..' declining returns to picker')
 T.eq(ui.hour,23,label..' declining retains selected hour')
 tick(g,'a');answer(g,true);picker(g,ui,'minute')
 tick(g,'down');T.eq(ui.minute,59,label..' minute wraps backwards')
 tick(g,'up');T.eq(ui.minute,0,label..' minute wraps forwards')
 tick(g,'down');tick(g,'a');answer(g,false)
 T.eq(ui.phase,'minute',label..' declining minutes returns without saving')
 T.eq(Clock.isSet(g.save),false,label..' declining leaves save unchanged')
 tick(g,'a');answer(g,true)
 T.eq(ui.phase,'response',label..' both confirmed values are read back')
 T.eq(ui:question():find('QA night response.',1,true)~=nil,true,label..' response uses imported native fragment')
 T.eq(Clock.isSet(g.save),false,label..' response acknowledgement still owns commitment')
 untilState(g,function()return n==1 end,'clock completion')
 T.eq(g.stack:top(),parent,label..' completion restores exact parent')
 T.eq(Clock.hour(g.save),23,label..' confirmed hour reaches native RTC')
 T.eq(Clock.minute(g.save),59,label..' confirmed minute reaches native RTC')
 local round=assert(Save.decode(Save.encode(g.save)))
 T.eq(Clock.minute(round),59,label..' normal save codec preserves confirmed RTC')
 ui:finish();ui:complete();T.eq(n,1,label..' duplicate finish cannot repeat callback')
 -- Real special lowering and coroutine runner stay suspended through NO.
 g=game();local Runner=require('src.script.ScriptRunner');local runner=Runner.new(g,{})
 local rows=assert(require('src.script.Gen2ScriptVM').compile({map_scripts={scripts={qa={
  {'special',37,'SetDayOfWeek'},{'end'}}}}},'qa'))
 T.eq(#Runner.validate(rows),0,label..' native special lowers to valid production commands')
 local completed=0;runner:run(rows,{onDone=function()completed=completed+1 end})
 local day=g.stack:top();T.eq(getmetatable(day),UI,label..' actual special opens shared native day mode')
 T.eq(runner:isRunning(),true,label..' actual script waits for selection')
 T.eq(day.day,0,label..' native day picker opens on Sunday')
 tick(g,'down');T.eq(day.day,6,label..' weekday wraps backwards')
 tick(g,'a');answer(g,false)
 T.eq(runner:isRunning(),true,label..' NO cannot resume original script')
 T.eq(g.save.rtc,nil,label..' NO cannot write weekday anchor')
 tick(g,'up');T.eq(day.day,0,label..' weekday wraps forwards')
 tick(g,'a');answer(g,true)
 T.eq(Clock.weekday(g.save),0,label..' accepted special writes shared weekday')
 T.eq(runner:isRunning(),false,label..' accepted special resumes real runner')
 T.eq(completed,1,label..' real runner completes once')
 day:finish();T.eq(completed,1,label..' repeated special finish cannot resume twice')
 -- The production Oak step must yield to the same child and advance once.
 g=game();local advanced=0;local speech={game=g,cfg={},advance=function()advanced=advanced+1 end}
 g.stack:push(parent);require('src.ui.OakSpeech').runStep(speech,{kind='initclock'})
 local child=g.stack:top();T.eq(getmetatable(child),UI,label..' real Oak step opens native clock')
 picker(g,child,'hour');tick(g,'a');answer(g,true);picker(g,child,'minute')
 tick(g,'a');answer(g,true);untilState(g,function()return advanced==1 end,'Oak resumes')
 T.eq(g.stack:top(),parent,label..' Oak clock completion preserves parent ownership')
 T.eq(Clock.isSet(g.save),true,label..' actual Oak continuation follows committed RTC')
 for _,api in ipairs({{1,'native'},{2,'native'}})do
  local files={['mods/setclock/manifest.json']=Json.encode({id='setclock',name='Native clock UI client',version='1.0.0',api=api[1],content_format=api[2],entry='main.lua',affects_link=false}),
   ['mods/setclock/main.lua']=[[
    local mod=...;local Screen=require('src.ui.gen2.InitClock')
    mod.exports.make=function(game)return Screen.new(game,{autoConfirm=true})end
   ]]}
  local loaded=T.sdk.loadMods({'mods/setclock'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
  T.eq(#loaded.errors,0,label..' actual loader admits native clock UI client')
  local own=game();local screen=loaded.loader.exports.setclock.make(own)
  T.eq(getmetatable(screen),UI,label..' loaded client uses native owner instead of a stub')
  own.stack:push(screen)
  untilState(own,function()return screen.done end,'loaded clock UI completion')
  T.eq(Clock.isSet(own.save),true,label..' loaded UI client commits native RTC')
  T.eq(Clock.hour(own.save),10,label..' loaded UI client keeps native default hour')
  require('src.mods.Loader').teardown();loaded.release()
 end
end
-- The shared Oak class also serves other editions. Preserve their existing
-- music-before-build contract rather than changing Gen1 while adding GSC.
local Music=require('src.core.Music');local play=Music.play;local order
Music.play=function(...)order[#order+1]='music';return play(...)end
for _,edition in ipairs({'red','blue','yellow','prism','polishedcrystal','gold','silver','crystal'})do
 V.set(edition);order={}
 local native=edition=='gold'or edition=='silver'or edition=='crystal'
 local speech={game=game(),cfg={},buildSteps=function()
  order[#order+1]='build';return {{kind=native and'initclock'or'say'}}
 end,advance=function()order[#order+1]='advance'end}
 require('src.ui.OakSpeech').enter(speech)
 T.same(order,native and{'build','advance'}or{'music','build','advance'},edition..' preserves appropriate native music/build ordering')
 if native then
  order={};speech.buildSteps=function()order[#order+1]='build';return {{kind='say'}}end
  require('src.ui.OakSpeech').enter(speech)
  T.same(order,{'build','music','advance'},edition..' explicit clock removal still starts professor music')
 end
end
Music.play=play
for _,edition in ipairs({'prism','polishedcrystal'})do
 V.set(edition);T.eq(require('src.ui.OakSpeech').gen2Steps()[1].id,'oak_welcome',edition..' keeps its own introduction')
end
for _,hour in ipairs({0,3,4,10,11,17,18,23})do
 local response=UI.responseKey(hour)
 T.eq(response,(hour<4 or hour>=18)and'soDark'or(hour<=10 and'overslept'or'yikes'),'hour response boundary '..hour)
end
V.set(version);Clock.resetObservations()
T.finish('native initial clock/day widgets, original Oak admission and actual script continuation')
