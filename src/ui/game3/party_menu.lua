-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source party extensions edit the real native submenu and input phase.
local Native=require('src.compat.gen1.NativeSession')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local M={}
local current
local function retire()
 local c=current;current=nil
 if c then
  c.mons:release();c.game,c.screen,c.save,c.data,c.loader,c.rows,c.nativeList,c.list=nil,nil,nil,nil,nil,nil,nil,nil
  c.extras,c.party={},{}
 end
end
local function observe(screen)
 local g=Native.game();if not(g and g.stack)then retire();return end
 local class=package.loaded['src.ui.Gen3PartyMenu']
 if not class then retire();return end
 if not screen then for i=#g.stack.states,1,-1 do if getmetatable(g.stack.states[i])==class then screen=g.stack.states[i];break end end end
 if not screen or getmetatable(screen)~=class or screen.game~=g then retire();return end
 if not current or current.screen~=screen or current.save~=g.save or current.data~=g.data then
  retire()
  local c={screen=screen,game=g,save=g.save,data=g.data,loader=g.mods,edition=require('src.core.GameVersion').get(),extras={},party={}}
  current=c
  function c:valid()
   if not self.game or Native.game()~=self.game or self.game.save~=self.save or self.game.data~=self.data
    or self.game.mods~=self.loader or require('src.core.GameVersion').get()~=self.edition then return false end
   for _,s in ipairs(self.game.stack.states)do if s==self.screen then return true end end
   return false
  end
  c.mons=require('src.compat.gen1.PokemonView').new(g,function()return c:valid()end)
 end
 if not current:valid()then retire();return end
 return current
end
local function actions(c)
 local s=c.screen;if not s.submenu then c.list,c.nativeList=nil,nil;return nil end
 if s.submenu~=c.nativeList then
  c.nativeList=s.submenu;c.list={};c.rows={}
  for i,row in ipairs(s.submenu)do
   local key=row.move or(type(row.action)=='string'and row.action:upper()or('NATIVE_ACTION_'..i))
   c.list[i]=key;c.rows[key]=row
  end
 end
 return c.list
end
local function sync(c)
 if not c or not c:valid()or not c.screen.submenu then return end
 local list=actions(c);local rows={}
 for i,key in ipairs(list or{})do
  assert(type(key)=='string','invalid party action label')
  rows[i]=c.rows[key]or{label=key,action='source_field_move',sourceLabel=key,sourceOwner=Call.owner(M,'update')}
  local texts=c.extras._actionTexts
  if texts and texts.list==list and texts.texts[i]then
   local copy={};for k,v in pairs(rows[i])do copy[k]=v end;copy.label=texts.texts[i];rows[i]=copy
  end
 end
 assert(#rows>0,'party action list cannot be empty')
 c.nativeList=rows;c.screen.submenu=rows
 c.screen.subIndex=math.max(1,math.min(#rows,c.screen.subIndex or 1))
end
function M.update()return Boundary.invoke('party.update')end
function M.handleInput()return Boundary.invoke('party.input')end
function M._dispatch(screen,dt,body)
 local c=observe(screen);if not c then return body()end;actions(c)
 local result=Boundary.dispatch('party.update',body,function()return Call.call(M,'update',dt)end)
 sync(c);return result
end
function M._input(screen,body)
 local c=observe(screen);if not c then return body()end;actions(c)
 return Boundary.dispatch('party.input',function()sync(c);return body()end,function()return Call.call(M,'handleInput',screen.game.input)end)
end
function M._fieldAction(screen,mon,row)
 local c=observe(screen);if not c then return false end
 local typed=c.mons:view(mon)
 local result=Call.call(require('src.core.game3.field_moves'),'fromMenu',row.sourceLabel,
  {mon=typed,session=require('src.core.Game3').forNative(c.game).session})
 if type(result)=='table'and result.text then screen:say(result.text)end
 return true
end
local service={release=retire,poll=function()if current and not current:valid()then retire()end end,
 releaseOwner=function(_,who)
  local c=current;if not c or not c:valid()then retire();return end
  local list=c.screen.submenu
  if list then
   for i=#list,1,-1 do if list[i].action=='source_field_move'and list[i].sourceOwner==who then table.remove(list,i)end end
   if #list==0 then c.screen.submenu=nil else c.screen.subIndex=math.min(c.screen.subIndex or 1,#list)end
  end
  c.nativeList,c.list,c.rows=nil,nil,nil;c.extras={}
 end}
require('src.core.game3.asset_stream').register(service)
M._service=service
setmetatable(M,{__index=function(_,key)
 local c=observe();if not c then if key=='open'then return false end;return nil end
 local s=c.screen
 if key=='open'then return not s.closed end
 if key=='mode'then return s.submenu and'action'or'party'end
 if key=='cursor'then return s.index end
 if key=='actionCursor'then return s.subIndex or 1 end
 if key=='ACTIONS'then return actions(c)end
 if key=='_party'then
  local party=s:party();for i,m in ipairs(party)do c.party[i]=c.mons:view(m)end
  for i=#c.party,#party+1,-1 do c.party[i]=nil end;return c.party
 end
 if key=='_cursorOptionText'then return function(label)local row=c.rows and c.rows[label];return row and row.label or label end end
 return c.extras[key]
end,__newindex=function(t,key,value)
 if type(value)=='function'and(key=='update'or key=='handleInput')then rawset(t,key,value);return end
 local c=assert(observe(),'native party menu is not open')
 if key=='ACTIONS'then assert(type(value)=='table','invalid party actions');actions(c);c.list=value
 elseif key=='actionCursor'then assert(type(value)=='number'and value%1==0 and value>=1,'invalid party action cursor');c.screen.subIndex=value
 else c.extras[key]=value end
end})
return M
