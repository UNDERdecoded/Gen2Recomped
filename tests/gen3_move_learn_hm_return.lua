-- Actual native menu methods and HM-set reader; presentation is stubbed.
-- Rendered native controller/input follow-ups are separate evidence.
local function native(path,modules)
 local f=assert(loadfile(path));setfenv(f,setmetatable({require=function(n)return assert(modules[n],n)end},{__index=_G}));return f()
end
local Strings=setmetatable({source=function(s)return s end},{__call=function(_,s,...)return s:format(...)end})
local modules={['src.render.Font']={},['src.core.Strings']=Strings}
modules['src.ui.MoveLearnMenu']=native('src/ui/MoveLearnMenu.lua',modules)
modules['src.render.TextBox']={new=function(game,text,done)return{game=game,text=text,onDone=done}end}
local Learn=native('src/ui/Gen3MoveLearnMenu.lua',modules)
for _,case in ipairs{'summary','fallback','list','retired'}do
 local stack={states={}};function stack:push(s)self.states[#self.states+1]=s end
 function stack:pop()return table.remove(self.states)end;function stack:top()return self.states[#self.states]end
 local Game={data={constants={machines={{kind='HM',move='CUT'},{kind='TM',move='GROWL'}}}},stack=stack}
 local cut={id='CUT',pp=13};local mon={moves={cut,{id='GROWL',pp=20}}}
 local screen=Learn.new(Game,mon,'EMBER');stack:push(screen)
 screen.selecting=case=='list';local asks=0
 screen.askOnSummary=function()
  asks=asks+1
  if case=='fallback'then return false end
  stack:push({summary=true});return true
 end
 assert(screen:forget(1)==false and mon.moves[1]==cut and cut.pp==13)
 local box=stack:pop();assert(type(box.onDone)=='function','HM refusal has no return callback')
 if case=='retired'then stack:pop();stack:push({unrelated=true})end
 box.onDone()
 assert(mon.moves[1]==cut and cut.pp==13,'HM refusal mutated native moves/PP')
 if case=='summary'then assert(asks==1 and stack:top().summary)
 elseif case=='fallback'then assert(asks==1 and screen.selecting and stack:top()==screen)
 elseif case=='list'then assert(asks==0 and screen.selecting and stack:top()==screen)
 else assert(asks==0 and stack:top().unrelated)end
end
print('PASS_NATIVE_GEN3_HM_RETURN actual menu/HM reader; chooser reopen; unavailable-summary list; existing list; retired screen; no PP/move mutation. Presentation stub only.')
